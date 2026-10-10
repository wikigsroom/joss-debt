extends RefCounted
## Movement presentation only. Health, hits, skills and results stay authoritative.
var state: Dictionary = {}
var correction = Vector2.ZERO
var visual_position = Vector2.ZERO
var ready = false

func clear() -> void:
	state.clear()
	correction = Vector2.ZERO
	ready = false

func from_player(player: Dictionary) -> Dictionary:
	return {"pos": Vector2(player.pos), "dash_left": float(player.dash_left), "dash_cd": float(player.dash_cd), "buffer_dash": float(player.buffer_dash),
		"dash_dir": Vector2(player.dash_dir), "stun_until": float(player.get("stun_until", 0)),
		"push_left": float(player.get("push_left", 0)), "push_remaining": Vector2(player.get("push_remaining", Vector2.ZERO))}

func observe(actor, server_player: Dictionary, history: Array, playing: bool) -> void:
	var old_position = visual_position
	state = from_player(server_player)
	state.time = actor.time
	if playing:
		for input in history: advance(actor, input.frame, float(input.seconds))
	if ready and playing and old_position.distance_to(state.pos) < 140:
		correction = old_position - Vector2(state.pos)
	else:
		correction = Vector2.ZERO
		visual_position = state.pos
	ready = true

func advance(actor, frame: Dictionary, delta: float) -> void:
	if state.is_empty(): return
	state.dash_cd = maxf(0, float(state.dash_cd) - delta)
	state.buffer_dash = maxf(0, float(state.buffer_dash) - delta)
	state.time += delta
	if frame.get("dash", false): state.buffer_dash = .08
	var move = Vector2(frame.get("move", Vector2.ZERO)).limit_length(1)
	var locked = state.time < float(state.stun_until)
	if state.buffer_dash > 0 and state.dash_cd <= 0 and not locked:
		var direction = Vector2(frame.get("dash_direction", Vector2.ZERO))
		if direction.length() < .1: direction = move if move.length() > .1 else Vector2(frame.get("aim", actor.player.aim))
		state.dash_dir = direction.normalized()
		state.dash_left = .2
		state.dash_cd = 2.0 + (.3 if actor.contract("d06") else 0.0)
		state.buffer_dash = 0.0
	if state.dash_left > 0:
		state.dash_left = maxf(0, float(state.dash_left) - delta)
		state.pos = actor.geometry.slide(state.pos, state.dash_dir * ((160 + 20 * actor.stack("r34")) / .2) * delta, 12)
	elif not locked:
		var speed = float(actor.db.row("characters", actor.run.character).speed) * actor.stat_multiplier("move_speed") * (1 + .06 * actor.stack("r33"))
		state.pos = actor.geometry.slide(state.pos, move * speed * delta, 12)
	if state.push_left > 0:
		var fraction = 1.0 - pow(maxf(0, float(state.push_left) - delta) / float(state.push_left), 2)
		var displacement = Vector2(state.push_remaining) * fraction
		state.pos = actor.geometry.slide(state.pos, displacement, 12)
		state.push_remaining -= displacement
		state.push_left = maxf(0, float(state.push_left) - delta)
		if state.push_left <= .000001: state.push_left = 0.0; state.push_remaining = Vector2.ZERO

func tick(actor, frame: Dictionary, delta: float, playing: bool) -> void:
	if not ready: return
	if playing and actor.player.hp > 0: advance(actor, frame, delta)
	correction *= exp(-20 * delta)
	visual_position = actor.geometry.constrain_floor(Vector2(state.pos) + correction, 12)
	actor.player.pos = visual_position
	if playing:
		actor.player.move = Vector2(frame.get("move", Vector2.ZERO))
		var aim = Vector2(frame.get("aim", actor.player.aim))
		if not aim.is_zero_approx(): actor.player.aim = aim; actor.player.facing_direction = aim
