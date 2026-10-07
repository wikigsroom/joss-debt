extends Button
const UI = preload("res://scripts/ui/game_theme.gd")

func _make_custom_tooltip(for_text: String) -> Object:
	var panel = PanelContainer.new()
	var width = clampf(UI.body_font().get_string_size(for_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 72, 430)
	panel.custom_minimum_size = Vector2(width + 36, 44)
	panel.add_theme_stylebox_override("panel", UI.style(UI.INSET, UI.EDGE, 16))
	var text = Label.new()
	text.text = for_text
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_override("font", UI.body_font())
	text.add_theme_font_size_override("font_size", 18)
	text.add_theme_color_override("font_color", UI.TEXT)
	panel.add_child(text)
	return panel
