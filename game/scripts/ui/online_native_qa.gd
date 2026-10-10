extends Node
## Real native UI, real input events, and two real WebSocket clients.
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Store = preload("res://scripts/core/save_store.gd")
var app
var directory = ""
var opponent
var checks: Array = []
var captures: Array = []
var previous_clipboard = ""
var drive_opponent = false
var url = "ws://127.0.0.1:18777"
var offline_digest = ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-url="): url = arg.trim_prefix("--online-url=")
	call_deferred("run")

func frames(count: int = 3) -> void:
	for i in count: await get_tree().process_frame

func until(predicate: Callable, seconds: float = 6) -> bool:
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000:
		if predicate.call(): return true
		await get_tree().process_frame
	return predicate.call()

func expect(id: String, condition: bool, detail: String = "") -> void:
	checks.append({"id": id, "passed": condition, "detail": detail})
	if not condition: print("ONLINE_NATIVE_FAIL ", id, " ", detail)
	else: print("ONLINE_NATIVE_PASS ", id)

func key(code: int, modifiers: bool = false) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.physical_keycode = code; event.keycode = code; event.pressed = pressed; event.ctrl_pressed = modifiers
		Input.parse_input_event(event)
		await frames(2)
		await get_tree().physics_frame

func hold(code: int, seconds: float) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	Input.parse_input_event(event)
	await get_tree().create_timer(seconds).timeout
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event)
	await frames(3)

func target(id: String) -> bool:
	await frames(3)
	var controls = app.keyboard.candidates(app.modal)
	for attempt in controls.size() + 3:
		var owner = app.get_viewport().gui_get_focus_owner()
		if is_instance_valid(owner) and str(owner.get_meta("nav_id", "")) == id: return true
		await key(KEY_TAB)
	expect("keyboard_path_" + id, false, app.screen)
	return false

func activate(id: String) -> bool:
	if not await target(id): return false
	await key(KEY_ENTER)
	return true

func paste(id: String, value: String) -> void:
	if await target(id):
		DisplayServer.clipboard_set(value)
		await key(KEY_A, true)
		await key(KEY_V, true)

func capture(name_value: String) -> void:
	app.notice_left = 0
	await frames(2)
	await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var path = directory.path_join("online-" + name_value + ".png")
	captures.append({"name": name_value, "saved": image.save_png(path) == OK, "path": path,
		"screen": app.screen, "phase": str(app.online.session.room.get("phase", "")), "size": [image.get_width(), image.get_height()]})

func _physics_process(_delta: float) -> void:
	if drive_opponent and opponent != null and opponent.can_play():
		var frame = Protocol.empty_input()
		var player = opponent.presentation[1].player
		frame.move = Vector2.LEFT if player.pos.x > 700 else Vector2.ZERO
		frame.aim = Vector2.LEFT
		opponent.submit_input(frame)

func resume_both() -> bool:
	await activate("online_resume")
	opponent.request("resume")
	return await until(func(): return app.online.session.can_play() and opponent.can_play(), 7)

