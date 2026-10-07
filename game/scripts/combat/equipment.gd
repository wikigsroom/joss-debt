extends RefCounted
## Single-slot equipment, transaction-safe ground rewards, and isolated rare RNG.
const Composer = preload("res://scripts/combat/attack_composer.gd")
const MANUAL_KINDS = ["active", "trinket", "relic", "battery"]

static func normalize(w) -> void:
	if not w.run.has("active_item"): w.run.active_item = {"id": "a01", "charge": 3.0}
	if not w.run.has("trinket"): w.run.trinket = ""
	if not w.run.has("equipment_seen"): w.run.equipment_seen = {"active_items": [], "trinkets": []}
	if not w.player.has("item_cd"): w.player.item_cd = 0.0
	if not w.player.has("item_buffs"): w.player.item_buffs = {}
	if not w.stats.has("active_uses"): w.stats.active_uses = 0
	if not w.stats.has("rare_drops"): w.stats.rare_drops = 0
	if not w.stats.has("equipment_swaps"): w.stats.equipment_swaps = 0
	var id = str(w.run.active_item.get("id", ""))
	if not id.is_empty() and not w.run.equipment_seen.active_items.has(id): w.run.equipment_seen.active_items.append(id)

static func bonus(w, stat: String) -> float:
	var row = w.db.row("trinkets", str(w.run.get("trinket", "")))
	var amount = float(row.get("value", 0)) if row.get("stat", "") == stat else 0.0
	var buff = w.player.get("item_buffs", {}).get(stat, {})
	if float(buff.get("until", 0)) > w.time: amount += float(buff.get("value", 0))
	return amount

static func multiplier(w, stat: String) -> float:
	return 1.0 + bonus(w, stat)

static func active_row(w) -> Dictionary:
	return w.db.row("active_items", str(w.run.get("active_item", {}).get("id", "")))

static func charge(w, rooms: float = 1.0) -> void:
	var row = active_row(w)
	if row.is_empty(): return
	var previous = float(w.run.active_item.charge)
	w.run.active_item.charge = minf(float(row.charge_rooms), previous + rooms * multiplier(w, "charge_efficiency"))
	if w.run.active_item.charge > previous:
		w.emit("item_charge", {"id": row.id, "ready": w.run.active_item.charge >= row.charge_rooms})

static func spawn(w, kind: String, id: String, point: Vector2, state: Dictionary = {}, delay: float = .35) -> Dictionary:
	var drop = {"uid": w.next_uid(), "kind": kind, "id": id, "pos": w.geometry.nearest_free(point, 16),
		"value": 1, "delay": delay, "natural": false, "magnet": false, "gear_state": state.duplicate(true)}
	if kind == "active" and state.is_empty():
		drop.gear_state = {"id": id, "charge": float(w.db.row("active_items", id).charge_rooms)}
	w.pickups.append(drop)
	w.emit("loot_spawn", {"pos": drop.pos, "type": kind, "id": id})
	return drop

static func rare_drop(w, domain: String, source: String, point: Vector2) -> bool:
	if w.run.get("training", false) or not w.run.result.is_empty(): return false
	if not w.reward_once("rare_roll/" + domain): return false
	var random = w.roll("rare_drops/v1/" + source)
	var chance = float(w.db.equipment.rare_drops.get(source, 0)) * multiplier(w, "luck")
	if random.unit() >= minf(.15, chance) or int(w.room_flags.get("rare_drop_count", 0)) >= 2: return false
	var weights = w.db.equipment.rare_drops.weights
	var kind = str(random.weighted(["battery", "active", "trinket", "relic"], [float(weights.battery), float(weights.active), float(weights.trinket), float(weights.modifier)]))
	var id = "battery"
	if kind != "battery":
		var pool = w.db.rows("active_items" if kind == "active" else "trinkets") if kind != "relic" else w.db.equipment.relics
		pool = pool.filter(func(row): return kind != "relic" or w.stack(row.id) < int(row.stack_limit))
		if pool.is_empty(): kind = "battery"
		else: id = str(random.choose(pool).id)
	spawn(w, kind, id, point)
	w.room_flags.rare_drop_count = int(w.room_flags.get("rare_drop_count", 0)) + 1
	w.stats.rare_drops = int(w.stats.get("rare_drops", 0)) + 1
	return true

static func death_drop(w, enemy: Dictionary) -> void:
	if enemy.summoned or not enemy.natural_reward: return
	rare_drop(w, "enemy_" + str(int(enemy.uid)), "boss" if enemy.boss else ("elite" if enemy.elite else "normal"), enemy.pos)

