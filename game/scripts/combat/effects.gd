extends RefCounted
## Relic and route effects stay in the simulation. Secondary damage never re-enters primary procs.

static func once(w, key: String) -> bool:
	key = "effect_" + key
	if w.room_flags.get(key, false):
		return false
	w.room_flags[key] = true
	return true

static func ready(w, key: String, cooldown: float) -> bool:
	key = "effect_cd_" + key
	if w.time < float(w.room_flags.get(key, -1.0)):
		return false
	w.room_flags[key] = w.time + cooldown
	return true

static func energy(w, amount: float) -> void:
	w.player.energy = minf(100.0, w.player.energy + amount)

static func skill_cost(w) -> int:
	if w.room_flags.get("free_skill_pending", false):
		return 0
	return maxi(18, int(w.db.row("skills", w.player.skill).energy_cost) - 3 * w.stack("r19") - 4 * w.talent("t_ash_3b"))

static func mark_duration(w) -> float:
	return 5.0 + 2.0 * int(w.run.character == "c_ink") + 1.5 * w.stack("r42") + w.talent("t_ink_1b") + int(w.stack("r46") > 0 and w.run.contracts.is_empty())

static func fire_duration(w, base: float) -> float:
	return base + .75 * w.stack("r03") + .5 * w.talent("t_fire_1b")

static func ash_radius(w) -> float:
	return minf(420, (220 if w.run.character == "c_umbrella" else 120) + 60 * w.talent("t_ash_1b") + 80 * w.stack("r22") + 40 * w.talent("t_wind_2b") * int(w.player.dash_left > 0))

static func primary_multiplier(w, enemy: Dictionary = {}) -> float:
	var value = 1.0 + .1 * mini(2, w.run.contracts.size()) * w.stack("r46")
	value += .1 * w.talent("t_ink_2b") * int(not w.run.contracts.is_empty())
	if not enemy.is_empty() and enemy.mark >= 3 and w.stack("r44") > 0:
		var weapon = w.db.row("weapons", w.player.weapon)
		if int(weapon.pierce) + w.stack("r41") + w.talent("t_ink_1a") + int(w.run.character == "c_ink") == 0:
			value += .1
	return value

static func detonation_multiplier(w, item: Dictionary, aligned: bool) -> float:
	var value = 1.0
	if item.burn >= 3 and w.stack("r06") > 0: value += .2
	if item.burn >= 2: value += .15 * w.talent("t_fire_2b")
	if w.run.contracts.is_empty(): value += .05 * w.talent("t_ink_2b")
	if aligned: value += .2 * w.stack("r45") + .15 * w.talent("t_ink_3a")
	return value

static func primary_after(w, enemy: Dictionary, damage: float, attack: int) -> void:
	if w.stack("r14") > 0 and int(enemy.primary_hits) % 3 == 0 and ready(w, "eight_%d" % enemy.uid, 2.0):
		var neighbor = w.nearest_unmarked(enemy.pos, 160, [enemy.uid])
		if not neighbor.is_empty() and neighbor.mark == 0: w.add_mark(neighbor, 1, false)
	if w.stack("r48") > 0 and attack % 3 == 0:
		var spec = w.db.row("weapons", w.player.weapon)
		if int(spec.pierce) + w.stack("r41") + w.talent("t_ink_1a") + int(w.run.character == "c_ink") == 0 and ready(w, "empty_ledger", 3.0):
			w.add_mark(enemy, 3, false)
	var transfer = .35 * w.stack("r13") + .2 * w.talent("t_thread_2b")
	if transfer > 0:
		for group in w.chains:
			if group.has(enemy.uid) and group.size() > 1:
				var other = w.enemy_by_uid(group[-1] if group[0] == enemy.uid else group[0])
				if not other.is_empty(): w.damage_enemy(other, damage * transfer, "secondary")
				break
	if w.stack("r52") > 0:
		var spec = w.db.row("weapons", w.player.weapon)
		if int(spec.pierce) + w.stack("r41") + w.talent("t_ink_1a") + int(w.run.character == "c_ink") > 0:
			var candidates = w.enemies.filter(func(e): return not e.dead and e.uid != enemy.uid and e.mark > 0 and e.pos.distance_to(enemy.pos) <= 260)
			candidates.sort_custom(func(a, b): return enemy.pos.distance_squared_to(a.pos) < enemy.pos.distance_squared_to(b.pos))
			if not candidates.is_empty():
				var other = candidates[0]
				w.room_flags.forced_links["%d:%d" % [mini(enemy.uid, other.uid), maxi(enemy.uid, other.uid)]] = minf(enemy.mark_until, other.mark_until)
	if w.talent("t_wind_2a") > 0 and int(enemy.primary_hits) % 3 == 0 and w.player.weapon != "w05" and w.stack("r35") == 0:
		w.secondary_bullet(w.player.pos, -w.player.aim, damage * .25)