func run() -> void:
	previous_clipboard = DisplayServer.clipboard_get()
	DirAccess.make_dir_recursive_absolute(directory)
	await frames(6)
	await key(KEY_ENTER); await key(KEY_ENTER)
	await activate("online")
	expect("main_menu_keyboard_opens_online", app.online.active() and app.screen == "online")
	offline_digest = JSON.stringify(Store.encode(app.save_session.current)).sha256_text()
	await capture("hub")
	await activate("online_config")
	await paste("online_endpoint", url)
	await paste("online_nickname", "Paper A")
	await activate("online_save_address")
	expect("keyboard_endpoint_and_name_save", app.online.session.endpoint == url and app.online.session.nickname == "Paper A")
	await activate("online_loadout")
	await activate("online_character_c_lantern")
	await activate("online_skill_s09")
	await activate("online_weapon_w14")
	expect("keyboard_all_characters_skills_weapons_selectable", app.online.session.loadout == {"character": "c_lantern", "weapon": "w14", "skill": "s09"})
	await capture("loadout")
	await key(KEY_ESCAPE)
	await activate("online_queue")
	expect("first_connection_explains_data_before_network", app.online.page == "consent" and not app.online.session.wants_connection)
	await capture("connection-consent")
	await activate("online_consent")
	expect("real_queue_wait", await until(func(): return app.online.session.state == "queued"))
	opponent = Session.new(directory.path_join("opponent"))
	add_child(opponent)
	opponent.connect_service(url, "Paper B")
	if not await until(func(): return opponent.state == "online"):
		expect("opponent_connection", false); finish(); return
	opponent.request("queue", {"loadout": {"character": "c_mask", "weapon": "w08", "skill": "s10"}})
	expect("native_client_real_pair", await until(func(): return app.online.session.room.get("phase") == "lobby"))
	await capture("lobby")
	await activate("online_ready")
	opponent.request("ready")
	expect("native_ready_to_draft", await until(func(): return app.online.session.room.get("phase") == "draft"))
	await capture("draft")
	await key(KEY_4)
	expect("number_four_selects_last_card", await until(func(): return app.online.session.room.get("picked", [-1, -1])[0] == 3))
	opponent.request("choose", {"index": 0})
	expect("native_countdown_to_playing", await until(func(): return app.online.session.can_play(), 7))
	if app.online.session.presentation.size() != 2: finish(); return
	drive_opponent = true
	var old_position: Vector2 = app.world.player.pos
	await hold(KEY_D, .6)
	expect("keyboard_movement_sent_to_authority", opponent.presentation[0].player.pos.x > old_position.x + 35)
	await hold(KEY_RIGHT, .7)
	expect("arrow_key_fires_at_opponent", app.online.session.presentation[1].player.hp < app.online.session.presentation[1].player.max_hp)
	await key(KEY_Q)
	expect("keyboard_character_skill", await until(func(): return app.world.player.skill_cd > 0 or app.world.player.energy < 95, 2))
	expect("other_player_uses_real_hero_renderer", app.renderer.online_actors.size() == 1 and app.world.enemies[0].online_actor)
	await capture("combat")
	await key(KEY_ESCAPE)
	expect("escape_pauses_both_clients", await until(func(): return app.online.session.room.get("phase") == "suspended" and opponent.room.get("phase") == "suspended"))
	await capture("pause")
	await activate("online_build")
	expect("pause_build_has_both_histories", app.online.page == "build" and app.online.session.room.builds[0].size() == 1 and app.online.session.room.builds[1].size() == 1)
	await capture("build")
	await key(KEY_ESCAPE)
	expect("keyboard_resumes_both", await resume_both())
	await key(KEY_TAB)
	expect("tab_tactical_map_and_pause", await until(func(): return app.online.page == "arena" and opponent.room.get("phase") == "suspended"))
	await capture("map")
	await key(KEY_ESCAPE)
	expect("map_returns_to_pause", app.online.page == "status")
	expect("map_resume", await resume_both())
	app.online.session.simulate_link_loss()
	expect("native_loss_suspends_other", await until(func(): return opponent.room.get("phase") == "suspended"))
	await capture("reconnect")
	expect("native_automatic_reconnect", await until(func(): return app.online.session.state == "room" and app.online.session.room.get("phase") == "suspended", 8))
	expect("reconnect_keyboard_resume", await resume_both())
	# Real native wide viewport with the same safe-area and touch input path as Android.
	app.mobile_ui = true
	app.settings.touch = true
	app.adapter.touch_mode = true
	app.get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	app.get_window().size = Vector2i(2400, 1080)
	await frames(5)
	app.qa_display_safe = Rect2(72, 24, 2256, 1020)
	app.qa_display_dpi = 360
	app.apply_safe_area()
	await frames(5)
	app.online.enter_battle()
	var touch = InputEventScreenTouch.new()
	var screen_transform = app.get_viewport().get_screen_transform()
	touch.index = 61; touch.pressed = true; touch.position = screen_transform * app.adapter.control_center("move")
	Input.parse_input_event(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 61; drag.position = screen_transform * (app.adapter.control_center("move") + Vector2(42, 0)); drag.relative = screen_transform.basis_xform(Vector2(42, 0))
	Input.parse_input_event(drag)
	old_position = app.world.player.pos
	await get_tree().create_timer(.45).timeout
	touch = touch.duplicate(); touch.pressed = false
	Input.parse_input_event(touch)
	expect("native_wide_touch_movement", opponent.presentation[0].player.pos.x > old_position.x + 15)
	expect("native_right_hand_actions", app.adapter.control_center("dash").x > app.adapter.safe_rect.get_center().x and app.adapter.control_center("skill").x > app.adapter.safe_rect.get_center().x)
	await capture("wide-mobile")
	# Record real battle frames, with genuine keyboard aim/fire driving the beam.
	var held_fire = InputEventKey.new()
	held_fire.physical_keycode = KEY_RIGHT; held_fire.keycode = KEY_RIGHT; held_fire.pressed = true
	Input.parse_input_event(held_fire)
	for i in 20:
		await capture("motion-%02d" % i)
		await get_tree().create_timer(.06).timeout
	held_fire = held_fire.duplicate(); held_fire.pressed = false
	Input.parse_input_event(held_fire)
	opponent.request("leave")
	expect("native_forfeit_result_visible", await until(func(): return app.online.session.room.get("phase") == "finished"))
	await capture("result")
	await activate("online_return")
	await activate("online_code")
	await paste("online_room_code", "001725")
	await key(KEY_ENTER)
	expect("keyboard_six_digit_create", await until(func(): return app.online.session.room.get("phase") == "lobby" and app.online.session.room.get("code") == "001725"))
	opponent.request("code", {"code": "001725", "loadout": {"character": "c_paper", "weapon": "w01", "skill": "s01"}})
	expect("same_code_second_client_joins", await until(func(): return app.online.session.room.get("players", []).size() == 2))
	await capture("code-room")
	await key(KEY_ESCAPE)
	await activate("online_confirm_leave")
	expect("keyboard_leave_lobby", await until(func(): return app.online.session.room.is_empty()))
	opponent.request("leave")
	await key(KEY_ESCAPE)
	expect("online_returns_main_menu", not app.online.active() and app.menu_page == "title")
	expect("offline_save_unchanged_by_online", JSON.stringify(Store.encode(app.save_session.current)).sha256_text() == offline_digest)
	finish()

func finish() -> void:
	drive_opponent = false
	if opponent != null: opponent.disconnect_service()
	if app.online.active(): app.online.session.disconnect_service()
	DisplayServer.clipboard_set(previous_clipboard)
	var failed = checks.filter(func(item): return not item.passed)
	var file = FileAccess.open(directory.path_join("online-native.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"passed": failed.is_empty(), "checks": checks, "failures": failed, "captures": captures, "real_transport": true, "physical_android": false}, "\t", true, true))
		file.close()
	print("ONLINE_NATIVE_RESULT checks=%d failures=%d captures=%d" % [checks.size(), failed.size(), captures.size()])
	app.get_tree().quit(0 if failed.is_empty() else 1)
