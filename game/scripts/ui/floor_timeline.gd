extends Control
## Read-only complete campaign line. Floor state follows the saved simulation.
const UI = preload("res://scripts/ui/game_theme.gd")
var world

func center(floor_id: int) -> Vector2:
	var count = int(world.run.floor_limit)
	return Vector2(28 + (floor_id - 1) * (size.x - 56) / maxi(1, count - 1), 23)

func _draw() -> void:
	if world == null: return
	for floor_id in range(1, int(world.run.floor_limit)):
		var from = center(floor_id)
		var to = center(floor_id + 1)
		draw_line(from, to, UI.JADE if floor_id < int(world.run.floor) else UI.EDGE, 3, true)

static func attach(app, rect: Rect2) -> void:
	var timeline = load("res://scripts/ui/floor_timeline.gd").new()
	timeline.world = app.world
	timeline.position = rect.position
	timeline.size = rect.size
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.set_meta("floor_timeline", true)
	timeline.set_meta("current_floor", int(app.world.run.floor))
	app.modal.add_child(timeline)
	for floor_id in range(1, int(app.world.run.floor_limit) + 1):
		var current = floor_id == int(app.world.run.floor)
		var completed = floor_id < int(app.world.run.floor)
		var region = app.world.Campaign.biome(app.world.db, str(app.world.run.seed_text), floor_id) if app.world.run.get("campaign", false) else app.world.db.rows("regions")[mini(2, floor_id - 1)]
		var point = timeline.center(floor_id)
		var node = app.panel(timeline, Rect2(point - Vector2.ONE * 17, Vector2.ONE * 34), UI.ACCENT if current else (UI.SURFACE if completed else UI.INSET), UI.JADE if completed else UI.EDGE)
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.set_meta("floor_id", floor_id)
		node.set_meta("floor_state", "current" if current else ("completed" if completed else "future"))
		node.tooltip_text = "第%d重 · %s%s" % [floor_id, region.name, " · 剧情首领" if floor_id == 6 else (" · 最终总账" if floor_id == 11 else "")]
		node.accessibility_name = node.tooltip_text
		var value = app.label(node, str(floor_id), Rect2(0, 1, 34, 31), 17, UI.TEXT if current or completed else UI.MUTED)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if completed: app.icon(node, "check", Rect2(25, 23, 13, 13), UI.JADE)
		elif floor_id in [6, 11]: app.icon(node, "crown", Rect2(25, 23, 13, 13), UI.GOLD)
		var name = app.label(timeline, str(region.name), Rect2(point.x - 38, 45, 76, 25), 13, UI.ACCENT if current else UI.MUTED)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
