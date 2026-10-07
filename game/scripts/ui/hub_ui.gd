extends RefCounted
## Shared modern controls and approved courtyard sprites.
const UI = preload("res://scripts/ui/game_theme.gd")
const DailySeed = preload("res://scripts/core/daily_seed.gd")
const GOLD = UI.MUTED
const Portrait = preload("res://scripts/ui/npc_portrait.gd")
const NPC_PAGES = ["wishes", "archive", "debts", "shop", "personal"]
const PAGE_NAMES = ["还愿簿", "铜盘图鉴", "旧账回顾", "器具灯摊", "留名与结局"]
const PAGE_SHORT = ["还愿", "图鉴", "账簿", "器具", "留名"]

static func scroll_list(ui) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(390, 246)
	scroll.size = Vector2(790, 380)
	ui.modal.add_child(scroll)
	var list = VBoxContainer.new()
	list.custom_minimum_size.x = 766
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	return list

static func tile(ui, list: VBoxContainer, height: float = 108) -> Panel:
	var row = Panel.new()
	row.custom_minimum_size = Vector2(766, height)
	row.add_theme_stylebox_override("panel", ui.box_style(Color("30372f"), Color("635c44")))
	list.add_child(row)
	return row

static func draw(ui, page: String) -> void:
	ui.dim(.61)
	ui.label(ui.modal, "还愿庭", Rect2(56, 35, 370, 76), 48)
	ui.icon_button(ui.modal, "旧愿回看", "book-open", Rect2(736, 53, 56, 56), func(): ui.show_hub("story"))
	ui.icon_button(ui.modal, "善缘 %d" % ui.progress.data.merit, "sparkles", Rect2(816, 53, 176, 56), func(): ui.show_hub(), false, str(ui.progress.data.merit))
	var daily = ui.icon_button(ui.modal, "每日", "crown", Rect2(604, 53, 112, 56), ui.begin_daily_run, true, "每日种子")
	daily.disabled = ui.save_session.read_only or not ui.progress.data.characters.has(ui.selected)
	daily.tooltip_text = DailySeed.title() + " · 固定初始供物，不计善缘"
	ui.icon_button(ui.modal, "动身还愿  →", "play", Rect2(1016, 53, 190, 56), ui.show_menu, true, "动身")
	var npcs = ui.world.db.rows("npcs")
	for i in npcs.size():
		var npc = npcs[i]
		var card = ui.button(ui.modal, "", Rect2(56, 169 + i * 98, 279, 84), func(): ui.show_hub(NPC_PAGES[i]))
		card.accessibility_name = npc.name + " · " + PAGE_NAMES[i]
		card.tooltip_text = card.accessibility_name
		if page == NPC_PAGES[i]: UI.select(card)
		var portrait = Portrait.new()
		portrait.npc_id = npc.id
		portrait.speaking = page == NPC_PAGES[i]
		portrait.position = Vector2(8, 2)
		portrait.size = Vector2(86, 79)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		ui.label(card, npc.name, Rect2(106, 11, 163, 29), 23)
		ui.label(card, PAGE_SHORT[i], Rect2(106, 46, 163, 25), 16, GOLD)
	ui.panel(ui.modal, Rect2(360, 169, 847, 478), Color("20281f"), Color("635c44"))
	match page:
		"archive": archive(ui)
		"training": training(ui)
		"debts": debts(ui)
		"shop": shop(ui)
		"personal": personal(ui)
		"story": story(ui)
		_: wishes(ui)
	var npc_index = NPC_PAGES.find(page)
	ui.reading_text(ui.modal, [ui.story.npc(npcs[npc_index].id, ui.npc_line_index) if npc_index >= 0 else "回应过的愿，都可以回来读。"], Rect2(360, 652, 830, 60), 17, GOLD)

