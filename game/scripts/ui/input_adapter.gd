extends RefCounted
## Keyboard/mouse, controller, and three independent touch IDs yield one ActionFrame.
const Profile = preload("res://scripts/ui/input_profile.gd")
const DEFAULT_LAYOUT = {"move": [.105, .80], "aim": [.895, .80], "dash": [.25, .65], "skill": [.75, .65], "active_item": [.70, .88]}
const PRESETS = {"phone": DEFAULT_LAYOUT, "tablet": {"move": [.12, .81], "aim": [.88, .81], "dash": [.27, .66], "skill": [.73, .66], "active_item": [.68, .88]}}
var profile = Profile.new()
var layout: Dictionary = DEFAULT_LAYOUT.duplicate(true)
var control_scale = 1.0
var control_sizes: Dictionary = {"move": 1.0, "aim": 1.0, "dash": 1.0, "skill": 1.0, "active_item": 1.0}
var minimum_stick_radius = 48.0
var control_gap = 8.0
var phase = "combat"
var item_visible = true
var touch_firing = false
var recent_move = Vector2.ZERO
var recent_move_at = -1000
var aim_released_at = -1000
var control_opacity = 1.0
var fixed_sticks = false
var deadzone = .18
var minimum_action_radius = 40.0
var fire_toggle = false
var fire_latched = false
var previous_fire = false
var release_gate = false

var aim = Vector2.UP
var keyboard_aim_active = false
var touch_mode = false
var mirror = false
var fingers: Dictionary = {}
var move_id = -1
var aim_id = -1
var left_origin = Vector2(145, 570)
var right_origin = Vector2(910, 570)
var move_touch = Vector2.ZERO
var aim_touch = Vector2.ZERO
var pending_dash = false
var pending_skill = false
var pending_active_item = false
var pending_interact = false
var previous_pad: Dictionary = {}
var held_action_ids: Dictionary = {}
var safe_rect = Rect2(0, 0, 1280, 720)
var last_device = "keyboard"

static func projected_direction(value: Vector2) -> Vector2:
	return Vector2(value.x, value.y / .84722).normalized() * value.length() if value.length() > 0 else Vector2.ZERO

func safe_point(value: Vector2, margin: float = 50) -> Vector2:
	return value.clamp(safe_rect.position + Vector2.ONE * margin, safe_rect.end - Vector2.ONE * margin)

func clear() -> void:
	fingers.clear()
	held_action_ids.clear()
	move_id = -1
	aim_id = -1
	move_touch = Vector2.ZERO
	aim_touch = Vector2.ZERO
	pending_dash = false
	pending_skill = false
	pending_active_item = false
	pending_interact = false
	previous_pad.clear()
	fire_latched = false
	previous_fire = false
	release_gate = true
	touch_firing = false
	recent_move = Vector2.ZERO
	recent_move_at = -1000
	aim_released_at = -1000

func control_radius(action: String) -> float:
	var factor = control_scale * float(control_sizes.get(action, 1.0))
	return maxf(minimum_stick_radius, 72.0 * factor) if action in ["move", "aim"] else maxf(minimum_action_radius, 46.0 * factor)

func control_travel(action: String) -> float:
	return control_radius(action) * .72

func enabled(action: String) -> bool:
	if action == "move" or action == "dash": return phase in ["combat", "clear"]
	if action == "active_item": return item_visible and phase in ["combat", "clear"]
	return phase == "combat"

func set_phase(value: String, equipped: bool) -> void:
	if value != phase or equipped != item_visible:
		clear()
	phase = value
	item_visible = equipped

func set_control_size(action: String, value: float) -> bool:
	if not control_sizes.has(action): return false
	var previous = control_sizes[action]
	control_sizes[action] = clampf(value, .75, 1.75)
	if not valid_layout():
		control_sizes[action] = previous
		return false
	return true

