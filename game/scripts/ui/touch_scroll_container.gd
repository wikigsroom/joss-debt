extends ScrollContainer
class_name InkTouchScrollContainer

## Native ScreenDrag handling, independent of touch-to-mouse emulation.
## Keep taps available to descendants; cancel their pending press when a
## genuine scroll starts. Maps opt into two-axis panning; other pages scroll
## vertically. All distances and velocities are in the container's coordinates.
const DRAG_DEADZONE := 12.0
const AXIS_BIAS := 0.72
const INERTIA_DECELERATION := 2600.0
const MAX_INERTIA := 2200.0
const FLING_MIN_SPEED := 60.0
const FLING_RELEASE_WINDOW_USEC := 100000

var pan_horizontal := false
var _touch_id := -1
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _dragging := false
var _scroll_started := false
var _inertia := Vector2.ZERO
var _last_motion_usec := 0
var _tap_target: BaseButton
var _tap_signal_button: BaseButton
var _tap_callable := Callable()
var _tap_fired := false
var _last_observed_scroll := Vector2.ZERO

func _ready() -> void:
	set_meta("touch_scroll", "true")
	add_to_group("menu_touch_scroll")
	# The container observes ScreenTouch in _input, but it must not become the
	# GUI hit-test owner for a tap. Passing the GUI event through keeps a short
	# press on a child Button a real activation while the container still owns
	# the gesture after the vertical drag deadzone is crossed.
	mouse_filter = Control.MOUSE_FILTER_PASS
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if pan_horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_deadzone = roundi(DRAG_DEADZONE)
	mouse_force_pass_scroll_events = true
	resized.connect(cancel_touch_scroll)
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		cancel_touch_scroll()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		cancel_touch_scroll()

func _process(delta: float) -> void:
	if _touch_id >= 0: return
	if not is_visible_in_tree():
		cancel_touch_scroll()
		return
	var current_scroll = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
	# A page can reset scroll_vertical while a fling is still decelerating. Treat
	# that jump as an external command, otherwise the next tap can move away
	# from the row the user just selected.
	if _inertia.length() > 0.0 and current_scroll.distance_to(_last_observed_scroll) > 0.5:
		_inertia = Vector2.ZERO
		_finish_scroll()
	var moved = _scroll_by(_inertia * delta)
	if absf(moved.x) < 0.001: _inertia.x = 0
	if absf(moved.y) < 0.001: _inertia.y = 0
	_inertia = _inertia.move_toward(Vector2.ZERO, INERTIA_DECELERATION * delta)
	if _inertia.length() < FLING_MIN_SPEED:
		_inertia = Vector2.ZERO
		_finish_scroll()
	_last_observed_scroll = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	# A phone can emit a mouse event after the native touch. Prevent the built-in
	# mouse drag path from also scrolling this same gesture a second time.
	if event.device == InputEvent.DEVICE_ID_EMULATION and _touch_id >= 0 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_handle_drag(event)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		# A new deliberate keyboard/mouse action stops a prior touch fling.
		if _touch_id < 0 and _scroll_started: cancel_touch_scroll()

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if _touch_id >= 0:
			return
		if not _contains_touch(event.position):
			return
		# Leave a real scrollbar thumb to its native drag handling.
		for bar in [get_v_scroll_bar(), get_h_scroll_bar()]:
			if bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position): return
		cancel_touch_scroll()
		_touch_id = event.index
		_touch_start = _local_point(event.position)
		_touch_last = _touch_start
		_last_motion_usec = Time.get_ticks_usec()
		_tap_target = _button_at(self, event.position)
		_tap_fired = false
		if is_instance_valid(_tap_target):
			_tap_callable = _mark_tap_fired.bind(_tap_target)
			_tap_signal_button = _tap_target
			if not _tap_target.is_connected("pressed", _tap_callable):
				_tap_target.pressed.connect(_tap_callable, CONNECT_ONE_SHOT)
		return
	if event.index != _touch_id: return
	var was_dragging = _dragging
	_touch_id = -1
	_dragging = false
	if was_dragging: get_viewport().set_input_as_handled()
	var tap_target = _tap_target
	var tap_is_pending = not was_dragging
	_tap_target = null
	_tap_fired = false
	if event.canceled or not was_dragging or Time.get_ticks_usec() - _last_motion_usec > FLING_RELEASE_WINDOW_USEC:
		_inertia = Vector2.ZERO
	if _inertia.length() >= FLING_MIN_SPEED:
		set_process(true)
	else:
		_finish_scroll()
	if tap_is_pending and is_instance_valid(tap_target):
		# ScreenTouch-to-mouse emulation is not consistent on every Android
		# backend. Defer one frame so a normal Button press gets first chance; the
		# fallback only emits when the child did not receive that tap.
		call_deferred("_complete_tap", tap_target)