static func wishes(ui) -> void:
	ui.label(ui.modal, "把愿翻成下一页", Rect2(389, 186, 780, 46), 30)
	var list = scroll_list(ui)
	for item in ui.world.db.rows("meta_unlocks"):
		var row = tile(ui, list, 122)
		var grants = item.grants.get("relic_ids", [])
		ui.add_art(row, "res://assets/relics/" + (grants[0] if not grants.is_empty() else "r17") + ".png", Rect2(9, 15, 82, 82))
		ui.label(row, item.name, Rect2(108, 10, 431, 32), 22)
		var detail = "、".join(grants.map(func(id): return ui.world.db.name_of("relics", id)))
		if detail.is_empty(): detail = {"u_memory_index": "故事页按角色整理", "u_training": "练习已见首领的攻击", "u_loadout": "保存初始器具偏好", "u_coin_pickup": "拾钱半径 120 → 160"}.get(item.id, "")
		ui.label(row, detail, Rect2(108, 47, 431, 31), 16)
		var reason = ui.progress.reason(item)
		ui.label(row, reason if not reason.is_empty() else "横向解锁 · 每页只需回应一次", Rect2(108, 81, 431, 31), 15, GOLD)
		var purchased = ui.progress.data.unlocks.has(item.id)
		var action = ui.button(row, "已还愿" if purchased else "%d善缘 · 翻页" % item.cost, Rect2(554, 37, 185, 48), func(): ui.progress.purchase(item.id); ui.show_hub(), not purchased)
		action.disabled = purchased or not reason.is_empty() or ui.progress.data.merit < item.cost

static func archive(ui) -> void:
	ui.label(ui.modal, "见过的，都会留下", Rect2(389, 186, 585, 46), 30)
	ui.button(ui.modal, "去铜盘练习", Rect2(991, 186, 188, 48), func(): ui.show_hub("training"), true)
	var list = scroll_list(ui)
	for kind in ["bosses", "enemies", "relics", "weapons"]:
		for id in ui.progress.data.seen[kind]:
			var item = ui.world.db.row(kind, id)
			if item.is_empty(): continue
			var row = tile(ui, list)
			ui.add_art(row, "res://assets/" + kind + "/" + id + ".png", Rect2(10, 8, 92, 92))
			ui.label(row, item.name, Rect2(117, 11, 596, 32), 23)
			var text = str(item.get("behavior", item.get("pattern", item.get("role", ""))))
			if kind == "weapons": text = "伤害 %.0f · 射程 %.0f · 攻击间隔 %.2f秒" % [item.damage, item.range, item.interval_s]
			elif kind == "bosses": text = "三阶段 · 先读预警，再把余烬留在破绽上。"
			ui.label(row, text, Rect2(117, 50, 622, 48), 17, GOLD)
	if list.get_child_count() == 0:
		var row = tile(ui, list, 162)
		ui.label(row, "先动身，再认识这座城。\n敌人、器具与供物的发现会自动写入。", Rect2(27, 30, 700, 100), 22, GOLD)

static func training(ui) -> void:
	ui.label(ui.modal, "铜盘演阵", Rect2(389, 186, 720, 46), 30)
	var list = scroll_list(ui)
	var row = tile(ui, list, 157)
	ui.add_art(row, "res://assets/npcs/training_stand.png", Rect2(15, 18, 112, 112))
	ui.label(row, "挂烬 · 连债 · 焚账", Rect2(149, 18, 543, 39), 26)
	ui.label(row, "当前还愿人：%s\n练习不消耗心火，不计善缘与任务。" % ui.world.db.name_of("characters", ui.selected), Rect2(149, 67, 387, 60), 18, GOLD)
	var action = ui.button(row, "进入靶场", Rect2(552, 92, 187, 48), func(): ui.begin_training(""), true)
	action.disabled = not ui.progress.data.characters.has(ui.selected)
	if ui.progress.has_feature("seen_boss_pattern_training"):
		for id in ui.progress.data.bosses:
			var boss_row = tile(ui, list, 118)
			ui.add_art(boss_row, "res://assets/bosses/" + id + ".png", Rect2(14, 10, 96, 96))
			ui.label(boss_row, ui.world.db.name_of("bosses", id), Rect2(136, 18, 362, 35), 23)
			for phase in 3: ui.button(boss_row, "阵%d" % (phase + 1), Rect2(435 + phase * 104, 63, 93, 42), func(): ui.begin_training(id, phase))

