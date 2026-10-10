extends Node
const Session = preload("res://scripts/network/online_session.gd")
const Screens = preload("res://scripts/ui/online_ui.gd")
const Shortcuts = preload("res://scripts/core/choice_shortcuts.gd")
const Motion = preload("res://scripts/ui/weapon_motion.gd")
const Prediction = preload("res://scripts/network/motion_prediction.gd")
var app
var session
var enabled = false
var page = "hub"
var offline_world
var queued_action = ""
var code_draft = ""
var endpoint_draft = ""
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

func initialize(host, folder: String = "user://online-client") -> void:
	app = host
	session = Session.new(folder)
	add_child(session)
	session.changed.connect(refresh)
	session.state_received.connect(receive_state)
	session.events_received.connect(receive_events)
	session.problem.connect(func(code):
		if enabled: app.notice(Screens.error_text(code)))
	var character = app.world.db.row("characters", str(session.loadout.get("character", "")))
	if character.is_empty(): session.loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
	elif not character.skills.has(session.loadout.get("skill", "")): session.loadout.skill = character.skills[0]
	if app.world.db.row("weapons", str(session.loadout.get("weapon", ""))).is_empty(): session.loadout.weapon = "w01"

func active() -> bool:
	return enabled

func open() -> void:
	exit_requested = false
	if not enabled:
		enabled = true
		offline_world = app.world
		endpoint_draft = session.endpoint
		name_draft = session.nickname
	page = "hub"
	refresh()

func close() -> void:
	enabled = false
	queued_action = ""
	session.disconnect_service()
	app.adapter.clear()
	app.aim_assist.clear()
	app.world = offline_world
	app.renderer.world = offline_world
	app.renderer.online_actors.clear()
	app.renderer.online_motions.clear()
	app.renderer.visual_effects.clear()
	app.renderer.weapon_motion.clear()
	if is_instance_valid(online_hud): online_hud.queue_free()
	online_hud = null
	render_actors.clear()
	prediction.clear()
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
	if session.state in ["connecting", "reconnecting"] and session.wants_connection: return
	if session.state in ["online", "queued", "room"]: perform_queued_action(); return
	if session.state in ["expired", "incompatible"]:
		page = "identity" if session.state == "expired" else "hub"
		refresh()
		return
	if session.identity.get("consent", "") != "1.4":
		page = "consent"
		refresh()
		return
	session.connect_service(session.endpoint, session.nickname)

func accept_connection() -> void:
	session.identity.consent = "1.4"
	if not session.save_preferences(): app.notice(Screens.error_text("local_storage_unavailable")); return
	page = "hub"
	connect_service(queued_action)

func perform_queued_action() -> void:
	if queued_action.is_empty() or session.state != "online": return
	var action = queued_action
	queued_action = ""
	if action == "queue": session.request("queue", {"loadout": session.loadout})
	elif action == "code": session.request("code", {"code": code_draft, "loadout": session.loadout})

func join_code() -> void:
	if not Session.Protocol.valid_code(code_draft): app.notice("请输入六位数字，保留开头的 0。"); return
	connect_service("code")

func save_address() -> void:
	var address = endpoint_draft.strip_edges().trim_suffix("/")
	if not session.valid_endpoint(address): app.notice("请输入 ws:// 或 wss:// 开头的服务器地址。"); return
	session.disconnect_service()
	session.endpoint = address
	session.nickname = Session.Protocol.clean_name(name_draft)
	session.load_identity()
	if not session.save_preferences(): app.notice("联机设置暂未存下。"); return
	page = "hub"
	refresh()

func choose(index: int) -> void:
	if str(session.room.get("phase", "")) != "draft": return
	var seat = int(session.room.get("seat", 0))
	if int(session.room.picked[seat]) >= 0: return
	if session.pending.values().any(func(command): return command.get("op") == "choose"): return
	session.request("choose", {"index": index})

func ready() -> void:
	if session.room.get("phase") == "lobby":
		var seat = int(session.room.seat)
		session.request("ready", {"ready": not bool(session.room.ready[seat])})

func pause() -> void:
	app.adapter.clear()
	session.clear_input()
	if session.state == "room" and session.room.get("phase") not in ["suspended", "finished", "lobby"]: session.request("pause")
	page = "status"
	app.paused = true
	refresh()

func show_build() -> void:
	if session.room.is_empty(): return
	if session.room.get("phase") in ["playing", "countdown", "round_result", "draft"]: session.request("pause")
	session.clear_input()
	app.adapter.clear()
	page = "build"
	refresh()

