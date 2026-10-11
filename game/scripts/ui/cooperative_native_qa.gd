extends "res://scripts/ui/online_native_qa.gd"
## Native menus, actual input events and a second real network client.
var image_writers: Array = []
var autonomous = false
var door_destination = -1
var touch_held = false
var network_problems: Array = []
var last_action_at = -1.0

func diagnostics() -> Dictionary:
	var own = app.online.session
	return {"screen": app.screen, "page": app.online.page, "paused": app.paused, "state": own.state, "error": own.last_error,
		"phase": own.room.get("phase", ""), "reason": own.room.get("reason", ""), "suspend_reason": own.room.get("suspend_reason", ""), "connected": own.room.get("connected", []),
		"hp": own.presentation.map(func(actor): return actor.player.hp),
		"state_age": own.now() - own.last_state_received, "can_play": own.can_play(), "adapter_phase": app.adapter.phase,
		"aim_id": app.adapter.aim_id, "move_id": app.adapter.move_id, "firing": app.adapter.touch_firing,
		"weapon": app.world.player.get("weapon", ""), "sample_fire": own.latest_input.get("fire", false),
		"own_shots": own.presentation[0].stats.get("shots", -1) if own.presentation.size() > 0 else -1,
		"peer_shots": opponent.presentation[0].stats.get("shots", -1) if opponent != null and opponent.presentation.size() > 0 else -1,
		"peer_state": opponent.state if opponent != null else "", "peer_error": opponent.last_error if opponent != null else "", "problems": network_problems.duplicate()}

func expect(id: String, condition: bool, detail: String = "") -> void:
	super.expect(id, condition, detail if condition else JSON.stringify(diagnostics()))

func capture(name_value: String) -> void:
	app.notice_left = 0
	await frames(2)
	await RenderingServer.frame_post_draw
	var bitmap = app.get_viewport().get_texture().get_image()
	if name_value.begins_with("motion-"): bitmap.resize(1200, 540, Image.INTERPOLATE_LANCZOS)
	var path = directory.path_join("online-" + name_value + ".png")
	var thread = Thread.new()
	var started = thread.start(func(): return bitmap.save_png(path) == OK)
	captures.append({"name": name_value, "saved": false, "path": path, "screen": app.screen, "phase": app.online.session.room.get("phase", ""),
		"size": [bitmap.get_width(), bitmap.get_height()], "npcs": app.world.enemies.size(), "room": app.world.run.get("room", -1),
		"doors": Protocol.encode_tree(app.world.room_doors()), "positions": Protocol.encode_tree(app.online.session.room.get("actors", []).map(func(actor): return actor.player.pos)), "diagnostics": diagnostics()})
	image_writers.append({"thread": thread, "index": captures.size() - 1, "started": started == OK})

