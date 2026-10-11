extends "res://scripts/combat/world.gd"
## Existing weapon/skill rules run on the server with another player as target.
var opponent_reference: WeakRef
var opponent:
	get: return opponent_reference.get_ref() if opponent_reference != null else null
	set(value): opponent_reference = weakref(value) if value != null else null
var pending_hits: Array = []
var online_biome: Dictionary = {}
var seat = 0

func region_spec() -> Dictionary:
	return online_biome if not online_biome.is_empty() else super.region_spec()

func initialize_duel(loadout: Dictionary, arena: Dictionary, seed_value: int, seat_value: int) -> void:
	seat = seat_value
	online_biome = arena
	start(str(loadout.character), seed_value, 1, {"weapon": str(loadout.weapon)})
	run.online = true
	run.campaign = true
	run.graph.backgrounds = {"0": 0}
	run.room_plan = ["combat"]
	geometry.build("room_open_1", 1)
	geometry.objects.clear()
	geometry.cells.clear()
	geometry.blocks.clear()
	geometry.baked_cells.clear()
	geometry.configure_biome(arena.id, 0)
	player.pos = geometry.nearest_free(Vector2(340 if seat == 0 else 940, 360), 12)
	player.aim = Vector2.RIGHT if seat == 0 else Vector2.LEFT
	player.facing_direction = player.aim
	player.skill = str(loadout.skill)
	player.max_hp = float(db.row("characters", str(loadout.character)).health) * 24.0
	player.hp = player.max_hp
	player.energy = 100.0
	player.invulnerable = 1.0
	player.push_left = 0.0
	player.push_remaining = Vector2.ZERO
	player.stun_until = 0.0
	player.radius = 12.0
	player.dead = false
	enemies.clear()
	bullets.clear()
	zones.clear()
	delayed.clear()
	pickups.clear()
	events.clear()
	mode = "combat"

func attach_opponent(other) -> void:
	opponent = other
	var target = spawn_enemy("e01", other.player.pos)
	target.uid = 1001 + int(other.seat)
	target.radius = 12.0
	target.online_actor = true
	target.online_character = str(other.run.character)
	target.natural_reward = false
	target.shield_layers = 0
	target.control_resistance = .65
	uid = maxi(uid, 2000 + seat * 1000000)
	sync_opponent()

func sync_opponent() -> void:
	if opponent == null or enemies.is_empty(): return
	var target = enemies[0]
	target.pos = opponent.player.pos
	target.hp = opponent.player.hp
	target.max_hp = opponent.player.max_hp
	target.dead = opponent.player.hp <= 0
	target.aim = opponent.player.aim
	target.online_weapon = opponent.player.weapon
	target.online_player = opponent.player.duplicate(true)

func advance_actor(frame: Dictionary, delta: float) -> void:
	time += delta
	stats.elapsed += delta
	for key in proc_ledger.keys():
		if time > float(proc_ledger[key].expires): proc_ledger.erase(key)
	for key in room_flags.get("composition_ledger", {}).keys():
		if time > float(room_flags.composition_ledger[key]): room_flags.composition_ledger.erase(key)
	for cooldown in ["shot_cd", "skill_cd", "dash_cd", "invulnerable", "guard", "passive_cd", "buffer_dash", "buffer_skill", "item_cd"]:
		player[cooldown] = maxf(0.0, float(player.get(cooldown, 0)) - delta)
	if frame.get("dash", false): player.buffer_dash = .08
	if frame.get("skill", false): player.buffer_skill = .08
	var move = Vector2(frame.get("move", Vector2.ZERO)).limit_length(1)
	var aim = Vector2(frame.get("aim", player.aim))
	if aim.length_squared() > .0001:
		player.aim = aim.normalized()
		player.facing_direction = player.aim
	player.move = move
	player.still = float(player.still) + delta if move.length_squared() < .01 else 0.0
	var locked = time < float(player.get("stun_until", 0))
	if player.buffer_dash > 0 and player.dash_cd <= 0 and not locked:
		var direction = Vector2(frame.get("dash_direction", Vector2.ZERO))
		start_dash(direction if direction.length() > .1 else (move if move.length() > .1 else player.aim))
	var previous = Vector2(player.pos)
	if player.dash_left > 0:
		player.dash_left = maxf(0, float(player.dash_left) - delta)
		player.pos = geometry.slide(player.pos, player.dash_dir * ((160 + 20 * stack("r34")) / .2) * delta, 12)
		if player.dash_left <= .00001:
			begin_pulse("dash_landing")
			Effects.dash_end(self)
	elif not locked:
		var speed = float(db.row("characters", str(run.character)).speed) * stat_multiplier("move_speed") * (1 + .06 * stack("r33"))
		player.pos = geometry.slide(player.pos, move * speed * delta, 12)
	if float(player.get("push_left", 0)) > 0: Impact.tick(self, player, delta)
	player.moved_distance = float(player.moved_distance) + previous.distance_to(player.pos)
	player.energy = minf(100, float(player.energy) + 5.0 * delta)

