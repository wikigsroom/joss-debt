extends RefCounted
## One rounded, icon-led native skin. Game art remains in its own reference palette.
const BACKGROUND = Color("171e20")
const SURFACE = Color("242f32")
const INSET = Color("1b2528")
const LIFTED = Color("344341")
const EDGE = Color("43534f")
const TEXT = Color("edf2e7")
const MUTED = Color("a7b5af")
const ACCENT = Color("ee956f")
const JADE = Color("9dd6bf")
const GOLD = Color("ebc386")
const RADIUS = 24
const ICON_SIZE = 24
static var font_cache: Dictionary = {}
static var icon_cache: Dictionary = {}

static func body_font(bold: bool = false) -> Font:
	var key = "bold" if bold else "body"
	if not font_cache.has(key):
		var file: FontFile = load("res://assets/fonts/IncenseRounded-%s.ttf" % ("Bold" if bold else "Medium"))
		file.fallbacks = [load("res://assets/fonts/NotoSansSC.ttf")]
		font_cache[key] = file
	return font_cache[key]

static func display_font() -> Font:
	if not font_cache.has("display"):
		var file: FontFile = load("res://assets/fonts/SmileySans-Oblique.ttf")
		file.fallbacks = [body_font(true)]
		font_cache.display = file
	return font_cache.display

static func icon(key: String) -> Texture2D:
	if not icon_cache.has(key):
		var path = "res://assets/ui/icons/" + key + ".svg"
		if ResourceLoader.exists(path): icon_cache[key] = load(path)
	return icon_cache.get(key)

static func surface(color: Color) -> Color:
	var key = color.to_html(false)
	var mapped = {"242725": BACKGROUND, "30372f": SURFACE, "34352c": SURFACE, "2d3029": SURFACE,
		"252d26": SURFACE, "20281f": INSET, "423127": SURFACE, "454437": LIFTED, "4f5145": EDGE}
	var result: Color = mapped.get(key, color)
	result.a = color.a
	return result

static func style(background: Color = SURFACE, border: Color = Color.TRANSPARENT, radius: int = RADIUS, border_width: int = 1) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = surface(background)
	result.border_color = border
	result.set_border_width_all(border_width if border.a > 0 else 0)
	result.set_corner_radius_all(radius)
	result.shadow_color = Color(0, 0, 0, .16)
	result.shadow_size = 8
	result.shadow_offset = Vector2(0, 4)
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result

static func install(theme: Theme) -> void:
	theme.default_font = body_font()
	theme.default_font_size = 20
	theme.set_stylebox("panel", "TooltipPanel", style(INSET, EDGE, 16))
	theme.set_font("font", "TooltipLabel", body_font())
	theme.set_font_size("font_size", "TooltipLabel", 18)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	for type in ["LineEdit", "TextEdit", "OptionButton"]:
		theme.set_stylebox("normal", type, style(INSET, EDGE, 16))
		theme.set_stylebox("focus", type, style(Color.TRANSPARENT, ACCENT, 16, 2))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("caret_color", type, ACCENT)
		theme.set_color("selection_color", type, Color("675046"))
	var knob_image = icon("circle-dot").get_image()
	knob_image.resize(24, 24, Image.INTERPOLATE_LANCZOS)
	var knob_texture = ImageTexture.create_from_image(knob_image)
	for type in ["HSlider", "VSlider"]:
		for key in ["slider", "grabber_area", "grabber_area_highlight"]:
			var track = style(EDGE if key == "slider" else JADE, Color.TRANSPARENT, 3)
			track.shadow_size = 0
			track.content_margin_left = 0
			track.content_margin_right = 0
			track.content_margin_top = 3
			track.content_margin_bottom = 3
			theme.set_stylebox(key, type, track)
		theme.set_icon("grabber", type, knob_texture)
		theme.set_icon("grabber_highlight", type, knob_texture)
	var clear_icon = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for key in ["increment", "decrement", "increment_pressed", "increment_highlight", "decrement_pressed", "decrement_highlight"]:
		theme.set_icon(key, "VScrollBar", clear_icon)
	for key in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var track = style(INSET if key == "scroll" else EDGE, Color.TRANSPARENT, 3)
		track.shadow_size = 0
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 0
		track.content_margin_bottom = 0
		theme.set_stylebox(key, "VScrollBar", track)

static func button_styles(button: Button, primary: bool = false, radius: int = RADIUS) -> void:
	button.add_theme_font_override("font", body_font(true))
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("font_hover_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("font_pressed_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("font_focus_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("font_disabled_color", Color("748681"))
	button.add_theme_color_override("icon_normal_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("icon_hover_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("icon_pressed_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("icon_focus_color", BACKGROUND if primary else TEXT)
	button.add_theme_color_override("icon_disabled_color", Color("71807c"))
	button.add_theme_constant_override("icon_max_width", ICON_SIZE)
	button.add_theme_constant_override("h_separation", 10)
	button.add_theme_stylebox_override("normal", style(ACCENT if primary else SURFACE, Color.TRANSPARENT, radius))
	button.add_theme_stylebox_override("hover", style(Color("ffaf87") if primary else LIFTED, Color.TRANSPARENT, radius))
	button.add_theme_stylebox_override("pressed", style(Color("dc815d") if primary else Color("40524c"), Color.TRANSPARENT, radius))
	var focus_style = style(Color.TRANSPARENT, TEXT if primary else ACCENT, radius, 2)
	focus_style.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("disabled", style(INSET, Color.TRANSPARENT, radius))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func select(button: Button) -> void:
	button.add_theme_stylebox_override("normal", style(LIFTED, ACCENT, 22, 2))
	button.add_theme_stylebox_override("hover", style(LIFTED.lightened(.05), ACCENT, 22, 2))

static func round_texture(texture: TextureRect, radius: float = 24.0) -> void:
	var shader = load("res://scripts/ui/rounded_texture.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("extent", texture.size)
	material.set_shader_parameter("radius", radius)
	texture.material = material
