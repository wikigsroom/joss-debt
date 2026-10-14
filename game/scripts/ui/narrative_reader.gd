extends "res://scripts/ui/touch_scroll_container.gd"
## Wrapped body copy retains the approved body font and never pushes actions offscreen.

func populate(lines: Array, body_font: Font, point_size: int, color: Color) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_ALL
	var list = VBoxContainer.new()
	# Give wrapped paragraphs the reader width up front. Without a concrete
	# width Godot can calculate a zero-height minimum for a Label inside a
	# VBoxContainer, which makes the body appear blank and leaves no scroll
	# range on the enlarged story page.
	list.custom_minimum_size.x = size.x
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	list.add_theme_constant_override("separation", roundi(point_size * .8))
	add_child(list)
	for text in lines:
		var paragraph = Label.new()
		paragraph.text = str(text)
		# Chinese prose has no whitespace boundary; arbitrary wrapping keeps each
		# paragraph complete instead of trimming it as a one-line caption.
		paragraph.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		var paragraph_height = body_font.get_multiline_string_size(paragraph.text, HORIZONTAL_ALIGNMENT_LEFT, size.x, point_size).y
		paragraph.custom_minimum_size = Vector2(size.x, maxf(body_font.get_height(point_size), paragraph_height))
		paragraph.size_flags_horizontal = Control.SIZE_FILL
		paragraph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		paragraph.add_theme_font_override("font", body_font)
		paragraph.add_theme_font_size_override("font_size", point_size)
		paragraph.add_theme_color_override("font_color", color)
		paragraph.clip_text = false
		paragraph.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
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
