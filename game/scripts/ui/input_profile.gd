extends RefCounted
## Device bindings are local profile data. Conflicts swap atomically.
const ACTION_NAMES = {"up": "向上移动", "down": "向下移动", "left": "向左移动", "right": "向右移动",
	"aim_up": "向上瞄准", "aim_down": "向下瞄准", "aim_left": "向左瞄准", "aim_right": "向右瞄准",
	"fire": "主攻击", "skill": "焚债", "active_item": "主动道具", "dash": "身法", "interact": "拾取 / 交互", "pause": "暂停 / 返回", "map": "行路图", "inventory": "愿簿", "fullscreen": "全屏"}
const KEYBOARD_ACTIONS = ["up", "down", "left", "right", "aim_up", "aim_down", "aim_left", "aim_right", "fire", "skill", "active_item", "dash", "interact", "map", "inventory", "pause", "fullscreen"]
const PAD_ACTIONS = ["up", "down", "left", "right", "aim_up", "aim_down", "aim_left", "aim_right", "fire", "skill", "active_item", "dash", "interact", "map", "inventory", "pause", "fullscreen"]
const ALTERNATES = {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "skill": KEY_Q}
static var pristine = defaults()
var bindings: Dictionary = defaults()

static func defaults() -> Dictionary:
	return {"keyboard": {"up": {"type": "key", "code": KEY_W}, "down": {"type": "key", "code": KEY_S},
		"left": {"type": "key", "code": KEY_A}, "right": {"type": "key", "code": KEY_D},
		"aim_up": {"type": "key", "code": KEY_UP}, "aim_down": {"type": "key", "code": KEY_DOWN},
		"aim_left": {"type": "key", "code": KEY_LEFT}, "aim_right": {"type": "key", "code": KEY_RIGHT},
		"fire": {"type": "mouse", "code": MOUSE_BUTTON_LEFT}, "skill": {"type": "mouse", "code": MOUSE_BUTTON_RIGHT},
		"active_item": {"type": "key", "code": KEY_F},
		"dash": {"type": "key", "code": KEY_SPACE}, "interact": {"type": "key", "code": KEY_E},
		"map": {"type": "key", "code": KEY_TAB}, "inventory": {"type": "key", "code": KEY_I},
		"pause": {"type": "key", "code": KEY_ESCAPE}, "fullscreen": {"type": "key", "code": KEY_F11}},
		"controller": {"up": {"type": "axis", "code": JOY_AXIS_LEFT_Y, "sign": -1}, "down": {"type": "axis", "code": JOY_AXIS_LEFT_Y, "sign": 1},
		"left": {"type": "axis", "code": JOY_AXIS_LEFT_X, "sign": -1}, "right": {"type": "axis", "code": JOY_AXIS_LEFT_X, "sign": 1},
		"aim_up": {"type": "axis", "code": JOY_AXIS_RIGHT_Y, "sign": -1}, "aim_down": {"type": "axis", "code": JOY_AXIS_RIGHT_Y, "sign": 1},
		"aim_left": {"type": "axis", "code": JOY_AXIS_RIGHT_X, "sign": -1}, "aim_right": {"type": "axis", "code": JOY_AXIS_RIGHT_X, "sign": 1},
		"fire": {"type": "axis", "code": JOY_AXIS_TRIGGER_RIGHT, "sign": 1}, "skill": {"type": "button", "code": JOY_BUTTON_RIGHT_SHOULDER},
		"active_item": {"type": "button", "code": JOY_BUTTON_X},
		"dash": {"type": "axis", "code": JOY_AXIS_TRIGGER_LEFT, "sign": 1}, "interact": {"type": "button", "code": JOY_BUTTON_A},
		"map": {"type": "button", "code": JOY_BUTTON_LEFT_STICK}, "inventory": {"type": "button", "code": JOY_BUTTON_BACK},
		"pause": {"type": "button", "code": JOY_BUTTON_START}, "fullscreen": {"type": "button", "code": JOY_BUTTON_Y}}}

func load_data(data) -> void:
	bindings = defaults()
	if not data is Dictionary: return
	for device in bindings:
		var incoming = data.get(device, {})
		if not incoming is Dictionary: continue
		var used: Array = []
		var candidate = bindings[device].duplicate(true)
		# Adding an action must preserve older custom bindings that already use F/X.
		if not incoming.has("active_item"):
			var occupied: Array = []
			for action in candidate:
				if action == "active_item": continue
				var value = incoming.get(action, candidate[action])
				if valid_binding(device, value): occupied.append(normalize_binding(value))
			var alternatives = [KEY_F, KEY_G, KEY_V, KEY_R] if device == "keyboard" else [JOY_BUTTON_X, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_DPAD_UP]
			for code in alternatives:
				var binding = {"type": "key" if device == "keyboard" else "button", "code": code}
				if not occupied.has(binding):
					candidate.active_item = binding
					break
		var valid = true
		for action in candidate:
			var value = incoming.get(action, candidate[action])
			if not valid_binding(device, value) or used.has(value):
				valid = false
				break
			var normalized = normalize_binding(value)
			if used.has(normalized):
				valid = false
				break
			candidate[action] = normalized
			used.append(normalized)
		if valid: bindings[device] = candidate

