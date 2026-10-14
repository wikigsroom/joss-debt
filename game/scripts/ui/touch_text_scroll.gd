extends Control
class_name InkTouchTextScroll

## Adds native ScreenTouch scrolling to TextEdit/RichTextLabel without
## replacing their selection, caret or keyboard behaviour. Godot's desktop
## text controls do not consistently consume ScreenDrag on Android, so this
## proxy owns only a confirmed vertical drag and leaves taps to the child.
const DRAG_DEADZONE := 12.0
const INERTIA_DECELERATION := 2600.0
const MAX_INERTIA := 2200.0
const FLING_MIN_SPEED := 60.0
const FLING_RELEASE_WINDOW_USEC := 100000

var target: Control
var _touch_id := -1
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _dragging := false
var _inertia := 0.0
var _last_motion_usec := 0

func set_target(control: Control) -> void:
	target = control

func _ready() -> void:
	set_meta("touch_text_scroll", "true")
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)

func _process(delta: float) -> void:
	if _touch_id >= 0 or not is_visible_in_tree() or not is_instance_valid(target): return
	var bar = target.get_v_scroll_bar()
	var before = bar.value
	bar.value = clampf(bar.value + _inertia * delta, 0.0, maxf(0.0, bar.max_value - bar.page))
	var moved = bar.value - before
	if absf(moved) < 0.001: _inertia = 0.0
	_inertia = move_toward(_inertia, 0.0, INERTIA_DECELERATION * delta)
	if absf(_inertia) < FLING_MIN_SPEED:
		_inertia = 0.0
		set_process(false)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(target): return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if _touch_id >= 0 or not _contains(event.position): return
		var bar = target.get_v_scroll_bar()
		if bar.max_value <= bar.page: return
		if bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position): return
		_touch_id = event.index
		_touch_start = _local_point(event.position)
		_touch_last = _touch_start
		_last_motion_usec = Time.get_ticks_usec()
		_inertia = 0.0
		return
	if event.index != _touch_id: return
	var was_dragging = _dragging
	_touch_id = -1
	_dragging = false
	if was_dragging: get_viewport().set_input_as_handled()
	if event.canceled or not was_dragging or Time.get_ticks_usec() - _last_motion_usec > FLING_RELEASE_WINDOW_USEC:
		_inertia = 0.0
	if absf(_inertia) >= FLING_MIN_SPEED: set_process(true)

func _handle_drag(event: InputEventScreenDrag) -> void:
	var point = _local_point(event.position)
	var delta = point - _touch_last
	var total = point - _touch_start
	_touch_last = point
	if not _dragging:
		if absf(total.y) < DRAG_DEADZONE or absf(total.y) < absf(total.x) * .72: return
		_dragging = true
	get_viewport().set_input_as_handled()
	var bar = target.get_v_scroll_bar()
	var before = bar.value
	bar.value = clampf(bar.value - delta.y, 0.0, maxf(0.0, bar.max_value - bar.page))
	var now = Time.get_ticks_usec()
	var elapsed = clampf(float(now - _last_motion_usec) / 1000000.0, 1.0 / 240.0, 0.1)
	_inertia = clampf((bar.value - before) / elapsed, -MAX_INERTIA, MAX_INERTIA)
	_last_motion_usec = now

func _contains(point: Vector2) -> bool:
	if not get_global_rect().has_point(point): return false
	var ancestor = get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(point): return false
		ancestor = ancestor.get_parent()
	return true

func _local_point(screen_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_point
