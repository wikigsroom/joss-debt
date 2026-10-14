extends RefCounted
const TouchScroll = preload("res://scripts/ui/touch_scroll_container.gd")
const UI = preload("res://scripts/ui/game_theme.gd")
const Menu = preload("res://scripts/ui/menu_flow.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Modern = preload("res://scripts/ui/modern_ui.gd")
const RouteMap = preload("res://scripts/ui/route_map.gd")
static var art_regions: Dictionary = {}
static var art_textures: Dictionary = {}

static func art(c, parent: Control, path: String, rect: Rect2) -> void:
	if not ResourceLoader.exists(path): return
	if art_regions.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/online-art-layout.json"))
		if data is Dictionary: art_regions = data.get("records", {})
	var texture: Texture2D = load(path)
	if art_regions.has(path):
		if not art_textures.has(path):
			var bounds = art_regions[path].region
			var bitmap = texture.get_image()
			if bitmap.is_compressed(): bitmap.decompress()
			# Cache measured thumbnails in memory; source artwork stays unchanged.
			art_textures[path] = ImageTexture.create_from_image(bitmap.get_region(Rect2i(bounds[0], bounds[1], bounds[2], bounds[3])))
		texture = art_textures[path]
	var picture = TextureRect.new()
	# Drop the native texture minimum before assigning a smaller UI rectangle.
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = texture
	picture.position = rect.position
	picture.size = rect.size
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_meta("online_art_size", rect.size)
	parent.add_child(picture)
	if path.contains("/portraits/"): UI.round_texture(picture, 20)

static func error_text(code: String) -> String:
	return {"invalid_endpoint": "联机配置异常，请更新游戏。", "invalid_code": "请输入六位数字房间码。", "room_full": "这盏灯已有两人，请换一个房间码。",
		"room_started": "对局已经开始。", "server_full": "服务器暂时满员，请稍后再试。", "busy": "请先结束当前匹配或房间。",
		"invalid_choice": "这一轮已经选择过，或选择已失效。", "not_choosing": "当前无法选择供物。", "invalid_loadout": "配装无效，请重新选择。",
		"version_mismatch": "双方需要使用与服务器相同的游戏版本。", "session_expired": "这份联机身份已过期，请确认后创建新身份。",
		"session_replaced": "这份身份已在另一处登录。", "room_expired": "等待房间已到期，请重新点灯。",
		"storage_unavailable": "服务器正在恢复存档写入，对局暂时停战。", "local_storage_unavailable": "本机联机存档无法写入，操作未发送。",
		"invalid_server_packet": "连接数据异常，正在尝试恢复。", "stale_request": "操作已过期，请重新选择。",
		"stale_choice": "房间奖励已经变化，请重新选择。", "room_mode_mismatch": "此房间玩法不同，请双方选择相同模式。",
		"stale_context": "房间状态已经变化，请重新操作。", "command_timeout": "操作确认超时，正在恢复连接。",
		"state_timeout": "地图同步中断，正在恢复连接。", "too_many_pending_requests": "正在确认上一项操作，请稍候。",
		"battle_unavailable": "战斗连接暂时不可达，请重试或切换网络。", "battle_connect_failed": "战斗连接未建立，请检查网络后重试。",
		"battle_disconnected": "战斗连接中断，正在恢复共灯。", "battle_bind_timeout": "战斗连接超时，正在重连。",
		"snapshot_too_large": "房间同步数据超出限制，请联系开发者。"}.get(code, "操作未完成，请稍后重试。")

static func connection_text(c) -> String:
	var s = c.session
	match s.state:
		"online": return "已连接 · %d ms" % s.latency_ms
		"room": return "房间已连接 · %d ms" % s.latency_ms
		"queued": return "正在寻找另一位还愿人…"
		"connecting": return "正在点亮共灯…"
		"synchronizing": return "正在恢复地图状态…"
		"reconnecting": return "正在恢复连接 · 第 %d 次尝试" % maxi(1, s.retry_count)
		"storage": return error_text("storage_unavailable")
		"local_storage": return error_text("local_storage_unavailable")
		"expired": return error_text(s.last_error if not s.last_error.is_empty() else "session_expired")
		"incompatible": return error_text("version_mismatch")
	return "共灯连接已关闭"

static func action(c, parent: Control, text: String, icon: String, rect: Rect2, callback: Callable, primary: bool = false, id: String = "") -> Button:
	var button = c.app.icon_button(parent, text, icon, rect, callback, primary, text)
	button.add_theme_constant_override("icon_max_width", 32 if rect.size.y >= 72 else 26)
	button.add_theme_constant_override("h_separation", 14)
	button.add_theme_font_size_override("font_size", 24 if primary and rect.size.x > 300 else 21)
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
	var header_size = maxf(56, app.mobile_button_height) if app.mobile_ui else 56.0
	var privacy = app.icon_button(sheet, "隐私政策", "shield", Rect2(1080 - 2 * header_size - 16, 24, header_size, header_size), func(): OS.shell_open("https://xhz.sidcloud.cn/privacy-policy"))
	privacy.set_meta("nav_id", "online_privacy")
	app.screen = "online"
	app.menu_page = "online"
	app.modal.set_meta("navigation_page", navigation if not navigation.is_empty() else c.page)
	app.icon(sheet, "circle-dot", Rect2(38, 606, 20, 20), UI.JADE)
	c.status_label = app.label(sheet, connection_text(c), Rect2(70, 603, 818, 27), 16, UI.MUTED)
	return sheet

static func show(c) -> void:
	if c.page == "leave_confirm": leave_confirm(c); return
	if c.page == "build": build(c); return
	if c.page == "repay": cooperative_repayment(c); return
	if c.page == "arena": arena(c); return
	if not c.session.room.is_empty():
		match str(c.session.room.get("phase", "")):
			"lobby": lobby(c)
			"draft": draft(c)
			"finished": result(c)
			"settling": settling(c)
			_: suspended(c)
		return
	match c.page:
		"profile": profile(c)
		"loadout": loadout(c)
		"code": code(c)
		"identity": identity(c)
		_: hub(c)

static func settling(c) -> void:
	var sheet = shell(c, "收好这盏灯", "", "settling")
	c.app.icon(sheet, "hourglass", Rect2(529, 252, 94, 94), UI.JADE)
	c.app.label(sheet, "正在保存本次行愿", Rect2(326, 384, 500, 44), 28, UI.TEXT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func hub(c) -> void:
	var app = c.app
	var coop = c.session.game_mode == "coop"
	var sheet = shell(c, "共灯" if coop else "对灯", "两人合作闯关 · 十一层共同行愿 · 倒地互救" if coop else "两人实时对战 · 三局两胜 · 每轮四选一", "hub")
	var portrait = app.panel(sheet, Rect2(40, 144, 440, 440), UI.SURFACE, Color.TRANSPARENT)
	art(c, portrait, "res://assets/portraits/" + str(c.session.loadout.character) + ".png", Rect2(54, 16, 332, 332))
	var selected = app.panel(portrait, Rect2(20, 364, 400, 60), UI.INSET, Color.TRANSPARENT)
	art(c, selected, "res://assets/weapons/" + str(c.session.loadout.weapon) + ".png", Rect2(10, 6, 48, 48))
	art(c, selected, "res://assets/skills/" + str(c.session.loadout.skill) + ".png", Rect2(70, 6, 48, 48))
	app.label(selected, app.world.db.name_of("characters", c.session.loadout.character), Rect2(140, 13, 244, 34), 24)
	var matching = c.session.state == "queued" or c.queued_action == "queue"
	var expired = c.session.state == "expired"
	var incompatible = c.session.state == "incompatible"
	var fast_text = "重新点灯" if expired else "更新游戏" if incompatible else "取消匹配" if matching else "寻找队友" if coop else "快速对战"
	var fast = action(c, sheet, fast_text, "refresh-cw" if expired or incompatible else "x" if matching else "shuffle", Rect2(552, 144, 526, 88), func():
		if expired: c.show_page("identity")
		elif incompatible: OS.shell_open("https://github.com/wikigsroom/joss-debt/releases/latest")
		elif matching: c.cancel_matching()
		else: c.connect_service("queue"), true, "queue")
	fast.set_meta("nav_default", true)
	action(c, sheet, "六位房间码", "lock", Rect2(552, 248, 526, 80), func(): c.show_page("code"), false, "code").disabled = matching
	action(c, sheet, "配装", "sword", Rect2(552, 344, 255, 72), func(): c.show_page("loadout"), false, "loadout").disabled = matching
	action(c, sheet, "昵称", "settings-2", Rect2(823, 344, 255, 72), func(): c.name_draft = c.session.nickname; c.show_page("profile"), false, "profile").disabled = matching
	var stat = c.session.stats
	var cooperate = action(c, sheet, "合作闯关", "heart", Rect2(552, 448, 255, 64), func(): c.set_mode("coop"), coop, "mode_coop")
	var duel = action(c, sheet, "切磋对战", "sword", Rect2(823, 448, 255, 64), func(): c.set_mode("duel"), not coop, "mode_duel")
	cooperate.disabled = matching
	duel.disabled = matching
	app.label(sheet, "%d 次共同行愿    %d 次失灯" % [stat.get("coop_wins", 0), stat.get("coop_losses", 0)] if coop else "%d 胜    %d 负    %d 平" % [stat.wins, stat.losses, stat.draws], Rect2(561, 529, 510, 32), 20, UI.JADE)
	app.label(sheet, "共享地图与纸钱，各自选择成长。" if coop else "平等配装 · 离线成长不影响切磋。", Rect2(561, 567, 516, 26), 17, UI.MUTED)

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

static func profile(c) -> void:
	var app = c.app
	var sheet = shell(c, "你的名字", "队友会看到这个昵称，无需注册账号", "profile")
	app.icon(sheet, "settings-2", Rect2(528, 162, 80, 80), UI.JADE)
	app.label(sheet, "联机昵称", Rect2(240, 279, 680, 38), 25)
	var nickname = editor(c, sheet, Rect2(240, 333, 680, 80), c.name_draft, "还愿人", "nickname", func(value): c.name_draft = value, 16)
	nickname.set_meta("nav_default", true)
	nickname.text_submitted.connect(func(_value): c.save_profile())
	app.label(sheet, "请勿使用真实姓名、手机号或其他个人联系方式。", Rect2(240, 437, 680, 32), 18, UI.MUTED)
	action(c, sheet, "保存昵称", "check", Rect2(390, 504, 380, 80), c.save_profile, true, "save_profile")

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
	var sheet = shell(c, "联机配装", "所有还愿人、器具与角色技能平等开放", "loadout")
	var portrait = app.panel(sheet, Rect2(32, 144, 252, 440), UI.SURFACE, Color.TRANSPARENT)
	art(c, portrait, "res://assets/portraits/" + str(selection.character) + ".png", Rect2(16, 38, 220, 260))
	app.label(portrait, app.world.db.name_of("characters", selection.character), Rect2(16, 322, 220, 44), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chars = app.world.db.rows("characters")
	for i in chars.size():
		var row = chars[i]
		var tile = app.button(sheet, row.name, Rect2(310 + i * 132, 144, 120, 92), func():
			selection.character = row.id; selection.skill = row.skills[0]; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.set_meta("nav_id", "online_character_" + str(row.id))
		tile.set_meta("nav_default", row.id == selection.character)
		art(c, tile, "res://assets/heroes/" + str(row.id) + "_down.png", Rect2(30, 6, 60, 60))
		app.label(tile, row.name, Rect2(4, 67, 112, 24), 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if row.id == selection.character: UI.select(tile)
	var selected_char = app.world.db.row("characters", selection.character)
	for i in selected_char.skills.size():
		var id = str(selected_char.skills[i])
		var tile = app.button(sheet, app.world.db.name_of("skills", id), Rect2(310 + i * 264, 252, 250, 76), func(): selection.skill = id; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.set_meta("nav_id", "online_skill_" + id)
		art(c, tile, "res://assets/skills/" + id + ".png", Rect2(12, 10, 56, 56))
		app.label(tile, app.world.db.name_of("skills", id), Rect2(82, 18, 156, 38), 21)
		if id == selection.skill: UI.select(tile)
	var scroll = TouchScroll.new()
	scroll.position = Vector2(310, 348)
	scroll.size = Vector2(802, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for row in app.world.db.rows("weapons"):
		var tile = app.button(grid, row.name + " · " + str(row.mode), Rect2(0, 0, 120, 104), func(): selection.weapon = row.id; c.session.save_preferences(); c.refresh())
		tile.text = ""
		tile.custom_minimum_size = Vector2(120, maxf(104, app.mobile_button_height))
		tile.set_meta("nav_id", "online_weapon_" + str(row.id))
		art(c, tile, "res://assets/weapons/" + str(row.id) + ".png", Rect2(28, 8, 64, 64))
		app.label(tile, row.name, Rect2(4, 78, 112, 24), 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if row.id == selection.weapon: UI.select(tile)
	app.label(portrait, "配装已自动保存", Rect2(16, 390, 220, 30), 17, UI.JADE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func player_card(c, parent: Control, seat: int, rect: Rect2) -> void:
	var app = c.app
	var state = c.session.room
	var card = app.panel(parent, rect, UI.SURFACE, Color.TRANSPARENT)
	if seat >= state.players.size():
		app.icon(card, "shuffle", Rect2(144, 102, 64, 64), UI.MUTED)
		app.label(card, "等待另一位还愿人", Rect2(24, 218, 304, 44), 22, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var loadout = state.players[seat]
	art(c, card, "res://assets/portraits/" + str(loadout.character) + ".png", Rect2(80, 16, 192, 192))
	var name_label = app.label(card, str(state.names[seat]) + (" · 你" if seat == int(state.seat) else ""), Rect2(24, 223, 304, 38), 23)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = name_label.text
	art(c, card, "res://assets/weapons/" + str(loadout.weapon) + ".png", Rect2(110, 280, 56, 56))
	art(c, card, "res://assets/skills/" + str(loadout.skill) + ".png", Rect2(186, 280, 56, 56))
	var online = state.connected[seat]
	var ready = bool(state.ready[seat]) if state.phase == "lobby" else bool(state.resume_ready[seat])
	app.label(card, "已准备" if ready and online else ("等待准备" if online else "暂时离线"), Rect2(24, 350, 304, 30), 19, UI.JADE if ready else UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func lobby(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "两人点灯", "快速匹配" if state.quick else "房间  " + str(state.code), "lobby")
	player_card(c, sheet, 0, Rect2(129, 139, 352, 386))
	player_card(c, sheet, 1, Rect2(669, 139, 352, 386))
	app.icon(sheet, "heart" if state.get("game_mode") == "coop" else "sword", Rect2(544, 278, 64, 64), UI.JADE)
	if not state.quick:
		var height = maxf(56, app.mobile_button_height) if app.mobile_ui else 56.0
		var copy = app.icon_button(sheet, "复制房间码", "copy", Rect2(1080 - 3 * height - 32, 24, height, height), func(): DisplayServer.clipboard_set(str(state.code)); app.notice("房间码已复制。"))
		copy.set_meta("nav_id", "online_copy_code")
	var ready = bool(state.ready[int(state.seat)])
	var start = action(c, sheet, "取消准备" if ready else "准备", "x" if ready else "check", Rect2(393, 526, 364, 72), c.ready, true, "ready")
	start.set_meta("nav_default", true)

static func draft(c) -> void:
	if c.session.room.get("game_mode") == "coop": cooperative_choices(c); return
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
		art(c, card, "res://assets/relics/" + id + ".png", Rect2(59, 18, 140, 140))
		app.label(card, str(row.name), Rect2(16, 177, 226, 44), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.label(card, str(row.get("description", row.get("behavior", ""))), Rect2(24, 233, 210, 60), 17, UI.MUTED)
		card.tooltip_text = str(row.name) + " · " + str(row.get("behavior", ""))
		app.label(card, str(i + 1), Rect2(107, 300, 44, 30), 23, UI.JADE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if selected == i: UI.select(card)
	app.label(sheet, "已选择，等待对方…" if selected >= 0 else "数字 1 / 2 / 3 / 4 直选 · Enter 确认当前卡片", Rect2(54, 526, 825, 44), 20, UI.JADE if selected >= 0 else UI.MUTED)
	action(c, sheet, "构筑", "book-open", Rect2(904, 526, 186, 72), c.show_build, false, "build")

static func suspended(c) -> void:
	var app = c.app
	var state = c.session.room
	var phase = str(state.get("phase", ""))
	var reconnecting = c.session.state == "reconnecting"
	var sheet = shell(c, "等灯回来" if reconnecting or state.get("suspend_reason") in ["disconnect", "server_restarted"] else "暂歇一盏灯", "双方准备后恢复；暂停期间输入、计时与伤害全部停止", "suspended")
	app.icon(sheet, "refresh-cw" if reconnecting else "pause", Rect2(519, 151, 100, 100), UI.JADE)
	var seconds = ceili(float(state.get("grace_left", Protocol.RECONNECT_SECONDS)))
	c.waiting_label = app.label(sheet, "双方准备后继续" if state.get("game_mode") == "coop" and state.get("suspend_reason") == "menu" else "等待恢复 · %d 秒" % seconds, Rect2(320, 284, 510, 56), 32)
	c.waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.label(sheet, "恢复后保留房间、配装、血量与成长选择。", Rect2(235, 362, 682, 42), 21, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var confirmed = phase == "suspended" and bool(state.resume_ready[int(state.seat)])
	var button = action(c, sheet, "等待对方准备" if confirmed else "准备继续", "check", Rect2(176, 454, 312, 82), c.resume, true, "resume")
	button.disabled = c.session.state != "room" or phase != "suspended" or confirmed
	button.set_meta("nav_default", not button.disabled)
	action(c, sheet, "构筑", "book-open", Rect2(509, 454, 188, 82), c.show_build, false, "build")
	action(c, sheet, "离开", "log-out", Rect2(718, 454, 232, 82), func(): c.show_page("leave_confirm"), false, "leave")

static func result(c) -> void:
	if c.session.room.get("game_mode") == "coop": cooperative_result(c); return
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
	var sheet = shell(c, "离开这盏灯？", "离开会结束本次合作。断线可在90秒内重连，双方准备后继续。" if c.session.room.get("game_mode") == "coop" else "对战中离开会判负；离线离开则在重连期限结束后结算。", "leave_confirm")
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
	var sheet = shell(c, "两人的愿", "每次供物、技能、器具与契约选择均保留 · 返回后双方准备继续", "build")
	var has_repayment = false
	if state.get("game_mode") == "coop" and not c.session.presentation.is_empty():
		var own = c.session.presentation[int(state.seat)]
		if bool(state.get("scene", {}).get("stairs", false)) and not own.run.contracts.is_empty():
			has_repayment = true
			action(c, sheet, "偿还契约 · 共享金币 %d" % int(own.run.coins), "scroll-text", Rect2(350, 530, 450, 64), func(): c.show_page("repay"), false, "repay")
	for seat in 2:
		var x = 38 + seat * 556
		app.label(sheet, str(state.names[seat]) + (" · 你" if seat == int(state.seat) else ""), Rect2(x, 145, 510, 44), 28, UI.JADE if seat == int(state.seat) else UI.ACCENT)
		var scroll = TouchScroll.new()
		scroll.position = Vector2(x, 214)
		scroll.size = Vector2(530, 302 if has_repayment else 340)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		sheet.add_child(scroll)
		var list = VBoxContainer.new()
		list.add_theme_constant_override("separation", 12)
		scroll.add_child(list)
		var build: Array = state.get("builds", [[], []])[seat]
		if build.is_empty(): app.label(list, "本局尚未选择供物", Rect2(16, 16, 470, 60), 22, UI.MUTED)
		for i in build.size():
			var info = Modern.history_row(app, build[i]) if build[i] is Dictionary else {"title": app.world.db.name_of("relics", str(build[i])), "description": app.world.db.row("relics", str(build[i])).get("behavior", ""), "art": "res://assets/relics/" + str(build[i]) + ".png"}
			var tile = app.button(list, info.title, Rect2(0, 0, 510, 106), func(): app.notice(str(info.title) + " · " + str(info.description)))
			tile.text = ""
			tile.custom_minimum_size = Vector2(510, 106)
			tile.set_meta("nav_id", "online_history_%d_%d" % [seat, i])
			if not str(info.art).is_empty(): art(c, tile, str(info.art), Rect2(17, 15, 76, 76))
			else: app.icon(tile, "sparkles", Rect2(29, 29, 50, 50), UI.JADE)
			app.label(tile, "%d · %s" % [i + 1, info.title], Rect2(115, 20, 365, 35), 25)
			app.label(tile, str(info.description), Rect2(115, 63, 365, 33), 16, UI.MUTED)

static func arena(c) -> void:
	if c.session.room.get("game_mode") == "coop": cooperative_map(c); return
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "这盏灯的位置", str(state.get("arena", {}).get("name", "对灯")), "arena")
	if c.session.presentation.is_empty(): return
	var picture = Rect2(180, 150, 800, 420)
	var path = str(state.arena.backgrounds[0])
	if not path.begins_with("res://"): path = "res://assets/" + path
	art(c, sheet, path, picture)
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
		art(c, panel, "res://assets/heroes/" + str(loadout.character) + "_down.png", Rect2(7, 11, 63, 63))
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
	app.icon_button(c.online_hud, "暂停", "pause", Rect2(1214 - height, 128, height, height), c.pause)
	app.icon_button(c.online_hud, "本局构筑", "book-open", Rect2(1214 - 2 * height - 12, 128, height, height), c.show_build)
	app.icon_button(c.online_hud, "场地位置", "map", Rect2(1214 - 3 * height - 24, 128, height, height), c.show_arena)
	if c.session.room.get("game_mode") == "coop":
		app.icon_button(c.online_hud, "拾取 / 救援 · E", "heart", Rect2(1214 - height, 206, height, height), func(): app.adapter.pending_interact = true)

static func cooperative_choices(c) -> void:
	var app = c.app
	var state = c.session.room
	var sheet = shell(c, "两盏灯的愿", "各自选择成长 · 双方完成后继续闯关", "cooperative_choices")
	var waiting = int(state.picked[int(state.seat)]) >= 0
	var offers: Array = state.offers
	var replacement = state.get("choice_mode") == "replace"
	if replacement:
		app.label(sheet, "愿簿已满 · 选择一件供物替换", Rect2(100, 139, 850, 48), 25, UI.GOLD)
		var ids = c.session.presentation[int(state.seat)].run.relics.keys()
		for i in ids.size():
			var id = str(ids[i])
			var button = action(c, sheet, app.world.db.name_of("relics", id), "sparkles", Rect2(44 + (i % 6) * 180, 217 + int(i / 6) * 132, 168, 114), func(): c.cooperative_action("replace", id), false, "replace_" + id)
			button.text = ""
			button.icon = null
			art(c, button, "res://assets/relics/" + id + ".png", Rect2(50, 7, 68, 68))
			app.label(button, app.world.db.name_of("relics", id), Rect2(8, 78, 152, 28), 18).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action(c, sheet, "放弃新供物", "x", Rect2(395, 525, 360, 74), func(): c.cooperative_action("replace"), false, "cancel_replace")
		return
	c.choice_page = clampi(c.choice_page, 0, maxi(0, int((offers.size() - 1) / 4)))
	var start = c.choice_page * 4
	var count = mini(4, offers.size() - start)
	var origin = (1152 - (count * 258 + maxi(0, count - 1) * 16)) * .5
	for i in count:
		var index = start + i
		var choice = offers[index]
		var kind = str(choice.get("reward_kind", choice.kind))
		var table = {"relic": "relics", "weapon": "weapons", "skill": "skills", "talent": "talents", "contract": "debt_contracts"}.get(kind, "")
		var row = app.world.db.row(table, str(choice.id)) if not table.is_empty() else {}
		var title = str(choice.get("name", row.get("name", "续灯" if choice.kind == "heal" else choice.id)))
		var body = str(choice.get("behavior", row.get("description", row.get("behavior", ""))))
		var card = app.button(sheet, title, Rect2(origin + i * 274, 162, 258, 329), func(): c.choose(index))
		card.text = ""
		card.disabled = waiting or bool(choice.get("taken", false)) or not str(choice.get("reason", "")).is_empty()
		card.tooltip_text = body + (" · " + str(choice.reason) if not str(choice.get("reason", "")).is_empty() else "")
		card.set_meta("nav_id", "online_choice_" + str(index))
		card.set_meta("nav_default", i == 0 and not card.disabled)
		var art_id = str(choice.get("art_id", choice.id))
		var art_table = "relics" if choice.has("art_id") else table
		if art_table in ["relics", "weapons", "skills"]: art(c, card, "res://assets/" + art_table + "/" + art_id + ".png", Rect2(77, 24, 104, 104))
		else: app.icon(card, "heart" if choice.kind == "heal" else "scroll-text" if choice.kind == "contract" else "leaf", Rect2(97, 44, 64, 64), UI.JADE)
		app.label(card, title, Rect2(16, 148, 226, 60), 24).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.label(card, body, Rect2(24, 216, 210, 66), 17, UI.MUTED)
		app.label(card, str(i + 1), Rect2(20, 289, 30, 28), 19, UI.GOLD)
		app.icon(card, "coins", Rect2(91, 292, 22, 22), UI.GOLD)
		app.label(card, str(int(choice.get("price", 0))), Rect2(124, 289, 54, 28), 19, UI.GOLD)
		if int(choice.get("hp_cost", 0)) > 0:
			app.icon(card, "heart", Rect2(181, 292, 22, 22))
			app.label(card, "-%d" % int(choice.hp_cost), Rect2(210, 289, 40, 28), 18, UI.ACCENT)
	app.label(sheet, "已完成 · 等待队友" if waiting else "1 / 2 / 3 / 4 直选 · ↑↓←→ 与 Enter 导航", Rect2(49, 499, 1038, 32), 19, UI.JADE if waiting else UI.MUTED)
	if offers.size() > 4:
		action(c, sheet, "上一页", "arrow-left", Rect2(40, 530, 169, 64), func(): c.choice_page = maxi(0, c.choice_page - 1); c.refresh(), false, "previous_choices")
		action(c, sheet, "下一页", "arrow-right", Rect2(225, 530, 169, 64), func(): c.choice_page = mini(int((offers.size() - 1) / 4), c.choice_page + 1); c.refresh(), false, "next_choices")
	var skip = action(c, sheet, "完成" if state.choice_mode in ["shop", "debt"] else "跳过", "check", Rect2(445, 530, 205, 64), func(): c.cooperative_action("skip"), false, "skip")
	skip.disabled = waiting or (not offers.is_empty() and offers[0].kind == "skill")
	var reroll = action(c, sheet, "重掷", "rotate-ccw", Rect2(667, 530, 185, 64), func(): c.cooperative_action("reroll"), false, "reroll")
	reroll.disabled = waiting or state.choice_mode != "choice" or c.session.presentation[int(state.seat)].run.rerolls <= 0
	action(c, sheet, "构筑", "book-open", Rect2(869, 530, 212, 64), c.show_build, false, "build")

static func cooperative_repayment(c) -> void:
	var app = c.app
	var state = c.session.room
	var own = c.session.presentation[int(state.seat)]
	var sheet = shell(c, "还一份愿", "楼层出口 · 使用共享金币偿还你自己的契约", "repay")
	app.label(sheet, "共享金币 %d" % int(own.run.coins), Rect2(55, 135, 1030, 48), 27, UI.GOLD)
	var scroll = TouchScroll.new()
	scroll.position = Vector2(55, 196)
	scroll.size = Vector2(1035, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	if own.run.contracts.is_empty(): app.label(list, "本层契约已偿还", Rect2(12, 12, 900, 64), 26, UI.JADE)
	for contract in own.run.contracts:
		var id = str(contract.id)
		var row = app.world.db.row("debt_contracts", id)
		var cost = int(row.repay_price) + int(contract.interest)
		var button = action(c, list, "%s · ◈ %d" % [str(row.name), cost], "scroll-text", Rect2(0, 0, 1000, 90), func(): c.cooperative_action("repay", id), false, "repay_" + id)
		button.custom_minimum_size = Vector2(1000, 90)
		button.disabled = own.run.coins < cost or state.get("suspend_reason") != "menu"
		button.tooltip_text = str(row.get("behavior", ""))

static func cooperative_result(c) -> void:
	var app = c.app
	var state = c.session.room
	var won = int(state.winner) == 2
	var sheet = shell(c, "共同行愿完成" if won else "两盏灯暂歇", "合作结果由服务器保存 · 离线愿簿保持独立", "result")
	app.icon(sheet, "crown" if won else "heart", Rect2(510, 148, 120, 120), UI.GOLD if won else UI.JADE)
	app.label(sheet, "十一层行愿" if won else "第 %d 层 · 清房 %d" % [int(state.round), int(state.score[0])], Rect2(263, 296, 630, 74), 43).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.label(sheet, {"team_defeat": "两人均已倒地", "team_victory": "一起走到了最后一页", "partner_left": "队友离开了合作", "reconnect_timeout": "恢复连接超时"}.get(str(state.reason), "本次合作结束"), Rect2(263, 398, 630, 40), 23, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rematch = action(c, sheet, "已准备" if state.rematch_ready[int(state.seat)] else "再走一程", "rotate-ccw", Rect2(170, 492, 314, 80), func(): c.session.request("rematch"), true, "rematch")
	rematch.disabled = not state.connected.all(func(value): return value) or state.rematch_ready[int(state.seat)]
	rematch.set_meta("nav_default", not rematch.disabled)
	action(c, sheet, "构筑", "book-open", Rect2(507, 492, 188, 80), c.show_build, false, "build")
	action(c, sheet, "回大厅", "house", Rect2(718, 492, 263, 80), c.leave, false, "return")

static func cooperative_map(c) -> void:
	var app = c.app
	var sheet = shell(c, "共同行路", "两人到同一扇门集合后换房 · 地图仅用于查看", "arena")
	if c.session.presentation.is_empty(): return
	var dungeon = c.session.presentation[int(c.session.room.seat)]
	var scroll = TouchScroll.new()
	scroll.pan_horizontal = true
	scroll.position = Vector2(82, 155)
	scroll.size = Vector2(988, 430)
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var canvas = Control.new()
	var minimum = Vector2.INF
	var maximum = -Vector2.INF
	for coordinate in dungeon.run.graph.coords:
		minimum = minimum.min(Vector2(coordinate))
		maximum = maximum.max(Vector2(coordinate))
	var visual = RouteMap.new()
	visual.world = dungeon
	visual.origin = minimum
	visual.spacing = 88
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.custom_minimum_size = (maximum - minimum) * visual.spacing + Vector2(110, 110)
	scroll.add_child(canvas)
	canvas.add_child(visual)
	for i in dungeon.run.graph.types.size():
		if not RouteMap.Graph.visible(dungeon.run.graph, i): continue
		var kind = str(dungeon.run.graph.types[i])
		var current = i == int(dungeon.run.room)
		var name = str(RouteMap.Graph.NAMES.get(kind, kind))
		var node = app.icon_button(canvas, name, RouteMap.ROOM_ICONS.get(kind, "circle-dot"), Rect2(visual.location(Vector2(dungeon.run.graph.coords[i])) - Vector2(30, 30), Vector2(60, 60)), func(): app.notice(name + " · 沿房间内的门集合前行"), current)
		node.set_meta("nav_id", "online_map_room_" + str(i))
		if current: scroll.ensure_control_visible.call_deferred(node)

