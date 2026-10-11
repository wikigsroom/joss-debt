extends RefCounted
const World = preload("res://scripts/network/cooperative_world.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var world = World.new()
var id = ""
var phase = "countdown"
var countdown = 3.0
var tick_index = 0
var loadouts: Array = []
var events: Array = []
var event_serial = 0
var winner = -1
var reason = ""
var resume_phase = "playing"

func begin(match_id: String, players: Array, seed_input: int) -> void:
	id = match_id
	loadouts = players.duplicate(true)
	world.begin_cooperation(loadouts, seed_input)
	push_event("cooperative_start", {"seed": seed_input})

func choice_token(seat: int) -> String:
	return "%s/%d/%d" % [id, seat, world.choice_serial[seat]]

func choose(seat: int, index: int) -> bool:
	if phase != "draft" or seat not in [0, 1]: return false
	world.select_player(seat)
	if not world.take_choice(index): return false
	world.choice_serial[seat] += 1
	world.flush()
	collect_events()
	sync_phase()
	return true

func action(seat: int, operation: String, value: String = "") -> bool:
	if seat not in [0, 1]: return false
	if operation != "repay" and phase != "draft": return false
	world.select_player(seat)
	match operation:
		"repay":
			if phase != "playing" or world.mode != "checkpoint": return false
			var index = world.run.contracts.find_custom(func(contract): return str(contract.id) == value)
			if not world.repay(index): return false
		"skip":
			if world.mode not in ["choice", "shop", "debt"] or not world.choices.is_empty() and world.choices[0].kind == "skill": return false
			# Special rooms finish for this player; teammate still chooses separately.
			world.skip_choice()
		"reroll":
			if not world.reroll(): return false
		"replace":
			if not world.replace_relic(value): return false
		_:
			return false
	world.choice_serial[seat] += 1
	world.flush()
	collect_events()
	sync_phase()
	return true

func sync_phase() -> void:
	world.flush()
	if not world.alive(0) and not world.alive(1): finish(-1, "team_defeat"); return
	if world.contexts.all(func(context): return context.run.get("result", "") == "victory"):
		finish(2, "team_victory")
		return
	phase = "draft" if world.contexts.any(func(context): return context.mode in ["choice", "shop", "debt", "replace"]) else "playing"

func advance(frames: Array, delta: float = 1.0 / 60.0) -> void:
	if phase == "finished": return
	if phase == "countdown":
		countdown = maxf(0, countdown - delta)
		if countdown <= 0: sync_phase()
		return
	if phase == "draft": return
	tick_index += 1
	world.step(frames, delta)
	collect_events()
	sync_phase()

func collect_events() -> void:
	for event in world.take_events():
		if event.kind in ["save_requested", "run_end"]: continue
		push_event("combat", event)

func push_event(kind: String, data: Dictionary = {}) -> void:
	event_serial += 1
	var entry = data.duplicate(true)
	entry.event_id = event_serial
	entry.event_type = kind
	entry.tick = tick_index
	events.append(entry)
	if events.size() > 160: events.pop_front()

func finish(result: int, cause: String) -> void:
	if phase == "finished": return
	winner = 2 if result == 2 else -1
	reason = cause
	phase = "finished"
	push_event("finished", {"winner": winner, "reason": reason})

func view(seat: int, since_event: int = 0, replication: bool = false, shared = null) -> Dictionary:
	if shared == null: shared = {}
	world.flush()
	var views: Array = shared.get("actors", [])
	for index in (0 if not views.is_empty() else 2):
		var context = world.contexts[index]
		var visible_run = context.run.duplicate(not replication)
		for key in ["room_history", "damage_history", "relic_pool", "growth_log"]: visible_run.erase(key)
		visible_run.coins = world.coins
		views.append({"run": visible_run, "player": context.player.duplicate(true), "time": world.time,
			"bullets": [], "zones": [], "enemies": [], "chains": context.chains.duplicate(true), "delayed": [], "room_flags": context.get("_flags", {}).duplicate(true), "stats": context.stats.duplicate(true)})
	var context = world.contexts[seat]
	var offers: Array = []
	for entry in context.choices:
		world.select_player(seat)
		var offer = entry.duplicate(true)
		offer.reason = world.choice_reason(entry)
		offers.append(offer)
	world.select_player(0)
	shared.actors = views
	var shared_flags: Dictionary = {}
	for key in world.SHARED_FLAGS:
		if world.room_flags.has(key): shared_flags[key] = world.room_flags[key]
	var scene: Dictionary = shared.get("scene", {})
	if scene.is_empty():
		scene = {"serial": world.scene_serial, "mode": "clear" if world.contexts.all(func(player): return player.mode in ["clear", "checkpoint"]) else "combat",
			"template": world.geometry.template_id, "objects": world.geometry.objects.duplicate(not replication), "pickups": world.pickups.duplicate(not replication),
			"enemies": presentation_entities(world.enemies, ["attack_history"], not replication), "bullets": presentation_entities(world.bullets, ["recipe", "hits", "pulse", "attack"], not replication), "zones": presentation_entities(world.zones, ["recipe", "hits", "pulse"], not replication),
			"delayed": presentation_entities(world.delayed.filter(func(action): return action.type == "debt_bullet"), ["pair"], not replication), "flags": shared_flags.duplicate(true), "stairs": world.contexts[0].mode == "checkpoint", "rescue": world.rescue.duplicate(true)}
		shared.scene = scene
	if not shared.has("builds"): shared.builds = world.contexts.map(func(player): return player.run.growth_log.duplicate(not replication))
	return {"id": id, "game_mode": "coop", "phase": phase, "round": int(world.run.floor), "tick": tick_index, "remaining": world.time,
		"countdown": countdown, "score": [int(world.run.cleared), int(world.run.cleared)], "winner": winner, "reason": reason,
		"arena": world.region_spec().duplicate(true), "players": loadouts.duplicate(true), "actors": views, "scene": scene,
		"offers": offers, "choice_mode": context.mode, "choice_token": choice_token(seat), "replacement": context.run.get("replacement", {}).duplicate(true),
		"picked": world.contexts.map(func(player): return -1 if player.mode in ["choice", "shop", "debt", "replace"] else 0),
		"builds": shared.builds,
		"events": events.filter(func(event): return int(event.event_id) > since_event), "event_serial": event_serial}

static func presentation_entities(entities: Array, private_keys: Array, deep: bool = true) -> Array:
	# Simulation recipes, victim ledgers and delayed skill payloads remain in the
	# durable checkpoint; replicas receive the fields their renderer actually uses.
	var result: Array = []
	for entity in entities:
		var visible = entity.duplicate(deep)
		for key in private_keys: visible.erase(key)
		result.append(visible)
	return result

func checkpoint() -> Dictionary:
	return {"mode": "coop", "id": id, "phase": phase, "countdown": countdown, "tick": tick_index, "loadouts": loadouts.duplicate(true),
		"winner": winner, "reason": reason, "events": events.duplicate(true), "event_serial": event_serial, "world": world.full_checkpoint()}

func recover(data: Dictionary) -> bool:
	if data.get("mode") != "coop" or data.get("loadouts", []).size() != 2 or not world.recover_cooperation(data.get("world", {})): return false
	id = str(data.id)
	phase = str(data.phase)
	countdown = float(data.countdown)
	tick_index = int(data.tick)
	loadouts = data.loadouts.duplicate(true)
	winner = int(data.winner)
	reason = str(data.reason)
	events = data.events.duplicate(true)
	event_serial = int(data.event_serial)
	return true
