extends RefCounted
const Actor = preload("res://scripts/network/duel_actor.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Content = preload("res://scripts/core/content_db.gd")
const RandomStream = preload("res://scripts/core/run_rng.gd")
const DRAFT_POOL = ["r01", "r03", "r05", "r06", "r08", "r19", "r20", "r27", "r33", "r34", "r35", "r38", "r39", "r40", "r41", "r42", "r43", "r44", "r47", "r48", "r55", "r56", "r57", "r58", "r59", "r60", "r61", "r62", "r63", "r64", "r65", "r66"]
var db = Content.new()
var id = ""
var seed_value = 1
var phase = "draft"
var round_index = 1
var tick_index = 0
var remaining = 120.0
var countdown = 3.0
var round_break = 4.0
var draft_remaining = 30.0
var score = [0, 0]
var loadouts: Array = []
var builds: Array = [[], []]
var offers: Array = [[], []]
var picked = [-1, -1]
var actors: Array = []
var arena: Dictionary = {}
var events: Array = []
var event_serial = 0
var winner = -1
var round_winner = -1
var reason = ""
var random

func begin(match_id: String, players: Array, seed_input: int) -> void:
	id = match_id
	seed_value = seed_input
	loadouts = players.duplicate(true)
	random = RandomStream.new(seed_value)
	prepare_draft()

func prepare_draft() -> void:
	phase = "draft"
	draft_remaining = 30.0
	picked = [-1, -1]
	for seat in 2:
		var available = DRAFT_POOL.filter(func(id): return builds[seat].count(id) < int(db.row("relics", id).get("stack_limit", 1)))
		offers[seat] = random.shuffle(available).slice(0, 4)
	push_event("draft", {"round": round_index})

func choose(seat: int, index: int) -> bool:
	if phase != "draft" or seat not in [0, 1] or index < 0 or index >= 4 or picked[seat] >= 0: return false
	picked[seat] = index
	builds[seat].append(offers[seat][index])
	if picked[0] >= 0 and picked[1] >= 0: start_round()
	return true

func start_round() -> void:
	arena = random.choose(db.expansion.biomes).duplicate(true)
	actors.clear()
	for seat in 2:
		var actor = Actor.new()
		actor.initialize_duel(loadouts[seat], arena, seed_value + round_index * 29, seat)
		for relic in builds[seat]: actor.run.relics[relic] = int(actor.run.relics.get(relic, 0)) + 1
		actor.player.max_hp += float(actor.stat_bonus("max_health")) * 24
		actor.player.hp = actor.player.max_hp
		actors.append(actor)
	for seat in 2: actors[seat].attach_opponent(actors[1 - seat])
	remaining = 120.0
	countdown = 3.0
	phase = "countdown"
	push_event("round_start", {"round": round_index, "arena": arena.id})

func advance(frames: Array, delta: float = 1.0 / 60.0) -> void:
	if phase == "finished": return
	if phase == "draft":
		draft_remaining = maxf(0, draft_remaining - delta)
		if draft_remaining <= 0:
			for seat in 2:
				if picked[seat] < 0: choose(seat, 0)
		return
	if phase == "countdown":
		countdown = maxf(0, countdown - delta)
		if countdown <= 0:
			phase = "playing"
			push_event("fight", {"round": round_index})
		return
	if phase == "round_result":
		round_break -= delta
		if round_break <= 0:
			round_index += 1
			prepare_draft()
		return
	tick_index += 1
	remaining = maxf(0, remaining - delta)
	for seat in 2: actors[seat].advance_actor(frames[seat], delta)
	for seat in 2: actors[seat].advance_attacks(frames[seat], delta)
	for seat in 2:
		var pending: Array = actors[seat].pending_hits
		if not pending.is_empty():
			var combined = pending[0].duplicate(true)
			combined.damage = 0.0
			for hit in pending:
				combined.damage += float(hit.damage)
				combined.crit = combined.crit or hit.crit
				if hit.source == "detonate": combined.source = "detonate"
			combined.damage = minf(120, combined.damage)
			apply_hit(combined)
		actors[seat].pending_hits.clear()
	for seat in 2:
		actors[seat].sync_opponent()
		for event in actors[seat].take_events():
			if event.kind in ["save_requested", "run_end"]: continue
			event.seat = seat
			push_event("combat", event)
	var alive_a = actors[0].player.hp > 0
	var alive_b = actors[1].player.hp > 0
	if not alive_a or not alive_b:
		finish_round(0 if alive_a else (1 if alive_b else -1), "defeat")
	elif remaining <= 0:
		var health_a = float(actors[0].player.hp) / actors[0].player.max_hp
		var health_b = float(actors[1].player.hp) / actors[1].player.max_hp
		finish_round(-1 if absf(health_a - health_b) < .0001 else (0 if health_a > health_b else 1), "time")

func apply_hit(hit: Dictionary) -> void:
	var target = actors[1 - int(hit.seat)]
	var player = target.player
	if float(player.invulnerable) > 0: return
	var guarded = float(player.guard) > 0 and Vector2(player.aim).dot(Vector2(player.pos).direction_to(hit.origin)) > -.1
	if guarded:
		target.emit("deflect", {"pos": player.pos})
		target.Effects.deflect(target)
		if hit.source == "primary": target.secondary_bullet(player.pos, Vector2(player.pos).direction_to(hit.origin), float(hit.damage) * .45)
		return
	var damage = float(hit.damage)
	if int(player.armor) > 0:
		player.armor = 0
		target.Effects.armor_break(target)
		damage *= .5
		target.emit("armor_break", {"pos": player.pos})
	player.hp = maxf(0, float(player.hp) - damage)
	player.dead = player.hp <= 0
	player.invulnerable = .075
	player.visual_hurt_at = target.time
	if player.dead: player.visual_death_at = target.time
	target.stats.damage_taken += damage
	var attacker = actors[int(hit.seat)]
	if attacker.run.character == "c_paper" and hit.source == "primary" and attacker.time >= float(attacker.player.get("online_energy_at", 0)):
		attacker.player.energy = minf(100, float(attacker.player.energy) + 2)
		attacker.player.online_energy_at = attacker.time + .25
	var push = Vector2(hit.direction).normalized() * clampf(float(hit.push) * .35, 0, 30)
	player.push_remaining = (Vector2(player.push_remaining) + push).limit_length(45)
	player.push_left = .12 if not player.push_remaining.is_zero_approx() else 0.0
	target.emit("player_hurt", {"pos": player.pos, "hp": player.hp, "damage": damage, "direction": -Vector2(hit.direction)})
	actors[int(hit.seat)].emit("hit", {"pos": player.pos, "uid": 1001 + target.seat, "damage": damage,
		"source": hit.source, "crit": hit.crit, "heavy": hit.source == "detonate",
		"weapon": actors[int(hit.seat)].player.weapon,
		"weapon_mode": db.row("weapons", actors[int(hit.seat)].player.weapon).mode})

func finish_round(seat: int, cause: String) -> void:
	round_winner = seat
	if seat >= 0: score[seat] += 1
	phase = "round_result"
	round_break = 4.0
	push_event("round_result", {"winner": seat, "reason": cause, "score": score.duplicate()})
	if score[0] >= 2 or score[1] >= 2 or round_index >= 5:
		finish(-1 if score[0] == score[1] else (0 if score[0] > score[1] else 1), "completed")

func finish(seat: int, cause: String) -> void:
	if phase == "finished": return
	winner = seat
	reason = cause
	phase = "finished"
	push_event("finished", {"winner": winner, "reason": reason, "score": score.duplicate()})

func push_event(kind: String, data: Dictionary = {}) -> void:
	event_serial += 1
	var entry = data.duplicate(true)
	entry.event_id = event_serial
	entry.event_type = kind
	entry.tick = tick_index
	events.append(entry)
	if events.size() > 160: events.pop_front()

func actor_view(actor) -> Dictionary:
	return {"run": actor.run.duplicate(true), "player": actor.player.duplicate(true), "time": actor.time,
		"bullets": actor.bullets.duplicate(true), "zones": actor.zones.duplicate(true),
		"enemies": actor.enemies.duplicate(true), "chains": actor.chains.duplicate(true),
		"delayed": actor.delayed.duplicate(true), "room_flags": actor.room_flags.duplicate(true), "stats": actor.stats.duplicate(true)}

func view(seat: int, since_event: int = 0) -> Dictionary:
	var views: Array = []
	for actor in actors: views.append(actor_view(actor))
	return {"id": id, "phase": phase, "round": round_index, "tick": tick_index, "remaining": remaining, "draft_remaining": draft_remaining,
		"countdown": countdown, "score": score.duplicate(), "round_winner": round_winner,
		"winner": winner, "reason": reason, "arena": arena, "players": loadouts,
		"offers": offers[seat].duplicate(), "picked": picked.duplicate(), "builds": builds.duplicate(true),
		"actors": views, "events": events.filter(func(event): return int(event.event_id) > since_event), "event_serial": event_serial}

func checkpoint() -> Dictionary:
	var data = {"id": id, "seed": seed_value, "phase": phase, "round": round_index, "tick": tick_index,
		"remaining": remaining, "countdown": countdown, "round_break": round_break, "draft_remaining": draft_remaining, "score": score,
		"loadouts": loadouts, "builds": builds, "offers": offers, "picked": picked, "arena": arena,
		"winner": winner, "round_winner": round_winner, "reason": reason,
		"rng": random.state, "event_serial": event_serial, "events": events, "actors": []}
	for actor in actors: data.actors.append(actor.snapshot())
	return data

func recover(data: Dictionary) -> bool:
	if data.get("loadouts", []).size() != 2 or data.get("actors", []).size() not in [0, 2]: return false
	id = str(data.id)
	seed_value = int(data.seed)
	phase = str(data.phase)
	round_index = int(data.round)
	tick_index = int(data.tick)
	remaining = float(data.remaining)
	draft_remaining = float(data.get("draft_remaining", 30))
	countdown = float(data.countdown)
	round_break = float(data.round_break)
	score = data.score.duplicate()
	loadouts = data.loadouts.duplicate(true)
	builds = data.builds.duplicate(true)
	offers = data.offers.duplicate(true)
	picked = data.picked.duplicate()
	arena = data.arena.duplicate(true)
	winner = int(data.winner)
	round_winner = int(data.round_winner)
	reason = str(data.reason)
	random = RandomStream.new()
	random.state = int(data.rng)
	event_serial = int(data.event_serial)
	events = data.events.duplicate(true)
	actors.clear()
	for seat in data.actors.size():
		var actor = Actor.new()
		actor.restore_duel(data.actors[seat], arena, seat)
		actors.append(actor)
	for seat in actors.size():
		actors[seat].opponent = actors[1 - seat]
		actors[seat].sync_opponent()
	return true