func show_arena() -> void:
	if session.presentation.is_empty(): return
	if session.room.get("phase") in ["playing", "countdown", "round_result"]: session.request("pause")
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
	if page == "consent": queued_action = ""; show_page("hub"); return
	if page in ["config", "loadout", "code", "identity"] and session.room.is_empty(): show_page("hub"); return
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
			if index >= 0: choose(index); return true
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
	if phase in ["playing", "countdown", "round_result"] and session.state == "room" and page not in ["build", "arena", "leave_confirm"]:
		enter_battle()
		return
	app.paused = true
	app.hud.visible = false
	if is_instance_valid(online_hud): online_hud.visible = false
	app.adapter.clear()
	Screens.show(self)

func receive_state(value: Dictionary) -> void:
	if not enabled: return
	if session.presentation.size() == 2:
		if int(value.get("round", 0)) != last_round:
			last_round = int(value.get("round", 0))
			app.renderer.visual_effects.clear()
			app.renderer.weapon_motion.clear()
			app.renderer.online_motions.clear()
			prediction.clear()
			opponent_ready = false
			opponent_elapsed = 1.0
		bind_worlds()
	update_hud()
	if is_instance_valid(status_label):
		status_label.text = Screens.connection_text(self) + (" · %d 秒后默认第一项" % ceili(float(value.get("draft_remaining", 30))) if value.get("phase") == "draft" else "")
	if is_instance_valid(waiting_label): waiting_label.text = "等待恢复 · %d 秒" % ceili(float(value.get("suspend_remaining", 90)))

func bind_worlds() -> void:
	var seat = int(session.room.get("seat", 0))
	app.world = session.presentation[seat]
	app.renderer.world = app.world
	app.renderer.online_actors = {1001 + 1 - seat: session.presentation[1 - seat]}
	# Both players' attacks remain visible; opponent projectiles use danger colours.
	var own = session.room.actors[seat]
	var other = session.room.actors[1 - seat]
	if bound_snapshot != session.snapshot_serial:
		bound_snapshot = session.snapshot_serial
		prediction.observe(app.world, own.player, session.input_history, session.can_play())
		opponent_from = opponent_visual if opponent_ready else Vector2(other.player.pos)
		opponent_to = Vector2(other.player.pos)
		if opponent_from.distance_to(opponent_to) > 140: opponent_from = opponent_to
		opponent_elapsed = 0
		opponent_ready = true
	app.world.bullets = own.bullets.duplicate(true)
	app.world.zones = own.zones.duplicate(true)
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
		if int(event.seat) == seat: own.append(event)
		else: other.append(event)
	app.renderer.accept(own)
	app.renderer.accept_opponent(other, 1001 + 1 - seat)
	app.audio.accept(own + other)
	app.haptics.accept(own, app.adapter.last_device)

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
	if app.screen == "game" and not app.paused and session.can_play() and not app.orientation.blocked:
		app.adapter.set_phase("combat", false)
		var frame = app.adapter.sample(app.renderer.to_world(app.get_viewport().get_mouse_position()), app.world.player.pos)
		if app.adapter.last_device in ["touch", "controller"]:
			var weapon = app.world.db.row("weapons", app.world.player.weapon)
			var mode = "off" if weapon.mode == "controlled" else str(app.settings.aim_mode)
			if frame.get("manual_aim", false) and mode == "auto": mode = "light"
			frame.aim = app.aim_assist.apply(frame.aim, app.world.player.pos, app.world.enemies, app.world.geometry, app.world.time, mode, float(weapon.range), session.event_match, weapon.mode)
		session.submit_input(frame)
		prediction.tick(app.world, frame, delta, true)
	else:
		app.adapter.set_phase("result", false)
		session.clear_input()
		if not session.presentation.is_empty(): prediction.tick(app.world, {}, delta, false)
	if session.presentation.size() == 2:
		opponent_elapsed = minf(1, opponent_elapsed + delta / (1.0 / Session.Protocol.SNAPSHOT_RATE))
		opponent_visual = opponent_from.lerp(opponent_to, opponent_elapsed)
		var seat = int(session.room.seat)
		session.presentation[1 - seat].player.pos = opponent_visual
		if not app.world.enemies.is_empty(): app.world.enemies[0].pos = opponent_visual
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
	energy_bar.value = float(session.presentation[seat].player.energy)

func focus_lost() -> void:
	if enabled and session.room.get("phase") in ["playing", "countdown", "round_result", "draft"]: pause()
	session.clear_input()
