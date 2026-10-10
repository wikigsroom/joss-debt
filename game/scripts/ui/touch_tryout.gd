extends Node2D
## A full-surface input sandbox. No combat, account, save or gameplay RNG is changed.
const UI = preload("res://scripts/ui/game_theme.gd")
var app
var puppet = Vector2.ZERO
var last_action = ""
var body: Font
var layer: CanvasLayer

func _ready() -> void:
	set_meta("touch_trial", true)
	body = UI.body_font()
	app.screen = "touch_trial"
	app.paused = true
	app.hud.visible = false
	app.clear_modal()
	app.adapter.clear()
	app.adapter.set_phase("combat", true)
	puppet = app.adapter.safe_rect.get_center()
	layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var control = Control.new()
	control.theme = app.interface.theme
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(control)
	var safe = app.adapter.safe_rect
	app.icon_button(control, "结束试操作", "check", Rect2(safe.end.x - 224, safe.position.y + 20, 200, maxf(64, app.adapter.minimum_action_radius * 2)), finish, true, "完成")

func finish() -> void:
	if is_queued_for_deletion(): return
	app.adapter.clear()
	app.persist_settings()
	app.ControlSettings.show_layout(app)
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		app.adapter.event(event)
		if event is InputEventScreenDrag: get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		finish()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var frame = app.adapter.sample(Vector2.ZERO, Vector2.ZERO)
	puppet += Vector2(frame.move) * delta * 260
	puppet = app.adapter.safe_point(puppet, 55)
	if frame.dash: last_action = "身法"
	elif frame.skill: last_action = "焚债"
	elif frame.active_item: last_action = "道具"
	elif frame.fire: last_action = "攻击"
	queue_redraw()

func _draw() -> void:
	var safe = app.adapter.safe_rect
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), UI.INSET)
	var sprite = app.renderer.textures.get("c_paper_down")
	if sprite != null: draw_texture_rect(sprite, Rect2(puppet - Vector2(48, 80), Vector2(96, 96)), false)
	draw_line(puppet - Vector2(0, 28), puppet - Vector2(0, 28) + app.adapter.aim * 110, UI.JADE, 3, true)
	draw_string(body, safe.position + Vector2(24, 55), "试操作 · " + last_action, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.TEXT)
	for action in ["move", "aim", "dash", "skill", "active_item"]:
		var center = app.adapter.control_center(action)
		if action == "move" and app.adapter.move_id >= 0: center = app.adapter.left_origin
		if action == "aim" and app.adapter.aim_id >= 0: center = app.adapter.right_origin
		var radius = app.adapter.control_radius(action)
		draw_circle(center, radius, Color(UI.SURFACE, app.adapter.control_opacity))
		draw_arc(center, radius, 0, TAU, 40, UI.JADE if action == "move" else UI.ACCENT, 2, true)
		if action in ["move", "aim"]:
			var value = app.adapter.move_touch if action == "move" else app.adapter.aim_touch
			draw_circle(center + value * app.adapter.control_travel(action), radius * .3, UI.TEXT)
		else:
			var icon = UI.icon({"dash":"wind", "skill":"flame", "active_item":"zap"}[action])
			draw_texture_rect(icon, Rect2(center - Vector2.ONE * radius * .4, Vector2.ONE * radius * .8), false)
