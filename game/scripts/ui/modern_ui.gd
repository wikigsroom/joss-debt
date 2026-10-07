extends RefCounted
## Product sheets share icon semantics, a restrained palette and one rounded rhythm.
const UI = preload("res://scripts/ui/game_theme.gd")
const Review = preload("res://scripts/ui/run_review.gd")
const ROUTE_ICONS = {"fire": "flame", "thread": "link", "ash": "sparkles", "seal": "shield", "wind": "wind", "ink": "pencil"}
const ROUTE_ART = {"fire": "r01", "thread": "r09", "ash": "r17", "seal": "r25", "wind": "r33", "ink": "r41"}
const ROUTE_TINTS = {"fire": Color("ee956f"), "thread": Color("d99bd5"), "ash": Color("ebc386"), "seal": Color("9dd6bf"), "wind": Color("8ec9ea"), "ink": Color("b9a4e8")}

static func menu(app) -> void:
	match str(app.menu_page):
		"splash": app.MenuFlow.splash(app)
		"files": app.MenuFlow.files(app)
		"title": title_menu(app)
		"challenges": app.MenuFlow.challenges(app)
		"stats": app.MenuFlow.stats(app)
		"items": app.MenuFlow.collection(app, false)
		"bestiary": app.MenuFlow.collection(app, true)
		"ending_archive": app.MenuFlow.ending_archive(app)
		"ending_view": app.MenuFlow.ending_view(app)
		"statistics": app.MenuFlow.statistics(app)
		"loadout": app.MenuFlow.loadout(app)
		_: character_select(app)

static func title_menu(app) -> void:
	app.MenuFlow.main_menu(app)

static func character_select(app) -> void:
	app.paused = true
	app.ui_signature = ""
	app.screen = "menu"
	app.hud.visible = false
	app.renderer.hub = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.9)
	app.label(app.modal, "香火债", Rect2(56, 42, 390, 72), 58)
	app.label(app.modal, "INCENSE DEBT", Rect2(60, 115, 360, 26), 16, UI.MUTED)
	var nav_size = maxf(64, app.mobile_button_height) if app.mobile_ui else 52.0
	app.icon_button(app.modal, "返回主菜单" if app.selected_run_kind == "normal" else "返回挑战", "arrow-left", Rect2(1208 - nav_size, 48, nav_size, nav_size), app.go_back)
	app.label(app.modal, "每日还愿" if app.selected_run_kind == "daily" else "新局", Rect2(844, 55, 254, 44), 24, UI.JADE)
	var selected = app.world.db.row("characters", app.selected)
	var hero = app.panel(app.modal, Rect2(56, 168, 412, 448), Color("e1d1ad"), Color.TRANSPARENT)
	var portrait = TextureRect.new()
	portrait.texture = load("res://assets/portraits/" + app.selected + ".png")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size = Vector2(412, 412)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(portrait)
	UI.round_texture(portrait, 24)
	app.label(hero, selected.name, Rect2(26, 396, 310, 42), 29, UI.BACKGROUND)
	app.icon(hero, "check" if app.progress.data.personal[app.selected].stage >= 1 else "flame", Rect2(352, 402, 26, 26), Color("844b38"))
	app.label(app.modal, "还愿人", Rect2(528, 133, 630, 46), 30)
	var characters = app.world.db.rows("characters")
	for i in characters.size():
		var character = characters[i]
		var unlocked = app.progress.data.characters.has(character.id)
		var choose = app.button(app.modal, "", Rect2(528 + (i % 3) * 232, 194 + int(i / 3) * 156, 216, 140), func():
			app.selected = character.id
			app.selected_weapon = ""
			if unlocked: app.show_menu("characters")
			else: app.show_character_details())
		choose.accessibility_name = "选择" + character.name
		choose.tooltip_text = character.name + " · " + character.passive + ("" if unlocked else "\n留名条件：" + character.unlock)
		choose.accessibility_description = choose.tooltip_text
		choose.set_meta("character_id", character.id)
		choose.set_meta("nav_default", app.selected == character.id)
		if app.selected == character.id: UI.select(choose)
		app.add_art(choose, "res://assets/heroes/" + character.id + "_down.png", Rect2(61, 1, 94, 100))
		var name = app.label(choose, character.name, Rect2(16, 102, 184, 30), 21)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not unlocked:
			choose.get_child(0).modulate = Color(.64, .64, .64)
			app.icon(choose, "lock", Rect2(176, 14, 20, 20), UI.MUTED)
		elif app.selected == character.id:
			app.icon(choose, "check", Rect2(176, 14, 20, 20), UI.ACCENT)
	var equipment = app.panel(app.modal, Rect2(528, 514, 680, 86), UI.INSET, Color.TRANSPARENT)
	equipment.mouse_filter = Control.MOUSE_FILTER_PASS
	equipment.tooltip_text = selected.passive if app.progress.data.characters.has(app.selected) else "留名条件：" + selected.unlock
	app.icon(equipment, "heart", Rect2(22, 29, 25, 25), UI.ACCENT)
	app.label(equipment, str(int(selected.health)), Rect2(57, 23, 47, 40), 25)
	app.add_art(equipment, "res://assets/weapons/" + app.starting_weapon(app.selected) + ".png", Rect2(124, 14, 58, 58))
	app.label(equipment, app.world.db.name_of("weapons", app.starting_weapon(app.selected)), Rect2(190, 29, 146, 33), 19)
	app.add_art(equipment, "res://assets/skills/" + str(selected.skills[0]) + ".png", Rect2(351, 14, 58, 58))
	var character_index = characters.find(selected)
	app.label(equipment, app.CHARACTER_TAGS[maxi(0, character_index)], Rect2(423, 29, 226, 33), 19, UI.JADE)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 64.0
	var achievement_summary = app.progress.achievement_summary(app.selected)
	var achievement_x = 528 + height + 12
	var loadout_x = achievement_x + 210
	var start_x = loadout_x + height + 12
	var achievement_button = app.icon_button(app.modal, "角色成就", "crown", Rect2(achievement_x, 622, 198, height), func(): app.show_achievements(app.selected), false, "成就 %d/%d" % [int(achievement_summary.unlocked), int(achievement_summary.total)])
	achievement_button.set_meta("character_achievement_button", app.selected)
	achievement_button.tooltip_text = "查看%s的四项角色成就" % selected.name
	var information = app.icon_button(app.modal, "角色详情", "info", Rect2(528, 622, height, height), app.show_character_details)
	app.icon_button(app.modal, "初始器具", "sword", Rect2(loadout_x, 622, height, height), func(): app.show_menu("loadout"))
	var start = app.icon_button(app.modal, "入巷还愿  →", "play", Rect2(start_x, 622, 1208 - start_x, height), app.request_new_run, true, "挑战动身" if app.selected_run_kind == "daily" else "动身")
	start.set_meta("nav_id", "begin_run")
	start.disabled = app.save_session.read_only or not app.progress.data.characters.has(app.selected)
	if start.disabled:
		start.text = "愿簿保护" if app.save_session.read_only else "未留名"
		start.icon = UI.icon("lock")
		start.tooltip_text = app.save_session.message if app.save_session.read_only else selected.unlock
	var marks = app.progress.achievement_rows(app.selected)
	var seed_button = app.icon_button(app.modal, "固定12位愿种" + (" · " + app.seed_draft if not app.seed_draft.is_empty() else " · 单次生效"), "shuffle", Rect2(1012, 51, 64, 64), func(): app.SeedUI.show(app))
	seed_button.set_meta("nav_id", "seed_input")
	seed_button.disabled = app.selected_run_kind == "daily"
	for i in marks.size():
		var row = marks[i]
		var achieved = app.progress.achievement_unlocked(str(row.id))
		var mark = app.icon_button(app.modal, "角色印记 " + (str(row.name) if achieved else "未完成"), str(row.icon), Rect2(56 + i * 96, 622, height, height), func(): app.show_achievements(app.selected))
		mark.set_meta("completion_mark", str(row.id))
		mark.modulate = Color.WHITE if achieved else Color(.6, .67, .63)
		if achieved: UI.select(mark)