func reset_layout(preset: String = "phone") -> void:
	layout = PRESETS.get(preset, DEFAULT_LAYOUT).duplicate(true)
	for key in control_sizes: control_sizes[key] = 1.0
	control_scale = 1.0
	clear()

func control_center(action: String) -> Vector2:
	var values = layout.get(action, DEFAULT_LAYOUT[action])
	var normalized = Vector2(values[0], values[1])
	if mirror: normalized.x = 1 - normalized.x
	return safe_point(safe_rect.position + normalized * safe_rect.size, control_radius(action) + 6)

func move_control(action: String, normalized: Vector2) -> bool:
	if not layout.has(action): return false
	var old = layout[action]
	normalized = normalized.clamp(Vector2(.02, .40), Vector2(.98, .96))
	if mirror: normalized.x = 1 - normalized.x
	layout[action] = [normalized.x, normalized.y]
	if not valid_layout():
		layout[action] = old
		return false
	return true

func valid_layout() -> bool:
	var actions = layout.keys()
	for i in actions.size():
		for j in range(i + 1, actions.size()):
			if control_center(actions[i]).distance_to(control_center(actions[j])) < control_radius(actions[i]) + control_radius(actions[j]) + control_gap: return false
	return true

func configure(data: Dictionary) -> void:
	profile.load_data(data.get("bindings", {}))
	deadzone = clampf(float(data.get("deadzone", .18)), .08, .35)
	fixed_sticks = bool(data.get("fixed_sticks", false))
	fire_toggle = bool(data.get("fire_toggle", false))
	control_scale = clampf(float(data.get("control_scale", 1)), .75, 1.25)
	var incoming_sizes = data.get("touch_sizes", {})
	for key in control_sizes:
		control_sizes[key] = clampf(float(incoming_sizes.get(key, 1.0)), .75, 1.75) if incoming_sizes is Dictionary else 1.0
	control_opacity = clampf(float(data.get("control_opacity", 1)), .35, 1)
	layout = DEFAULT_LAYOUT.duplicate(true)
	var incoming = data.get("touch_layout", {})
	if incoming is Dictionary:
		for action in layout:
			var values = incoming.get(action, layout[action])
			if values is Array and values.size() == 2 and (values[0] is float or values[0] is int) and (values[1] is float or values[1] is int):
				layout[action] = [clampf(float(values[0]), .02, .98), clampf(float(values[1]), .35, .96)]
		if not incoming.has("active_item") and not valid_layout():
			# Keep older customized controls when adding a fifth touch target.
			for y in [.89, .70, .52]:
				for x in [.91, .72, .52, .32, .12]:
					layout.active_item = [x, y]
					if valid_layout(): break
				if valid_layout(): break
	if not valid_layout():
		control_scale = 1.0
		layout = DEFAULT_LAYOUT.duplicate(true)
		for key in control_sizes: control_sizes[key] = 1.0
	clear()

func dash_center() -> Vector2:
	return control_center("dash")

func skill_center() -> Vector2:
	return control_center("skill")

