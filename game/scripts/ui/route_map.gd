extends Control
const Graph = preload("res://scripts/core/room_graph.gd")
const UI = preload("res://scripts/ui/game_theme.gd")
const Modern = preload("res://scripts/ui/modern_ui.gd")
const FloorTimeline = preload("res://scripts/ui/floor_timeline.gd")
var world
var mobile_graph = false
var origin = Vector2.ZERO
var spacing = 74.0
const ROOM_ICONS = {"combat": "sword", "reward": "sparkles", "debt": "scroll-text", "elite": "shield", "shop": "coins", "boss": "crown", "event": "book-open", "secret": "link", "optional_boss": "crown", "sacrifice": "flame", "judge": "circle-dot", "angel": "sun", "challenge": "sword"}

static func point(coordinate: Vector2, touch: bool = false) -> Vector2:
	return Vector2(664, 180) + coordinate * Vector2(250, 66)

func location(coordinate: Vector2) -> Vector2:
	return Vector2(52, 52) + (coordinate - origin) * spacing

func _draw() -> void:
	if world == null: return
	for edge in world.run.graph.edges:
		if not Graph.visible(world.run.graph, int(edge[0])) or not Graph.visible(world.run.graph, int(edge[1])): continue
		var a = location(world.run.graph.coords[int(edge[0])])
		var b = location(world.run.graph.coords[int(edge[1])])
		var explored = world.run.visited.has(int(edge[0])) or world.run.visited.has(int(edge[1])) or int(world.run.room) in edge
		draw_line(a, b, Color(UI.JADE, .6) if explored else UI.EDGE, 3, true)

static func list_view(ui, sheet: Control, page: String) -> void:
	var scroll = ScrollContainer.new()
	var tabs_height = maxf(52, ui.mobile_button_height) if ui.mobile_ui else 52.0
	scroll.position = Vector2(18, tabs_height + 32)
	scroll.size = Vector2(312, 509 - tabs_height - 46)
	sheet.add_child(scroll)
	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.custom_minimum_size = Vector2(292, 0)
	scroll.add_child(list)
	var entries: Array = []
	if page == "history":
		for entry in ui.world.run.get("growth_log", []):
			var info = Modern.history_row(ui, entry)
			entries.append({"name": info.title, "body": info.description, "art": info.art, "icon": Modern.history_icon(str(info.kind))})
	else:
		entries.append({"name": ui.world.db.name_of("weapons", ui.world.player.weapon), "body": ui.world.db.row("weapons", ui.world.player.weapon).behavior, "icon": "sword", "art": "res://assets/weapons/" + ui.world.player.weapon + ".png"})
		entries.append({"name": ui.world.db.name_of("skills", ui.world.player.skill), "body": "当前焚债", "icon": "flame", "art": "res://assets/skills/" + ui.world.player.skill + ".png"})
		var active = ui.world.Equipment.active_row(ui.world)
		if not active.is_empty(): entries.append({"name": active.name, "body": active.behavior + " · %d/%d充能" % [int(ui.world.run.active_item.charge), int(active.charge_rooms)], "icon": "zap", "art": "res://assets/active_items/" + active.id + ".png"})
		if not str(ui.world.run.trinket).is_empty():
			var trinket = ui.world.db.row("trinkets", ui.world.run.trinket)
			entries.append({"name": trinket.name, "body": trinket.behavior, "icon": "circle-dot", "art": "res://assets/trinkets/" + trinket.id + ".png"})
		for id in ui.world.run.relics:
			entries.append({"name": ui.world.db.name_of("relics", id) + " ×%d" % int(ui.world.run.relics[id]), "body": ui.world.db.row("relics", id).behavior, "icon": "sparkles", "art": "res://assets/relics/" + id + ".png"})
		for id in ui.world.run.talents:
			var row = ui.world.db.row("talents", id)
			entries.append({"name": str(row.name), "body": str(row.get("behavior", row.get("effect", "行愿词条"))), "icon": "leaf", "art": ""})
		for debt in ui.world.run.contracts:
			var row = ui.world.db.row("debt_contracts", str(debt.id))
			entries.append({"name": str(row.name), "body": str(row.get("behavior", "未偿契约")), "icon": "scroll-text", "art": ""})
		for synergy in ui.world.active_synergies():
			entries.append({"name": str(synergy.name), "body": str(synergy.get("behavior", "已成组合")), "icon": "layers", "art": ""})
	for i in entries.size():
		var entry = entries[i]
		var button = ui.button(list, str(entry.name), Rect2(0, 0, 292, 64), func(): ui.notice(str(entry.get("body", entry.get("description", entry.name)))))
		button.custom_minimum_size = Vector2(292, maxf(72,ui.mobile_button_height) if ui.mobile_ui else 62)
		button.tooltip_text = str(entry.get("body", entry.get("description", entry.name)))
		button.set_meta("nav_id", "map_" + page + "_" + str(i))
		button.set_meta("map_build_entry", i)
		if not str(entry.get("art", "")).is_empty(): ui.add_art(button, str(entry.art), Rect2(8, 7, 48, 48))
		else: ui.icon(button, str(entry.get("icon", "sparkles")), Rect2(20, 19, 24, 24), UI.JADE)
		button.add_theme_stylebox_override("normal", UI.style(UI.SURFACE, Color.TRANSPARENT, 22))
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.modal.set_meta("map_entry_count", entries.size())

