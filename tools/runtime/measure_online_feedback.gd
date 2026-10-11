extends "res://scripts/ui/cooperative_native_qa.gd"
## External observer of the exported game's real rendering and keyboard input.
## No authority edits, fabricated entities, HP changes or prediction calls.
var render_intervals: Array = []
var draw_durations: Array = []
var npc_counts: Array = []
var movement_latencies: Array = []
var shot_latencies: Array = []
var last_render_at = 0
var observing = false
var capture_busy = false
var skip_frames = 0
var probe: Dictionary = {}

func _ready() -> void:
	super._ready()
	RenderingServer.frame_post_draw.connect(rendered)

func rendered() -> void:
	var now = Time.get_ticks_usec()
	if not observing or capture_busy or skip_frames > 0 or not app.online.session.can_play() or app.screen != "game" or app.paused:
		last_render_at = 0
		skip_frames = maxi(0, skip_frames - 1)
		return
	if last_render_at > 0:
		render_intervals.append((now - last_render_at) / 1000.0)
		draw_durations.append(float(app.renderer.last_draw_us) / 1000.0)
		npc_counts.append(app.world.enemies.size())
	last_render_at = now
	if not probe.is_empty():
		var shown = app.world.player.pos.distance_to(probe.position) > .05 if probe.kind == "move" else app.online.attack_prediction.serial > probe.serial
		if shown:
			var elapsed = (now - int(probe.started)) / 1000.0
			if probe.kind == "move": movement_latencies.append(elapsed)
			else: shot_latencies.append(elapsed)
			probe = {}

func keyboard_probe(code: int, kind: String) -> void:
	probe = {"kind": kind, "started": Time.get_ticks_usec(), "position": Vector2(app.world.player.pos), "serial": app.online.attack_prediction.serial}
	var event = InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	Input.parse_input_event(event)
	var seen = await until(func(): return probe.is_empty(), .2)
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event)
	expect("visible_local_%s_%d" % [kind, movement_latencies.size() if kind == "move" else shot_latencies.size()], seen)
	probe = {}
	await frames(2)

func capture(name_value: String) -> void:
	capture_busy = true
	await super.capture(name_value)
	capture_busy = false; skip_frames = 3
	if name_value == "coop-combat":
		observing = true
		await frames(5)
		for index in 8:
			await until(func(): return app.online.session.can_play() and app.online.attack_prediction.cooldown < .001, 1)
			var position = Vector2(app.world.player.pos)
			var direction = Vector2.RIGHT if index % 2 == 0 else Vector2.LEFT
			if not app.world.geometry.clear_swept_segment(position, position + direction * 25, 12): direction = -direction
			await keyboard_probe(KEY_D if direction.x > 0 else KEY_A, "move")
			await keyboard_probe(KEY_UP, "shot")
	elif name_value == "coop-wide-touch":
		# Sample actual rendered cooperative combat without PNG readback for this
		# interval. The inherited fixture drives both normal players and real NPCs.
		await get_tree().create_timer(6).timeout

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted = values.duplicate(); sorted.sort()
	return float(sorted[mini(sorted.size() - 1, ceili(sorted.size() * fraction) - 1)])

func finish() -> void:
	observing = false
	var report = {"scope": "Actual Windows EXE pack, OpenGL native rendering, two real cooperative clients and injected keyboard events. Measurements exclude PNG capture, resize, menus and scene loading; no physical Android claim.",
		"samples": render_intervals.size(), "render_frame_p95_ms": percentile(render_intervals, .95), "render_frame_p99_ms": percentile(render_intervals, .99),
		"renderer_draw_p95_ms": percentile(draw_durations, .95), "renderer_draw_p99_ms": percentile(draw_durations, .99),
		"frames_with_npcs": npc_counts.filter(func(count): return count > 0).size(), "max_visible_npcs": npc_counts.max() if not npc_counts.is_empty() else 0,
		"movement_to_visible_frame_ms": movement_latencies, "shot_to_visible_frame_ms": shot_latencies,
		"movement_p95_ms": percentile(movement_latencies, .95), "shot_p95_ms": percentile(shot_latencies, .95),
		"physical_android_tested": false, "virtualization": "none"}
	report.passed = movement_latencies.size() == 8 and shot_latencies.size() == 8 and report.movement_p95_ms <= 33.5 and report.shot_p95_ms <= 33.5 and render_intervals.size() >= 180
	var file = FileAccess.open(directory.path_join("render-input.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	expect("local_feedback_within_two_frames", report.passed, JSON.stringify(report))
	super.finish()