func event(event_value: InputEvent) -> void:
	# GUI still receives touch-emulated clicks. Gameplay must keep their touch
	# device identity, charge handoff and movement-based dash direction.
	if (event_value is InputEventMouseButton or event_value is InputEventMouseMotion) and event_value.device == InputEvent.DEVICE_ID_EMULATION: return
	if event_value is InputEventMouseMotion and event_value.relative.length() > .5:
		keyboard_aim_active = false
	if event_value is InputEventKey or event_value is InputEventMouseButton or event_value is InputEventMouseMotion: last_device = "keyboard"
	elif event_value is InputEventJoypadButton or (event_value is InputEventJoypadMotion and absf(event_value.axis_value) > deadzone): last_device = "controller"
	if profile.event_matches("dash", event_value): pending_dash = true
	if profile.event_matches("interact", event_value): pending_interact = true
	if profile.event_matches("skill", event_value): pending_skill = true
	if profile.event_matches("active_item", event_value): pending_active_item = true
	if profile.event_matches("fire", event_value): release_gate = false
	for action in ["aim_up", "aim_down", "aim_left", "aim_right"]:
		if profile.event_matches(action, event_value):
			release_gate = false
			keyboard_aim_active = true
	if event_value is InputEventScreenTouch:
		last_device = "touch"
		if event_value.canceled:
			release_finger(event_value.index)
			aim_released_at = -1000
			return
		if event_value.pressed and not safe_rect.has_point(event_value.position): return
		touch_mode = true
		if event_value.pressed:
			fingers[event_value.index] = event_value.position
			if enabled("dash") and event_value.position.distance_to(dash_center()) <= control_radius("dash") + 2:
				pending_dash = true
				held_action_ids[event_value.index] = "dash"
			elif enabled("skill") and event_value.position.distance_to(skill_center()) <= control_radius("skill") + 2:
				pending_skill = true
				held_action_ids[event_value.index] = "skill"
			elif enabled("active_item") and event_value.position.distance_to(control_center("active_item")) <= control_radius("active_item") + 2:
				pending_active_item = true
				held_action_ids[event_value.index] = "active_item"
			else:
				var action = stick_at(event_value.position)
				if action == "move":
					move_id = event_value.index
					left_origin = control_center("move") if fixed_sticks else floating_origin(action, event_value.position)
					move_touch = ((event_value.position - left_origin) / control_travel("move")).limit_length() if fixed_sticks else Vector2.ZERO
				elif action == "aim":
					aim_id = event_value.index
					release_gate = false
					right_origin = control_center("aim") if fixed_sticks else floating_origin(action, event_value.position)
					aim_touch = ((event_value.position - right_origin) / control_travel("aim")).limit_length() if fixed_sticks else Vector2.ZERO
		else:
			release_finger(event_value.index)
	if event_value is InputEventScreenDrag:
		if not fingers.has(event_value.index): return
		fingers[event_value.index] = event_value.position
		if event_value.index == move_id:
			move_touch = ((event_value.position - left_origin) / control_travel("move")).limit_length()
		if event_value.index == aim_id:
			aim_touch = ((event_value.position - right_origin) / control_travel("aim")).limit_length()

func release_finger(index: int) -> void:
	fingers.erase(index)
	held_action_ids.erase(index)
	if index == move_id:
		move_id = -1
		move_touch = Vector2.ZERO
	if index == aim_id:
		aim_released_at = Time.get_ticks_msec()
		aim_id = -1
		aim_touch = Vector2.ZERO
		touch_firing = false

func stick_at(point: Vector2) -> String:
	if not fixed_sticks and point.y < safe_rect.position.y + safe_rect.size.y * .45: return ""
	var best = INF
	var result = ""
	for action in ["move", "aim"]:
		if not enabled(action) or (move_id >= 0 if action == "move" else aim_id >= 0): continue
		var distance = point.distance_to(control_center(action)) / control_radius(action)
		if distance <= (1.12 if fixed_sticks else 1.9) and distance < best:
			best = distance
			result = action
	return result

func floating_origin(action: String, point: Vector2) -> Vector2:
	var origin = safe_point(point, control_radius(action) + 6)
	for button in ["dash", "skill", "active_item"]:
		if not enabled(button): continue
		var center = control_center(button)
		var clearance = control_radius(button) + control_radius(action) + control_gap
		if origin.distance_to(center) < clearance:
			var direction = center.direction_to(origin)
			if direction.is_zero_approx(): direction = Vector2.DOWN
			origin = safe_point(center + direction * clearance, control_radius(action) + 6)
	return origin

