extends Node
const Session = preload("res://scripts/network/online_session.gd")
const Screens = preload("res://scripts/ui/online_ui.gd")
const Shortcuts = preload("res://scripts/core/choice_shortcuts.gd")
const Motion = preload("res://scripts/ui/weapon_motion.gd")
const Prediction = preload("res://scripts/network/motion_prediction.gd")
const Interpolation = preload("res://scripts/network/remote_interpolation.gd")
const AttackPrediction = preload("res://scripts/network/attack_prediction.gd")
var attack_prediction = AttackPrediction.new()
var interpolation = Interpolation.new()
var app
var session
var service_endpoint = Session.OFFICIAL_ENDPOINT
var enabled = false
var page = "hub"
var offline_world
var queued_action = ""
var code_draft = ""
var name_draft = ""
var status_label: Label
var online_hud: Control
var bars: Array = []
var timer_label: Label
var score_label: Label
var energy_bar: ProgressBar
var hud_status: Label
var hud_arena: Label
var last_round = -1
var render_actors: Array = []
var exit_requested = false
var prediction = Prediction.new()
var bound_snapshot = -1
var opponent_from = Vector2.ZERO
var opponent_to = Vector2.ZERO
var opponent_visual = Vector2.ZERO
var opponent_elapsed = 1.0
var opponent_ready = false
var waiting_label: Label
var choice_page = 0
var last_scene = -1
var pause_pending = false
var pause_context_retry_used = false
var last_phase = ""

func initialize(host, folder: String = "user://online-client") -> void:
	app = host
	session = Session.new(folder)
	if app.qa_active:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--online-url=") and session.valid_endpoint(arg.trim_prefix("--online-url=")):
				service_endpoint = arg.trim_prefix("--online-url=")
	if session.endpoint != service_endpoint:
		session.endpoint = service_endpoint
		session.load_identity()
	add_child(session)
	session.changed.connect(connection_changed)
	session.state_received.connect(receive_state)
	session.events_received.connect(receive_events)
	session.entity_state_received.connect(receive_entity_state)
	session.input_sampled.connect(sample_local_input)
	session.command_completed.connect(func(operation, succeeded, code):
		if operation == "pause" and not succeeded:
			pause_pending = false
			if code == "stale_context" and not pause_context_retry_used:
				# A newer authoritative epoch can arrive between the input key and
				# the command reaching the server. Retry once with fresh context.
				pause_context_retry_used = true
				call_deferred("retry_pause_after_stale")
			refresh()
	)
	session.problem.connect(func(code):
		if enabled: app.notice(Screens.error_text(code)))
	var character = app.world.db.row("characters", str(session.loadout.get("character", "")))
	if character.is_empty(): session.loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
	elif not character.skills.has(session.loadout.get("skill", "")): session.loadout.skill = character.skills[0]
	if app.world.db.row("weapons", str(session.loadout.get("weapon", ""))).is_empty(): session.loadout.weapon = "w01"

func active() -> bool:
	return enabled

func connection_changed() -> void:
	# Network authentication can complete while a player is typing or navigating
	# loadouts. Preserve these controls and their focus instead of rebuilding them.
	if enabled and page in ["profile", "loadout", "code"] and session.room.is_empty() and session.state not in ["queued", "expired", "incompatible"]:
		perform_queued_action()
		if is_instance_valid(status_label): status_label.text = Screens.connection_text(self)
		return
	refresh()

func open() -> void:
	exit_requested = false
	if not enabled:
		enabled = true
		offline_world = app.world
		name_draft = session.nickname
	page = "hub"
	refresh()
	connect_service()

func close() -> void:
	enabled = false
	pause_pending = false
	pause_context_retry_used = false
	last_phase = ""
	queued_action = ""
	session.disconnect_service()
	app.adapter.clear()
	app.aim_assist.clear()
	app.world = offline_world
	app.renderer.world = offline_world
	app.renderer.online_actors.clear()
	app.renderer.online_motions.clear()
	app.renderer.online_death_clocks.clear()
	app.renderer.visual_effects.clear()
	app.renderer.weapon_motion.clear()
	if is_instance_valid(online_hud): online_hud.queue_free()
	online_hud = null
	render_actors.clear()
	prediction.clear()
	attack_prediction.clear()
	opponent_ready = false
	bound_snapshot = -1
	last_round = -1
	app.show_menu("title")
	if exit_requested: app.get_tree().quit()