func touch_action(index: int, action: String, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = app.get_viewport().get_screen_transform() * app.adapter.control_center(action)
	Input.parse_input_event(event)

func touch_vector(index: int, action: String, direction: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = app.get_viewport().get_screen_transform() * (app.adapter.control_center(action) + direction * 45)
	event.relative = app.get_viewport().get_screen_transform().basis_xform(direction * 45)
	Input.parse_input_event(event)

func combat_input(session, seat: int) -> Dictionary:
	var actor = session.presentation[seat]
	var frame = Protocol.empty_input()
	var enemy = actor.nearest_enemy(actor.player.pos)
	if not enemy.is_empty():
		var direction = actor.player.pos.direction_to(enemy.pos)
		frame.aim = direction
		frame.fire = true
		var reach = float(actor.db.row("weapons", actor.player.weapon).range)
		var distance = actor.player.pos.distance_to(enemy.pos)
		if distance > reach * .72 or not actor.geometry.clear_segment(actor.player.pos, enemy.pos):
			actor.geometry.rebuild_flow(enemy.pos)
			frame.move = actor.geometry.toward(actor.player.pos, enemy.pos)
		elif distance < 150: frame.move = -direction
		else: frame.move = direction.orthogonal() * (.65 if seat == 0 else -.65)
		# Move out of real hostile trajectories instead of standing still in the
		# second combat room. This never changes HP, drops or authoritative state.
		for bullet in actor.bullets:
			if not bullet.friendly and actor.player.pos.distance_to(bullet.pos) < 90:
				frame.move = Vector2(bullet.dir).orthogonal().normalized()
				if (actor.player.pos - bullet.pos).dot(frame.move) < 0: frame.move = -frame.move
				frame.dash = actor.player.dash_cd <= 0
				break
		frame.skill = actor.player.skill_cd <= 0 and actor.player.energy >= actor.skill_cost()
	elif door_destination >= 0:
		for door in actor.room_doors():
			if int(door.destination) == door_destination:
				actor.geometry.rebuild_flow(door.pos)
				frame.move = actor.geometry.toward(actor.player.pos, door.pos) if actor.player.pos.distance_to(door.pos) > 24 else Vector2.ZERO
	return frame

func _physics_process(_delta: float) -> void:
	if drive_opponent and opponent != null and opponent.can_play():
		var seat = int(opponent.room.seat)
		opponent.submit_input(combat_input(opponent, seat))
	if autonomous and app.online.session.can_play() and app.adapter.phase == "combat":
		# A scene/menu transition releases fingers; begin the next real gesture.
		if app.adapter.move_id < 0: touch_action(91, "move", true)
		if app.adapter.aim_id < 0: touch_action(92, "aim", true)
		var frame = combat_input(app.online.session, int(app.online.session.room.seat))
		touch_vector(92, "aim", Vector2(frame.aim.x, frame.aim.y * .84722).normalized() if frame.fire else Vector2.ZERO)
		touch_vector(91, "move", Vector2(frame.move.x, frame.move.y * .84722))
		if app.world.time - last_action_at > .3:
			if frame.skill: touch_action(93, "skill", true); touch_action(93, "skill", false)
			if frame.dash: touch_action(94, "dash", true); touch_action(94, "dash", false)
			last_action_at = app.world.time

func run() -> void:
	previous_clipboard = DisplayServer.clipboard_get()
	DirAccess.make_dir_recursive_absolute(directory)
	app.online.session.problem.connect(func(code): network_problems.append({"client": 0, "code": code}))
	await frames(6)
	await key(KEY_ENTER); await key(KEY_ENTER)
	await activate("online")
	expect("keyboard_opens_default_cooperative_hub", app.online.active() and app.online.session.game_mode == "coop")
	offline_digest = JSON.stringify(Store.encode(app.save_session.current)).sha256_text()
	await capture("coop-hub")
	expect("cooperative_open_connects_automatically", app.online.session.wants_connection and await until(func(): return app.online.session.state == "online", 15))
	expect("cooperative_has_no_endpoint_editor", not has_control("online_endpoint") and not has_control("online_config"))
	await activate("online_profile")
	await paste("online_nickname", "Paper A")
	await capture("coop-profile")
	await activate("online_save_profile")
	await activate("online_loadout")
	await activate("online_character_c_mask")
	await activate("online_weapon_w14")
	await capture("coop-loadout")
	await key(KEY_ESCAPE)
	await activate("online_queue")
	expect("cooperative_matching_uses_existing_automatic_connection", app.online.page != "consent" and app.online.session.wants_connection)
	expect("cooperative_queue_waits_for_partner", await until(func(): return app.online.session.state == "queued"))
	opponent = Session.new(directory.path_join("opponent"))
	opponent.problem.connect(func(code): network_problems.append({"client": 1, "code": code}))
	add_child(opponent)
	opponent.connect_service(url, "Paper B")
	if not await until(func(): return opponent.state == "online"): expect("second_native_socket", false); finish(); return
	opponent.request("queue", {"loadout": {"character": "c_ink", "weapon": "w07", "skill": "s16"}, "game_mode": "coop"})
	expect("native_cooperative_matchmaking", await until(func(): return app.online.session.room.get("phase") == "lobby"))
	await capture("coop-lobby")
	await activate("online_ready")
	opponent.request("ready")
	expect("native_cooperative_campaign_starts", await until(func(): return app.online.session.can_play(), 7))
	if app.online.session.presentation.size() != 2: finish(); return
	expect("two_heroes_and_real_monsters", app.renderer.online_actors.size() == 1 and app.world.enemies.all(func(enemy): return not enemy.get("online_actor", false)))
	var position = Vector2(app.world.player.pos)
	await hold(KEY_D, .45)
	expect("cooperative_wasd_movement", opponent.presentation[0].player.pos.x > position.x + 20)
	await hold(KEY_UP, .6)
	expect("cooperative_arrow_key_shooting", await until(func(): return opponent.presentation[0].stats.shots > 0, 1.0))
	await key(KEY_Q)
	expect("cooperative_keyboard_skill", await until(func(): return app.world.player.skill_cd > 0, 2))
	await capture("coop-combat")
	await key(KEY_ESCAPE)
	expect("cooperative_escape_pauses_team", await until(func(): return opponent.room.get("phase") == "suspended"))
	await capture("coop-pause")
	expect("mutual_keyboard_resume", await resume_both())
	await key(KEY_TAB)
	expect("cooperative_tab_opens_dungeon_map", app.online.page == "arena" and app.keyboard.candidates(app.modal).any(func(control): return str(control.get_meta("nav_id", "")).begins_with("online_map_room_")))
	await capture("coop-map")
	await key(KEY_ESCAPE)
	expect("map_keyboard_return", await resume_both())
	app.online.session.simulate_link_loss()
	expect("cooperative_native_reconnect", await until(func(): return app.online.session.state == "room" and app.online.session.room.get("phase") == "suspended", 9))
	await capture("coop-reconnect")
	expect("cooperative_reconnect_resume", await resume_both())
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
	await until(func(): return app.online.session.can_play())
	touch_action(91, "move", true)
	touch_action(92, "aim", true)
	touch_held = true
	autonomous = true
	drive_opponent = true
	await frames(8)
	expect("cooperative_right_hand_touch_fire", app.adapter.aim_id == 92 and app.adapter.touch_firing)
	expect("right_hand_dash_and_skill", app.adapter.control_center("dash").x > app.adapter.safe_rect.get_center().x and app.adapter.control_center("skill").x > app.adapter.safe_rect.get_center().x)
	await capture("coop-wide-touch")
	for i in 20:
		await capture("motion-%02d" % i)
		await get_tree().create_timer(.07).timeout
	var completed = await until(func(): return app.online.session.room.get("phase") == "draft" or app.world.mode == "clear", 25)
	expect("two_real_clients_clear_npc_room", completed and app.online.session.room.get("phase") != "finished")
	# The first ordinary room grants 10 XP; some seeds do not offer growth yet.
	# Reach the next real combat room rather than injecting a reward fixture.
	for attempt in 3:
		if app.online.session.room.get("phase") == "draft": break
		var doors = app.world.room_doors()
		var fresh = doors.filter(func(door): return not app.world.run.visited.has(int(door.destination)))
		var combats = fresh.filter(func(door): return app.world.run.graph.types[int(door.destination)] == "combat")
		var candidates = combats if not combats.is_empty() else fresh
		if candidates.is_empty(): break
		door_destination = int(candidates[0].destination)
		var old_room = int(app.world.run.room)
		var moved = await until(func(): return int(app.world.run.room) != old_room and int(opponent.presentation[1].run.room) == int(app.world.run.room), 16)
		expect("physical_team_door_before_growth_%d" % attempt, moved)
		door_destination = -1
		if not moved: break
		await until(func(): return app.online.session.room.get("phase") == "draft" or app.world.mode == "clear", 25)
	autonomous = false
	touch_action(91, "move", false); touch_action(92, "aim", false)
	touch_held = false
	expect("native_growth_offered_after_real_room_clears", app.online.session.room.get("phase") == "draft")
	if app.online.session.room.get("phase") == "draft":
		await capture("coop-growth")
		var count = app.online.session.room.builds[0].size()
		await key(KEY_1)
		expect("cooperative_number_one_selects_growth", await until(func(): return app.online.session.room.builds[0].size() > count))
		for attempt in 10:
			if opponent.room.get("phase") != "draft": break
			if int(opponent.room.picked[1]) < 0: opponent.request("choose", {"index": 0, "choice_token": opponent.room.choice_token})
			if int(app.online.session.room.picked[0]) < 0: await key(KEY_1)
			await get_tree().create_timer(.3).timeout
		expect("both_growth_choices_resume_game", await until(func(): return app.online.session.can_play()))
	if app.online.session.can_play():
		await key(KEY_I)
		await until(func(): return app.online.session.room.get("phase") == "suspended")
		expect("pause_history_contains_both_growth_logs", app.online.page == "build" and app.online.session.room.builds[0].size() > 0 and app.online.session.room.builds[1].size() > 0)
		await capture("coop-history")
		await key(KEY_ESCAPE)
		await resume_both()
		var doors = app.world.room_doors()
		if not doors.is_empty():
			door_destination = int(doors[0].destination)
			var old_room = int(app.world.run.room)
			touch_action(91, "move", true); touch_action(92, "aim", true)
			touch_held = true; autonomous = true
			expect("real_touch_same_door_transitions_both", await until(func(): return int(app.world.run.room) != old_room and int(opponent.presentation[1].run.room) == int(app.world.run.room), 16))
			autonomous = false
			touch_action(91, "move", false); touch_action(92, "aim", false)
			touch_held = false
			await capture("coop-next-room")
	opponent.request("leave")
	expect("native_partner_leave_ends_cooperation", await until(func(): return app.online.session.room.get("phase") == "finished" and app.online.session.room.get("reason") == "partner_left"))
	await until(func(): return app.online.page == "status" and app.keyboard.candidates(app.modal).any(func(control): return str(control.get_meta("nav_id", "")) == "online_return"))
	await capture("coop-result")
	await activate("online_return")
	await until(func(): return app.online.session.room.is_empty())
	await key(KEY_ESCAPE)
	expect("cooperation_returns_offline_menu", not app.online.active() and app.menu_page == "title")
	expect("offline_save_kept_separate", JSON.stringify(Store.encode(app.save_session.current)).sha256_text() == offline_digest)
	finish()

func finish() -> void:
	autonomous = false
	if touch_held:
		touch_action(91, "move", false); touch_action(92, "aim", false)
	for item in image_writers: captures[item.index].saved = bool(item.thread.wait_to_finish()) if item.started else false
	super.finish()