static func treasure_cache(w) -> void:
	# Authored treasure-room equipment gives every run meaningful slot decisions.
	# Rare combat drops are still independent of this guaranteed pedestal.
	if w.run.get("training", false) or not w.reward_once("equipment_cache/v1"): return
	var kind = "trinket" if int(w.run.floor) % 2 == 1 else "active"
	var pool = w.db.rows("trinkets" if kind == "trinket" else "active_items")
	pool = pool.filter(func(row): return row.id != (str(w.run.trinket) if kind == "trinket" else str(w.run.active_item.id)))
	if not pool.is_empty(): spawn(w, kind, str(w.roll("equipment_cache/v1").choose(pool).id), Vector2(640, 380))

static func nearest(w) -> Dictionary:
	var candidates = w.pickups.filter(func(drop): return drop.kind in MANUAL_KINDS and float(drop.delay) <= 0 and drop.pos.distance_to(w.player.pos) <= 64)
	candidates.sort_custom(func(a, b):
		var da = a.pos.distance_squared_to(w.player.pos)
		var db = b.pos.distance_squared_to(w.player.pos)
		return int(a.uid) < int(b.uid) if is_equal_approx(da, db) else da < db)
	return candidates[0] if not candidates.is_empty() else {}

static func interact(w) -> bool:
	if w.mode not in ["combat", "clear"]: return false
	var drop = nearest(w)
	if drop.is_empty(): return false
	return take(w, drop)

static func take(w, drop: Dictionary, replace_id: String = "") -> bool:
	if not w.pickups.has(drop) or drop.kind not in MANUAL_KINDS or drop.delay > 0: return false
	var table = {"active": "active_items", "trinket": "trinkets", "relic": "relics"}.get(drop.kind, "")
	if not table.is_empty() and w.db.row(table, str(drop.id)).is_empty(): return false
	if drop.kind == "relic":
		if w.stack(drop.id) >= int(w.db.row("relics", drop.id).stack_limit):
			w.emit("item_notice", {"text": "已持有这件供物"})
			return false
		if w.run.relics.size() >= 12 and w.stack(drop.id) == 0 and replace_id.is_empty():
			w.run.replacement = {"choice": {"kind": "relic", "id": drop.id, "price": 0},
				"index": -1, "return_mode": w.mode, "ground_uid": int(drop.uid)}
			w.mode = "replace"
			w.emit("save_requested")
			return true
		if not replace_id.is_empty():
			if not w.run.relics.has(replace_id) or replace_id == drop.id: return false
			var old = spawn(w, "relic", replace_id, w.player.pos - w.player.aim * 48, {}, .7)
			old.value = int(w.run.relics[replace_id])
			w.run.relics.erase(replace_id)
		w.run.relics[drop.id] = mini(int(w.db.row("relics", drop.id).stack_limit), w.stack(drop.id) + int(drop.value))
	elif drop.kind == "battery":
		var row = active_row(w)
		if row.is_empty() or w.run.active_item.charge >= row.charge_rooms:
			w.emit("item_notice", {"text": "主动道具充能已满，火芯可以留在这里"})
			return false
		charge(w, 1.0 / multiplier(w, "charge_efficiency"))
	elif drop.kind == "active":
		var old = w.run.active_item.duplicate(true)
		if not str(old.get("id", "")).is_empty(): spawn(w, "active", old.id, w.player.pos - w.player.aim * 48, old, .7)
		w.run.active_item = drop.gear_state.duplicate(true)
		if not w.run.equipment_seen.active_items.has(drop.id): w.run.equipment_seen.active_items.append(drop.id)
		w.stats.equipment_swaps += 1
	elif drop.kind == "trinket":
		var old = str(w.run.trinket)
		if not old.is_empty(): spawn(w, "trinket", old, w.player.pos - w.player.aim * 48, {}, .7)
		w.run.trinket = str(drop.id)
		if not w.run.equipment_seen.trinkets.has(drop.id): w.run.equipment_seen.trinkets.append(drop.id)
		w.stats.equipment_swaps += 1
	w.pickups.erase(drop)
	if drop.kind != "battery": w.record_growth_choice("active" if drop.kind == "active" else drop.kind, drop.id, "", "", 0, 0, "ground")
	w.emit("equipment_taken", {"pos": w.player.pos, "id": drop.id, "type": drop.kind})
	w.emit("save_requested")
	return true

static func use_reason(w) -> String:
	var row = active_row(w)
	if row.is_empty(): return "尚未持有主动道具"
	if w.player.item_cd > 0: return "道具尚在收招"
	if float(w.run.active_item.charge) < float(row.charge_rooms): return "道具还需清房充能"
	if row.effect == "heal" and w.player.hp >= w.player.max_hp: return "心火已满"
	if row.effect == "reroll_ground" and not w.pickups.any(func(drop): return drop.kind in ["active", "trinket", "relic"]): return "房内没有可重掷的装备"
	return ""

