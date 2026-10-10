extends SceneTree
## Runs the real menu, room renderer and touch input on a native surface, never an emulator.
var app
var directory = ""
var baseline = false
var dpi = 400.0
var cutout_side = "none"
var checks: Array = []
var captures: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--display-output="): directory = argument.trim_prefix("--display-output=")
		if argument.begins_with("--display-dpi="): dpi = float(argument.trim_prefix("--display-dpi="))
		if argument.begins_with("--display-cutout="): cutout_side = argument.trim_prefix("--display-cutout=")
		if argument == "--display-baseline": baseline = true
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func expect(id: String, passed: bool, detail = "") -> void:
	checks.append({"id": id, "passed": passed, "detail": str(detail)})
	if not passed: print("DISPLAY QA FAIL: ", id, " ", detail)

func frames(count: int = 3) -> void:
	for i in count:
		app._process(0)
		app.update_hud()
		app.renderer.queue_redraw()
		await process_frame

func capture(id: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var saved = image.save_png(directory.path_join(id + ".png")) == OK
	captures.append({"name": id, "size": [image.get_width(), image.get_height()]})
	expect("capture/" + id, saved)

func touch(id: int, point: Vector2, down: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id; event.position = root.get_final_transform() * point; event.pressed = down
	Input.parse_input_event(event)
	await frames(2)

func controls(node: Node, found: Array) -> void:
	if node is Button and node.is_visible_in_tree(): found.append(node)
	for child in node.get_children(): controls(child, found)

func check_menu(id: String) -> void:
	var buttons: Array = []
	controls(app.modal, buttons)
	var safe = app.adapter.safe_rect.grow(6)
	var complete = not buttons.is_empty()
	for button in buttons:
		var rect = button.get_global_rect()
		var parent = button.get_parent()
		while parent != null:
			if parent is ScrollContainer: rect = rect.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if rect.has_area(): complete = complete and safe.grow(.2).encloses(rect)
	expect("menu/" + id + "/safe-buttons", complete)

func run() -> void:
	app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.qa_capture_enabled = false; app.qa_active = true
	app.set_physics_process(false); app.set_process(false); app.audio.set_muted(true)
	if not baseline:
		app.qa_display_dpi = dpi
		var pixels = Vector2(DisplayServer.window_get_size())
		if cutout_side != "none":
			var left = 72.0 if cutout_side in ["left", "punch-left"] else 0.0
			app.qa_display_safe = Rect2(0, 0, pixels.x, pixels.y) if cutout_side == "punch-left" else Rect2(left, 0, pixels.x - 72, pixels.y - 24)
			app.qa_display_cutouts = [Rect2(8 if cutout_side in ["left", "punch-left"] else pixels.x - 56, pixels.y * .46, 48, 48)]
	app.apply_safe_area(dpi)
	app.world.start("c_paper", 20261011)
	app.world.enemies.clear(); app.world.bullets.clear(); app.world.zones.clear(); app.world.take_events()
	app.renderer.hub = false; app.renderer.reduce_motion = true
	app.renderer.set_process(false); app.renderer.clock = 1.25; app.renderer.position = Vector2.ZERO
	app.screen = "game"; app.paused = false; app.world.mode = "combat"
	app.clear_modal(); app.hud.visible = true; app.notice_left = 0
	app.adapter.touch_mode = true; app.adapter.fixed_sticks = true
	app.adapter.set_phase("combat", false); app.update_hud()
	await capture("combat")
	if not baseline:
		var surface = Rect2(Vector2.ZERO, root.get_visible_rect().size)
		var arena = app.renderer.arena_transform * Rect2(0, 0, 1280, 720)
		expect("complete-room-in-safe-area", app.adapter.safe_rect.grow(6.2).encloses(arena))
		expect("uniform-room-scale", is_equal_approx(app.renderer.arena_transform.x.length(), app.renderer.arena_transform.y.length()))
		expect("valid-touch-layout", app.adapter.valid_layout())
		var split = app.adapter.safe_rect.get_center().x
		var right_actions = app.adapter.control_center("move").x + app.adapter.control_radius("move") < split
		for action in ["aim", "dash", "skill", "active_item"]:
			right_actions = right_actions and app.adapter.control_center(action).x - app.adapter.control_radius(action) > split
		expect("default-left-movement-right-combat", right_actions)
		if cutout_side == "punch-left":
			expect("punch-hole-reserved-with-full-os-safe-rect", app.adapter.safe_rect.position.x >= 56 / root.get_screen_transform().x.length())
		for action in ["move", "aim", "dash", "skill", "active_item"]:
			var r = app.adapter.control_radius(action)
			expect("safe-touch/" + action, app.adapter.safe_rect.encloses(Rect2(app.adapter.control_center(action) - Vector2.ONE * r, Vector2.ONE * r * 2)))
		for point in [Vector2(640, 360), Vector2(64, 360), Vector2(1216, 360), Vector2(640, 72), Vector2(640, 648)]:
			expect("world-input-roundtrip/" + str(point), app.renderer.to_world(app.renderer.stage * point).distance_to(point) < .02)
		for child in app.hud.get_children():
			if child is Button and child.has_meta("hud_action"):
				expect("safe-hud/" + str(child.get_meta("hud_action")), app.adapter.safe_rect.grow(6).encloses(child.get_global_rect()))
				expect("48dp-hud/" + str(child.get_meta("hud_action")), child.get_global_rect().size.x * root.get_screen_transform().x.length() * 160 / dpi >= 47.99)
		await touch(30, app.adapter.control_center("move"), true)
		expect("real-move-input", app.adapter.move_id == 30)
		await touch(31, app.adapter.control_center("aim"), true)
		expect("real-aim-input", app.adapter.aim_id == 31 and app.adapter.move_id == 30)
		await touch(30, app.adapter.control_center("move"), false)
		await touch(31, app.adapter.control_center("aim"), false)
		expect("real-touch-release", app.adapter.move_id == -1 and app.adapter.aim_id == -1)
		if cutout_side != "none":
			var state = JSON.stringify(app.Store.encode(app.world.snapshot()))
			var previous_layout = app.adapter.layout.duplicate(true)
			await touch(32, app.adapter.control_center("move"), true)
			var pixels = Vector2(DisplayServer.window_get_size())
			var next_left = 72.0 if cutout_side == "right" else 0.0
			app.qa_display_safe = Rect2(next_left, 0, pixels.x - 72, pixels.y - 24)
			app.qa_display_cutouts = [Rect2(8 if cutout_side == "right" else pixels.x - 56, pixels.y * .46, 48, 48)]
			app.apply_safe_area(dpi)
			expect("rotation-releases-owned-touch", app.adapter.move_id == -1 and app.adapter.aim_id == -1)
			expect("rotation-preserves-run-and-layout", state == JSON.stringify(app.Store.encode(app.world.snapshot())) and previous_layout == app.adapter.layout)
			await capture("rotated-combat")
	app.show_pause(); await frames()
	if not baseline: check_menu("pause")
	await capture("pause")
	app.show_menu("splash"); await frames()
	if not baseline: check_menu("splash")
	await capture("splash")
	app.show_menu("files"); await frames()
	if not baseline: check_menu("files")
	await capture("files")
	app.show_menu("title"); await frames()
	if not baseline: check_menu("title")
	await capture("title")
	app.world.choices = [{"kind":"relic", "id":"r01", "price":0, "slot":"display1"}, {"kind":"relic", "id":"r02", "price":0, "slot":"display2"}, {"kind":"relic", "id":"r03", "price":0, "slot":"display3"}, {"kind":"relic", "id":"r04", "price":0, "slot":"display4"}]
	app.world.mode = "choice"; app.screen = "game"; app.show_mobile_choice(); await frames()
	if not baseline: check_menu("skill-choice")
	await capture("skill-choice")
	var passed = checks.all(func(row): return row.passed)
	var file = FileAccess.open(directory.path_join("native.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "baseline": baseline, "checks": checks,
		"captures": captures, "physical_pixels": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"viewport": str(root.get_visible_rect()), "safe_area": str(app.adapter.safe_rect), "cutout": cutout_side,
		"dpi": dpi, "version": ProjectSettings.get_setting("application/config/version"),
		"scope": "Native desktop graphics, real touch dispatch, simulated handset dimensions/insets; no physical Android claim"}, "\t"))
	file.close()
	print("DISPLAY QA: ", checks.size(), " checks, ", captures.size(), " captures; passed=", passed)
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(.25).timeout
	quit(0 if passed else 1)
