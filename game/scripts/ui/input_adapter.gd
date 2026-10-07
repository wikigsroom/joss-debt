extends RefCounted
## Keyboard/mouse, controller, and three independent touch IDs yield one ActionFrame.
const Profile = preload("res://scripts/ui/input_profile.gd")
const DEFAULT_LAYOUT = {"move": [.11328125, .7916667], "aim": [.7109375, .7916667], "dash": [.8125, .8402778], "skill": [.9140625, .75]}
var profile = Profile.new()
var layout: Dictionary = DEFAULT_LAYOUT.duplicate(true)
var control_scale = 1.0
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
	pending_interact = false
	previous_pad.clear()
	fire_latched = false
	previous_fire = false
	release_gate = true

func control_radius(action: String) -> float:
	return 72.0 * control_scale if action in ["move", "aim"] else maxf(minimum_action_radius, 46.0 * control_scale)

func control_center(action: String) -> Vector2:
	var values = layout.get(action, DEFAULT_LAYOUT[action])
	var normalized = Vector2(values[0], values[1])
	if mirror: normalized.x = 1 - normalized.x
	return safe_point(safe_rect.position + normalized * safe_rect.size, control_radius(action) + 6)

func move_control(action: String, normalized: Vector2) -> bool:
	if not layout.has(action): return false
	var old = layout[action]
	normalized = normalized.clamp(Vector2(.02, .35), Vector2(.98, .96))
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
			if control_center(actions[i]).distance_to(control_center(actions[j])) < control_radius(actions[i]) + control_radius(actions[j]) + 8: return false
	return true

func configure(data: Dictionary) -> void:
	profile.load_data(data.get("bindings", {}))
	deadzone = clampf(float(data.get("deadzone", .18)), .08, .35)
	fixed_sticks = bool(data.get("fixed_sticks", false))
	fire_toggle = bool(data.get("fire_toggle", false))
	control_scale = clampf(float(data.get("control_scale", 1)), .75, 1.25)
	control_opacity = clampf(float(data.get("control_opacity", 1)), .35, 1)
	layout = DEFAULT_LAYOUT.duplicate(true)
	var incoming = data.get("touch_layout", {})
	if incoming is Dictionary:
		for action in layout:
			var values = incoming.get(action, layout[action])
			if values is Array and values.size() == 2 and (values[0] is float or values[0] is int) and (values[1] is float or values[1] is int):
				layout[action] = [clampf(float(values[0]), .02, .98), clampf(float(values[1]), .35, .96)]
	if not valid_layout():
		control_scale = 1.0
		layout = DEFAULT_LAYOUT.duplicate(true)
	clear()

func dash_center() -> Vector2:
	return control_center("dash")

func skill_center() -> Vector2:
	return control_center("skill")

func event(event_value: InputEvent) -> void:
	if event_value is InputEventMouseMotion and event_value.relative.length() > .5:
		keyboard_aim_active = false
	if event_value is InputEventKey or event_value is InputEventMouseButton or event_value is InputEventMouseMotion: last_device = "keyboard"
	elif event_value is InputEventJoypadButton or (event_value is InputEventJoypadMotion and absf(event_value.axis_value) > deadzone): last_device = "controller"
	if profile.event_matches("dash", event_value): pending_dash = true
	if profile.event_matches("interact", event_value): pending_interact = true
	if profile.event_matches("skill", event_value): pending_skill = true
	if profile.event_matches("fire", event_value): release_gate = false
	for action in ["aim_up", "aim_down", "aim_left", "aim_right"]:
		if profile.event_matches(action, event_value):
			release_gate = false
			keyboard_aim_active = true
	if event_value is InputEventScreenTouch:
		last_device = "touch"
		if event_value.pressed and not safe_rect.has_point(event_value.position): return
		touch_mode = true
		if event_value.pressed:
			fingers[event_value.index] = event_value.position
			if event_value.position.distance_to(dash_center()) <= control_radius("dash") + 2:
				pending_dash = true
				held_action_ids[event_value.index] = "dash"
			elif event_value.position.distance_to(skill_center()) <= control_radius("skill") + 2:
				pending_skill = true
				held_action_ids[event_value.index] = "skill"
			elif ((event_value.position.x < 640) != mirror) and move_id < 0:
				move_id = event_value.index
				left_origin = control_center("move") if fixed_sticks else safe_point(event_value.position, control_radius("move") + 2)
				move_touch = ((event_value.position - left_origin) / (70 * control_scale)).limit_length() if fixed_sticks else Vector2.ZERO
			elif aim_id < 0:
				aim_id = event_value.index
				release_gate = false
				right_origin = control_center("aim") if fixed_sticks else safe_point(event_value.position, control_radius("aim") + 2)
				aim_touch = ((event_value.position - right_origin) / (70 * control_scale)).limit_length() if fixed_sticks else Vector2.ZERO
		else:
			fingers.erase(event_value.index)
			held_action_ids.erase(event_value.index)
			if event_value.index == move_id:
				move_id = -1
				move_touch = Vector2.ZERO
			if event_value.index == aim_id:
				aim_id = -1
				aim_touch = Vector2.ZERO
	if event_value is InputEventScreenDrag:
		fingers[event_value.index] = event_value.position
		if event_value.index == move_id:
			move_touch = ((event_value.position - left_origin) / (70 * control_scale)).limit_length()
		if event_value.index == aim_id:
			aim_touch = ((event_value.position - right_origin) / (70 * control_scale)).limit_length()

func sample(mouse: Vector2, player_position: Vector2) -> Dictionary:
	var movement = Vector2(profile.strength("keyboard", "right") - profile.strength("keyboard", "left"), profile.strength("keyboard", "down") - profile.strength("keyboard", "up"))
	var firing = profile.strength("keyboard", "fire") > .5
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
		var buttons = {"skill": profile.strength("controller", "skill", pad) > .25, "dash": profile.strength("controller", "dash", pad) > .25, "interact": profile.strength("controller", "interact", pad) > .5}
		pending_skill = pending_skill or (buttons.skill and not previous_pad.get("skill", false))
		pending_dash = pending_dash or (buttons.dash and not previous_pad.get("dash", false))
		pending_interact = pending_interact or (buttons.interact and not previous_pad.get("interact", false))
		previous_pad = buttons
	if touch_mode:
		if move_touch.length() > deadzone:
			movement = projected_direction(move_touch)
		elif move_id >= 0:
			movement = Vector2.ZERO
		if aim_touch.length() > deadzone:
			aim = projected_direction(aim_touch).normalized()
		firing = firing or aim_touch.length() > 0.22
	if release_gate:
		if not firing: release_gate = false
		firing = false
	if fire_toggle and last_device != "touch":
		if firing and not previous_fire: fire_latched = not fire_latched
		previous_fire = firing
		firing = fire_latched
	var result = {"move": movement.limit_length(), "aim": aim, "fire": firing,
		"dash": pending_dash, "skill": pending_skill, "interact": pending_interact}
	pending_dash = false
	pending_skill = false
	pending_interact = false
	return result
