extends "res://scripts/combat/world.gd"
## One authoritative dungeon. Player contexts never own a second NPC simulation.
const PERSONAL = ["run", "player", "stats", "chains", "pair_cooldowns", "proc_ledger", "choices", "choice_queue", "mode", "attack_uid", "active_pulse", "pulse_serial", "touch_charge_transfer"]
const ROUTE = ["floor", "floor_limit", "room", "graph", "room_plan", "visited", "room_history", "seed", "seed_text", "campaign", "optional_bosses"]
const SHARED_FLAGS = ["combat_kills", "summoned", "summon_rewards", "chain_pairs", "forced_links", "boss_ids", "waves", "wave_count", "wave_index", "wave_pending_at", "debt_pair", "debt_fire_at", "entry_slow_until", "secret_inspect"]
var contexts: Array = []
var seat = 0
var coins = 10
var scene_serial = 0
var choice_serial = [0, 0]
var rescue = {"helper": -1, "target": -1, "progress": 0.0, "hurt_at": -1.0}
var initialized = false
var flow_cache: Array = [{}, {}]
var flow_at = [-1.0, -1.0]

func begin_cooperation(loadouts: Array, seed_input: int) -> void:
	start(str(loadouts[0].character), seed_input, 11, {"weapon": str(loadouts[0].weapon)})
	player.skill = str(loadouts[0].skill)
	run.online = true
	run.cooperative = true
	player.downed = false
	player.hurt_at = -10.0
	contexts.append(personal_state())
	var second = load("res://scripts/combat/world.gd").new()
	second.start(str(loadouts[1].character), seed_input, 11, {"weapon": str(loadouts[1].weapon)})
	second.player.skill = str(loadouts[1].skill)
	second.run.online = true
	second.run.cooperative = true
	second.player.downed = false
	second.player.hurt_at = -10.0
	second.attack_uid = 1000000
	var state: Dictionary = {}
	for key in PERSONAL: state[key] = second.get(key)
	state._flags = local_flags(second.room_flags)
	contexts.append(state)
	initialized = true
	for index in 2:
		for entry in contexts[index].run.growth_log:
			if entry.type == "skill" and entry.source == "initial": entry.id = loadouts[index].skill; entry.reward_id = loadouts[index].skill
	sync_route()
	contexts[1].player.pos = geometry.nearest_free(player.pos + Vector2(48, -12), 12)
	stamp_entities()
	flush()

func personal_state() -> Dictionary:
	var result: Dictionary = {}
	for key in PERSONAL: result[key] = get(key)
	result._flags = local_flags(room_flags)
	return result

