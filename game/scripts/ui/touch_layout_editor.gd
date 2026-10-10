extends Control
signal selected_changed(action: String)
## The preview edits the same normalized centers used for drawing and capture.
var adapter
var font: Font
var dragged = ""
var active_finger = -1
var status: Label
var selected = "move"
const LABELS = {"move": "移动", "aim": "瞄准", "dash": "身法", "skill": "焚债", "active_item": "道具"}

func _draw() -> void:
	if adapter == null: return
	for action in LABELS:
		var normalized = (adapter.control_center(action) - adapter.safe_rect.position) / adapter.safe_rect.size
		var center = normalized * size
		var radius = adapter.control_radius(action) * size.x / adapter.safe_rect.size.x
		var color = Color("bc3c2f") if action == dragged or (has_focus() and action == selected) else Color("242725")
		draw_circle(center, radius, Color(color, .85))
		draw_arc(center, radius, 0, TAU, 40, Color("e7d8b6") if action == dragged else Color("c39a51"), 2, true)
		draw_string(font, center + Vector2(-23, 8), LABELS[action], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("e7d8b6"))

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var actions = LABELS.keys()
		selected = actions[(actions.find(selected) + 1) % actions.size()]
		selected_changed.emit(selected)
		queue_redraw()
		accept_event()
		return
	for direction in {"ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT, "ui_up": Vector2.UP, "ui_down": Vector2.DOWN}:
		if event.is_action_pressed(direction):
			var center = (adapter.control_center(selected) - adapter.safe_rect.position) / adapter.safe_rect.size
			var shift = {"ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT, "ui_up": Vector2.UP, "ui_down": Vector2.DOWN}[direction] * .015
			adapter.move_control(selected, center + shift)
			queue_redraw()
			accept_event()
			return
	var point = Vector2.ZERO
	var pressed = false
	var released = false
	var motion = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and active_finger == -1:
		point = event.position
		motion = not dragged.is_empty()
	elif event is InputEventScreenTouch:
		if event.canceled and event.index == active_finger:
			dragged = ""
			active_finger = -1
			queue_redraw()
			accept_event()
			return
		point = event.position
		pressed = event.pressed and active_finger < 0
		released = not event.pressed and active_finger == event.index
		if pressed: active_finger = event.index
	elif event is InputEventScreenDrag and event.index == active_finger:
		point = event.position
		motion = true
	else: return
	if pressed:
		var distance = 52.0
		for action in LABELS:
			var center = (adapter.control_center(action) - adapter.safe_rect.position) / adapter.safe_rect.size * size
			if center.distance_to(point) < distance:
				distance = center.distance_to(point)
				dragged = action
				selected = action
				selected_changed.emit(selected)
	if motion and not dragged.is_empty():
		var success = adapter.move_control(dragged, point / size)
		if status != null: status.text = "松手后可继续微调，保存后用于战斗。" if success else "触点需留出间距，避免误触。"
	if released:
		dragged = ""
		active_finger = -1
	queue_redraw()
	accept_event()