func advance_attacks(frame: Dictionary, delta: float) -> void:
	sync_opponent()
	update_enemies(delta)
	update_chains()
	if time >= float(player.get("stun_until", 0)):
		if player.buffer_skill > 0 and player.skill_cd <= 0 and cast_skill(): player.buffer_skill = 0.0
		if frame.get("active_item", false): use_active_item()
		shoot_input(bool(frame.get("fire", false)), delta, bool(frame.get("charge_hold", false)), frame.get("device", "") == "touch")
	update_bullets(delta)
	update_zones(delta)
	update_delayed(delta)
	if not enemies.is_empty() and opponent != null:
		opponent.player.stun_until = maxf(float(opponent.player.get("stun_until", 0)), minf(time + .35, float(enemies[0].get("stun_until", 0))))
	if bullets.size() > 120: bullets = bullets.slice(bullets.size() - 120)
	if zones.size() > 64: zones = zones.slice(zones.size() - 64)
	if delayed.size() > 128: delayed = delayed.slice(delayed.size() - 128)

func update_enemies(_delta: float) -> void:
	for target in enemies:
		target.hit_flash = maxf(0, float(target.hit_flash) - _delta)
		if time >= float(target.mark_until): target.mark = 0
		if time >= float(target.burn_until): target.burn = 0
		if int(target.burn) > 0 and time >= float(target.burn_next):
			target.burn_next = time + 1
			begin_pulse("online_burn")
			damage_enemy(target, 3.0 * int(target.burn), "burn")
			Effects.burn_tick(self, target)

func damage_enemy(enemy: Dictionary, amount: float, source: String, crit: bool = false, travel_direction: Vector2 = Vector2.ZERO, push_distance: float = -1) -> void:
	if opponent == null or enemy.dead or not is_finite(amount): return
	if source == "secondary" and not claim_secondary(): return
	if source == "primary" and run.character == "c_bell": amount *= 1 + .05 * mini(3, int(enemy.mark))
	var direction = travel_direction if travel_direction.length_squared() > .0001 else player.pos.direction_to(enemy.pos)
	pending_hits.append({"damage": clampf(amount, 1, 120), "source": source, "crit": crit,
		"direction": direction, "push": Impact.distance(self, source, crit) if push_distance < 0 else push_distance,
		"position": Vector2(enemy.pos), "origin": Vector2(player.pos), "seat": seat})

func damage_player(_amount: int, _source: Dictionary = {}, _incoming = null) -> void:
	# Hazard damage is translated into opposing attacks by the match authority.
	pass

func kill_enemy(_enemy: Dictionary, _source: String) -> void:
	pass

func restore_duel(snapshot: Dictionary, arena: Dictionary, seat_value: int) -> void:
	seat = seat_value
	online_biome = arena
	for key in ["run", "player", "enemies", "bullets", "pickups", "zones", "delayed", "chains", "enemy_ledger", "reward_ledger", "pair_cooldowns", "choices", "choice_queue", "room_flags", "stats", "proc_ledger"]:
		set(key, snapshot[key].duplicate(true))
	for key in ["time", "uid", "attack_uid", "mode", "active_pulse", "pulse_serial"]: set(key, snapshot[key])
	rng.state = int(snapshot.rng)
	streams.clear()
	for key in snapshot.streams:
		var stream = RunRng.new()
		stream.state = int(snapshot.streams[key])
		streams[key] = stream
	geometry.build("room_open_1", 1)
	geometry.objects.clear()
	geometry.cells.clear()
	geometry.blocks.clear()
	geometry.baked_cells.clear()
	geometry.configure_biome(arena.id, 0)