static func activate(w) -> bool:
	if w.mode not in ["combat", "clear"]: return false
	var reason = use_reason(w)
	if not reason.is_empty():
		w.emit("item_notice", {"text": reason})
		return false
	var row = active_row(w)
	w.run.active_item.charge = 0.0
	w.player.item_cd = .4
	w.player.visual_cast_at = w.time
	w.stats.active_uses += 1
	w.begin_pulse("active_" + row.id)
	var damage = 28.0 * multiplier(w, "damage")
	match row.effect:
		"bombs":
			for i in 3:
				var point = w.geometry.nearest_free(w.player.pos + w.player.aim.rotated((i - 1) * .32) * (105 + i * 34), 16)
				Composer.schedule_area(w, point, 90 * multiplier(w, "blast_radius"), damage * 1.8, .3 + i * .14, "ember_blast", "active/%d/%d" % [w.stats.active_uses, i])
		"heal":
			w.player.hp = mini(int(w.player.max_hp), int(w.player.hp) + 2)
			w.run.heal_misses = 0
		"mirror":
			w.player.invulnerable = maxf(w.player.invulnerable, 1.6)
			for bullet in w.bullets.duplicate():
				if not bullet.friendly and bullet.pos.distance_to(w.player.pos) < 190:
					w.bullets.erase(bullet)
					var reflected = w.secondary_bullet(bullet.pos, -bullet.dir, damage)
					if not reflected.is_empty(): reflected.style = "jade_needle"
		"ink_field", "lotus_guard":
			var guard = row.effect == "lotus_guard"
			var previous_zones = w.zones.size()
			w.add_zone(w.player.pos, 92 if guard else 158, 3.2, damage * .65, true)
			if w.zones.size() > previous_zones:
				var zone = w.zones[-1]
				zone.style = "blast_lotus" if guard else "blast_ink"
				zone.fx_preset = "lotus_field" if guard else "ink_field"
				zone.follows_player = guard
				zone.item_slow = not guard
			if guard: w.player.invulnerable = maxf(w.player.invulnerable, 1.1)
		"thread_beams", "seekers":
			w.attack_uid += 1
			var weapon = w.db.row("weapons", "w24" if row.effect == "thread_beams" else "w10").duplicate(true)
			weapon.pellets = 5 if row.effect == "thread_beams" else 6
			weapon.damage = damage
			var recipe = Composer.recipe(w, weapon)
			recipe.primary = false
			recipe.fx_family = "thread" if row.effect == "thread_beams" else "lotus"
			Composer.fire(w, weapon, recipe, damage, false, w.player.pos, w.player.aim)
		"ash_bell":
			for drop in w.pickups.duplicate():
				if drop.kind in ["ash", "coin"]:
					w.collect(drop)
					w.pickups.erase(drop)
			w.player.energy = minf(100, w.player.energy + 20)
		"reroll_ground":
			var random = w.roll("active_reroll/v1")
			for drop in w.pickups:
				if drop.kind not in ["active", "trinket", "relic"]: continue
				var pool = w.db.rows("active_items" if drop.kind == "active" else ("trinkets" if drop.kind == "trinket" else "relics"))
				pool = pool.filter(func(item): return item.id != drop.id and (drop.kind != "relic" or (w.run.relic_pool.has(item.id) and w.stack(item.id) < int(item.stack_limit))))
				if pool.is_empty(): continue
				var item = random.choose(pool)
				drop.id = item.id
				if drop.kind == "active": drop.gear_state = {"id": item.id, "charge": minf(float(item.charge_rooms), float(drop.gear_state.charge))}
		"freeze":
			w.bullets = w.bullets.filter(func(bullet): return bullet.friendly or bullet.pos.distance_to(w.player.pos) > 260)
			for enemy in w.enemies:
				if enemy.dead: continue
				enemy.stun_until = maxf(enemy.stun_until, w.time + (.25 if enemy.boss else 2.0))
		"haste":
			w.player.item_buffs.move_speed = {"value": .4, "until": w.time + 4.0}
			w.player.item_buffs.fire_rate = {"value": .25, "until": w.time + 4.0}
			w.player.dash_cd = minf(w.player.dash_cd, .5)
		"chain_lightning":
			w.attack_uid += 1
			var weapon = w.db.row("weapons", "w21").duplicate(true)
			var recipe = Composer.recipe(w, weapon)
			recipe.primary = false
			recipe.fx_family = "storm"
			for i in 3: Composer.schedule_fire(w, weapon, recipe, damage * 1.6, false, w.player.pos, w.player.aim, i * .16)
	w.emit("active_item", {"pos": w.player.pos, "id": row.id, "effect": row.effect})
	w.emit("save_requested")
	return true
