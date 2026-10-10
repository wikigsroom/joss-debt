extends RefCounted
const UI = preload("res://scripts/ui/game_theme.gd")
const Menu = preload("res://scripts/ui/menu_flow.gd")
const Protocol = preload("res://scripts/network/protocol.gd")

static func error_text(code: String) -> String:
	return {"invalid_endpoint": "服务器地址格式不正确。", "invalid_code": "请输入六位数字房间码。", "room_full": "这盏灯已有两人，请换一个房间码。",
		"room_started": "对局已经开始。", "server_full": "服务器暂时满员，请稍后再试。", "busy": "请先结束当前匹配或房间。",
		"invalid_choice": "这一轮已经选择过，或选择已失效。", "not_choosing": "当前无法选择供物。", "invalid_loadout": "配装无效，请重新选择。",
		"version_mismatch": "双方需要使用与服务器相同的游戏版本。", "session_expired": "这份联机身份已过期，请确认后创建新身份。",
		"session_replaced": "这份身份已在另一处登录。", "room_expired": "等待房间已到期，请重新点灯。",
		"storage_unavailable": "服务器正在恢复存档写入，对局暂时停战。", "local_storage_unavailable": "本机联机存档无法写入，操作未发送。",
		"invalid_server_packet": "连接数据异常，正在尝试恢复。", "stale_request": "操作已过期，请重新选择。"}.get(code, "操作未完成，请稍后重试。")

static func connection_text(c) -> String:
	var s = c.session
	match s.state:
		"online": return "已连接 · %d ms" % s.latency_ms
		"room": return "房间已连接 · %d ms" % s.latency_ms
		"queued": return "正在寻找另一位还愿人…"
		"connecting": return "正在连接服务器…"
		"reconnecting": return "正在恢复连接 · 第 %d 次尝试" % maxi(1, s.retry_count)
		"storage": return error_text("storage_unavailable")
		"expired": return error_text(s.last_error if not s.last_error.is_empty() else "session_expired")
		"incompatible": return error_text("version_mismatch")
	return "选择服务器后点灯"

static func action(c, parent: Control, text: String, icon: String, rect: Rect2, callback: Callable, primary: bool = false, id: String = "") -> Button:
	var button = c.app.icon_button(parent, text, icon, rect, callback, primary, text)
	button.set_meta("nav_id", "online_" + (id if not id.is_empty() else text))
	return button