static func debts(ui) -> void:
	ui.label(ui.modal, "账必须写清楚", Rect2(389, 186, 768, 46), 30)
	var list = scroll_list(ui)
	for item in ui.world.db.rows("debt_contracts"):
		var row = tile(ui, list, 138)
		ui.add_art(row, "res://assets/relics/" + item.reward + ".png", Rect2(12, 17, 90, 90))
		ui.label(row, "%s  ·  第%d章  ·  风险%d" % [item.name, item.min_floor, item.risk_points], Rect2(121, 10, 593, 33), 22)
		ui.label(row, "所得：%s  /  偿还%d纸钱" % [ui.world.db.name_of("relics", item.reward), item.repay_price], Rect2(121, 51, 602, 30), 17, GOLD)
		ui.label(row, item.penalty, Rect2(121, 87, 609, 43), 16)

static func shop(ui) -> void:
	ui.label(ui.modal, "器具先试，再带出门", Rect2(389, 186, 780, 46), 30)
	var list = scroll_list(ui)
	for id in ui.progress.starting_weapons(ui.selected):
		var weapon = ui.world.db.row("weapons", id)
		var row = tile(ui, list, 138)
		ui.add_art(row, "res://assets/weapons/" + id + ".png", Rect2(15, 15, 106, 106))
		ui.label(row, weapon.name, Rect2(142, 19, 587, 37), 25)
		ui.label(row, weapon.get("behavior", ""), Rect2(142, 64, 365, 65), 17, GOLD)
		ui.button(row, "带着它动身", Rect2(526, 80, 215, 44), func(): ui.choose_starting_weapon(id), true)
	var note = tile(ui, list, 124)
	ui.label(note, "个人愿页第二阶段开放另一件初始器具。\n每次只带一件，不叠加永久伤害。", Rect2(25, 22, 698, 81), 20, GOLD)

static func personal(ui) -> void:
	ui.label(ui.modal, "每个人都值得被记住", Rect2(389, 186, 774, 46), 30)
	var list = scroll_list(ui)
	var name_row = tile(ui, list, 124)
	ui.label(name_row, "你的愿名", Rect2(23, 14, 170, 32), 24)
	var wish = LineEdit.new()
	wish.position = Vector2(199, 18)
	wish.size = Vector2(338, 47)
	wish.text = ui.progress.data.wish_name
	wish.max_length = 12
	wish.add_theme_font_size_override("font_size", 22)
	wish.add_theme_stylebox_override("normal", ui.box_style(Color("242725"), GOLD))
	wish.add_theme_stylebox_override("focus", ui.box_style(Color("30372f"), Color("e7d8b6"), 2))
	name_row.add_child(wish)
	ui.button(name_row, "留在牌上", Rect2(552, 18, 185, 47), func():
		var name_value = wish.text.strip_edges()
		if name_value.is_empty(): name_value = "无名之愿"
		var previous = ui.progress.data.wish_name
		ui.progress.data.wish_name = name_value
		if not ui.progress.save(): ui.progress.data.wish_name = previous
		ui.show_hub("personal"), true)
	ui.label(name_row, "最多十二字 · 只记愿名，保存在本机。", Rect2(23, 78, 710, 31), 17, GOLD)
	for character in ui.world.db.rows("characters"):
		var page = ui.progress.data.personal[character.id]
		var row = tile(ui, list, 169)
		ui.add_art(row, "res://assets/heroes/" + character.id + "_down.png", Rect2(8, 19, 117, 124))
		ui.label(row, "%s · 愿页 %d / 3" % [character.name, page.stage], Rect2(140, 12, 590, 36), 24)
		var mastery = ui.progress.MASTERY[character.id]
		var task = "%s  %.0f / %d\n同局选择 %s 与 %s\n击败无主神" % [mastery[0], minf(page.progress, mastery[2]), mastery[2], ui.world.db.name_of("routes", character.routes[0]), ui.world.db.name_of("routes", character.routes[1])]
		ui.label(row, task, Rect2(140, 55, 590, 98), 17, GOLD)
		if page.stage >= 1:
			ui.label(row, "留名", Rect2(21, 136, 94, 31), 21, Color("db7553"))
		if page.stage >= 3:
			ui.button(row, "读个人页", Rect2(591, 15, 146, 40), func(): ui.show_story_page(ui.story.content.pages.filter(func(p): return p.id == "story.personal." + character.id)[0]))
	var endings_row = tile(ui, list, 117)
	ui.label(endings_row, "愿的归处", Rect2(23, 14, 700, 34), 24)
	var names = {"burn": "焚账", "repay": "偿还", "rewrite": "换约"}
	ui.label(endings_row, "已收藏：" + ("、".join(ui.progress.data.endings.map(func(id): return names[id])) if not ui.progress.data.endings.is_empty() else "尚未抵达"), Rect2(23, 60, 701, 40), 18, GOLD)