static func pause(app, reason: String) -> void:
	if app.world.run.is_empty(): return
	app.paused = true
	app.screen = "pause"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.8)
	var sheet_rect = Rect2(194, 50, 892, 620) if app.mobile_ui else Rect2(334, 76, 612, 568)
	var sheet = app.panel(app.modal, sheet_rect, UI.INSET, Color.TRANSPARENT)
	var sheet_width = sheet_rect.size.x
	app.icon(sheet, "pause", Rect2((sheet_width - 48) * .5, 28, 48, 48), UI.ACCENT)
	var title = app.label(sheet, "灯下歇息", Rect2(36, 90, sheet_width - 72, 52), 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if reason != "灯还燃着，账可以慢慢还。":
		var detail = app.label(sheet, reason, Rect2(36, 148, sheet_width - 72, 42), 18, UI.MUTED)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 60.0
	var action_width = sheet_width - 96
	var first_y = 204 if reason == "灯还燃着，账可以慢慢还。" else 210
	app.icon_button(sheet, "继续动身", "play", Rect2(48, first_y, action_width, height), app.resume_game, true, "继续").grab_focus()
	app.icon_button(sheet, "本局记录", "scroll-text", Rect2(48, first_y + height + 14, action_width, height), app.show_run_history, false, "成长")
	var compact_width = height * 3 + 28
	var compact_x = (sheet_width - compact_width) * .5
	app.icon_button(sheet, "灯下设置", "settings-2", Rect2(compact_x, first_y + (height + 14) * 2, height, height), app.show_settings)
	app.icon_button(sheet, "成就", "crown", Rect2(compact_x + height + 14, first_y + (height + 14) * 2, height, height), app.show_achievements)
	app.icon_button(sheet, "存下这页 · 回主菜单", "house", Rect2(compact_x + (height + 14) * 2, first_y + (height + 14) * 2, height, height), app.save_to_menu)
	var seed_y = first_y + (height + 14) * 3 + 8
	app.label(sheet, str(app.world.run.get("seed_text", app.Seed.text(int(app.world.run.seed)))), Rect2(48, seed_y, action_width - 66, 42), 26, UI.JADE)
	var copy = app.icon_button(sheet, "复制本局12位愿种", "copy", Rect2(sheet_width - 100, seed_y - 4, 52, 52), func(): DisplayServer.clipboard_set(str(app.world.run.get("seed_text", app.Seed.text(int(app.world.run.seed))))); app.notice("愿种已复制。"))
	copy.set_meta("nav_id", "copy_seed")
	app.icon(sheet, "keyboard", Rect2(48, sheet_rect.size.y - 42, 22, 22), UI.MUTED)
	app.label(sheet, "方向键选择 · Enter 确认 · Esc 继续", Rect2(80, sheet_rect.size.y - 48, sheet_width - 128, 32), 16, UI.MUTED)
	app.audio.set_paused(true)

static func history_source_label(entry: Dictionary) -> String:
	var source = str(entry.get("source", "choice"))
	if source == "initial": return "初始"
	if source == "special": return "特殊房"
	if source == "repay": return "偿还"
	if source == "ground": return "拾取"
	return "已选"

static func history_icon(kind: String) -> String:
	return {"weapon": "sword", "skill": "flame", "relic": "sparkles", "talent": "leaf", "contract": "scroll-text",
		"sacrifice": "flame", "judgment": "circle-dot", "blessing": "sun", "repay": "check", "heal": "heart", "event": "book-open", "active": "zap", "trinket": "circle-dot"}.get(kind, "layers")

static func history_tint(kind: String) -> Color:
	return {"weapon": UI.GOLD, "skill": UI.ACCENT, "relic": UI.JADE, "talent": UI.GOLD, "contract": Color("d99bd5"),
		"sacrifice": UI.ACCENT, "judgment": UI.GOLD, "blessing": UI.JADE, "repay": UI.JADE, "heal": UI.JADE, "event": UI.MUTED}.get(kind, UI.MUTED)

static func history_row(app, entry: Dictionary) -> Dictionary:
	var kind = str(entry.get("type", ""))
	var id = str(entry.get("id", ""))
	var reward_kind = str(entry.get("reward_kind", kind))
	var reward_id = str(entry.get("reward_id", id))
	var table = {"weapon": "weapons", "skill": "skills", "relic": "relics", "talent": "talents", "contract": "debt_contracts", "repay": "debt_contracts", "active": "active_items", "trinket": "trinkets"}.get(kind, "")
	var row: Dictionary = app.world.db.row(table, id) if not table.is_empty() else {}
	var title = str(row.get("name", id))
	var description = str(row.get("behavior", ""))
	var art = ""
	if kind == "contract":
		var reward = app.world.db.row("relics", reward_id)
		title = "借愿 · " + str(row.get("name", id))
		description = "所得「%s」 · %s" % [reward.get("name", reward_id), row.get("penalty", "")]
		art = "res://assets/relics/%s.png" % reward_id
	elif kind == "repay":
		title = "偿还 · " + str(row.get("name", id))
		description = "已清除这份债约的后续压力"
		art = "res://assets/relics/%s.png" % str(app.world.db.row("debt_contracts", id).get("reward", "r17"))
	elif kind == "talent":
		art = "res://assets/relics/%s.png" % ROUTE_ART.get(str(row.get("route", "ash")), "r17")
	elif kind in ["weapon", "skill", "relic", "active", "trinket"]:
		art = "res://assets/%s/%s.png" % [table, id]
	else:
		var special_names = {"max_hp": "添一页 · 最大心火", "heal": "续心香", "rest": "歇一盏", "remember": "记住这一页", "interest": "翻开利息页"}
		title = special_names.get(id, id if not id.is_empty() else "特殊收益")
		description = description if not description.is_empty() else ("奖励：" + reward_kind)
	return {"kind": kind, "id": id, "reward_kind": reward_kind, "reward_id": reward_id, "title": title, "description": description, "art": art}

static func history_card(app, parent: Control, entry: Dictionary, index: int, width: float) -> void:
	var info = history_row(app, entry)
	var card = app.panel(parent, Rect2(0, 0, width, 78), UI.SURFACE, Color.TRANSPARENT)
	card.custom_minimum_size = Vector2(width, 78)
	card.set_meta("history_index", str(index))
	app.icon(card, history_icon(info.kind), Rect2(16, 25, 27, 27), history_tint(info.kind))
	if not info.art.is_empty() and ResourceLoader.exists(info.art): app.add_art(card, info.art, Rect2(54, 10, 56, 56))
	var title = app.label(card, info.title, Rect2(124, 10, width - 264, 30), 20)
	title.clip_text = true
	var room = "第%d章 · 房%d" % [int(entry.get("floor", 0)), int(entry.get("room_index", 0)) + 1]
	var meta = "%s  ·  %s  ·  %s" % [room, history_source_label(entry), info.kind]
	app.label(card, meta, Rect2(124, 43, width - 264, 24), 14, UI.MUTED)
	var short = info.description.split("；")[0]
	if short.length() > 32: short = short.left(31) + "…"
	app.label(card, short, Rect2(width - 132, 16, 112, 44), 14, UI.MUTED)
	var badge = app.panel(card, Rect2(width - 44, 22, 26, 26), UI.INSET, Color.TRANSPARENT)
	app.icon(badge, "check", Rect2(5, 5, 16, 16), UI.JADE)

static func run_history(app) -> void:
	if app.world.run.is_empty(): return
	app.paused = true
	app.screen = "run_history"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.91)
	var log: Array = app.world.run.get("growth_log", [])
	var shell = app.panel(app.modal, Rect2(42, 34, 1196, 652), UI.INSET, Color.TRANSPARENT)
	app.label(shell, "本局记录", Rect2(28, 20, 500, 54), 38)
	app.label(shell, "所有已选择的武器、技能、供物、行愿与债约都会按时间留档", Rect2(31, 76, 720, 28), 16, UI.MUTED)
	var counter = app.label(shell, "%d 项" % log.size(), Rect2(1000, 30, 112, 38), 21, UI.JADE)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.set_meta("history_entry_count", str(log.size()))
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	app.icon_button(shell, "收起记录", "x", Rect2(1128, 20, height, height), app.show_pause)
	var list_panel = app.panel(shell, Rect2(28, 122, 748, 478), UI.SURFACE, Color.TRANSPARENT)
	var scroll = ScrollContainer.new()
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.accessibility_name = "本局全部成长记录"
	scroll.set_meta("nav_default", true)
	scroll.position = Vector2(12, 12)
	scroll.size = Vector2(724, 454)
	list_panel.add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	if log.is_empty():
		app.icon(list_panel, "layers", Rect2(294, 178, 40, 40), UI.MUTED)
		app.label(list_panel, "还没有选择记录", Rect2(210, 232, 326, 34), 21, UI.MUTED)
	else:
		for i in range(log.size() - 1, -1, -1): history_card(app, list, log[i], i, 708)
	var summary = app.panel(shell, Rect2(800, 122, 368, 478), UI.SURFACE, Color.TRANSPARENT)
	app.icon(summary, "layers", Rect2(24, 22, 28, 28), UI.JADE)
	app.label(summary, "当前构筑", Rect2(67, 19, 250, 34), 24)
	var weapon = app.world.db.row("weapons", app.world.player.weapon)
	var skill = app.world.db.row("skills", app.world.player.skill)
	app.add_art(summary, "res://assets/weapons/%s.png" % app.world.player.weapon, Rect2(24, 76, 72, 72))
	app.label(summary, weapon.name, Rect2(112, 88, 226, 30), 20)
	app.label(summary, "当前主武器", Rect2(112, 119, 226, 22), 14, UI.MUTED)
	app.add_art(summary, "res://assets/skills/%s.png" % app.world.player.skill, Rect2(24, 168, 72, 72))
	app.label(summary, skill.name, Rect2(112, 180, 226, 30), 20, UI.JADE)
	app.label(summary, "当前焚债技能", Rect2(112, 211, 226, 22), 14, UI.MUTED)
	var stats = [["sparkles", str(app.world.run.relics.size()), "供物"], ["leaf", str(app.world.run.talents.size()), "行愿"], ["scroll-text", str(app.world.run.contracts.size()), "债约"]]
	for i in stats.size():
		var stat = stats[i]
		var cell = app.panel(summary, Rect2(24 + i * 108, 270, 96, 72), UI.INSET, Color.TRANSPARENT)
		app.icon(cell, stat[0], Rect2(35, 12, 24, 24), UI.GOLD if i == 1 else UI.MUTED)
		var value = app.label(cell, stat[1], Rect2(8, 39, 80, 25), 19)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var route_names: Array = []
	for route in app.world.db.rows("routes"):
		var count = app.world.run.talents.filter(func(id): return app.world.db.row("talents", id).route == route.id).size()
		if count > 0: route_names.append("%s ×%d" % [route.name, count])
	app.label(summary, "已点亮路线", Rect2(24, 367, 320, 28), 16, UI.MUTED)
	app.label(summary, "、".join(route_names) if not route_names.is_empty() else "尚未形成路线", Rect2(24, 401, 320, 60), 19, UI.TEXT if not route_names.is_empty() else UI.MUTED)
	app.icon_button(shell, "返回暂停", "pause", Rect2(800, 610, 368, height), app.show_pause, false, "暂停")

