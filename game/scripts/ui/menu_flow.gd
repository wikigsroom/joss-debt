extends RefCounted
## Title -> file -> main -> run/stats/options. Extra game systems live below it.
const UI = preload("res://scripts/ui/game_theme.gd")
const Daily = preload("res://scripts/core/daily_seed.gd")
const ENDINGS = [
	["burn", "焚账", "解除所有债，带走重要的愿页，让剩下的旧账化灰。", "r17"],
	["repay", "偿还", "撕去利息页，留下已经回应的愿。还愿庭成为互助的集市。", "r54"],
	["rewrite", "换约", "不再记谁欠了多少。共同的账，只留下谁已经回应。", "r48"]]

static func shell(app, title: String, note: String = "") -> Control:
	app.paused = true
	app.screen = "menu"
	app.hud.visible = false
	app.renderer.hub = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.93)
	var sheet = app.panel(app.modal, Rect2(64, 42, 1152, 636), UI.INSET, Color.TRANSPARENT)
	app.label(sheet, title, Rect2(32, 24, 930, 62), 42)
	if not note.is_empty(): app.label(sheet, note, Rect2(35, 92, 1018, 38), 18, UI.MUTED)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var back = app.icon_button(sheet, "返回上一层", "arrow-left", Rect2(1080 - height, 24, height, height), app.go_back)
	back.set_meta("nav_id", "back")
	return sheet

static func splash(app) -> void:
	var sheet = shell(app, "")
	app.add_art(sheet, "res://assets/portraits/c_paper.png", Rect2(690, 48, 422, 510))
	app.label(sheet, "香火债", Rect2(54, 162, 650, 100), 78)
	app.label(sheet, "INCENSE DEBT", Rect2(60, 276, 500, 36), 22, UI.MUTED)
	app.label(sheet, "留一盏灯，回应未完的愿。", Rect2(60, 344, 585, 44), 24, UI.JADE)
	var start = app.icon_button(sheet, "翻开愿簿", "play", Rect2(60, 460, 426, 80), func(): app.show_menu("files"), true, "开始")
	start.set_meta("nav_default", true)
	start.set_meta("nav_id", "start")