static func show_sheet(ui, page: String = "build") -> void:
	ui.paused = true
	ui.screen = "route"
	ui.adapter.clear()
	ui.clear_modal()
	ui.dim(.94)
	ui.hud.visible = false
	ui.modal.set_meta("navigation_page", "map_" + page)
	ui.label(ui.modal, "行路", Rect2(42, 30, 1090, 60), 38)
	ui.label(ui.modal, "%s · 第%d重" % [ui.world.region_spec().name, int(ui.world.run.floor)], Rect2(45, 101, 212, 36), 18, UI.MUTED)
	FloorTimeline.attach(ui, Rect2(276, 86, 852, 78))
	var stats = ui.panel(ui.modal, Rect2(32, 178, 220, 509), UI.INSET, Color.TRANSPARENT)
	ui.label(stats, "还愿人", Rect2(18, 16, 180, 42), 24)
	var rows = ui.world.player_stat_rows()
	for i in rows.size():
		var row = rows[i]
		ui.icon(stats, str(row.icon), Rect2(19, 80 + i * 62, 22, 22), UI.JADE)
		ui.label(stats, str(row.label), Rect2(51, 67 + i * 62, 150, 32), 17, UI.MUTED)
		ui.label(stats, str(row.value), Rect2(51, 95 + i * 62, 150, 31), 23)
	ui.label(stats, str(ui.world.run.get("seed_text", ui.Seed.text(int(ui.world.run.seed)))), Rect2(18, 448, 189, 36), 18, UI.JADE)
	var map_panel = ui.panel(ui.modal, Rect2(268, 178, 612, 509), UI.INSET, Color.TRANSPARENT)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(10, 10)
	scroll.size = Vector2(592, 443)
	map_panel.add_child(scroll)
	var canvas = Control.new()
	var minimum = Vector2.INF
	var maximum = -Vector2.INF
	for coordinate in ui.world.run.graph.coords:
		minimum = minimum.min(Vector2(coordinate))
		maximum = maximum.max(Vector2(coordinate))
	var visual = load("res://scripts/ui/route_map.gd").new()
	visual.world = ui.world
	visual.origin = minimum
	visual.spacing = maxf(100,ui.mobile_button_height+14) if ui.mobile_ui else 78
	canvas.custom_minimum_size = (maximum - minimum) * visual.spacing + Vector2(110,110)
	scroll.add_child(canvas)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(visual)
	var current_action: Button
	for i in ui.world.run.graph.types.size():
		if not Graph.visible(ui.world.run.graph, i): continue
		var kind = str(ui.world.run.graph.types[i])
		var text = str(Graph.NAMES[kind])
		var ids = ui.world.Campaign.boss_ids(ui.world.run.graph, i) if ui.world.run.get("campaign", false) else []
		if not ids.is_empty(): text = " / ".join(ids.map(func(id): return ui.world.db.name_of("bosses", str(id))))
		var current = i == int(ui.world.run.room)
		var visited = ui.world.run.visited.has(i)
		var diameter = maxf(78,ui.mobile_button_height) if ui.mobile_ui else 54
		var action = ui.icon_button(canvas, "此处 · " + text if current else text, ROOM_ICONS[kind], Rect2(visual.location(ui.world.run.graph.coords[i]) - Vector2.ONE * diameter * .5, Vector2.ONE * diameter), func(): ui.notice("沿房间内的方向门前行 · " + text))
		action.set_meta("nav_id", "map_room_" + str(i))
		action.set_meta("map_room", i)
		action.add_theme_stylebox_override("normal", UI.style(UI.LIFTED if visited else UI.SURFACE, UI.ACCENT if current else Color.TRANSPARENT, roundi(diameter * .5), 3 if current else 0))
		if current: current_action = action
		if visited: ui.icon(action, "check", Rect2(diameter - 16, -2, 18, 18), UI.JADE)
	if current_action != null: scroll.ensure_control_visible.call_deferred(current_action)
	ui.label(map_panel, "沿房间方向门前行", Rect2(22, 463, 560, 34), 17, UI.MUTED)
	var build = ui.panel(ui.modal, Rect2(896, 178, 352, 509), UI.INSET, Color.TRANSPARENT)
	ui.icon_button(build, "完整当前构筑", "layers", Rect2(20, 16, 144, 52), func(): show_sheet(ui, "build"), page == "build", "构筑")
	ui.icon_button(build, "所有历史选择", "scroll-text", Rect2(178, 16, 154, 52), func(): show_sheet(ui, "history"), page == "history", "已选")
	list_view(ui, build, page)
	var back = ui.icon_button(ui.modal, "返回房间", "arrow-left", Rect2(1142, 40, 80 if ui.mobile_ui else 62, 80 if ui.mobile_ui else 62), ui.resume_game)
	back.set_meta("nav_default", true)