static func settings(app) -> void:
	if app.screen != "settings":
		app.remember_parent("settings")
		app.settings_return_to_menu = app.screen in ["menu", "hub"]
		app.settings_return_menu_page = app.menu_page if app.screen == "menu" else app.screen
	app.paused = true
	app.screen = "settings"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.92)
	var shell = app.panel(app.modal, Rect2(194, 48 if app.mobile_ui else 88, 892, 622 if app.mobile_ui else 548), UI.INSET, Color.TRANSPARENT)
	app.label(shell, "设置", Rect2(36, 26, 610, 60), 38)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	app.icon_button(shell, "收起", "x", Rect2(856 - height, 22, height, height), app.go_back)
	var rows = [["声音", "volume-2", "muted"], ["触控", "smartphone", "touch"], ["左右手", "hand", "mirror"], ["镜头", "eye", "reduce_motion"]]
	for i in rows.size():
		var entry = rows[i]
		var row = app.panel(shell, Rect2(32, 126 + i * (112 if app.mobile_ui else 94), 354, 100 if app.mobile_ui else 82), UI.SURFACE, Color.TRANSPARENT)
		app.icon(row, entry[1], Rect2(20, 36 if app.mobile_ui else 27, 28, 28), UI.MUTED)
		app.label(row, entry[0], Rect2(68, 32 if app.mobile_ui else 23, 153, 42), 23)
		var active = not app.settings[entry[2]] if entry[2] == "muted" else app.settings[entry[2]]
		var toggle_size = maxf(64, app.mobile_button_height) if app.mobile_ui else 62.0
		var toggle = app.icon_button(row, entry[0] + ("关闭" if active else "开启"), "check" if active else "x", Rect2(338 - toggle_size, 5 if app.mobile_ui else 10, toggle_size, toggle_size), func():
			app.settings[entry[2]] = not app.settings[entry[2]]
			app.apply_control_settings()
			app.audio.set_muted(app.settings.muted)
			app.persist_settings()
			app.show_settings(), active)
		toggle.tooltip_text = {"muted": "关闭或开启声音", "touch": "显示触屏双摇杆", "mirror": "交换左右手布局", "reduce_motion": "减弱镜头、顿帧与动态表现"}[entry[2]]
		toggle.set_meta("setting_key", entry[2])
		toggle.set_meta("nav_default", i == 0)
	var tiles = [["音量", "volume-2", "音量混音", app.show_audio_settings], ["按键", "gamepad-2", "操作映射", func(): app.ControlSettings.show_bindings(app)],
		["辅助", "crosshair", "瞄准与反馈", func(): app.ControlSettings.show_assistance(app)], ["布局", "touchpad", "触控布局", func(): app.ControlSettings.show_layout(app)],
		["愿簿", "upload", "愿簿传递", func(): app.SaveUI.show(app)], ["关于", "info", "关于与致谢", app.show_credits]]
	for i in tiles.size():
		var entry = tiles[i]
		var tile = app.button(shell, entry[2], Rect2(420 + (i % 2) * 214, 126 + int(i / 2) * (154 if app.mobile_ui else 125), 198, 138 if app.mobile_ui else 113), entry[3])
		tile.text = ""
		app.icon(tile, entry[1], Rect2(83, 32 if app.mobile_ui else 21, 32, 32), UI.JADE)
		var name = app.label(tile, entry[0], Rect2(16, 86 if app.mobile_ui else 67, 166, 32), 20)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func achievement_card(app, parent: Control, row: Dictionary, width: float) -> void:
	var progress = app.progress.achievement_progress(row)
	var unlocked = bool(progress.get("unlocked", false))
	var card = app.panel(parent, Rect2(0, 0, width, 104), UI.SURFACE if unlocked else UI.INSET, Color.TRANSPARENT)
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("nav_id", str(row.id))
	card.accessibility_name = str(row.name) if unlocked else "未揭示的愿"
	card.custom_minimum_size = Vector2(width, 104)
	card.set_meta("achievement_id", str(row.id))
	app.icon(card, str(row.get("icon", "layers")), Rect2(18, 22, 38, 38), UI.GOLD if unlocked else UI.MUTED)
	app.label(card, str(row.name) if unlocked else "未揭示的愿", Rect2(72, 14, width - 190, 30), 20, UI.TEXT if unlocked else UI.MUTED)
	var description = str(row.description) if unlocked else "完成条件后揭示记录"
	app.label(card, description, Rect2(72, 48, width - 180, 42), 14, UI.MUTED)
	var value = app.label(card, "%d / %d" % [int(progress.raw_value), int(progress.target)], Rect2(width - 102, 18, 76, 28), 15, UI.JADE if unlocked else UI.MUTED)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	app.icon(card, "check" if unlocked else "lock", Rect2(width - 48, 58, 22, 22), UI.JADE if unlocked else UI.MUTED)

