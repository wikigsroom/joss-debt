extends ScrollContainer
## Wrapped body copy retains the approved body font and never pushes actions offscreen.

func populate(lines: Array, body_font: Font, point_size: int, color: Color) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_ALL
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", roundi(point_size * .8))
	add_child(list)
	for text in lines:
		var paragraph = Label.new()
		paragraph.text = str(text)
		paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		paragraph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		paragraph.add_theme_font_override("font", body_font)
		paragraph.add_theme_font_size_override("font_size", point_size)
		paragraph.add_theme_color_override("font_color", color)
		paragraph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(paragraph)

func _gui_input(event: InputEvent) -> void:
	var shift = 0
	if event.is_action_pressed("ui_down"): shift = 64
	elif event.is_action_pressed("ui_up"): shift = -64
	elif event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_PAGEDOWN: shift = roundi(size.y * .85)
		elif event.physical_keycode == KEY_PAGEUP: shift = -roundi(size.y * .85)
	if shift != 0:
		scroll_vertical += shift
		accept_event()