static func bar_style(color: Color, radius: int = 7) -> StyleBoxFlat:
	var style = UI.style(color, Color.TRANSPARENT, radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_content_margin(side, 0)
	style.shadow_size = 0
	return style

static func shell(c, title: String, note: String = "", navigation: String = "") -> Control:
	var app = c.app
	var sheet = Menu.shell(app, title, note)
	app.screen = "online"
	app.menu_page = "online"
	app.modal.set_meta("navigation_page", navigation if not navigation.is_empty() else c.page)
	c.status_label = app.label(sheet, connection_text(c), Rect2(38, 613, 882, 22), 14, UI.MUTED)
	return sheet

static func show(c) -> void:
	if c.page == "leave_confirm": leave_confirm(c); return
	if c.page == "build": build(c); return
	if c.page == "arena": arena(c); return
	if not c.session.room.is_empty():
		match str(c.session.room.get("phase", "")):
			"lobby": lobby(c)
			"draft": draft(c)
			"finished": result(c)
			_: suspended(c)
		return
	match c.page:
		"consent": consent(c)
		"config": config(c)
		"loadout": loadout(c)
		"code": code(c)
		"identity": identity(c)
		_: hub(c)

static func consent(c) -> void:
	var app = c.app
	var sheet = shell(c, "连接对灯服务器", "首次连接前，请确认您选择的服务", "consent")
	app.label(sheet, "将连接到：", Rect2(135, 165, 820, 35), 20, UI.MUTED)
	app.label(sheet, c.session.endpoint, Rect2(135, 211, 870, 48), 28, UI.JADE)
	app.label(sheet, "连接后，所选服务器会处理连接 IP、匿名联机身份、昵称、\n配装、房间与操作信息，用于匹配、战斗裁定和断线恢复。\n对手能看到昵称、配装和对局状态。离线愿簿不会上传。\n请选择您信任的服务器；公网连接建议使用 wss。", Rect2(135, 294, 870, 140), 23, UI.TEXT)
	action(c, sheet, "隐私政策", "shield", Rect2(135, 477, 255, 76), func(): OS.shell_open("https://xhz.sidcloud.cn/privacy-policy"), false, "privacy")
	action(c, sheet, "返回", "arrow-left", Rect2(406, 477, 255, 76), func(): c.queued_action = ""; c.show_page("hub"), false, "decline")
	var accept = action(c, sheet, "同意并连接", "zap", Rect2(677, 477, 324, 76), c.accept_connection, true, "consent")
	accept.set_meta("nav_default", true)

static func hub(c) -> void:
	var app = c.app
	var sheet = shell(c, "对灯", "两人实时对战 · 三局两胜 · 每轮四选一", "hub")
	app.add_art(sheet, "res://assets/portraits/" + str(c.session.loadout.character) + ".png", Rect2(48, 142, 414, 400))
	var selected = app.panel(sheet, Rect2(92, 492, 340, 70), UI.SURFACE, Color.TRANSPARENT)
	app.add_art(selected, "res://assets/weapons/" + str(c.session.loadout.weapon) + ".png", Rect2(15, 7, 56, 56))
	app.add_art(selected, "res://assets/skills/" + str(c.session.loadout.skill) + ".png", Rect2(83, 7, 56, 56))
	app.label(selected, app.world.db.name_of("characters", c.session.loadout.character), Rect2(160, 14, 168, 40), 24)
	var height = maxf(72, app.mobile_button_height)
	var matching = c.session.state == "queued"
	var fast = action(c, sheet, "取消匹配" if matching else "快速对战", "x" if matching else "shuffle", Rect2(552, 158, 526, height), func(): c.session.request("cancel_queue") if matching else c.connect_service("queue"), true, "queue")
	fast.set_meta("nav_default", true)
	action(c, sheet, "六位房间码", "lock", Rect2(552, 158 + height + 16, 526, height), func(): c.show_page("code"), false, "code").disabled = matching
	action(c, sheet, "配装", "sword", Rect2(552, 158 + 2 * (height + 16), 255, height), func(): c.show_page("loadout"), false, "loadout").disabled = matching
	action(c, sheet, "服务器", "settings-2", Rect2(823, 158 + 2 * (height + 16), 255, height), func(): c.show_page("config"), false, "config").disabled = matching
	var stat = c.session.stats
	app.label(sheet, "%d 胜    %d 负    %d 平" % [stat.wins, stat.losses, stat.draws], Rect2(561, 442, 510, 38), 22, UI.JADE)
	app.label(sheet, "联机配装全部开放；离线成长不影响对战。\n同一房间中的两人需连接同一服务器。", Rect2(561, 495, 516, 62), 17, UI.MUTED)
	if c.session.state in ["expired", "incompatible"]:
		action(c, sheet, "处理连接" if c.session.state == "expired" else "检查服务器", "refresh-cw", Rect2(948, 554, 130, 56), func(): c.show_page("identity" if c.session.state == "expired" else "config"), false, "repair")

static func editor(c, parent: Control, rect: Rect2, value: String, placeholder: String, nav_id: String, changed: Callable, limit: int = 240) -> LineEdit:
	var field = LineEdit.new()
	field.position = rect.position
	field.size = rect.size.max(Vector2(0, c.app.mobile_button_height)) if c.app.mobile_ui else rect.size
	field.text = value
	field.placeholder_text = placeholder
	field.max_length = limit
	field.accessibility_name = placeholder
	field.set_meta("nav_id", "online_" + nav_id)
	field.set_meta("keyboard_label", placeholder)
	field.add_theme_font_size_override("font_size", 24)
	field.text_changed.connect(changed)
	parent.add_child(field)
	return field

static func config(c) -> void:
	var app = c.app
	var sheet = shell(c, "同一盏灯", "两位玩家填写相同的服务器地址", "config")
	app.icon(sheet, "settings-2", Rect2(72, 170, 74, 74), UI.JADE)
	app.label(sheet, "服务器地址", Rect2(181, 152, 790, 42), 25)
	var address = editor(c, sheet, Rect2(181, 210, 832, 72), c.endpoint_draft, "ws://192.168.1.10:18777", "endpoint", func(value): c.endpoint_draft = value)
	address.set_meta("nav_default", true)
	address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	app.label(sheet, "你的名字", Rect2(181, 308, 790, 42), 25)
	var nickname = editor(c, sheet, Rect2(181, 366, 832, 72), c.name_draft, "还愿人", "nickname", func(value): c.name_draft = value, 16)
	nickname.text_submitted.connect(func(_value): c.save_address())
	app.label(sheet, "同一 Wi-Fi 使用主机的局域网地址。互联网对战使用服务器提供的 wss:// 地址。\n联机会向所选服务器发送名字、对战输入和结果；身份密钥只用于恢复对局。", Rect2(181, 464, 832, 63), 17, UI.MUTED)
	action(c, sheet, "保存", "check", Rect2(770, 544, 242, 68), c.save_address, true, "save_address")

static func code(c) -> void:
	var app = c.app
	var sheet = shell(c, "约一盏灯", "双方输入相同的六位数字：先到者创建，后到者加入", "code")
	app.icon(sheet, "lock", Rect2(509, 148, 108, 108), UI.GOLD)
	var field = editor(c, sheet, Rect2(356, 288, 440, 94), c.code_draft, "000000", "room_code", func(value): c.code_draft = value, 6)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 48)
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.set_meta("nav_default", true)
	field.text_submitted.connect(func(_value): c.join_code())
	app.label(sheet, "房间码可包含开头的 0 · 每个房间限两人", Rect2(274, 409, 650, 36), 20, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action(c, sheet, "点灯 / 加入", "play", Rect2(380, 473, 392, 78), c.join_code, true, "join_code")

static func loadout(c) -> void:
	var app = c.app
	var selection = c.session.loadout
	var sheet = shell(c, "对灯配装", "所有还愿人、器具与角色技能平等开放", "loadout")
	app.add_art(sheet, "res://assets/portraits/" + str(selection.character) + ".png", Rect2(16, 160, 276, 330))
	app.label(sheet, app.world.db.name_of("characters", selection.character), Rect2(38, 477, 220, 44), 30).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chars = app.world.db.rows("characters")
	for i in chars.size():
		var row = chars[i]
		var tile = app.button(sheet, row.name, Rect2(310 + i * 132, 141, 120, 82), func():
			selection.character = row.id; selection.skill = row.skills[0]; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.set_meta("nav_id", "online_character_" + str(row.id))
		tile.set_meta("nav_default", row.id == selection.character)
		app.add_art(tile, "res://assets/heroes/" + str(row.id) + "_down.png", Rect2(32, 4, 56, 56))
		app.label(tile, row.name, Rect2(3, 57, 114, 24), 15).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if row.id == selection.character: UI.select(tile)
	var selected_char = app.world.db.row("characters", selection.character)
	for i in selected_char.skills.size():
		var id = str(selected_char.skills[i])
		var tile = app.button(sheet, app.world.db.name_of("skills", id), Rect2(310 + i * 264, 236, 250, 72), func(): selection.skill = id; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.set_meta("nav_id", "online_skill_" + id)
		app.add_art(tile, "res://assets/skills/" + id + ".png", Rect2(12, 10, 50, 50))
		app.label(tile, app.world.db.name_of("skills", id), Rect2(75, 17, 160, 38), 21)
		if id == selection.skill: UI.select(tile)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(310, 330)
	scroll.size = Vector2(802, 237)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for row in app.world.db.rows("weapons"):
		var tile = app.button(grid, row.name + " · " + str(row.mode), Rect2(0, 0, 120, 90), func(): selection.weapon = row.id; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.custom_minimum_size = Vector2(120, maxf(90, app.mobile_button_height))
		tile.set_meta("nav_id", "online_weapon_" + str(row.id))
		app.add_art(tile, "res://assets/weapons/" + str(row.id) + ".png", Rect2(33, 3, 54, 54))
		app.label(tile, row.name, Rect2(4, 61, 112, 24), 15).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if row.id == selection.weapon: UI.select(tile)
	app.label(sheet, "配装已自动保存", Rect2(47, 530, 226, 33), 17, UI.JADE)

static func player_card(c, parent: Control, seat: int, rect: Rect2) -> void:
	var app = c.app
	var state = c.session.room
	var card = app.panel(parent, rect, UI.SURFACE, Color.TRANSPARENT)
	if seat >= state.players.size():
		app.icon(card, "shuffle", Rect2(132, 78, 86, 86), UI.MUTED)
		app.label(card, "等待另一位还愿人", Rect2(25, 204, 300, 44), 23, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var loadout = state.players[seat]
	app.add_art(card, "res://assets/portraits/" + str(loadout.character) + ".png", Rect2(50, 8, 244, 214))
	app.label(card, str(state.names[seat]) + (" · 你" if seat == int(state.seat) else ""), Rect2(28, 211, 296, 40), 25).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.add_art(card, "res://assets/weapons/" + str(loadout.weapon) + ".png", Rect2(107, 259, 56, 56))
	app.add_art(card, "res://assets/skills/" + str(loadout.skill) + ".png", Rect2(190, 259, 56, 56))
	var online = state.connected[seat]
	var ready = bool(state.ready[seat]) if state.phase == "lobby" else bool(state.resume_ready[seat])
	app.label(card, "已准备" if ready and online else ("等待准备" if online else "暂时离线"), Rect2(22, 331, 300, 32), 20, UI.JADE if ready else UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func lobby(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "两人点灯", "快速匹配" if state.quick else "房间  " + str(state.code), "lobby")
	player_card(c, sheet, 0, Rect2(129, 139, 352, 386))
	player_card(c, sheet, 1, Rect2(669, 139, 352, 386))
	app.icon(sheet, "sword", Rect2(532, 272, 86, 86), UI.ACCENT)
	if not state.quick:
		action(c, sheet, "复制房间码", "copy", Rect2(889, 38, 150, 58), func(): DisplayServer.clipboard_set(str(state.code)); app.notice("房间码已复制。"), false, "copy_code")
	var ready = bool(state.ready[int(state.seat)])
	var start = action(c, sheet, "取消准备" if ready else "准备", "x" if ready else "check", Rect2(393, 536, 364, 76), c.ready, true, "ready")
	start.set_meta("nav_default", true)

static func draft(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "添一份愿", "第 %d 轮 · 选一份供物，之前的选择会保留" % int(state.round), "draft")
	var selected = int(state.picked[int(state.seat)])
	for i in state.offers.size():
		var id = str(state.offers[i])
		var row = app.world.db.row("relics", id)
		var card = app.button(sheet, "选择 " + str(row.name), Rect2(38 + i * 276, 161, 258, 346), func(): c.choose(i))
		card.text = ""
		card.disabled = selected >= 0
		card.set_meta("nav_id", "online_choice_" + str(i))
		card.set_meta("nav_default", i == 0)
		app.add_art(card, "res://assets/relics/" + id + ".png", Rect2(59, 18, 140, 140))
		app.label(card, str(row.name), Rect2(16, 177, 226, 44), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.label(card, str(row.get("description", row.get("behavior", ""))), Rect2(24, 233, 210, 60), 17, UI.MUTED)
		card.tooltip_text = str(row.name) + " · " + str(row.get("behavior", ""))
		app.label(card, str(i + 1), Rect2(107, 300, 44, 30), 23, UI.JADE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if selected == i: UI.select(card)
	app.label(sheet, "已选择，等待对方…" if selected >= 0 else "数字 1 / 2 / 3 / 4 直选 · Enter 确认当前卡片", Rect2(54, 526, 825, 44), 20, UI.JADE if selected >= 0 else UI.MUTED)
	action(c, sheet, "构筑", "book-open", Rect2(924, 533, 166, 76), c.show_build, false, "build")

static func suspended(c) -> void:
	var app = c.app
	var state = c.session.room
	var phase = str(state.get("phase", ""))
	var reconnecting = c.session.state == "reconnecting"
	var sheet = shell(c, "等灯回来" if reconnecting or state.get("suspend_reason") in ["disconnect", "server_restarted"] else "对灯暂停", "双方准备后恢复；暂停期间输入、计时与伤害全部停止", "suspended")
	app.icon(sheet, "refresh-cw" if reconnecting else "pause", Rect2(519, 151, 100, 100), UI.JADE)
	var seconds = ceili(float(state.get("suspend_remaining", Protocol.RECONNECT_SECONDS)))
	c.waiting_label = app.label(sheet, "等待恢复 · %d 秒" % seconds, Rect2(320, 284, 510, 56), 32)
	c.waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.label(sheet, "连接恢复后保留原配装、血量、比分与选择。", Rect2(235, 362, 682, 42), 21, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var confirmed = phase == "suspended" and bool(state.resume_ready[int(state.seat)])
	var button = action(c, sheet, "等待对方准备" if confirmed else "准备继续", "check", Rect2(176, 454, 312, 82), c.resume, true, "resume")
	button.disabled = c.session.state != "room" or phase != "suspended" or confirmed
	button.set_meta("nav_default", not button.disabled)
	action(c, sheet, "构筑", "book-open", Rect2(509, 454, 188, 82), c.show_build, false, "build")
	action(c, sheet, "离开", "log-out", Rect2(718, 454, 232, 82), func(): c.show_page("leave_confirm"), false, "leave")

static func result(c) -> void:
	var app = c.app
	var state = c.session.room
	var won = int(state.winner) == int(state.seat)
	var sheet = shell(c, "此灯共明" if int(state.winner) < 0 else ("你的灯更亮" if won else "下盏灯再见"), "三局两胜 · 对战结果已由服务器保存", "result")
	app.icon(sheet, "crown" if won else "sun", Rect2(515, 152, 110, 110), UI.GOLD)
	app.label(sheet, "%d   :   %d" % [state.score[int(state.seat)], state.score[1 - int(state.seat)]], Rect2(360, 286, 430, 92), 66).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var reason = {"forfeit": "对方离开" if won else "你已离开", "reconnect_timeout": "恢复连接超时", "completed": "对局完成"}.get(str(state.reason), "对局完成")
	app.label(sheet, reason, Rect2(340, 392, 470, 42), 22, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rematch = action(c, sheet, "已准备再战" if state.rematch_ready[int(state.seat)] else "再来一局", "rotate-ccw", Rect2(170, 492, 314, 80), func(): c.session.request("rematch"), true, "rematch")
	rematch.disabled = not state.connected.all(func(value): return value) or state.rematch_ready[int(state.seat)]
	rematch.set_meta("nav_default", not rematch.disabled)
	action(c, sheet, "构筑", "book-open", Rect2(507, 492, 188, 80), c.show_build, false, "build")
	action(c, sheet, "回大厅", "house", Rect2(718, 492, 263, 80), c.leave, false, "return")

static func leave_confirm(c) -> void:
	var app = c.app
	var sheet = shell(c, "离开这盏灯？", "对战中离开会判负；离线离开则在重连期限结束后结算。", "leave_confirm")
	app.icon(sheet, "log-out", Rect2(512, 182, 112, 112), UI.ACCENT)
	var stay = action(c, sheet, "留下", "arrow-left", Rect2(249, 408, 308, 88), func(): c.show_page("status"), true, "stay")
	stay.set_meta("nav_default", true)
	action(c, sheet, "确认离开", "log-out", Rect2(595, 408, 308, 88), c.leave, false, "confirm_leave")

static func identity(c) -> void:
	var app = c.app
	var sheet = shell(c, "重新点灯", "原身份失效或已在另一处登录。新身份会重新记录联机胜负。", "identity")
	app.icon(sheet, "lock", Rect2(515, 193, 108, 108), UI.MUTED)
	var cancel = action(c, sheet, "返回", "arrow-left", Rect2(249, 408, 308, 88), func(): c.show_page("hub"), true, "cancel_identity")
	cancel.set_meta("nav_default", true)
	action(c, sheet, "创建新身份", "refresh-cw", Rect2(595, 408, 308, 88), func(): c.session.forget_identity(); c.show_page("hub"); c.connect_service(), false, "new_identity")

static func build(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "两人的愿", "按轮次保留全部供物，返回后双方准备继续", "build")
	for seat in 2:
		var x = 38 + seat * 556
		app.label(sheet, str(state.names[seat]) + (" · 你" if seat == int(state.seat) else ""), Rect2(x, 145, 510, 44), 28, UI.JADE if seat == int(state.seat) else UI.ACCENT)
		var scroll = ScrollContainer.new()
		scroll.position = Vector2(x, 214)
		scroll.size = Vector2(530, 340)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		sheet.add_child(scroll)
		var list = VBoxContainer.new()
		list.add_theme_constant_override("separation", 12)
		scroll.add_child(list)
		var build: Array = state.get("builds", [[], []])[seat]
		if build.is_empty(): app.label(list, "本局尚未选择供物", Rect2(16, 16, 470, 60), 22, UI.MUTED)
		for i in build.size():
			var id = str(build[i])
			var row = app.world.db.row("relics", id)
			var tile = app.button(list, row.name, Rect2(0, 0, 510, 106), func(): app.notice(str(row.name) + " · " + str(row.get("behavior", ""))))
			tile.text = ""
			tile.custom_minimum_size = Vector2(510, 106)
			tile.set_meta("nav_id", "online_history_%d_%d" % [seat, i])
			app.add_art(tile, "res://assets/relics/" + id + ".png", Rect2(17, 15, 76, 76))
			app.label(tile, "%d · %s" % [i + 1, row.name], Rect2(115, 20, 365, 35), 25)
			app.label(tile, str(row.get("description", row.get("behavior", ""))), Rect2(115, 63, 365, 33), 16, UI.MUTED)

static func arena(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "这盏灯的位置", str(state.get("arena", {}).get("name", "对灯")), "arena")
	if c.session.presentation.is_empty(): return
	var picture = Rect2(180, 150, 800, 420)
	var path = str(state.arena.backgrounds[0])
	if not path.begins_with("res://"): path = "res://assets/" + path
	app.add_art(sheet, path, picture)
	for seat in 2:
		var pos: Vector2 = c.session.presentation[seat].player.pos
		var marker = picture.position + pos / Vector2(1280, 720) * picture.size
		app.icon(sheet, "circle-dot", Rect2(marker - Vector2.ONE * 16, Vector2.ONE * 32), UI.JADE if seat == int(state.seat) else UI.ACCENT)
		app.label(sheet, str(state.names[seat]), Rect2(marker + Vector2(-62, 19), Vector2(140, 34)), 18, UI.TEXT)

static func build_hud(c) -> void:
	var app = c.app
	c.online_hud = Control.new()
	c.online_hud.size = Vector2(1280, 720)
	c.online_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.interface.add_child(c.online_hud)
	var seat = int(c.session.room.get("seat", 0))
	c.bars = [null, null]
	for i in 2:
		var left = i == seat
		var x = 26 if left else 892
		var panel = app.panel(c.online_hud, Rect2(x, 18, 362, 90), Color(UI.INSET, .92), Color.TRANSPARENT)
		var loadout = c.session.room.players[i]
		app.add_art(panel, "res://assets/heroes/" + str(loadout.character) + "_down.png", Rect2(7, 11, 63, 63))
		app.label(panel, str(c.session.room.names[i]) + (" · 你" if left else ""), Rect2(82, 10, 254, 29), 20, UI.JADE if left else UI.ACCENT)
		var bar = ProgressBar.new()
		bar.position = Vector2(82, 51)
		bar.size = Vector2(254, 14)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", bar_style(UI.SURFACE))
		bar.add_theme_stylebox_override("fill", bar_style(UI.JADE if left else UI.ACCENT))
		panel.add_child(bar)
		c.bars[i] = bar
	var score = app.panel(c.online_hud, Rect2(494, 15, 292, 103), Color(UI.INSET, .92), Color.TRANSPARENT)
	c.score_label = app.label(score, "0   :   0", Rect2(19, 5, 254, 45), 32)
	c.score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.timer_label = app.label(score, "02:00", Rect2(19, 57, 128, 31), 23, UI.GOLD)
	c.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.hud_status = app.label(score, "", Rect2(149, 57, 128, 31), 18, UI.MUTED)
	c.hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arena_label = app.panel(c.online_hud, Rect2(420, 126, 440, 40), Color(UI.INSET, .85), Color.TRANSPARENT)
	c.hud_arena = app.label(arena_label, "", Rect2(8, 4, 424, 32), 17, UI.MUTED)
	c.hud_arena.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.energy_bar = ProgressBar.new()
	c.energy_bar.position = Vector2(39, 117)
	c.energy_bar.size = Vector2(326, 8)
	c.energy_bar.show_percentage = false
	c.energy_bar.add_theme_stylebox_override("background", bar_style(UI.INSET, 4))
	c.energy_bar.add_theme_stylebox_override("fill", bar_style(UI.GOLD, 4))
	c.online_hud.add_child(c.energy_bar)
	var height = maxf(60, app.mobile_button_height) if app.mobile_ui else 56.0
	app.icon_button(c.online_hud, "暂停对灯", "pause", Rect2(1214 - height, 128, height, height), c.pause)
	app.icon_button(c.online_hud, "本局构筑", "book-open", Rect2(1214 - 2 * height - 12, 128, height, height), c.show_build)
	app.icon_button(c.online_hud, "场地位置", "map", Rect2(1214 - 3 * height - 24, 128, height, height), c.show_arena)