static func valid_binding(device: String, value) -> bool:
	if not value is Dictionary or not value.get("code") is float and not value.get("code") is int: return false
	var code = int(value.code)
	match value.get("type", ""):
		"key": return device == "keyboard" and code > 0
		"mouse": return device == "keyboard" and code in [1, 2, 3, 8, 9]
		"button": return device == "controller" and code >= 0 and code < JOY_BUTTON_MAX
		"axis": return device == "controller" and code >= 0 and code < JOY_AXIS_MAX and int(value.get("sign", 0)) in [-1, 1]
	return false

static func normalize_binding(value: Dictionary) -> Dictionary:
	var result = {"type": str(value.type), "code": int(value.code)}
	if value.type == "axis": result.sign = int(value.sign)
	return result

func assign(device: String, action: String, binding: Dictionary) -> bool:
	if not bindings.has(device) or not bindings[device].has(action) or not valid_binding(device, binding): return false
	binding = normalize_binding(binding)
	var old = bindings[device][action].duplicate()
	for other in bindings[device]:
		if other != action and bindings[device][other] == binding: bindings[device][other] = old
	bindings[device][action] = binding.duplicate()
	return true

func reset_device(device: String) -> void:
	if bindings.has(device): bindings[device] = pristine[device].duplicate(true)

static func from_event(event_value: InputEvent, device: String) -> Dictionary:
	if (event_value is InputEventMouseButton or event_value is InputEventMouseMotion) and event_value.device == InputEvent.DEVICE_ID_EMULATION: return {}
	if device == "keyboard":
		if event_value is InputEventKey and event_value.pressed and not event_value.echo:
			return {"type": "key", "code": event_value.physical_keycode}
		if event_value is InputEventMouseButton and event_value.pressed:
			return {"type": "mouse", "code": event_value.button_index}
	else:
		if event_value is InputEventJoypadButton and event_value.pressed:
			return {"type": "button", "code": event_value.button_index}
		if event_value is InputEventJoypadMotion and absf(event_value.axis_value) >= .65:
			return {"type": "axis", "code": event_value.axis, "sign": -1 if event_value.axis_value < 0 else 1}
	return {}

func default_binding(device: String, action: String) -> bool:
	return bindings[device][action] == pristine[device].get(action, {})

func alternate_key(action: String) -> int:
	if not default_binding("keyboard", action): return 0
	var code = int(ALTERNATES.get(action, 0))
	for other in bindings.keyboard:
		var binding = bindings.keyboard[other]
		if other != action and binding.type == "key" and int(binding.code) == code: return 0
	return code

func event_matches(action: String, event_value: InputEvent) -> bool:
	var device = "controller" if event_value is InputEventJoypadButton or event_value is InputEventJoypadMotion else "keyboard"
	if not bindings[device].has(action): return false
	var binding = from_event(event_value, device)
	if binding == bindings[device][action]: return true
	return device == "keyboard" and event_value is InputEventKey and event_value.pressed and not event_value.echo and alternate_key(action) > 0 and event_value.physical_keycode == alternate_key(action)

func strength(device: String, action: String, pad: int = 0) -> float:
	var binding = bindings[device].get(action, {})
	if binding.is_empty(): return 0
	match binding.type:
		"key": return float(Input.is_physical_key_pressed(int(binding.code)) or (alternate_key(action) > 0 and Input.is_physical_key_pressed(alternate_key(action))))
		"mouse": return float(Input.is_mouse_button_pressed(int(binding.code)) or (alternate_key(action) > 0 and Input.is_physical_key_pressed(alternate_key(action))))
		"button": return float(Input.is_joy_button_pressed(pad, int(binding.code)))
		"axis": return maxf(0, Input.get_joy_axis(pad, int(binding.code)) * int(binding.sign))
	return 0

func hint(action: String, device: String = "keyboard") -> String:
	var binding = bindings[device].get(action, {})
	if binding.is_empty(): return "—"
	if binding.type == "key": return OS.get_keycode_string(int(binding.code))
	if binding.type == "mouse":
		var text = {1: "左键", 2: "右键", 3: "中键", 4: "滚轮上", 5: "滚轮下", 8: "侧键1", 9: "侧键2"}.get(int(binding.code), "鼠标%d" % int(binding.code))
		return text + (" / Q" if action == "skill" and alternate_key(action) > 0 else "")
	if binding.type == "button": return {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3", 9: "LB", 10: "RB", 11: "十字上", 12: "十字下", 13: "十字左", 14: "十字右"}.get(int(binding.code), "按键%d" % int(binding.code))
	var axis = {0: "左杆横", 1: "左杆纵", 2: "右杆横", 3: "右杆纵", 4: "LT", 5: "RT"}.get(int(binding.code), "轴%d" % int(binding.code))
	return axis + ("−" if int(binding.sign) < 0 else "+")