func local_flags(flags: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in flags:
		if key not in SHARED_FLAGS: result[key] = flags[key]
	return result

func flush() -> void:
	if not initialized: return
	coins = int(run.coins)
	contexts[seat] = personal_state()

func select_player(index: int) -> void:
	if not initialized or index == seat: return
	stamp_entities()
	flush()
	seat = index
	for key in PERSONAL: set(key, contexts[seat][key])
	for key in room_flags.keys():
		if key not in SHARED_FLAGS: room_flags.erase(key)
	room_flags.merge(contexts[seat].get("_flags", {}), true)
	run.coins = coins

func sync_route() -> void:
	if not initialized: return
	flush()
	for context in contexts:
		for key in ROUTE: context.run[key] = run[key]
		context.run.coins = coins

func stamp_entities() -> void:
	for collection in [bullets, zones, delayed]:
		for entity in collection:
			if not entity.has("owner"): entity.owner = seat

func alive(index: int) -> bool:
	return not contexts[index].player.get("downed", false) and float(contexts[index].player.hp) > 0

func closest_player(position: Vector2) -> int:
	var best = -1
	var distance = INF
	for index in 2:
		if not alive(index): continue
		var next = position.distance_squared_to(contexts[index].player.pos)
		if next < distance: best = index; distance = next
	return best

func prepare_entity(entity: Dictionary, kind: String) -> void:
	var target = closest_player(entity.get("pos", geometry.bounds.get_center())) if kind in ["enemy", "target"] else int(entity.get("owner", 0))
	if kind == "enemy" and int(entity.get("burn", 0)) > 0 and time >= float(entity.get("burn_next", INF)): target = int(entity.get("burn_owner", target))
	if target in [0, 1]:
		select_player(target)
		if kind in ["enemy", "target"]:
			if time >= float(flow_at[target]):
				geometry.flow = {}
				geometry.rebuild_flow(player.pos)
				flow_cache[target] = geometry.flow
				flow_at[target] = time + .25
			else: geometry.flow = flow_cache[target]

func begin_pulse(label: String = "effect") -> String:
	return super.begin_pulse("coop%d_%s" % [seat, label])

func emit(kind: String, data: Dictionary = {}) -> void:
	var value = data.duplicate(true)
	value.seat = seat
	super.emit(kind, value)

func reward_once(slot: String) -> bool:
	return super.reward_once("player%d_%s" % [seat, slot])

func contract(contract_id: String) -> bool:
	if initialized and contract_id in ["d01", "d02", "d05", "d08"]:
		return contexts.any(func(context): return context.run.contracts.any(func(debt): return debt.id == contract_id))
	return super.contract(contract_id)

func add_burn(enemy: Dictionary, count: int) -> void:
	enemy.burn_owner = seat
	super.add_burn(enemy, count)

func spawn_enemy(enemy_id: String, position: Vector2, elite: bool = false, summoned: bool = false, elite_variant_id: String = "") -> Dictionary:
	var enemy = super.spawn_enemy(enemy_id, position, elite, summoned, elite_variant_id)
	if not enemy.is_empty():
		enemy.hp *= 1.65
		enemy.max_hp *= 1.65
	return enemy

func spawn_boss(boss_id: String, point: Vector2 = Vector2(640, 330)) -> Dictionary:
	var boss = super.spawn_boss(boss_id, point)
	if not boss.is_empty():
		boss.hp *= 1.75
		boss.max_hp *= 1.75
	return boss

func kill_enemy(enemy: Dictionary, source: String) -> void:
	super.kill_enemy(enemy, source)
	if initialized and enemy.boss:
		for context in contexts:
			if not context.run.bosses_defeated.has(enemy.id): context.run.bosses_defeated.append(enemy.id)

func damage_player(amount: int, source: Dictionary = {}, incoming = null) -> void:
	if player.get("downed", false): return
	var hp = int(player.hp)
	super.damage_player(amount, source, incoming)
	if int(player.hp) < hp: player.hurt_at = time
	if player.hp <= 0:
		player.downed = true
		player.move = Vector2.ZERO
		player.dash_left = 0.0
		player.charge = 0.0
		mode = "combat" if not enemies.is_empty() else "clear"
		run.result = ""
		events = events.filter(func(event): return event.kind != "run_end")
		emit("cooperative_down", {"pos": player.pos})
	flush()

func damage_hazard(position: Vector2, radius: float, amount: int, source: Dictionary) -> void:
	for index in 2:
		if alive(index) and contexts[index].player.pos.distance_to(position) < radius:
			select_player(index)
			damage_player(amount, source, position)

func hostile_projectile_target(previous: Vector2, bullet: Dictionary) -> bool:
	var target = -1
	var distance = INF
	for index in 2:
		if not alive(index): continue
		var pos = Vector2(contexts[index].player.pos)
		if Geometry.segment_circle(previous, bullet.pos, pos, 12 + bullet.radius) and previous.distance_squared_to(pos) < distance:
			target = index
			distance = previous.distance_squared_to(pos)
	if target < 0: return false
	select_player(target)
	return true

func damage_hostile_zone(zone: Dictionary) -> void:
	for index in 2:
		if not alive(index): continue
		select_player(index)
		super.damage_hostile_zone(zone)

func interact_input() -> bool:
	var other = 1 - seat
	if contexts[other].player.get("downed", false) and player.pos.distance_to(contexts[other].player.pos) <= 72:
		if int(rescue.helper) != seat or int(rescue.target) != other:
			rescue = {"helper": seat, "target": other, "progress": 0.0, "hurt_at": float(player.hurt_at)}
		return true
	return super.interact_input()

func advance_rescue(delta: float) -> void:
	var helper = int(rescue.helper)
	var target = int(rescue.target)
	if helper < 0: return
	if not alive(helper) or alive(target) or contexts[helper].player.pos.distance_to(contexts[target].player.pos) > 72 or float(contexts[helper].player.hurt_at) > float(rescue.hurt_at):
		rescue.helper = -1
		rescue.progress = 0.0
		return
	rescue.progress += delta
	if rescue.progress < 3.0: return
	select_player(target)
	player.hp = mini(2, int(player.max_hp))
	player.downed = false
	player.invulnerable = 2.0
	player.visual_death_at = -100.0
	run.death_cause = {}
	emit("revive", {"pos": player.pos, "cooperative": true})
	emit("burst", {"pos": player.pos, "radius": 72, "style": "blast_lotus", "small": true})
	rescue.helper = -1
	rescue.progress = 0.0
	flush()

func step(frames: Array, delta: float) -> void:
	time += delta
	for index in 2:
		select_player(index)
		if not alive(index): continue
		advance_player(frames[index], delta)
		shoot_input(bool(frames[index].get("fire", false)), delta, bool(frames[index].get("charge_hold", false)), frames[index].get("device", "") == "touch")
		update_chains()
		stamp_entities()
		flush()
	update_enemies(delta)
	Scenery.tick(self)
	stamp_entities()
	update_bullets(delta)
	update_zones(delta)
	update_delayed(delta)
	update_pickups(delta)
	var secret = secret_entry()
	if not secret.is_empty():
		var observer = closest_player(secret.pos)
		if observer >= 0: select_player(observer); update_secret_discovery(delta)
	advance_rescue(delta)
	flush()
	enemies = enemies.filter(func(enemy): return not enemy.dead)
	if not alive(0) and not alive(1): return
	select_player(0 if alive(0) else 1)
	if mode == "combat" and enemies.is_empty() and delayed.is_empty(): finish_wave()
	flush()
	if contexts.all(func(context): return context.mode in ["clear", "checkpoint"]): check_doors()

func update_pickups(delta: float) -> void:
	for pickup in pickups.duplicate():
		pickup.delay = maxf(0, float(pickup.delay) - delta)
		if pickup.delay > 0 or pickup.kind in Equipment.MANUAL_KINDS: continue
		var target = closest_player(pickup.pos)
		if pickup.kind == "heal":
			var candidates = [0, 1].filter(func(index): return alive(index) and contexts[index].player.hp < contexts[index].player.max_hp)
			if not candidates.is_empty():
				candidates.sort_custom(func(a, b): return pickup.pos.distance_squared_to(contexts[a].player.pos) < pickup.pos.distance_squared_to(contexts[b].player.pos))
				target = candidates[0]
		if target < 0: continue
		select_player(target)
		var radius = 24.0 if pickup.kind == "heal" else Effects.ash_radius(self) if pickup.kind == "ash" else 120.0
		if pickup.pos.distance_to(player.pos) > radius and not pickup.magnet and not (mode == "clear" and pickup.kind != "heal"): continue
		pickup.magnet = true
		pickup.pos = pickup.pos.move_toward(player.pos, 650 * delta)
		if pickup.pos.distance_to(player.pos) < 20:
			collect(pickup)
			pickups.erase(pickup)
	flush()

func clear_room() -> void:
	var key = "%s/f%d/r%d/cooperative_clear" % [contexts[0].run.id, int(run.floor), int(run.room)]
	if int(room_flags.get("wave_index", 1)) < int(room_flags.get("wave_count", 1)) or reward_ledger.has(key): return
	reward_ledger[key] = true
	var type = "boss" if room_type() == "optional_boss" else room_type()
	run.coins += maxi(1, int(db.rules.loot.clear_coins.get(type, 0)) - int(type == "combat" and contract("d05")))
	flush()
	for index in 2:
		select_player(index)
		mode = "clear"
		run.cleared += 1
		run.merit += int(db.rules.progression.meta_currency.get(type, 0))
		run.xp += int(db.rules.progression.xp.get(type, 0))
		if stack("r26") > 0: player.armor = 1
		Effects.clear_room(self, type)
		Equipment.charge(self, 2.0 if type == "boss" else 1.0)
		while run.level < db.rules.progression.level_thresholds.size() and run.xp >= db.rules.progression.level_thresholds[int(run.level)]:
			run.level += 1
			choice_queue.append({"kind": "talent", "items": []})
		if type in ["elite", "challenge", "boss"]:
			choice_queue.append({"kind": "relic", "items": challenge_offer(3) if type == "challenge" else relic_offer(2 if type == "boss" else 3)})
		if type == "boss":
			player.max_hp = mini(12, int(player.max_hp) + 1)
			if not player.get("downed", false): player.hp = mini(int(player.max_hp), int(player.hp) + 2)
			if room_type() == "boss": choice_queue.append({"kind": "floor_end", "items": []})
		Equipment.rare_drop(self, "room_clear", "room", geometry.nearest_free(player.pos + Vector2(42, -30), 16))
		open_next_choice()
		choice_serial[index] += 1
		flush()
	bullets = bullets.filter(func(bullet): return bullet.friendly)
	zones = zones.filter(func(zone): return zone.friendly)
	emit("room_clear", {"type": type})
	stamp_entities()

func enter_room() -> void:
	# Initial World.start uses the ordinary room generator before contexts exist.
	if not initialized: super.enter_room(); return
	super.enter_room()
	var new_flags = local_flags(room_flags).duplicate(true)
	scene_serial += 1
	flow_at = [-1.0, -1.0]
	rescue.helper = -1
	sync_route()
	for context in contexts: context._flags = new_flags.duplicate(true)
	var primary_mode = mode
	var initial_choices = choices.duplicate(true)
	var origin = Vector2(player.pos)
	for index in 2:
		select_player(index)
		player.pos = geometry.nearest_free(origin + Vector2(38 * index, 0), 12)
		player.move = Vector2.ZERO
		player.dash_left = 0.0
		player.charge = 0.0
		player.invulnerable = 1.0
		chains.clear()
		pair_cooldowns.clear()
		choice_queue.clear()
		mode = primary_mode
		choices = initial_choices.duplicate(true)
		if primary_mode == "choice" and room_type() in ["reward", "secret"]:
			choices = relic_offer(2, true)
			if room_type() == "reward": choices.append({"kind": "weapon", "id": roll("loot").choose(db.rows("weapons")).id, "price": 0})
		elif room_type() in ["sacrifice", "judge", "angel"]: choices = special_room_choices(room_type())
		choice_serial[index] += 1
		flush()
	stamp_entities()

func check_doors() -> void:
	# All living players must reach the same physical threshold. Downed players
	# stay in the room until rescued; there is no remote map teleport command.
	if not alive(0) or not alive(1): return
	select_player(0)
	if contexts[0].mode == "checkpoint":
		var stair = room_door_position("north")
		if player.pos.distance_to(stair) < 80 and contexts[1].player.pos.distance_to(stair) < 80: next_floor()
		return
	var secret = secret_entry()
	if not secret.is_empty() and Graph.visible(run.graph, int(secret.room)) and player.pos.distance_to(secret.pos) < 70 and contexts[1].player.pos.distance_to(secret.pos) < 70:
		super.advance_room(int(secret.room))
		return
	for door in room_doors():
		if player.pos.distance_to(door.pos) < 70 and contexts[1].player.pos.distance_to(door.pos) < 70:
			super.advance_room(int(door.destination))
			return

func room_doors() -> Array:
	if mode == "checkpoint": return [{"direction": "north", "destination": -1, "pos": room_door_position("north"), "visited": false}]
	return super.room_doors()

func next_floor() -> void:
	select_player(0)
	run.floor += 1
	run.room = 0
	run.graph = Campaign.build(db, run.seed_text, int(run.floor))
	run.room_plan = run.graph.types.duplicate()
	run.visited = []
	run.room_history = {}
	sync_route()
	for context in contexts:
		for debt in context.run.contracts: debt.interest = mini(12, int(debt.interest) + 6)
	enter_room()
	if int(run.floor) == 2:
		for index in 2:
			select_player(index)
			mode = "choice"
			choices = []
			for skill in db.row("characters", run.character).skills.slice(1): choices.append({"kind": "skill", "id": skill, "price": 0})
			choice_serial[index] += 1
			flush()

func take_choice(index: int) -> bool:
	# Skill evolution changes equipment without rebuilding the shared room.
	if mode == "choice" and index >= 0 and index < choices.size() and choices[index].kind == "skill":
		var choice = choices[index]
		player.skill = str(choice.id)
		run.evolved = true
		record_growth_choice("skill", choice.id, "skill", choice.id)
		choices.clear()
		mode = "combat" if not enemies.is_empty() else "clear"
		return true
	return super.take_choice(index)

func full_checkpoint() -> Dictionary:
	stamp_entities()
	flush()
	var data = snapshot()
	data.cooperative = {"contexts": contexts.duplicate(true), "seat": seat, "coins": coins, "scene": scene_serial, "choices": choice_serial.duplicate(), "rescue": rescue.duplicate(true)}
	return data

func recover_cooperation(data: Dictionary) -> bool:
	if not data.get("cooperative", {}).get("contexts") is Array or data.cooperative.contexts.size() != 2: return false
	if not restore(data): return false
	contexts = data.cooperative.contexts.duplicate(true)
	seat = int(data.cooperative.seat)
	coins = int(data.cooperative.coins)
	scene_serial = int(data.cooperative.scene)
	choice_serial = data.cooperative.choices.duplicate()
	rescue = data.cooperative.rescue.duplicate(true)
	initialized = true
	for key in PERSONAL: set(key, contexts[seat][key])
	run.coins = coins
	return true