func request_quit() -> void:
	exit_requested = true
	if session.room.is_empty() and session.state != "queued": close()
	else: show_page("leave_confirm")

func show_page(value: String) -> void:
	page = value
	refresh()

func connect_service(action: String = "") -> void:
	queued_action = action
	if session.state in ["connecting", "reconnecting", "synchronizing"] and session.wants_connection: return
	if session.state in ["online", "queued", "room"]: perform_queued_action(); return
	if session.state in ["expired", "incompatible"]:
		page = "identity" if session.state == "expired" else "hub"
		refresh()
		return
	session.connect_service(service_endpoint, session.nickname)

func cancel_matching() -> void:
	queued_action = ""
	if session.state == "queued": session.request("cancel_queue")
	refresh()

func perform_queued_action() -> void:
	if queued_action.is_empty() or session.state != "online": return
	var action = queued_action
	queued_action = ""
	if action == "queue": session.request("queue", {"loadout": session.loadout, "game_mode": session.game_mode})
	elif action == "code": session.request("code", {"code": code_draft, "loadout": session.loadout, "game_mode": session.game_mode})

func join_code() -> void:
	if not Session.Protocol.valid_code(code_draft): app.notice("请输入六位数字，保留开头的 0。"); return
	connect_service("code")

func save_profile() -> void:
	if not session.room.is_empty() or session.state == "queued": return
	session.disconnect_service()
	session.nickname = Session.Protocol.clean_name(name_draft)
	if not session.save_preferences(): app.notice("联机设置暂未存下。"); return
	page = "hub"
	refresh()
	connect_service()

func choose(index: int) -> void:
	if str(session.room.get("phase", "")) != "draft": return
	var seat = int(session.room.get("seat", 0))
	if int(session.room.picked[seat]) >= 0: return
	if session.pending.values().any(func(command): return command.get("op") == "choose"): return
	session.request("choose", {"index": index, "choice_token": session.room.get("choice_token", "")})

func cooperative_action(operation: String, value: String = "") -> void:
	if session.room.get("game_mode") != "coop": return
	if session.room.get("phase") != "draft" and not (operation == "repay" and session.room.get("phase") == "suspended"): return
	if session.pending.values().any(func(command): return command.get("op") in ["choose", "cooperative_action"]): return
	session.request("cooperative_action", {"action": operation, "value": value, "choice_token": session.room.get("choice_token", "")})

func set_mode(value: String) -> void:
	if not session.room.is_empty() or session.state == "queued": return
	session.game_mode = value
	session.save_preferences()
	refresh()

func ready() -> void:
	if session.room.get("phase") == "lobby":
		var seat = int(session.room.seat)
		session.request("ready", {"ready": not bool(session.room.ready[seat])})

func request_pause_if_needed(phases: Array) -> void:
	# A map/build key can be followed by Escape before the authoritative pause
	# snapshot arrives. Reusing the same request window avoids sending a second
	# pause with the old epoch, which the server correctly rejects as stale.
	if pause_pending or session.state != "room": return
	if session.pending.values().any(func(command): return command.get("op") == "pause"):
		pause_pending = true
		return
	if session.room.get("phase") in phases:
		pause_context_retry_used = false
		pause_pending = session.request("pause") > 0

func retry_pause_after_stale() -> void:
	await get_tree().process_frame
	if not enabled or pause_pending or session.state != "room": return
	if session.room.get("phase") in ["playing", "countdown", "round_result", "draft"]:
		pause_pending = session.request("pause") > 0
		refresh()

func pause() -> void:
	app.adapter.clear()
	session.clear_input()
	request_pause_if_needed(["playing", "countdown", "round_result", "draft"])
	page = "status"
	app.paused = true
	refresh()

func show_build() -> void:
	if session.room.is_empty(): return
	request_pause_if_needed(["playing", "countdown", "round_result", "draft"])
	session.clear_input()
	app.adapter.clear()
	page = "build"
	refresh()

func show_arena() -> void:
	if session.presentation.is_empty(): return
	request_pause_if_needed(["playing", "countdown", "round_result"])
	session.clear_input()
	app.adapter.clear()
	page = "arena"
	refresh()