static func story(ui) -> void:
	ui.label(ui.modal, "旧愿 · 回应留下的页", Rect2(389, 186, 780, 46), 30)
	var list = scroll_list(ui)
	if ui.progress.has_feature("story_filter_by_character"):
		var filter_row = tile(ui, list, 82)
		var names = ["全部愿页"] + ui.world.db.rows("characters").map(func(c): return c.name)
		var ids = [""] + ui.world.db.rows("characters").map(func(c): return c.id)
		var choice = OptionButton.new()
		choice.position = Vector2(21, 17)
		choice.size = Vector2(351, 49)
		for name_value in names: choice.add_item(name_value)
		choice.select(maxi(0, ids.find(ui.story_filter)))
		choice.item_selected.connect(func(i): ui.story_filter = ids[i]; ui.show_hub("story"))
		filter_row.add_child(choice)
		ui.label(filter_row, "愿页索引 · 按还愿人翻找", Rect2(393, 23, 350, 43), 18, GOLD)
	for page in ui.story.pages(ui.progress.data, ui.story_filter):
		var row = tile(ui, list, 131)
		ui.label(row, page.title, Rect2(23, 15, 522, 38), 24)
		ui.label(row, page.lines[0], Rect2(23, 65, 514, 55), 17, GOLD)
		ui.button(row, "再读一次" if ui.progress.data.read_story_ids.has(page.id) else "展开愿页", Rect2(554, 43, 183, 48), func(): ui.show_story_page(page), true)
	if list.get_child_count() == 0:
		var row = tile(ui, list, 137)
		ui.label(row, "这一页还未写完。\n完成个人愿页后，故事会留在这里。", Rect2(23, 26, 702, 87), 22, GOLD)

static func endings(ui) -> void:
	ui.dim(.86)
	ui.label(ui.modal, "账停了。愿，留给你。", Rect2(106, 73, 1100, 84), 46)
	ui.label(ui.modal, "所有回应都有归处。选择这一局的结尾。", Rect2(107, 171, 1070, 40), 21, GOLD)
	var items = [["burn", "焚账", "解除所有债。带走几张重要的愿页，让剩下的账化灰。", "r17"], ["repay", "偿还", "撕去利息页，留下已被回应的愿。还愿庭成为互助的集市。", "r54"], ["rewrite", "换约", "不再记录谁欠了多少。让共同的账只记下：谁已经回应。", "r48"]]
	for i in items.size():
		var item = items[i]
		var card = ui.panel(ui.modal, Rect2(106 + i * 362, 240, 344, 371), Color("30372f"))
		ui.add_art(card, "res://assets/relics/" + item[3] + ".png", Rect2(116, 13, 112, 112))
		ui.label(card, item[1], Rect2(23, 143, 298, 44), 31)
		ui.label(card, item[2], Rect2(23, 205, 298, 96), 19)
		var reason = ui.progress.ending_reason(item[0])
		var action = ui.button(card, reason if not reason.is_empty() else "让愿归于此", Rect2(18, 312, 308, 48), func():
			if ui.finish_ending(item[0]):
				ui.clear_modal()
				ui.show_result(), true)
		action.add_theme_font_size_override("font_size", 17)
		action.disabled = not reason.is_empty()
