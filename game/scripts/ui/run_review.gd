extends RefCounted
## End-of-run disclosure reads the finished world and committed account ledger.
const UI = preload("res://scripts/ui/game_theme.gd")
const Damage = preload("res://scripts/core/damage_record.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")

static func source_art(app, parent: Control, source: Dictionary, rect: Rect2) -> void:
	var path = Damage.art_path(app.world.db, source)
	if path.is_empty(): app.icon(parent, "circle-question-mark", rect, UI.MUTED)
	else: app.add_art(parent, path, rect)

static func show(app, page: String = "damage", selected_index: int = -1) -> void:
	if app.world.run.is_empty() or app.world.run.result.is_empty(): return
	app.paused = true
	app.screen = "run_review"
	app.hud.visible = false
	app.adapter.clear()
	app.clear_modal()
	app.modal.set_meta("navigation_page", page)
	app.dim(.94)
	app.label(app.modal, "这一局", Rect2(64, 46, 850, 62), 40)
	app.label(app.modal, app.world.db.name_of("characters", app.world.run.character) + " · " + app.world.region_spec().name, Rect2(66, 113, 1000, 32), 18, UI.MUTED)
	var height = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	app.icon_button(app.modal, "返回结算", "x", Rect2(1208 - height, 52, height, height), app.show_result)
	var tabs = [["受击", "heart", "damage"], ["愿页", "book-open", "pages"]]
	for i in tabs.size():
		var tab = tabs[i]
		var action = app.icon_button(app.modal, "本局" + tab[0], tab[1], Rect2(64 + i * 260, 161, 244, height), func(): app.show_run_review(tab[2]), false, tab[0])
		if page == tab[2]: UI.select(action)
	app.icon_button(app.modal, "查看本局构筑", "layers", Rect2(953, 161, 255, height), func(): app.show_inventory(), false, "构筑")
	var top = 273.0 if app.mobile_ui else 249.0
	if page == "pages": pages(app, top)
	else: hits(app, top, selected_index)

static func hits(app, top: float, selected_index: int) -> void:
	var history: Array = app.world.run.get("damage_history", [])
	if history.is_empty():
		var empty = app.panel(app.modal, Rect2(64, top, 1144, 352), UI.INSET, Color.TRANSPARENT)
		app.icon(empty, "circle-question-mark", Rect2(40, 37, 58, 58), UI.MUTED)
		app.label(empty, "这页没有受击记录。", Rect2(129, 47, 950, 45), 26, UI.MUTED)
		return
	selected_index = clampi(selected_index if selected_index >= 0 else history.size() - 1, 0, history.size() - 1)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(64, top)
	scroll.size = Vector2(512, 352)
	app.modal.add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var row_height = maxf(92, app.mobile_button_height) if app.mobile_ui else 84.0
	for i in range(history.size() - 1, -1, -1):
		var hit = history[i]
		var tile = app.button(list, "查看受击 " + Damage.brief(app.world.db, hit), Rect2(0, 0, 496, row_height), func(): app.show_run_review("damage", i))
		tile.text = ""
		tile.custom_minimum_size = Vector2(496, row_height)
		tile.set_meta("damage_index", str(i))
		if i == selected_index: UI.select(tile)
		source_art(app, tile, hit.source, Rect2(12, 12, 62, 62))
		app.label(tile, Damage.name_of(app.world.db, hit.source), Rect2(92, 13, 322, 34), 21)
		app.label(tile, "%s  ·  %02d:%02d" % [Damage.LABELS[hit.source.kind], int(hit.at) / 60, int(hit.at) % 60], Rect2(93, 51, 320, 26), 16, UI.MUTED)
		app.icon(tile, "heart" if hit.damage > 0 else "shield", Rect2(442, 18, 23, 23), UI.ACCENT if hit.damage > 0 else UI.JADE)
		app.label(tile, str(int(hit.damage)), Rect2(447, 50, 32, 29), 20)
	var hit = history[selected_index]
	var detail = app.panel(app.modal, Rect2(604, top, 604, 352), UI.INSET, Color.TRANSPARENT)
	detail.set_meta("review_damage_index", str(selected_index))
	source_art(app, detail, hit.source, Rect2(23, 18, 110, 110))
	app.label(detail, Damage.name_of(app.world.db, hit.source), Rect2(155, 25, 426, 43), 28)
	app.label(detail, Damage.LABELS[hit.source.kind], Rect2(157, 83, 423, 33), 20, UI.MUTED)
	var metrics = [["heart", "%d → %d" % [hit.hp_before, hit.hp_after], "心火"], ["shield", str(int(hit.absorbed)), "抵消"], ["flame", str(int(hit.raw)), "袭来"]]
	for i in metrics.size():
		var metric = metrics[i]
		var cell = app.panel(detail, Rect2(23 + i * 190, 139, 176, 87), UI.SURFACE, Color.TRANSPARENT)
		app.icon(cell, metric[0], Rect2(15, 16, 24, 24), UI.JADE if i == 1 else UI.ACCENT)
		app.label(cell, metric[1], Rect2(53, 10, 110, 37), 24)
		app.label(cell, metric[2], Rect2(54, 53, 107, 24), 16, UI.MUTED)
	var advice = {"unknown": "旧愿未保留这次攻击者；继续游玩会记录新的来源。", "projectile": "横移让开弹道。身法可跨过飞弹，招架只挡正面。", "split": "碰墙后裂弹会返射，留意墙边的第二轮弹道。", "contact": "挂余烬后保持距离，留身法处理近身。", "lunge": "预警结束前向侧方闪避，避开冲锋方向。", "zone": "印区生效前会预告。离开边界，再回身焚债。", "debt": "催债弹来自债约牵出的玉青连线；偿还可移除它。"}[hit.source.kind]
	if hit.source.table == "enemies": advice = app.world.db.row("enemies", hit.source.id).counterplay + "。" + advice
	app.icon(detail, "info", Rect2(24, 256, 23, 23), UI.MUTED)
	app.label(detail, advice, Rect2(61, 246, 517, 61), 18, UI.MUTED)
	if hit.revived or hit.lethal:
		app.icon(detail, "rotate-ccw" if hit.revived else "flame", Rect2(25, 316, 20, 20), UI.GOLD)
		app.label(detail, "回魂签已消耗" if hit.revived else "最后一击", Rect2(61, 310, 517, 30), 17, UI.GOLD)