static func detonation_after(w, item: Dictionary, damage: float, targets: Array) -> void:
	# 镇门钉 belongs to the detonation landing point. Keeping the zone in the
	# detonation hook makes it work for every skill shape and keeps it separate
	# from dash-path relics (r39/r50).
	if w.stack("r31") > 0:
		w.add_zone(item.pos, 45, 1.5, 6, true)
	if w.stack("r02") > 0 or w.talent("t_thread_3b") > 0:
		var victim = w.enemy_by_uid(item.uid)
		if w.stack("r02") > 0 or (not victim.is_empty() and victim.dead):
			var other = w.nearest_unmarked(item.pos, 80 if w.stack("r02") > 0 else 160, targets)
			if not other.is_empty() and int(other.mark) == 0: w.add_mark(other, 1, false)
	if w.stack("r05") > 0:
		var other = w.nearest_enemy(item.pos, 500, [item.uid])
		var aim = Vector2.UP if other.is_empty() else item.pos.direction_to(other.pos)
		for sign_value in [-1, 1]: w.secondary_bullet(item.pos, aim.rotated(sign_value * .2), damage * .25)
	if w.stack("r43") > 0:
		w.delayed.append({"time": w.time + 1.0, "type": "fixed_damage", "pos": item.pos, "radius": 26.0, "damage": damage * .15, "pulse": w.active_pulse})
	if w.talent("t_ink_2a") > 0:
		w.delayed.append({"time": w.time + .8, "type": "fixed_target", "target": item.uid, "damage": damage * .1, "pulse": w.active_pulse})
	if item.burn >= 3 and w.talent("t_fire_3a") > 0:
		w.add_zone(item.pos, 44, fire_duration(w, 1.5), 6, true)
	if item.burn > 0 and w.talent("t_fire_2a") > 0:
		var spread_key = "fire_spread_%s_%d" % [w.active_pulse, item.group_uid]
		var spread = int(w.room_flags.get(spread_key, 0))
		if spread < 2:
			var other = w.nearest_enemy(item.pos, 120, targets)
			if not other.is_empty():
				w.add_burn(other, 1)
				w.room_flags[spread_key] = spread + 1
	var victim = w.enemy_by_uid(item.uid)
	if not victim.is_empty() and item.burn >= 3 and (w.stack("r06") > 0 or w.talent("t_fire_3a") > 0): victim.burn = 0

static func on_death(w, enemy: Dictionary, source: String) -> void:
	if enemy.burn > 0 and w.stack("r04") > 0:
		w.add_zone(enemy.pos, 34, fire_duration(w, 1.0), 3, true)
	if source == "detonate":
		var key = "skill_kills_" + w.active_pulse
		w.room_flags[key] = int(w.room_flags.get(key, 0)) + 1
		if int(w.room_flags[key]) >= 3:
			if w.stack("r07") > 0 and once(w, "everlight_refund"): energy(w, 12)
			if w.stack("r24") > 0 and once(w, "free_skill_awarded"): w.room_flags.free_skill_pending = true

static func after_skill(w, targets: Array, snapshot: Array) -> void:
	if targets.size() >= 3:
		if w.talent("t_fire_3b") > 0 and once(w, "longlight"): energy(w, 10)
		if w.talent("t_ash_3a") > 0 and once(w, "rekindle"): energy(w, 8)
	if int(w.run.get("repay_skill_refunds", 0)) > 0:
		w.run.repay_skill_refunds -= 1
		energy(w, 10)
	var replay = 0.0
	if w.stack("r47") > 0 and once(w, "rewrite_scroll"): replay += .35
	if w.talent("t_ink_3b") > 0 and once(w, "rewrite_talent"): replay += .25
	if replay > 0:
		w.delayed.append({"time": w.time + 1.0, "type": "skill_replay", "items": snapshot.duplicate(true), "factor": replay, "pulse": w.active_pulse})

static func burn_tick(w, enemy: Dictionary) -> void:
	enemy.burn_ticks = int(enemy.get("burn_ticks", 0)) + 1
	if w.stack("r08") > 0 and enemy.burn_ticks % 3 == 0 and ready(w, "samadhi_%d" % enemy.uid, 6.0):
		for other in w.enemies.duplicate():
			if not other.dead and other.pos.distance_to(enemy.pos) <= 80: w.damage_enemy(other, 6, "secondary")
		w.emit("burst", {"pos": enemy.pos, "radius": 80, "small": true})

