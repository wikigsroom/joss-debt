extends SceneTree
## Audit observations, not a replacement for physical Android acceptance.
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const World = preload("res://scripts/combat/world.gd")
var observations: Array = []
var report_dir = ""
var app

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audit-output="): report_dir = argument.trim_prefix("--audit-output=")
	if report_dir.is_empty(): report_dir = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/mobile-audit-2026-10-09")
	DirAccess.make_dir_recursive_absolute(report_dir)
	call_deferred("run_audit")

func touch(adapter, id: int, point: Vector2, pressed: bool = true) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = pressed
	adapter.event(event)

func drag(adapter, id: int, point: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = id
	event.position = point
	adapter.event(event)

func frame(adapter) -> Dictionary:
	return adapter.sample(Vector2.ZERO, Vector2.ZERO)

func record(id: String, confirmed: bool, data: Dictionary) -> void:
	observations.append({"id": id, "confirmed": confirmed, "observed": data})

func run_audit() -> void:
	var adapter = Adapter.new()
	touch(adapter, 1, Vector2(145, 570))
	drag(adapter, 1, Vector2(215, 570))
	touch(adapter, 2, Vector2(880, 560))
	drag(adapter, 2, Vector2(950, 560))
	var before = frame(adapter)
	touch(adapter, 2, Vector2(950, 560), false)
	touch(adapter, 2, adapter.dash_center())
	var after = frame(adapter)
	record("two_thumbs_dash_interrupts_fire", before.fire and not after.fire and after.dash and after.move.length() > .9,
		{"before_fire": before.fire, "after_fire": after.fire, "dash": after.dash, "move_preserved": after.move.length() > .9})
	var world = World.new()
	world.start("c_paper", 20261009)
	var charged = world.db.rows("weapons").filter(func(row): return row.mode == "nova")
	world.player.weapon = charged[0].id
	world.player.shot_cd = 0.0
	world.shoot_input(before.fire, .4)
	var charge_before = world.player.charge
	world.shoot_input(after.fire, 1.0 / 60.0)
	record("button_switch_discards_charge", charge_before > .39 and world.player.charge == 0,
		{"weapon": charged[0].id, "charge_before": charge_before, "charge_after": world.player.charge})
	adapter.clear()
	adapter.deadzone = .32
	adapter.aim = Vector2.UP
	touch(adapter, 3, Vector2(880, 560))
	drag(adapter, 3, Vector2(897.5, 560))
	var deadzone_frame = frame(adapter)
	record("fire_inside_aim_deadzone", deadzone_frame.fire and deadzone_frame.aim == Vector2.UP,
		{"deadzone": .32, "stick_length": adapter.aim_touch.length(), "aim": str(deadzone_frame.aim), "fire": deadzone_frame.fire})
	adapter.clear()
	adapter.deadzone = .18
	adapter.fixed_sticks = true
	touch(adapter, 4, Vector2(1140, 280))
	var away = frame(adapter)
	record("fixed_aim_captures_far_from_visible_stick", adapter.aim_id == 4 and away.fire,
		{"distance_from_stick": Vector2(1140, 280).distance_to(adapter.control_center("aim")), "stick_radius": adapter.control_radius("aim"), "fire": away.fire})
	adapter.clear()
	adapter.fixed_sticks = false
	var start = adapter.dash_center() - Vector2(95, 0)
	touch(adapter, 5, start)
	drag(adapter, 5, adapter.dash_center())
	var slid = frame(adapter)
	record("sliding_aim_onto_dash_does_not_dash", slid.fire and not slid.dash and adapter.aim_id == 5,
		{"fire": slid.fire, "dash": slid.dash, "floating_origin": str(adapter.right_origin),
		"overlaps_dash": adapter.right_origin.distance_to(adapter.dash_center()) < adapter.control_radius("aim") + adapter.control_radius("dash")})
	adapter.clear()
	touch(adapter, 6, Vector2(100, 180))
	record("move_capture_includes_upper_playfield", adapter.move_id == 6, {"pressed_point": "(100, 180)", "move_id": adapter.move_id})
	adapter.clear()
	adapter.fixed_sticks = true
	var moved_layout = adapter.move_control("aim", Vector2(.39, .66))
	touch(adapter, 16, adapter.control_center("aim"))
	var crossed = frame(adapter)
	record("custom_aim_crosses_half_screen_but_captures_move", moved_layout and adapter.move_id == 16 and adapter.aim_id == -1,
		{"layout_accepted": moved_layout, "aim_center": str(adapter.control_center("aim")), "move_id": adapter.move_id,
		"aim_id": adapter.aim_id, "movement": str(crossed.move), "fire": crossed.fire})
	adapter.configure({})
	touch(adapter, 7, Vector2(880, 560))
	drag(adapter, 7, Vector2(950, 560))
	touch(adapter, 7, Vector2(950, 560), false)
	var released = frame(adapter)
	record("ordinary_release_stops_attack", not released.fire and adapter.aim_id == -1, {"fire": released.fire, "aim_id": adapter.aim_id})
	adapter.clear()
	touch(adapter, 8, Vector2(145, 570))
	drag(adapter, 8, Vector2(215, 570))
	adapter.clear()
	var cleared = frame(adapter)
	record("lifecycle_clear_stops_movement", cleared.move == Vector2.ZERO and not cleared.fire, {"move": str(cleared.move), "fire": cleared.fire})
	var assist = preload("res://scripts/ui/aim_assist.gd").new()
	var geometry = world.geometry
	var source = Vector2(640, 360)
	var enemies = [{"uid": 1, "dead": false, "pos": source + Vector2.LEFT * 100, "arrival": 0.0}]
	var result = assist.apply(Vector2.RIGHT, source, enemies, geometry, 1.0, "auto", 300, "audit")
	record("auto_aim_ignores_manual_direction", result.dot(Vector2.RIGHT) < -.99,
		{"manual_direction": "RIGHT", "nearest_target": "LEFT", "effective_direction": str(result)})
	var settings = {
		"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect", "unset"),
		"emulate_mouse_from_touch": ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", "unset"),
		"orientation": ProjectSettings.get_setting("display/window/handheld/orientation"),
		"surface": str(root.size), "screen_transform": str(root.get_screen_transform())}
	if OS.get_cmdline_user_args().has("--audit-ui"):
		await audit_ui()
	var report = {"scope": "native Godot source audit with synthetic touch input; no physical Android device",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string, "settings": settings, "observations": observations}
	var file = FileAccess.open(report_dir.path_join("observations.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Mobile audit: %d observations recorded in %s" % [observations.size(), report_dir])
	if app != null:
		app.queue_free()
		await process_frame
		await process_frame
		# Allow the native audio mixer to release detached OGG playback buffers.
		await create_timer(.2).timeout
	world = null
	adapter = null
	assist = null
	geometry = null
	call_deferred("finish_audit")

func finish_audit() -> void:
	quit()

func audit_ui() -> void:
	app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.qa_capture_enabled = false
	app.qa_active = true
	app.set_physics_process(false)
	app.set_process(false)
	app.audio.set_muted(true)
	app.world.start("c_paper", 20261009)
	app.world.mode = "combat"
	app.world.enemies.clear()
	app.renderer.world = app.world
	app.renderer.hub = false
	app.screen = "game"
	app.paused = false
	app.hud.visible = true
	app.clear_modal()
	app.adapter.touch_mode = true
	app.renderer.combat_interface_visible = true
	app.update_hud()
	await process_frame
	await process_frame
	await screenshot("combat")
	var ui_before = app.interface.get_global_transform_with_canvas()
	var surface = root.size
	app.adapter.clear()
	var event = InputEventScreenTouch.new()
	event.index = 20
	event.position = Vector2(145, 570)
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var drag_event = InputEventScreenDrag.new()
	drag_event.index = 20
	drag_event.position = Vector2(215, 570)
	Input.parse_input_event(drag_event)
	await process_frame
	var press_capture = app.adapter.move_id
	event = InputEventScreenTouch.new()
	event.index = 20
	event.position = Vector2(1228, 48)
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	record("gui_release_over_pause", app.adapter.move_id == -1,
		{"move_id_before": press_capture, "move_id_after": app.adapter.move_id, "screen_after": app.screen})
	app.adapter.clear()
	app.show_tutorial()
	await process_frame
	await screenshot("tutorial")
	app.clear_modal()
	app.screen = "game"
	app.world.mode = "choice"
	app.world.choices = [{"kind": "relic", "id": "r01", "price": 0}, {"kind": "relic", "id": "r02", "price": 0}, {"kind": "relic", "id": "r03", "price": 0}]
	app.mobile_choice = 0
	app.show_choices()
	await process_frame
	await screenshot("choice")
	var sizing = []
	for control in app.keyboard.candidates(app.modal):
		if control is Button:
			sizing.append({"name": control.accessibility_name, "size": str(control.size), "rect": str(control.get_global_rect())})
	record("ui_geometry", true, {"surface": str(surface), "ui_transform": str(ui_before),
		"button_height": app.mobile_button_height, "dpi": DisplayServer.screen_get_dpi(), "choice_controls": sizing})
	app.world.mode = "replace"
	app.paused = false
	app.clear_modal()
	app.world.run.replacement = {"choice": {"kind": "relic", "id": "r17", "price": 0}, "index": 0, "return_mode": "choice"}
	app.world.run.relics.clear()
	for row in app.world.db.rows("relics").slice(0, 12): app.world.run.relics[row.id] = 1
	app.show_replacement()
	await process_frame
	await screenshot("replacement")

func screenshot(name: String) -> void:
	app.renderer.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(report_dir.path_join(name + ".png"))