func _handle_drag(event: InputEventScreenDrag) -> void:
	var point = _local_point(event.position)
	var delta = point - _touch_last
	var total = point - _touch_start
	_touch_last = point
	if not _dragging:
		if (total.length() if pan_horizontal else absf(total.y)) < DRAG_DEADZONE: return
		if not pan_horizontal and absf(total.y) < absf(total.x) * AXIS_BIAS: return
		_dragging = true
		_disconnect_tap_signal()
		_tap_target = null
		_tap_fired = false
		_begin_scroll()
	# Once accepted, the gesture retains its owner even on diagonal reversals,
	# outside the viewport, or at an edge. This prevents release-to-click leaks.
	get_viewport().set_input_as_handled()
	var moved = _scroll_by(-delta)
	_last_observed_scroll = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
	var now = Time.get_ticks_usec()
	var elapsed = clampf(float(now - _last_motion_usec) / 1000000.0, 1.0 / 240.0, 0.1)
	_inertia = (moved / elapsed).limit_length(MAX_INERTIA)
	_last_motion_usec = now

func _begin_scroll() -> void:
	# Godot buttons clear their touch owner on this notification, so the next
	# tap (including another finger index) works after a canceled drag.
	propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	_scroll_started = true
	scroll_started.emit()

func _finish_scroll() -> void:
	set_process(false)
	if _scroll_started:
		_scroll_started = false
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
		scroll_ended.emit()

func cancel_touch_scroll() -> void:
	_touch_id = -1
	_dragging = false
	_disconnect_tap_signal()
	_tap_target = null
	_tap_fired = false
	_inertia = Vector2.ZERO
	_finish_scroll()

func _mark_tap_fired(button: BaseButton) -> void:
	if button == _tap_target: _tap_fired = true

func _disconnect_tap_signal() -> void:
	if is_instance_valid(_tap_signal_button) and _tap_callable.is_valid() and _tap_signal_button.is_connected("pressed", _tap_callable):
		_tap_signal_button.pressed.disconnect(_tap_callable)
	_tap_signal_button = null
	_tap_callable = Callable()

func _complete_tap(button: BaseButton) -> void:
	if not _tap_fired and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
		button.emit_signal("pressed")
	_tap_fired = false
	# The release path clears _tap_target before this deferred fallback runs;
	# disconnect from the captured button directly so a missed native tap does
	# not leave a stale one-shot connection for the next gesture.
	if is_instance_valid(button) and _tap_callable.is_valid() and button.is_connected("pressed", _tap_callable):
		button.pressed.disconnect(_tap_callable)
	_tap_signal_button = null
	_tap_callable = Callable()

func _button_at(node: Node, point: Vector2) -> BaseButton:
	for index in range(node.get_child_count() - 1, -1, -1):
		var nested = _button_at(node.get_child(index), point)
		if nested != null: return nested
	if node is BaseButton and node.is_visible_in_tree() and not node.disabled and node.get_global_rect().has_point(point):
		return node
	return null

func _contains_touch(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(_local_point(point)): return false
	var ancestor = get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(point): return false
		ancestor = ancestor.get_parent()
	return true

func _local_point(screen_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_point

func _limits() -> Vector2:
	var h = get_h_scroll_bar()
	var v = get_v_scroll_bar()
	return Vector2(maxf(0, h.max_value - h.page) if pan_horizontal else 0.0, maxf(0, v.max_value - v.page))

func _scroll_by(offset: Vector2) -> Vector2:
	var h = get_h_scroll_bar()
	var v = get_v_scroll_bar()
	var before = Vector2(h.value, v.value)
	var next = (before + offset).clamp(Vector2.ZERO, _limits())
	if pan_horizontal: h.value = next.x
	v.value = next.y
	return Vector2(h.value, v.value) - before
