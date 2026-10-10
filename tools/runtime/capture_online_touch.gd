extends "res://scripts/ui/online_native_qa.gd"
## Run the compiled game's existing flow, then capture genuine right-stick fire.
var touch_aim_held = false
var image_writers: Array = []
var first_motion = true

func send_touch(index: int, control: String, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = app.get_viewport().get_screen_transform() * app.adapter.control_center(control)
	Input.parse_input_event(event)

func capture(name_value: String) -> void:
	if name_value.begins_with("motion-"):
		if first_motion:
			# The inherited keyboard-only fixture starts a held key here. This
			# recording uses the right touchscreen stick instead.
			var release_key = InputEventKey.new()
			release_key.physical_keycode = KEY_RIGHT
			release_key.keycode = KEY_RIGHT
			release_key.pressed = false
			Input.parse_input_event(release_key)
			first_motion = false
		await frames(2)
		await RenderingServer.frame_post_draw
		var bitmap = app.get_viewport().get_texture().get_image()
		bitmap.resize(1200, 540, Image.INTERPOLATE_LANCZOS)
		var path = directory.path_join("online-" + name_value + ".png")
		var writer = Thread.new()
		var started = writer.start(func(): return bitmap.save_png(path) == OK)
		captures.append({"name": name_value, "saved": false, "path": path, "screen": app.screen,
			"phase": str(app.online.session.room.get("phase", "")), "size": [bitmap.get_width(), bitmap.get_height()]})
		image_writers.append({"thread": writer, "index": captures.size() - 1, "started": started == OK})
		return
	if name_value == "result" and touch_aim_held:
		send_touch(62, "aim", false)
		touch_aim_held = false
		for item in image_writers:
			captures[item.index].saved = bool(item.thread.wait_to_finish()) if item.started else false
	await super.capture(name_value)
	if name_value != "wide-mobile": return
	# PNG readback/encoding in the inherited fixture blocks the main thread.
	# Wait for fresh real snapshots before pressing, then save motion PNGs off
	# the game thread so the stale-link input safety gate is not triggered.
	await until(func(): return app.online.session.can_play(), 4)
	await get_tree().create_timer(.3).timeout
	var old_hp = float(opponent.presentation[1].player.hp)
	send_touch(62, "aim", true)
	var transform = app.get_viewport().get_screen_transform()
	var drag = InputEventScreenDrag.new()
	drag.index = 62
	drag.position = transform * (app.adapter.control_center("aim") + Vector2(45, 0))
	drag.relative = transform.basis_xform(Vector2(45, 0))
	Input.parse_input_event(drag)
	touch_aim_held = true
	await frames(2)
	await get_tree().create_timer(.9).timeout
	expect("right_touch_aim_fires_real_server_damage", float(opponent.presentation[1].player.hp) < old_hp)
	expect("right_touch_continuous_fire_keeps_captured_finger", app.adapter.aim_id == 62 and app.adapter.touch_firing and bool(app.online.session.latest_input.fire))
	var old_energy = float(opponent.presentation[0].player.energy)
	send_touch(63, "skill", true)
	await frames(4)
	send_touch(63, "skill", false)
	expect("right_touch_skill_reaches_server", await until(func(): return float(opponent.presentation[0].player.energy) < old_energy - 5 or float(opponent.presentation[0].player.skill_cd) > 0, 2))