func sample(mouse: Vector2, player_position: Vector2) -> Dictionary:
	var movement = Vector2(profile.strength("keyboard", "right") - profile.strength("keyboard", "left"), profile.strength("keyboard", "down") - profile.strength("keyboard", "up"))
	var firing = last_device != "touch" and profile.strength("keyboard", "fire") > .5
	# Arrow keys are a dedicated keyboard twin-stick: WASD keeps movement free while
	# the four arrows aim and fire continuously, which is predictable on a laptop.
	var arrow_aim = Vector2(profile.strength("keyboard", "aim_right") - profile.strength("keyboard", "aim_left"), profile.strength("keyboard", "aim_down") - profile.strength("keyboard", "aim_up"))
	if arrow_aim.length() > .01:
		keyboard_aim_active = true
		last_device = "keyboard"
		aim = arrow_aim.normalized()
		firing = true
	if not touch_mode and last_device == "keyboard" and not keyboard_aim_active:
		var mouse_aim = mouse - player_position
		if mouse_aim.length() > 5 and arrow_aim.length() <= .01:
			aim = mouse_aim.normalized()
	if not Input.get_connected_joypads().is_empty():
		var pad = Input.get_connected_joypads()[0]
		var left = Vector2(profile.strength("controller", "right", pad) - profile.strength("controller", "left", pad), profile.strength("controller", "down", pad) - profile.strength("controller", "up", pad))
		var right = Vector2(profile.strength("controller", "aim_right", pad) - profile.strength("controller", "aim_left", pad), profile.strength("controller", "aim_down", pad) - profile.strength("controller", "aim_up", pad))
		if left.length() > deadzone:
			last_device = "controller"
			movement = projected_direction(left.limit_length())
		if right.length() > deadzone:
			last_device = "controller"
			aim = projected_direction(right).normalized()
		var pad_fire = profile.strength("controller", "fire", pad) > .22
		if pad_fire: last_device = "controller"
		firing = firing or pad_fire
		var buttons = {"skill": profile.strength("controller", "skill", pad) > .25, "dash": profile.strength("controller", "dash", pad) > .25, "interact": profile.strength("controller", "interact", pad) > .5, "active_item": profile.strength("controller", "active_item", pad) > .5}
		pending_skill = pending_skill or (buttons.skill and not previous_pad.get("skill", false))
		pending_dash = pending_dash or (buttons.dash and not previous_pad.get("dash", false))
		pending_interact = pending_interact or (buttons.interact and not previous_pad.get("interact", false))
		pending_active_item = pending_active_item or (buttons.active_item and not previous_pad.get("active_item", false))
		previous_pad = buttons
	if touch_mode:
		if move_touch.length() > deadzone:
			movement = projected_direction(move_touch)
			recent_move = movement.normalized()
			recent_move_at = Time.get_ticks_msec()
		elif move_id >= 0:
			movement = Vector2.ZERO
		if aim_touch.length() > deadzone:
			aim = projected_direction(aim_touch).normalized()
		if aim_touch.length() <= deadzone or not enabled("aim"): touch_firing = false
		elif aim_touch.length() >= maxf(.22, deadzone + .04): touch_firing = true
		firing = firing or touch_firing
	if release_gate:
		if not firing: release_gate = false
		firing = false
	if fire_toggle and last_device != "touch":
		if firing and not previous_fire: fire_latched = not fire_latched
		previous_fire = firing
		firing = fire_latched
	var result = {"move": movement.limit_length(), "aim": aim, "fire": firing,
		"dash": pending_dash, "skill": pending_skill, "interact": pending_interact, "active_item": pending_active_item,
		"device": last_device, "manual_aim": aim_id >= 0 and aim_touch.length() > deadzone,
		"dash_direction": recent_move if last_device == "touch" and Time.get_ticks_msec() - recent_move_at <= 250 else Vector2.ZERO,
		"charge_hold": last_device == "touch" and aim_id < 0 and Time.get_ticks_msec() - aim_released_at <= 150 and (pending_skill or pending_active_item or not held_action_ids.is_empty())}
	pending_dash = false
	pending_skill = false
	pending_active_item = false
	pending_interact = false
	return result