static func pages(app, top: float) -> void:
	var w = app.world
	var record: Dictionary = app.progress.data.runs.get(w.run.id, {})
	var earned = int(record.get("merit", 0)) + int(record.get("bonus_merit", 0))
	var summary = app.panel(app.modal, Rect2(64, top, 328, 352), UI.INSET, Color.TRANSPARENT)
	summary.set_meta("ledger_run_id", w.run.id)
	app.icon(summary, "leaf", Rect2(24, 24, 33, 33), UI.JADE)
	app.label(summary, "本局已记善缘", Rect2(75, 25, 225, 40), 22)
	var credit = app.label(summary, str(earned), Rect2(27, 92, 274, 88), 64)
	credit.set_meta("credited_merit", str(earned))
	app.label(summary, "入账 %d  ·  额外 %d" % [record.get("merit", 0), record.get("bonus_merit", 0)], Rect2(30, 191, 268, 33), 18, UI.MUTED)
	var unlocked: Array = record.get("characters_unlocked", [])
	if not unlocked.is_empty():
		app.label(summary, "新留名", Rect2(30, 243, 268, 32), 19, UI.MUTED)
		for i in unlocked.size():
			app.add_art(summary, "res://assets/heroes/" + unlocked[i] + "_down.png", Rect2(25 + i * 57, 281, 52, 56))
	else:
		app.icon(summary, "check" if not record.is_empty() else "info", Rect2(31, 277, 24, 24), UI.JADE)
		app.label(summary, "以已入账为准" if not record.is_empty() else "尚无结算记录", Rect2(73, 273, 231, 45), 18, UI.MUTED)
	var personal = app.progress.data.personal[w.run.character]
	var mastery = Progress.MASTERY[w.run.character]
	var route_names: Array = []
	for route in w.db.row("characters", w.run.character).routes: route_names.append(w.db.name_of("routes", route))
	var tasks = [[mastery[0], "%d / %d" % [mini(int(personal.progress), int(mastery[2])), mastery[2]], personal.progress >= mastery[2]],
		["同局行愿", " + ".join(route_names), personal.cross], ["击败「%s」" % w.db.name_of("bosses", "b37" if w.run.get("campaign", false) else "b03"), "总账有了归处", personal.final]]
	var new_pages: Array = record.get("personal_pages", [])
	for i in tasks.size():
		var task = tasks[i]
		var completed = int(personal.stage) > i
		var newly = new_pages.has(i + 1)
		var row = app.panel(app.modal, Rect2(416, top + i * 122, 792, 108), UI.SURFACE, Color.TRANSPARENT)
		row.set_meta("review_personal_page", str(i + 1))
		app.icon(row, "check" if completed else "book-open", Rect2(23, 37, 32, 32), UI.JADE if completed else UI.MUTED)
		app.label(row, task[0], Rect2(79, 17, 487, 39), 24)
		app.label(row, task[1], Rect2(80, 63, 485, 30), 18, UI.MUTED)
		var state = "本局完成" if newly else ("已留页" if completed else "待前页" if task[2] else "待回应")
		app.label(row, state, Rect2(580, 23, 189, 36), 21, UI.JADE if completed else UI.MUTED)
		if newly:
			app.icon(row, "leaf", Rect2(582, 72, 20, 20), UI.GOLD)
			app.label(row, "+%d" % ((i + 1) * 5), Rect2(615, 65, 153, 32), 19, UI.GOLD)