func leave() -> void:
	if session.state in ["online", "queued", "room"]:
		session.request("leave")
		page = "hub"
		refresh()
	else: close()

func resume() -> void:
	page = "status"
	if session.room.get("phase") == "suspended": session.request("resume")
	refresh()

func back() -> void:
	if page in ["profile", "loadout", "code", "identity"] and session.room.is_empty(): show_page("hub"); return
	if page == "repay": show_page("build"); return
	if page in ["build", "arena", "leave_confirm"]: exit_requested = false; show_page("status"); return
	if not session.room.is_empty():
		if session.room.get("phase") in ["playing", "countdown", "round_result", "draft"]: pause()
		elif session.room.get("phase") == "suspended" and not bool(session.room.resume_ready[int(session.room.seat)]): resume()
		else: show_page("leave_confirm")
	elif session.state == "queued": session.request("cancel_queue"); show_page("hub")
	else: close()

func handle_input(event: InputEvent) -> bool:
	if not enabled: return false
	if app.screen == "game":
		if app.adapter.profile.event_matches("pause", event): pause(); return true
		if app.adapter.profile.event_matches("map", event): show_arena(); return true
		if app.adapter.profile.event_matches("inventory", event): show_build(); return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if session.room.get("phase") == "draft" and page not in ["build", "arena", "leave_confirm"]:
			var index = Shortcuts.index_for(event)
			if index >= 0:
				if session.room.get("choice_mode") == "replace": return false
				choose(index + choice_page * 4 if session.room.get("game_mode") == "coop" else index)
				return true
		if app.screen == "game":
			if app.adapter.profile.event_matches("pause", event) or code == KEY_ESCAPE: pause(); return true
			if app.adapter.profile.event_matches("map", event): show_arena(); return true
			if app.adapter.profile.event_matches("inventory", event): show_build(); return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B: back(); return true
	return false

func refresh() -> void:
	if not enabled: return
	if exit_requested and page == "hub" and session.state == "online" and session.room.is_empty(): close(); return
	perform_queued_action()
	var phase = str(session.room.get("phase", ""))
	if phase in ["playing", "countdown", "round_result"] and session.state == "room" and not pause_pending and page not in ["build", "arena", "repay", "leave_confirm"]:
		enter_battle()
		return
	app.paused = true
	app.hud.visible = false
	if is_instance_valid(online_hud): online_hud.visible = false
	app.adapter.clear()
	Screens.show(self)

func receive_state(value: Dictionary) -> void:
	if not enabled: return
	if not str(value.get("id", "")).is_empty(): queued_action = ""
	var phase = str(value.get("phase", ""))
	if phase in ["suspended", "finished", "lobby"]:
		pause_pending = false
		pause_context_retry_used = false
	if phase == "finished" and last_phase != "finished": page = "status"
	last_phase = phase
	if session.presentation.size() == 2:
		if int(value.get("round", 0)) != last_round or int(value.get("scene", {}).get("serial", 0)) != last_scene:
			last_round = int(value.get("round", 0))
			last_scene = int(value.get("scene", {}).get("serial", 0))
			app.renderer.visual_effects.clear()
			app.renderer.weapon_motion.clear()
			app.renderer.online_motions.clear()
			app.renderer.online_death_clocks.clear()
			prediction.clear()
			attack_prediction.clear()
			interpolation.clear()
			opponent_ready = false
			opponent_elapsed = 1.0
		bind_worlds()
	update_hud()
	if is_instance_valid(status_label):
		status_label.text = Screens.connection_text(self) + (" · %d 秒后默认第一项" % ceili(float(value.get("draft_remaining", 30))) if value.get("phase") == "draft" and value.get("game_mode") != "coop" else "")
	if is_instance_valid(waiting_label): waiting_label.text = "双方准备后继续" if value.get("game_mode") == "coop" and value.get("suspend_reason") == "menu" else "等待恢复 · %d 秒" % ceili(float(value.get("grace_left", 90)))