static func on_ash(w, pickup: Dictionary) -> void:
	if not pickup.natural: return
	w.room_flags.ash_count = int(w.room_flags.get("ash_count", 0)) + 1
	if w.room_flags.ash_count % 3 == 0:
		var target = w.nearest_enemy(w.player.pos)
		if not target.is_empty():
			var damage = float(w.db.row("weapons", w.player.weapon).damage)
			if w.talent("t_ash_2a") > 0: w.secondary_bullet(w.player.pos, w.player.pos.direction_to(target.pos), damage * .25)
			if w.stack("r23") > 0:
				var bullet = w.secondary_bullet(w.player.pos, w.player.pos.direction_to(target.pos), damage * .3)
				if not bullet.is_empty(): bullet.applies_mark = true
	if w.stack("r49") > 0 and not w.chains.is_empty():
		var closest: Array = []
		var distance = INF
		for group in w.chains:
			var first = w.enemy_by_uid(group[0])
			if not first.is_empty() and first.pos.distance_to(w.player.pos) < distance:
				closest = group
				distance = first.pos.distance_to(w.player.pos)
		if not closest.is_empty() and ready(w, "ash_thread_%d" % closest[0], 1.0):
			for value in [closest[0], closest[-1]]:
				var enemy = w.enemy_by_uid(value)
				if not enemy.is_empty() and enemy.mark > 0: enemy.mark_until = w.time + mark_duration(w)

static func deflect(w) -> void:
	w.player.attack_bonus = .25 * w.stack("r25") + .2 * w.talent("t_seal_2a")
	w.player.attack_bonus_until = w.time + 2.0
	w.player.guard_count = mini(3, int(w.player.get("guard_count", 0)) + 1)
	w.stats.parries = int(w.stats.get("parries", 0)) + 1
	if w.stack("r28") > 0 and ready(w, "ward_coin", 2.0): energy(w, 8)
	if w.stack("r51") > 0:
		for pickup in w.pickups:
			if pickup.kind == "ash" and pickup.natural and pickup.pos.distance_to(w.player.pos) <= 160:
				pickup.delay = 0.0
				pickup.magnet = true

static func armor_break(w) -> void:
	if w.talent("t_seal_2b") > 0: energy(w, 6)
	if w.stack("r53") > 0 and ready(w, "lamp_cord", 2.0):
		var nearby = w.enemies.filter(func(e): return not e.dead and e.pos.distance_to(w.player.pos) <= 160)
		nearby.sort_custom(func(a, b): return w.player.pos.distance_squared_to(a.pos) < w.player.pos.distance_squared_to(b.pos))
		for i in mini(2, nearby.size()): w.add_burn(nearby[i], 1)

static func dodge(w) -> void:
	if w.room_flags.get("dash_dodged", false): return
	w.room_flags.dash_dodged = true
	w.stats.dodges += 1
	if w.talent("t_seal_1a") > 0 and int(w.room_flags.dash_armor) < 2:
		w.player.armor = 1
		w.room_flags.dash_armor += 1
	if w.stack("r37") > 0 and ready(w, "return_bell", 3.0): w.room_flags.side_shot_pending = true
	if w.talent("t_wind_3a") > 0: w.room_flags.dodge_return_pending = true

static func dash_end(w) -> void:
	var duration = maxf(2.0 * int(w.stack("r39") > 0 or w.stack("r50") > 0), 1.5 * w.talent("t_wind_3b"))
	if duration > 0:
		var damage = 6 if w.stack("r50") > 0 else (5 if w.stack("r39") > 0 else 3)
		for i in 4:
			w.add_zone(w.player.dash_start.lerp(w.player.pos, (i + .5) / 4.0), 25, fire_duration(w, duration), damage, true)
	if w.stack("r36") > 0:
		for pickup in w.pickups:
			if pickup.kind == "ash" and pickup.natural and w.geometry.segment_circle(w.player.dash_start, w.player.pos, pickup.pos, 96):
				pickup.delay = 0.0
				pickup.magnet = true

static func after_shot(w, damage: float) -> void:
	if w.room_flags.get("side_shot_pending", false):
		w.room_flags.side_shot_pending = false
		for sign_value in [-1, 1]: w.secondary_bullet(w.player.pos, w.player.aim.rotated(sign_value * .32), damage * .5)
	if w.room_flags.get("dodge_return_pending", false):
		w.room_flags.dodge_return_pending = false
		w.secondary_bullet(w.player.pos, -w.player.aim, damage * .4)
	if w.stack("r40") > 0 and int(w.stats.shots) % 2 == 0:
		w.delayed.append({"time": w.time + .3, "type": "repeat_attack", "weapon": w.player.weapon, "pos": w.player.pos,
			"aim": w.player.aim, "damage": damage * .45, "pulse": w.active_pulse})

static func clear_room(w, type: String) -> void:
	if type != "elite": return
	var key = str(int(w.run.floor))
	if w.stack("r21") > 0 and not w.chapter_favor_used("dish"):
		w.run.favors_used["dish_" + key] = true
		if w.player.hp < w.player.max_hp: w.player.hp += 1
		else: w.run.coins += 4
	if w.talent("t_seal_3b") > 0 and not w.chapter_favor_used("copper"):
		w.run.favors_used["copper_" + key] = true
		w.player.armor = 1
		w.player.hp = mini(w.player.max_hp, w.player.hp + 1)
