extends RefCounted
## Shared PC shortcut mapping for reward and skill choice sheets.

static func index_for(event_value: InputEvent) -> int:
	if not event_value is InputEventKey or not event_value.pressed or event_value.echo:
		return -1
	var physical = event_value.physical_keycode
	var logical = event_value.keycode
	var keys = [
		[KEY_1, KEY_KP_1],
		[KEY_2, KEY_KP_2],
		[KEY_3, KEY_KP_3],
		[KEY_4, KEY_KP_4],
	]
	for i in keys.size():
		# Physical code is preferred for layout-independent top-row input; the
		# logical fallback keeps remapped layouts and keypad events usable.
		if physical == keys[i][0] or physical == keys[i][1] or logical == keys[i][0] or logical == keys[i][1]:
			return i
	return -1