func bind_worlds() -> void:
	var seat = int(session.room.get("seat", 0))
	app.world = session.presentation[seat]
	app.renderer.world = app.world
	app.renderer.online_actors = {1001 + 1 - seat: session.presentation[1 - seat]}
	# Both players' attacks remain visible; opponent projectiles use danger colours.
	var own = session.room.actors[seat]
	var other = session.room.actors[1 - seat]
	var cooperative = session.room.get("game_mode") == "coop"
	if bound_snapshot != session.snapshot_serial:
		bound_snapshot = session.snapshot_serial
		prediction.observe(app.world, own.player, session.input_history, session.can_play())
		attack_prediction.observe(app.world, own.player, session.input_history)
		# Feed the measured battle RTT into the remote render buffer. This adapts
		# the interpolation window to the actual WAN path while local movement
		# remains client-predicted and does not inherit this presentation delay.
		interpolation.observe_clock(float(own.time), session.now(), session.latency_ms)
		var remote_player: Dictionary = other.player.duplicate(false)
		remote_player.uid = 1001 + 1 - seat
		interpolation.observe("opponent", [remote_player], float(other.time), session.state_sequence)
		opponent_ready = true
	if cooperative:
		app.world.bullets = session.room.scene.bullets
		app.world.zones = session.room.scene.zones
		return
	app.world.bullets = own.bullets.duplicate(false)
	app.world.zones = own.zones.duplicate(false)
	for bullet in other.bullets:
		var view = bullet.duplicate(true)
		view.friendly = false
		app.world.bullets.append(view)
	for zone in other.zones:
		var view = zone.duplicate(true)
		view.friendly = false
		app.world.zones.append(view)

func receive_events(events: Array) -> void:
	if not enabled or session.presentation.size() != 2: return
	bind_worlds()
	var seat = int(session.room.seat)
	var own: Array = []
	var other: Array = []
	for event in events:
		if event.get("event_type") != "combat": continue
		if int(event.seat) == seat:
			if attack_prediction.accept_event(event): own.append(event)
		else: other.append(event)
	app.renderer.accept(own)
	app.renderer.accept_opponent(other, 1001 + 1 - seat)
	app.audio.accept(own + other)
	app.haptics.accept(own, app.adapter.last_device)

func receive_entity_state(group: String, rows: Array, server_time: float, sequence: int, updated: Array) -> void:
	if not enabled: return
	interpolation.observe(group, rows, server_time, sequence, updated)
	if group.ends_with("bullets") and (group == "scene/bullets" or group == "actors/%d/bullets" % int(session.room.get("seat", 0))):
		attack_prediction.reconcile_bullets(rows, int(session.room.get("seat", 0)))

func sample_local_input(frame: Dictionary, delta: float) -> void:
	if not enabled or session.presentation.size() != 2: return
	prediction.tick(app.world, frame, delta, true)
	var events = attack_prediction.tick(app.world, frame, delta)
	if not events.is_empty():
		app.renderer.accept(events)
		app.audio.accept(events)
		app.haptics.accept(events, app.adapter.last_device)

func interpolate_entities(delta: float) -> void:
	if session.presentation.size() != 2: return
	interpolation.advance(delta, session.can_play())
	var seat = int(session.room.seat)
	var opponent = interpolation.sample("opponent")
	if not opponent.is_empty():
		opponent_visual = session.presentation[1 - seat].geometry.constrain_floor(opponent[0].pos, 12)
		session.presentation[1 - seat].player.pos = opponent_visual
		if session.room.get("game_mode") != "coop" and not app.world.enemies.is_empty(): app.world.enemies[0].pos = opponent_visual
	if session.room.get("game_mode") == "coop":
		for group in ["enemies", "bullets", "pickups", "zones", "delayed"]:
			var key = "scene/" + group
			if not interpolation.current.has(key): continue
			var rows = interpolation.sample(key, group == "enemies")
			for entity in rows:
				if entity.get("pos") is Vector2: entity.pos = app.world.geometry.constrain_floor(entity.pos, float(entity.get("radius", 5)))
			app.world.set(group, rows)
	else:
		var bullets: Array = []
		for index in 2:
			var rows = interpolation.sample("actors/%d/bullets" % index)
			for entity in rows:
				if index != seat: entity.friendly = false
				bullets.append(entity)
		app.world.bullets = bullets
	app.world.bullets = attack_prediction.merge(app.world.bullets, app.world)