static func files(app) -> void:
	var sheet = shell(app, "选择愿簿", "三个独立存档 · 角色、图鉴、成就与进行中的还愿分别保存")
	for slot in range(1, 4):
		var summary = app.save_slot_summary(slot)
		var card = app.button(sheet, "选择愿簿 %d" % slot, Rect2(38 + (slot - 1) * 366, 180, 344, 348), func(): app.select_save_slot(slot))
		card.text = ""
		card.set_meta("save_slot", str(slot))
		card.set_meta("nav_default", slot == app.save_slot)
		if slot == app.save_slot: UI.select(card)
		app.icon(card, "save" if summary.get("occupied", false) else "folder-open", Rect2(144, 36, 56, 56), UI.JADE)
		var title = app.label(card, "愿簿 %d" % slot, Rect2(24, 112, 296, 44), 30)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var line = app.label(card, str(summary.get("label", "空白槽位")), Rect2(24, 171, 296, 40), 22, UI.MUTED)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var run = str(summary.get("run", "从新愿开始"))
		var status = app.label(card, run, Rect2(30, 223, 284, 54), 18, UI.MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.icon(card, "crown", Rect2(105, 298, 22, 22), UI.GOLD)
		app.label(card, str(int(summary.get("achievements", 0))), Rect2(141, 290, 110, 36), 21)
	app.icon(sheet, "keyboard", Rect2(42, 582, 28, 28), UI.MUTED)
	app.label(sheet, "← → 选择愿簿 · Enter 打开 · Esc 回标题", Rect2(88, 575, 926, 40), 18, UI.MUTED)

static func main_menu(app) -> void:
	var sheet = shell(app, "香火债", "愿簿 %d  /  %s" % [app.save_slot, app.progress.data.wish_name])
	app.add_art(sheet, "res://assets/portraits/" + app.selected + ".png", Rect2(34, 152, 480, 380))
	var facts = [["sparkles", app.progress.data.merit], ["crown", app.progress.data.achievements.size()], ["sun", app.progress.data.endings.size()]]
	for i in facts.size():
		var chip = app.panel(sheet, Rect2(40 + i * 157, 554, 144, 52), UI.SURFACE, Color.TRANSPARENT)
		app.icon(chip, facts[i][0], Rect2(18, 14, 24, 24), UI.JADE)
		app.label(chip, str(int(facts[i][1])), Rect2(60, 8, 74, 36), 23)
	var has_run = not app.checkpoint.is_empty() and app.checkpoint.get("run", {}).get("result", "") == ""
	var entries = [
		["新局", "play", func(): app.open_character_select("normal")],
		["继续", "rotate-ccw", app.restore_run],
		["挑战", "sword", func(): app.show_menu("challenges")],
		["记录", "scroll-text", func(): app.show_menu("stats")],
		["还愿庭", "house", func(): app.show_hub()],
		["设置", "settings-2", app.show_settings],
		["离开", "log-out", app.request_quit]]
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 58.0
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(620, 126)
	scroll.size = Vector2(490, 488)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for i in entries.size():
		var entry = entries[i]
		var action = app.icon_button(list, entry[0], entry[1], Rect2(0, 0, 474, height), entry[2], i == 0, entry[0])
		action.custom_minimum_size = Vector2(474, height)
		action.set_meta("nav_id", ["new", "continue", "challenges", "stats", "hub", "settings", "quit"][i])
		action.set_meta("nav_default", i == 0)
		if i == 1:
			action.disabled = app.save_session.read_only or not has_run
			action.tooltip_text = "当前愿簿没有进行中的还愿" if not has_run else "恢复同一房间与构筑"

static func challenges(app) -> void:
	var sheet = shell(app, "挑战", "挑战先选规则，再选还愿人；固定种子不会增加局外成长")
	var card = app.panel(sheet, Rect2(100, 180, 952, 350), UI.SURFACE, Color.TRANSPARENT)
	app.icon(card, "sword", Rect2(44, 44, 76, 76), UI.ACCENT)
	app.label(card, "每日还愿", Rect2(157, 43, 750, 62), 38)
	var date_value = Time.get_date_dict_from_system()
	app.label(card, Daily.key(date_value), Rect2(159, 121, 727, 34), 24, UI.JADE)
	app.label(card, "固定初始器具与供物池 · 三章还愿\n可中途存下并继续 · 训练与每日不计角色成就", Rect2(159, 183, 724, 82), 22, UI.MUTED)
	var action = app.icon_button(card, "选择挑战角色", "play", Rect2(570, 273, 340, 64), func(): app.open_character_select("daily"), true, "选还愿人")
	action.disabled = app.save_session.read_only
	action.set_meta("nav_default", true)

static func stats(app) -> void:
	var sheet = shell(app, "记录", "记录属于当前愿簿 · 未发现的条目保持隐藏")
	var entries = [
		["成就", "crown", app.show_achievements],
		["物品图鉴", "sparkles", func(): app.collection_kind = "relics"; app.collection_id = ""; app.show_menu("items")],
		["怪物图鉴", "sword", func(): app.collection_kind = "enemies"; app.collection_id = ""; app.show_menu("bestiary")],
		["结局", "sun", func(): app.show_menu("ending_archive")],
		["统计", "layers", func(): app.show_menu("statistics")],
		["旧愿", "book-open", func(): app.show_hub("story")]]
	for i in entries.size():
		var entry = entries[i]
		var tile = app.button(sheet, entry[0], Rect2(38 + (i % 3) * 366, 174 + int(i / 3) * 204, 344, 186), entry[2])
		tile.text = ""
		tile.set_meta("nav_id", "stats_" + str(i))
		tile.set_meta("nav_default", i == 0)
		app.icon(tile, entry[1], Rect2(147, 28, 50, 50), UI.JADE)
		var name_value = app.label(tile, entry[0], Rect2(24, 104, 296, 48), 26)
		name_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func collection(app, bestiary: bool) -> void:
	var sheet = shell(app, "怪物图鉴" if bestiary else "物品图鉴")
	var kinds = ["enemies", "bosses"] if bestiary else ["relics", "weapons"]
	if not kinds.has(app.collection_kind): app.collection_kind = kinds[0]
	var names = {"enemies": "恶愿", "bosses": "首领", "relics": "供物", "weapons": "器具"}
	for i in kinds.size():
		var kind = kinds[i]
		var tab = app.icon_button(sheet, names[kind], "sword" if bestiary else "sparkles", Rect2(38 + i * 204, 103, 188, 56 if not app.mobile_ui else 72), func(): app.collection_kind = kind; app.collection_id = ""; app.show_menu(app.menu_page), false, names[kind])
		tab.set_meta("nav_id", "collection_" + kind)
		if kind == app.collection_kind: UI.select(tab)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(38, 191)
	scroll.size = Vector2(750, 376)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var seen: Array = app.progress.data.seen[app.collection_kind]
	for row in app.world.db.rows(app.collection_kind):
		var id = str(row.id)
		var known = seen.has(id)
		var tile = app.button(grid, row.name if known else "未发现", Rect2(0, 0, 138, 112), func(): app.collection_id = id; app.show_menu(app.menu_page))
		tile.text = ""
		tile.custom_minimum_size = Vector2(138, 112)
		tile.set_meta("nav_id", "catalog_" + id)
		# Hidden tiles stay readable and focusable without leaking their artwork.
		if known: app.add_art(tile, "res://assets/%s/%s.png" % [app.collection_kind, id], Rect2(33, 8, 72, 72))
		else: app.icon(tile, "lock", Rect2(51, 27, 36, 36), UI.MUTED)
		var name_value = app.label(tile, row.name if known else "未发现", Rect2(8, 82, 122, 24), 15, UI.TEXT if known else UI.MUTED)
		name_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if id == app.collection_id: UI.select(tile)
	var detail = app.panel(sheet, Rect2(812, 191, 300, 376), UI.SURFACE, Color.TRANSPARENT)
	if seen.has(app.collection_id):
		var row = app.world.db.row(app.collection_kind, app.collection_id)
		app.add_art(detail, "res://assets/%s/%s.png" % [app.collection_kind, app.collection_id], Rect2(70, 20, 160, 160))
		app.label(detail, row.name, Rect2(24, 190, 252, 45), 28)
		var description = str(row.get("behavior", row.get("counterplay", row.get("pattern", "已发现的首领"))))
		app.reading_text(detail, [description], Rect2(24, 251, 252, 100), 18, UI.MUTED)
	else:
		app.icon(detail, "lock", Rect2(126, 94, 48, 48), UI.MUTED)
		app.label(detail, "在还愿中遇见后\n这一页才会显影", Rect2(28, 175, 244, 120), 22, UI.MUTED)
	app.label(sheet, "%d / %d 已发现" % [seen.size(), app.world.db.rows(app.collection_kind).size()], Rect2(38, 582, 900, 34), 20, UI.JADE)

static func ending_archive(app) -> void:
	var sheet = shell(app, "结局", "%d / 3 已收藏" % app.progress.data.endings.size())
	for i in ENDINGS.size():
		var entry = ENDINGS[i]
		var known = app.progress.data.endings.has(entry[0])
		var tile = app.button(sheet, entry[1] if known else "未揭示的结局", Rect2(38 + i * 366, 186, 344, 356), func(): app.archive_ending = entry[0]; app.show_menu("ending_view"))
		tile.text = ""
		tile.disabled = not known
		if known: app.add_art(tile, "res://assets/relics/%s.png" % entry[3], Rect2(100, 40, 144, 144))
		else: app.icon(tile, "lock", Rect2(144, 82, 56, 56), UI.MUTED)
		var name_value = app.label(tile, entry[1] if known else "未揭示", Rect2(30, 228, 284, 60), 32, UI.TEXT if known else UI.MUTED)
		name_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func ending_view(app) -> void:
	for entry in ENDINGS:
		if entry[0] != app.archive_ending or not app.progress.data.endings.has(entry[0]): continue
		var sheet = shell(app, entry[1], "已收藏的结局")
		app.add_art(sheet, "res://assets/relics/%s.png" % entry[3], Rect2(92, 180, 290, 290))
		app.reading_text(sheet, [entry[2]], Rect2(448, 203, 582, 286), 30)

static func statistics(app) -> void:
	var summary: Dictionary = app.progress.data.achievement_stats
	var sheet = shell(app, "统计", "正式还愿 %d 次 · 胜利 %d 次 · 善缘 %d" % [int(summary.runs), int(summary.victories), int(app.progress.data.merit)])
	var characters = app.world.db.rows("characters")
	for i in characters.size():
		var character = characters[i]
		var data: Dictionary = summary.character_stats.get(character.id, {})
		var card = app.panel(sheet, Rect2(38 + (i % 3) * 366, 172 + int(i / 3) * 204, 344, 188), UI.SURFACE, Color.TRANSPARENT)
		app.add_art(card, "res://assets/heroes/%s_down.png" % character.id, Rect2(12, 27, 106, 127))
		app.label(card, character.name, Rect2(138, 22, 190, 40), 28)
		app.label(card, "还愿  %d\n胜利  %d\n愿页  %d / 3" % [int(data.get("runs", 0)), int(data.get("victories", 0)), int(app.progress.data.personal[character.id].stage)], Rect2(139, 76, 184, 91), 20, UI.MUTED)

static func loadout(app) -> void:
	var sheet = shell(app, "初始器具", "每次只携带一件 · 个人愿页第二阶段开放另一件器具")
	var weapons: Array = app.progress.starting_weapons(app.selected)
	for i in weapons.size():
		var id = str(weapons[i])
		var row = app.world.db.row("weapons", id)
		var card = app.panel(sheet, Rect2(140 + i * 462, 175, 412, 392), UI.SURFACE, Color.TRANSPARENT)
		app.add_art(card, "res://assets/weapons/%s.png" % id, Rect2(122, 24, 168, 168))
		app.label(card, row.name, Rect2(30, 201, 352, 40), 29)
		app.reading_text(card, [row.get("behavior", "")], Rect2(30, 253, 352, 55), 18, UI.MUTED)
		var action = app.icon_button(card, "携带" + row.name, "check", Rect2(30, 314, 352, 64), func(): app.choose_starting_weapon(id), true, "携带")
		action.set_meta("nav_default", id == app.starting_weapon(app.selected))

static func confirmation(app, quitting: bool = false) -> void:
	app.paused = true
	app.screen = "quit_confirm" if quitting else "new_run_confirm"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.95)
	var sheet = app.panel(app.modal, Rect2(270, 162, 740, 396), UI.INSET, Color.TRANSPARENT)
	app.icon(sheet, "log-out" if quitting else "rotate-ccw", Rect2(334, 28, 72, 72), UI.ACCENT)
	app.label(sheet, "离开灯下？" if quitting else "开始新的还愿？", Rect2(48, 124, 644, 58), 36)
	app.label(sheet, "当前进度会先存入愿簿。" if quitting else "当前愿簿有未完成的还愿。新局将替换这次还愿；角色与成就仍保留。", Rect2(48, 197, 644, 79), 22, UI.MUTED)
	var cancel = app.icon_button(sheet, "保留并返回", "arrow-left", Rect2(48, 300, 300, 64), app.cancel_confirmation, false, "返回")
	cancel.set_meta("nav_default", true)
	app.icon_button(sheet, "保存并离开" if quitting else "确认开始新局", "check", Rect2(390, 300, 300, 64), app.confirm_quit if quitting else app.confirm_new_run, true, "离开" if quitting else "开始")