static func achievements(app, character_id: String = "") -> void:
	app.remember_parent("achievements")
	app.paused = true
	app.screen = "achievements"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.93)
	app.modal.set_meta("navigation_page", character_id)
	var shell = app.panel(app.modal, Rect2(42, 28, 1196, 664), UI.INSET, Color.TRANSPARENT)
	app.label(shell, "成就愿簿", Rect2(28, 20, 450, 54), 38)
	app.label(shell, "每位还愿人的记录独立保存；达成后才揭示完整描述。", Rect2(31, 76, 720, 26), 16, UI.MUTED)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 54.0
	app.icon_button(shell, "收起成就", "x", Rect2(1128, 20, height, height), app.go_back)
	var filters = [{"id":"", "name":"全部", "icon":"layers"}]
	for character in app.world.db.rows("characters"):
		filters.append({"id": character.id, "name": character.name, "icon":"sparkles"})
	for i in filters.size():
		var filter = filters[i]
		var button_width = 154.0
		var tab = app.icon_button(shell, str(filter.name), str(filter.icon), Rect2(28 + i * (button_width + 8), 118, button_width, height), func(): app.show_achievements(str(filter.id)), str(filter.id) == character_id, "")
		tab.set_meta("nav_default", str(filter.id) == character_id)
		tab.set_meta("nav_id", "achievement_filter_" + str(filter.id))
		tab.text = str(filter.name)
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if str(filter.id) == character_id: UI.select(tab)
	var summary = app.progress.achievement_summary(character_id)
	app.label(shell, "%d / %d 已完成" % [int(summary.unlocked), int(summary.total)], Rect2(28, 184, 250, 31), 20, UI.JADE)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(28, 224)
	scroll.size = Vector2(1124, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.custom_minimum_size = Vector2(1124, 0)
	scroll.add_child(grid)
	for row in app.progress.achievement_rows(character_id): achievement_card(app, grid, row, 552)
	app.icon(shell, "keyboard", Rect2(28, 646, 22, 22), UI.MUTED)
	app.label(shell, "方向键筛选和翻阅 · PgUp / PgDn 翻页 · Esc 返回", Rect2(62, 642, 620, 30), 16, UI.MUTED)

static func choice_row(app, choice: Dictionary) -> Dictionary:
	var kinds = {"relic": "relics", "weapon": "weapons", "talent": "talents", "contract": "debt_contracts", "skill": "skills"}
	if choice.kind == "event" or choice.kind in ["sacrifice", "judgment", "blessing"]: return choice
	if choice.kind == "heal": return {"name": "续心香", "behavior": "恢复2心火。"}
	return app.world.db.row(kinds.get(choice.kind, "relics"), choice.id)

static func choice_art(choice: Dictionary, row: Dictionary) -> String:
	var id = str(choice.get("icon", choice.id))
	if choice.kind == "contract": id = row.reward
	elif choice.kind == "talent": id = ROUTE_ART.get(row.route, "r17")
	elif choice.kind == "heal": id = "r17"
	elif choice.kind in ["sacrifice", "judgment", "blessing"]:
		id = str(choice.get("art_id", id))
		if choice.get("reward_kind", "relic") == "weapon": return "res://assets/weapons/%s.png" % id
		if choice.get("reward_kind", "relic") == "talent": id = str(choice.get("art_id", "r17"))
	return "res://assets/%s/%s.png" % ["weapons" if choice.kind == "weapon" else ("skills" if choice.kind == "skill" else "relics"), id]

static func choices(app) -> void:
	app.hud.visible = false
	app.dim(.82)
	var kind = str(app.world.choices[0].kind) if not app.world.choices.is_empty() else "relic"
	var title = "选供物"
	if app.world.mode == "shop": title = "灯摊"
	elif app.world.mode == "debt": title = "借愿"
	elif kind == "talent": title = "成长"
	elif kind == "skill": title = "焚债演化"
	elif kind == "event": title = "回应旧愿"
	elif kind == "sacrifice": title = "献灯房"
	elif kind == "judgment": title = "判官房"
	elif kind == "blessing": title = "观音房"
	elif app.world.room_type() == "challenge": title = "破阵房"
	app.label(app.modal, title, Rect2(138, 122, 750, 65), 38)
	var wallet = app.panel(app.modal, Rect2(1034, 126, 108, 48), UI.SURFACE, Color.TRANSPARENT)
	app.icon(wallet, "coins", Rect2(17, 12, 24, 24), UI.GOLD)
	app.label(wallet, str(app.world.run.coins), Rect2(51, 8, 52, 34), 23)
	if app.mobile_ui and not app.world.choices.is_empty():
		mobile_choice(app)
		return
	var count = app.world.choices.size()
	var width = minf(308, (1004.0 - (count - 1) * 24) / maxi(1, count))
	var start = (1280 - (width * count + 24 * (count - 1))) / 2
	for i in count:
		var choice = app.world.choices[i]
		var row = choice_row(app, choice)
		var debt = choice.kind == "contract"
		var card = app.panel(app.modal, Rect2(start + i * (width + 24), 214, width, 408 if debt else 352), UI.SURFACE, Color.TRANSPARENT)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.tooltip_text = str(row.get("behavior", ""))
		app.icon(card, {"relic": "sparkles", "weapon": "sword", "talent": "leaf", "contract": "scroll-text", "heal": "heart", "skill": "flame", "event": "book-open", "sacrifice": "flame", "judgment": "circle-dot", "blessing": "sun"}.get(choice.kind, "sparkles"), Rect2(23, 20, 24, 24), UI.MUTED)
		if app.world.room_type() == "challenge": app.icon(card, "sword", Rect2(23, 20, 24, 24), UI.ACCENT)
		var number = app.panel(card, Rect2(width - 55, 16, 32, 32), UI.INSET, Color.TRANSPARENT)
		var hint = app.label(number, str(i + 1), Rect2(0, 1, 32, 28), 17, UI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.add_art(card, choice_art(choice, row), Rect2((width - 142) * .5, 42, 142, 142))
		var name = app.label(card, row.name, Rect2(20, 182, width - 40, 39), 26)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if debt:
			app.label(card, row.penalty, Rect2(24, 234, width - 48, 66), 17)
			app.icon(card, "coins", Rect2(24, 306, 20, 20), UI.GOLD)
			app.label(card, "%d  ·  +%d /章" % [row.repay_price, row.interest_per_floor], Rect2(55, 301, width - 76, 28), 17, UI.GOLD)
			card.tooltip_text = "得到「%s」\n%s\n偿还%d纸钱 · 跨章利息+%d · 风险%d" % [app.world.db.name_of("relics", row.reward), row.penalty, row.repay_price, row.interest_per_floor, row.risk_points]
		else:
			var description = str(row.get("behavior", ""))
			var brief = description.split("；")[0]
			if brief.length() > 46: brief = brief.left(45) + "…"
			var detail = app.label(card, brief, Rect2(24, 232, width - 48, 52), 17, UI.MUTED)
			detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if choice.kind == "skill":
				app.icon(card, "flame", Rect2(24, 20, 24, 24), UI.ACCENT)
				card.tooltip_text = description + "\n香火 %d · 冷却 %.1f秒" % [row.energy_cost, row.cooldown_s]
		var reason = app.world.choice_reason(choice)
		var taken = choice.get("taken", false)
		var can_trial = app.world.mode == "shop" and choice.kind == "weapon" and not taken
		var caption = "已取" if taken else ("献出%d心火" % int(choice.get("hp_cost", 0)) if choice.kind in ["sacrifice", "judgment"] else ("选取" if choice.price == 0 else str(choice.price)))
		var action = app.icon_button(card, "选择" + row.name, "check" if choice.price == 0 else "coins", Rect2(78 if can_trial else 18, 344 if debt else 290, width - (96 if can_trial else 36), 48), func(): app.choose_index(i), true, caption)
		action.tooltip_text = card.tooltip_text
		action.set_meta("nav_id", "choice_" + str(i))
		action.set_meta("nav_default", i == 0)
		action.disabled = not reason.is_empty() or (choice.kind == "heal" and app.world.player.hp >= app.world.player.max_hp)
		if not reason.is_empty():
			action.tooltip_text = reason
			action.text = "已取" if taken else "不足" if "纸钱" in reason else reason
		app.choice_buttons.append(action)
		if can_trial:
			var trial = app.icon_button(card, "试射" + row.name, "crosshair", Rect2(18, 290, 48, 48), func(): app.begin_shop_trial(i))
			trial.set_meta("shop_trial_index", i)
			trial.tooltip_text = "试射「%s」\n保留当前构筑，不扣纸钱。" % row.name
			if app.shop_trial_focus == i: trial.grab_focus()
	var evolution = kind == "skill"
	var footer_y = 638 if app.world.mode == "debt" else 605
	if not evolution:
		app.icon_button(app.modal, "留在此处 · 继续", "arrow-right", Rect2(963, footer_y, 179, 52), func(): app.world.skip_choice(); app.flush_events(); app.ui_signature = "", false, "继续")
	if app.world.mode in ["choice", "shop"] and kind in ["relic", "talent"]:
		var reroll = app.icon_button(app.modal, "换一页", "refresh-cw", Rect2(769, footer_y, 170, 52), func(): app.world.reroll(); app.flush_events(); app.ui_signature = "", false, "12" if app.world.mode == "shop" else str(app.world.run.rerolls))
		reroll.tooltip_text = "换一页 · 12纸钱" if app.world.mode == "shop" else "换一页 · 余%d次" % app.world.run.rerolls
		reroll.disabled = app.world.run.coins < 12 if app.world.mode == "shop" else app.world.run.rerolls <= 0
	if evolution:
		app.icon(app.modal, "gamepad-2", Rect2(139, footer_y + 14, 24, 24), UI.MUTED)
		app.label(app.modal, "1—4 直接选取", Rect2(176, footer_y + 9, 336, 36), 18, UI.MUTED)
	elif app.world.mode in ["choice", "shop"]:
		app.icon(app.modal, "keyboard", Rect2(139, footer_y + 14, 24, 24), UI.MUTED)
		app.label(app.modal, "1—4 直接选取", Rect2(176, footer_y + 9, 336, 36), 18, UI.MUTED)
	elif app.world.mode == "debt":
		app.icon(app.modal, "info", Rect2(139, footer_y + 14, 24, 24), UI.GOLD)
		app.label(app.modal, "先看代价，再借愿。", Rect2(176, footer_y + 9, 534, 36), 18, UI.MUTED)

static func mobile_choice(app) -> void:
	app.mobile_choice = clampi(app.mobile_choice, 0, app.world.choices.size() - 1)
	var choice = app.world.choices[app.mobile_choice]
	var row = choice_row(app, choice)
	var card = app.panel(app.modal, Rect2(126, 214, 1028, 362), UI.SURFACE, Color.TRANSPARENT)
	app.add_art(card, choice_art(choice, row), Rect2(38, 44, 224, 224))
	app.label(card, row.name, Rect2(300, 30, 683, 55), 34)
	var detail = str(row.get("behavior", ""))
	if choice.kind == "contract": detail = "所得：%s\n%s\n偿还 %d  ·  跨章 +%d" % [app.world.db.name_of("relics", row.reward), row.penalty, row.repay_price, row.interest_per_floor]
	elif choice.kind == "skill": detail += "\n香火 %d  ·  %.1f秒" % [row.energy_cost, row.cooldown_s]
	elif choice.kind in ["sacrifice", "judgment"]: detail += "\n代价：%d 心火" % int(choice.get("hp_cost", 0))
	app.label(card, detail, Rect2(300, 112, 683, 124), 24, UI.MUTED)
	var reason = app.world.choice_reason(choice)
	var action = app.icon_button(card, "选择" + row.name, "check" if choice.price == 0 else "coins", Rect2(697, 252, 305, app.mobile_button_height), func(): app.choose_index(app.mobile_choice), true, "选取" if choice.price == 0 else str(choice.price))
	if not reason.is_empty(): action.text = reason
	action.disabled = not reason.is_empty()
	app.choice_buttons.append(action)
	if app.world.mode == "shop" and choice.kind == "weapon" and not choice.get("taken", false):
		var trial = app.icon_button(card, "试射" + row.name, "crosshair", Rect2(300, 252, app.mobile_button_height, app.mobile_button_height), func(): app.begin_shop_trial(app.mobile_choice))
		trial.set_meta("shop_trial_index", app.mobile_choice)
		trial.tooltip_text = "试射「%s」\n保留当前构筑，不扣纸钱。" % row.name
		if app.shop_trial_focus == app.mobile_choice: trial.grab_focus()
	var height = app.mobile_button_height
	app.icon_button(app.modal, "上一件", "chevron-left", Rect2(126, 610, height, height), func(): app.mobile_choice = posmod(app.mobile_choice - 1, app.world.choices.size()); app.clear_modal(); app.show_choices())
	app.icon_button(app.modal, "下一件", "chevron-right", Rect2(148 + height, 610, height, height), func(): app.mobile_choice = posmod(app.mobile_choice + 1, app.world.choices.size()); app.clear_modal(); app.show_choices())
	app.label(app.modal, "%d / %d" % [app.mobile_choice + 1, app.world.choices.size()], Rect2(172 + height * 2, 634, 178, 45), 24, UI.MUTED)
	if choice.kind in ["relic", "talent"] and app.world.mode in ["shop", "choice"]:
		var reroll = app.icon_button(app.modal, "换一页", "refresh-cw", Rect2(718, 610, height, height), func(): app.world.reroll(); app.mobile_choice = 0; app.flush_events(); app.ui_signature = "")
		reroll.disabled = app.world.run.coins < 12 if app.world.mode == "shop" else app.world.run.rerolls <= 0
	if choice.kind != "skill":
		app.icon_button(app.modal, "留在此处 · 继续", "arrow-right", Rect2(846, 610, 308, height), func(): app.world.skip_choice(); app.flush_events(); app.ui_signature = "", false, "继续")

static func synergy_status(row: Dictionary) -> Dictionary:
	var count = int(row.get("owned_count", 0))
	if bool(row.get("complete", false)):
		return {"icon": "check", "color": UI.JADE, "label": "已成型", "count": count}
	if count > 0:
		return {"icon": "circle-dot", "color": UI.GOLD, "label": "进行中", "count": count}
	return {"icon": "lock", "color": UI.MUTED, "label": "未发现", "count": count}

static func synergy_card(app, grid: Control, row: Dictionary, selected_id: String) -> Button:
	var route = str(row.get("route", "fire"))
	var tint: Color = ROUTE_TINTS.get(route, UI.JADE)
	var tile = app.button(grid, "", Rect2(0, 0, 194, 112), func(): app.show_inventory("synergies", str(row.id)))
	tile.custom_minimum_size = Vector2(194, 112)
	tile.set_meta("item_id", str(row.id))
	tile.set_meta("synergy_id", str(row.id))
	tile.accessibility_name = str(row.name)
	var status = synergy_status(row)
	tile.tooltip_text = "%s · %s\n%s\n%s" % [row.name, status.label, row.result, row.tradeoff]
	if str(row.id) == selected_id:
		UI.select(tile)
	app.icon(tile, ROUTE_ICONS.get(route, "sparkles"), Rect2(12, 12, 21, 21), tint)
	var badge = app.panel(tile, Rect2(157, 10, 25, 25), UI.INSET, Color.TRANSPARENT)
	app.icon(badge, status.icon, Rect2(4, 4, 17, 17), status.color)
	var relics: Array = row.get("relics", [])
	for i in relics.size():
		var relic_id = str(relics[i])
		var art = "res://assets/relics/%s.png" % relic_id
		app.add_art(tile, art, Rect2(12 + i * 38, 39, 32, 32))
		if not row.get("owned_relics", []).has(relic_id):
			var veil = ColorRect.new()
			veil.position = Vector2(12 + i * 38, 39)
			veil.size = Vector2(32, 32)
			veil.color = Color(0.08, 0.1, 0.1, .64)
			veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(veil)
	var title = app.label(tile, str(row.name), Rect2(12, 77, 132, 25), 17, UI.TEXT)
	title.clip_text = true
	var progress = app.label(tile, "%d/3" % int(row.get("owned_count", 0)), Rect2(146, 77, 37, 24), 16, status.color)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return tile

static func synergy_detail(app, detail: Panel, row: Dictionary) -> void:
	var route = str(row.get("route", "fire"))
	var tint: Color = ROUTE_TINTS.get(route, UI.JADE)
	var status = synergy_status(row)
	app.icon(detail, ROUTE_ICONS.get(route, "sparkles"), Rect2(25, 15, 24, 24), tint)
	app.label(detail, str(row.name), Rect2(58, 11, 230, 31), 22)
	var status_chip = app.panel(detail, Rect2(290, 10, 92, 32), UI.INSET, Color.TRANSPARENT)
	app.icon(status_chip, status.icon, Rect2(9, 8, 16, 16), status.color)
	var status_label = app.label(status_chip, "%d/3" % status.count, Rect2(31, 4, 51, 23), 16, status.color)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var relics: Array = row.get("relics", [])
	for i in relics.size():
		var relic_id = str(relics[i])
		var chip = app.panel(detail, Rect2(407 + i * 48, 8, 40, 40), UI.INSET, Color.TRANSPARENT)
		app.add_art(chip, "res://assets/relics/%s.png" % relic_id, Rect2(4, 4, 32, 32))
		if not row.get("owned_relics", []).has(relic_id):
			var veil = ColorRect.new()
			veil.position = Vector2(4, 4)
			veil.size = Vector2(32, 32)
			veil.color = Color(0.08, 0.1, 0.1, .64)
			veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(veil)
	app.icon(detail, "sparkles", Rect2(25, 59, 18, 18), UI.JADE)
	var result = app.label(detail, str(row.result), Rect2(52, 55, 745, 25), 17, UI.TEXT)
	result.clip_text = true
	app.icon(detail, "info", Rect2(25, 88, 18, 18), UI.MUTED)
	var tradeoff = app.label(detail, str(row.tradeoff), Rect2(52, 84, 745, 25), 16, UI.MUTED)
	tradeoff.clip_text = true

static func inventory(app, page: String, selected_id: String) -> void:
	if app.world.run.is_empty(): return
	if app.screen not in ["inventory", "run_build"]: app.remember_parent("inventory")
	app.paused = true
	var finished = not app.world.run.get("result", "").is_empty()
	app.screen = "run_build" if finished else "inventory"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.modal.set_meta("navigation_page", page)
	app.dim(.91)
	app.label(app.modal, "本局构筑" if finished else "愿簿", Rect2(64, 57, 610, 65), 40)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var close: Callable = func(): app.return_to_parent("inventory")
	app.icon_button(app.modal, "收起愿簿", "x", Rect2(1208 - height, 57, height, height), close)
	var equipment = app.panel(app.modal, Rect2(64, 158, 282, 480), UI.INSET, Color.TRANSPARENT)
	var weapon = app.world.db.row("weapons", app.world.player.weapon)
	app.add_art(equipment, "res://assets/weapons/" + weapon.id + ".png", Rect2(71, 20, 140, 140))
	var name = app.label(equipment, weapon.name, Rect2(20, 172, 242, 40), 26)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.add_art(equipment, "res://assets/skills/" + app.world.player.skill + ".png", Rect2(32, 225, 62, 62))
	app.label(equipment, app.world.db.name_of("skills", app.world.player.skill), Rect2(112, 240, 150, 39), 21, UI.JADE)
	var active = app.world.Equipment.active_row(app.world)
	if not active.is_empty():
		app.add_art(equipment, "res://assets/active_items/" + active.id + ".png", Rect2(38, 300, 58, 58))
		app.label(equipment, "%d/%d" % [int(app.world.run.active_item.charge), int(active.charge_rooms)], Rect2(43, 360, 60, 24), 15, UI.JADE)
	if not str(app.world.run.trinket).is_empty(): app.add_art(equipment, "res://assets/trinkets/" + app.world.run.trinket + ".png", Rect2(169, 305, 48, 48))
	else: app.icon(equipment, "circle-dot", Rect2(181, 317, 24, 24), UI.EDGE)
	var routes = app.world.db.rows("routes")
	for i in routes.size():
		var route = routes[i]
		var count = app.world.run.talents.filter(func(id): return app.world.db.row("talents", id).route == route.id).size()
		var x = 30 + (i % 3) * 83
		var y = 395 + int(i / 3) * 41
		app.icon(equipment, ROUTE_ICONS[route.id], Rect2(x, y, 24, 24), UI.ACCENT if count > 0 else UI.EDGE)
		app.label(equipment, str(count), Rect2(x + 33, y - 4, 41, 34), 18, UI.TEXT if count > 0 else UI.MUTED)
	var tabs = [["供物", "relics", "sparkles"], ["装备", "equipment", "zap"], ["成长", "talents", "leaf"], ["债约", "contracts", "scroll-text"], ["组合册", "synergies", "layers"]]
	var tab_gap = 12.0
	var tab_width = (826.0 - tab_gap * (tabs.size() - 1)) / tabs.size()
	for i in tabs.size():
		var tab = tabs[i]
		var caption = tab[0] if page == tab[1] else ""
		var action = app.icon_button(app.modal, tab[0], tab[2], Rect2(382 + i * (tab_width + tab_gap), 158, tab_width, height), func(): app.show_inventory(tab[1]), false, caption)
		if page == tab[1]: UI.select(action)
	var entries: Array = app.world.run.relics.keys() if page == "relics" else (app.world.run.talents if page == "talents" else (app.world.run.contracts if page == "contracts" else app.world.synergy_rows()))
	if page == "equipment":
		entries = []
		if not active.is_empty(): entries.append({"id": active.id, "table": "active_items"})
		if not str(app.world.run.trinket).is_empty(): entries.append({"id": app.world.run.trinket, "table": "trinkets"})
	var ids = entries.map(func(entry): return str(entry.id) if page in ["contracts", "synergies", "equipment"] else str(entry))
	if not ids.has(selected_id): selected_id = str(ids[0]) if not ids.is_empty() else ""
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(382, 174 + height)
	scroll.size = Vector2(826, 282 - height if page != "synergies" else 282 - height)
	app.modal.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 4 if page == "synergies" else 6
	grid.add_theme_constant_override("h_separation", 12 if page == "synergies" else 16)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for id in ids:
		if page == "synergies":
			var synergy = entries[ids.find(id)]
			synergy_card(app, grid, synergy, selected_id)
			continue
		var kind = "debt_contracts" if page == "contracts" else page
		if page == "equipment": kind = entries[ids.find(id)].table
		var row = app.world.db.row(kind, id)
		var tile = app.button(grid, "", Rect2(0, 0, 121, 96), func(): app.show_inventory(page, id))
		tile.custom_minimum_size = Vector2(121, 96)
		tile.set_meta("item_id", id)
		tile.accessibility_name = row.name
		tile.tooltip_text = row.name + "\n" + str(row.get("behavior", row.get("penalty", "")))
		if id == selected_id: UI.select(tile)
		var art_id = ROUTE_ART[row.route] if page == "talents" else (row.reward if page == "contracts" else id)
		app.add_art(tile, "res://assets/%s/%s.png" % [kind if page == "equipment" else "relics", art_id], Rect2(24, 7, 74, 74))
		if page == "relics" and app.world.stack(id) > 1:
			app.label(tile, str(app.world.stack(id)), Rect2(92, 66, 25, 26), 17)
	var detail = app.panel(app.modal, Rect2(382, 478, 826, 118), UI.SURFACE, Color.TRANSPARENT)
	if selected_id.is_empty():
		app.icon(detail, "layers", Rect2(29, 42, 30, 30), UI.MUTED)
		app.label(detail, "靠近地面装备即可拾取。" if page == "equipment" else "组合会在持有供物后显影。", Rect2(83, 42, 689, 43), 22, UI.MUTED)
	elif page == "synergies":
		var synergy = entries[ids.find(selected_id)]
		synergy_detail(app, detail, synergy)
	else:
		var detail_kind = entries[ids.find(selected_id)].table if page == "equipment" else ("debt_contracts" if page == "contracts" else page)
		var row = app.world.db.row(detail_kind, selected_id)
		var item_name = app.label(detail, row.name, Rect2(25, 17, 775, 34), 25)
		item_name.set_meta("detail_item_id", selected_id)
		var description = str(row.get("behavior", ""))
		if detail_kind == "active_items": description += "  ·  %d/%d 清房充能" % [int(app.world.run.active_item.charge), int(row.charge_rooms)]
		if page == "contracts":
			var contract = entries[ids.find(selected_id)]
			description = "%s · 偿还 %d · 风险 %d" % [row.penalty, row.repay_price + contract.interest, row.risk_points]
		app.label(detail, description, Rect2(25, 61, 775, 48), 18, UI.MUTED)
	var composed = app.world.Composer.summary(app.world)
	for i in composed.size():
		var row = composed[i]
		var chip = app.panel(app.modal, Rect2(382 + i % 6 * 90, 610 + int(i / 6) * 40, 82, 34), UI.INSET, Color.TRANSPARENT)
		chip.tooltip_text = row.detail
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		app.icon(chip, row.icon, Rect2(9, 9, 16, 16), UI.JADE)
		app.label(chip, row.name, Rect2(30, 3, 50, 28), 13, UI.TEXT)
	app.icon_button(app.modal, "收起", "arrow-left", Rect2(952, 620, 256, height), close, false, "返回")

static func result(app) -> void:
	if app.world.run.is_empty(): return
	app.paused = true
	app.screen = "result"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	if app.world.run.result == "victory" and app.world.run.get("bosses_defeated", []).has("b37" if app.world.run.get("campaign", false) else "b03") and app.world.run.get("ending", "").is_empty():
		app.show_endings()
		return
	app.dim(.9)
	var win = app.world.run.result == "victory"
	app.icon(app.modal, "sun" if win else "flame", Rect2(608, 48, 64, 64), UI.ACCENT)
	var title = app.label(app.modal, "愿已有归处" if win else "火歇了，愿还在", Rect2(228, 126, 824, 74), 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cause_height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var cause = app.panel(app.modal, Rect2(314, 206, 652, cause_height), UI.INSET, Color.TRANSPARENT)
	var last: Dictionary = app.world.run.get("death_cause", {})
	if not win:
		Review.source_art(app, cause, last.get("source", {}), Rect2(16, 6, cause_height - 12, cause_height - 12))
		var name = app.label(cause, Review.Damage.brief(app.world.db, last), Rect2(cause_height + 15, (cause_height - 38) * .5, 619 - cause_height, 38), 22)
		name.set_meta("death_cause_id", last.get("source", {}).get("id", ""))
	else:
		app.icon(cause, "crown", Rect2(19, (cause_height - 28) * .5, 28, 28), UI.GOLD)
		app.label(cause, "回应了 %d 章旧愿" % int(app.world.run.floor), Rect2(74, (cause_height - 38) * .5, 550, 38), 22)
	var stats_top = 316 if app.mobile_ui else 288
	var entries = [["map", app.world.run.cleared, "清账"], ["flame", app.world.stats.detonations, "焚债"], ["link", app.world.stats.max_chain, "最长债链"], ["sparkles", roundi(app.world.stats.ash_energy), "收灰"], ["sword", app.world.stats.kills, "击退"], ["coins", app.world.run.coins, "纸钱"]]
	for i in entries.size():
		var entry = entries[i]
		var card = app.panel(app.modal, Rect2(194 + i * 151, stats_top, 137, 134), UI.SURFACE, Color.TRANSPARENT)
		app.icon(card, entry[0], Rect2(53, 17, 30, 30), UI.JADE)
		var number = app.label(card, str(int(entry[1])), Rect2(12, 57, 113, 44), 31)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var label = app.label(card, entry[2], Rect2(12, 103, 113, 25), 16, UI.MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var size = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var loot: Array = [["weapons", app.world.player.weapon], ["skills", app.world.player.skill]]
	var relics: Array = app.world.run.relics.keys()
	for i in mini(6 if app.mobile_ui else 12, relics.size()): loot.append(["relics", relics[i]])
	var width = loot.size() * size + (loot.size() - 1) * 12
	for i in loot.size():
		var item = loot[i]
		var tile = app.button(app.modal, "查看本局" + app.world.db.name_of(item[0], item[1]), Rect2((1280 - width) * .5 + i * (size + 12), stats_top + 156, size, size), func(): app.show_inventory("relics", item[1] if item[0] == "relics" else ""))
		tile.text = ""
		tile.set_meta("result_item_id", item[1])
		app.add_art(tile, "res://assets/" + item[0] + "/" + item[1] + ".png", Rect2(5, 5, size - 10, size - 10))
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 64.0
	var left = (1280 - (216 + 336 + height * 2 + 48)) * .5
	var bottom = 582 if app.mobile_ui else 552
	app.icon_button(app.modal, "回到灯下", "house", Rect2(left, bottom, 216, height), func(): app.show_menu("title"), false, "灯下")
	app.icon_button(app.modal, "本局构筑", "layers", Rect2(left + 232, bottom, height, height), func(): app.show_inventory())
	app.icon_button(app.modal, "受击与愿页", "book-open", Rect2(left + 248 + height, bottom, height, height), app.show_run_review)
	var retry = app.icon_button(app.modal, "再点一盏 · 新局", "refresh-cw", Rect2(left + 264 + height * 2, bottom, 336, height), func(): app.begin_run(app.world.run.character), true, "再点一盏")
	retry.disabled = app.save_session.read_only
	retry.grab_focus()