func enter_battle() -> void:
	if session.presentation.size() != 2: return
	bind_worlds()
	if app.screen != "game" or app.paused:
		app.clear_modal()
		app.adapter.clear()
	app.screen = "game"
	app.paused = false
	app.renderer.hub = false
	app.hud.visible = false
	if not is_instance_valid(online_hud): Screens.build_hud(self)
	online_hud.visible = true
	page = "status"
	update_hud()

func physics(delta: float) -> void:
	if not enabled: return
	# Preserve held fingers through a brief stale snapshot. Transport still rejects
	# input while stale; a real pause, disconnect or menu releases the controls.
	var battle_visible = app.screen == "game" and not app.paused and session.state == "room" and session.room.get("phase") == "playing" and not app.orientation.blocked
	if battle_visible:
		app.adapter.set_phase("combat", session.room.get("game_mode") == "coop" and not str(app.world.run.get("active_item", {}).get("id", "")).is_empty())
		var frame = app.adapter.sample(app.renderer.to_world(app.get_viewport().get_mouse_position()), app.world.player.pos)
		if app.adapter.last_device in ["touch", "controller"]:
			var weapon = app.world.db.row("weapons", app.world.player.weapon)
			var mode = "off" if weapon.mode == "controlled" else str(app.settings.aim_mode)
			if frame.get("manual_aim", false) and mode == "auto": mode = "light"
			frame.aim = app.aim_assist.apply(frame.aim, app.world.player.pos, app.world.enemies, app.world.geometry, app.world.time, mode, float(weapon.range), session.event_match, weapon.mode)
		if app.world.player.get("downed", false): frame = Session.Protocol.empty_input()
		session.submit_input(frame)
		if not session.can_play(): prediction.tick(app.world, frame, delta, false)
	else:
		app.adapter.set_phase("result", false)
		session.clear_input()
		if not session.presentation.is_empty(): prediction.tick(app.world, {}, delta, false)
	interpolate_entities(delta)
	update_hud()
	app.update_hud()

func update_hud() -> void:
	if not is_instance_valid(online_hud) or session.presentation.size() != 2: return
	var seat = int(session.room.get("seat", 0))
	for i in 2:
		var player = session.presentation[i].player
		bars[i].value = 100 * float(player.hp) / maxf(1, float(player.max_hp))
		bars[i].tooltip_text = "%s  %d / %d" % [session.room.names[i], ceili(player.hp), ceili(player.max_hp)]
	var scores = session.room.get("score", [0, 0])
	score_label.text = "%d   :   %d" % [scores[seat], scores[1 - seat]]
	var phase = str(session.room.get("phase", ""))
	timer_label.text = str(ceili(float(session.room.get("countdown", 3)))) if phase == "countdown" else "%02d:%02d" % [int(session.room.get("remaining", 120)) / 60, int(session.room.get("remaining", 120)) % 60]
	hud_status.text = "准备" if phase == "countdown" else ("本轮平局" if int(session.room.get("round_winner", -1)) < 0 else ("本轮胜出" if int(session.room.round_winner) == seat else "下一轮再来")) if phase == "round_result" else "%d ms" % session.latency_ms
	hud_arena.text = "%s · 第 %d 轮" % [str(session.room.get("arena", {}).get("name", "对灯")), int(session.room.get("round", 1))]
	if session.room.get("game_mode") == "coop":
		score_label.text = "第 %d 层" % int(app.world.run.floor)
		timer_label.text = "◈ %d" % int(app.world.run.coins)
		hud_arena.text = str(session.room.arena.name) + " · " + app.world.Graph.NAMES.get(app.world.room_type(), "行愿")
		var scene = session.room.scene
		if app.world.player.get("downed", false): hud_status.text = "等待救援"
		elif int(scene.rescue.helper) >= 0: hud_status.text = "救援 %.1f" % maxf(0, 3 - float(scene.rescue.progress))
		elif session.presentation[1 - seat].player.get("downed", false): hud_status.text = "靠近 · E 救援"
		elif bool(scene.stairs): hud_status.text = "北门集合"
		elif scene.mode == "clear": hud_status.text = "同门集合"
	energy_bar.value = float(session.presentation[seat].player.energy)

func focus_lost() -> void:
	if enabled and session.room.get("phase") in ["playing", "countdown", "round_result", "draft"]: pause()
	session.clear_input()
