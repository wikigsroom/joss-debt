extends RefCounted
## Shared "ink and cinnabar talisman" skin. Gameplay keeps a dark ink base;
## menus layer warm xuan-paper surfaces and brush-like selection states on top.
const BACKGROUND = Color("181513")
const SURFACE = Color("2c2723")
const INSET = Color("211d1a")
const LIFTED = Color("40342d")
const EDGE = Color("806b57")
const CANVAS = Color("eadcc2")
const CANVAS_DARK = Color("d6c2a0")
const TEXT = Color("f4e6ca")
const MUTED = Color("c2ab8b")
const PAPER_MUTED = Color("765b43")
const ACCENT = Color("b74432")
const JADE = Color("a5c7ae")
const GOLD = Color("ddb574")
const SEAL = Color("8d3028")
const RADIUS = 20
const ICON_SIZE = 24
const PickupArt = preload("res://scripts/ui/pickup_art.gd")
static var font_cache: Dictionary = {}
static var icon_cache: Dictionary = {}
const INK_ICON_REGIONS = {
	"play": Rect2i(0, 0, 313, 313), "restart": Rect2i(313, 0, 314, 313),
	"combat": Rect2i(627, 0, 313, 313), "shuffle": Rect2i(940, 0, 314, 313),
	"scroll": Rect2i(0, 313, 313, 314), "house": Rect2i(313, 313, 314, 314),
	"settings": Rect2i(627, 313, 313, 314), "exit": Rect2i(940, 313, 314, 314),
	"back": Rect2i(0, 627, 313, 313), "close": Rect2i(313, 627, 314, 313),
	"pause": Rect2i(627, 627, 313, 313), "crown": Rect2i(940, 627, 314, 313),
	"sparkle": Rect2i(0, 940, 313, 314), "sun": Rect2i(313, 940, 314, 314),
	"leaf": Rect2i(627, 940, 313, 314), "shield": Rect2i(940, 940, 314, 314)
}

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
	if key.begins_with("ink:"): return ink_icon(key.trim_prefix("ink:"))
	if key in PickupArt.UI_KEYS: return PickupArt.icon(key)
	if not icon_cache.has(key):
		var path = "res://assets/ui/icons/" + key + ".svg"
		if ResourceLoader.exists(path): icon_cache[key] = load(path)
	return icon_cache.get(key)

static func ink_icon(key: String) -> Texture2D:
	var cache_key = "ink-icon:" + key
	if icon_cache.has(cache_key): return icon_cache[cache_key]
	if not INK_ICON_REGIONS.has(key): return null
	var atlas = texture("icons-01")
	if atlas == null: return null
	var region = AtlasTexture.new()
	region.atlas = atlas
	region.region = INK_ICON_REGIONS[key]
	icon_cache[cache_key] = region
	return region

static func texture(key: String) -> Texture2D:
	var cache_key = "ink:" + key
	if not icon_cache.has(cache_key):
		var path = "res://assets/ui/ink/" + key + ".png"
		if ResourceLoader.exists(path): icon_cache[cache_key] = load(path)
	return icon_cache.get(cache_key)

static func icon_tint(key: String, color: Color) -> Color:
	# Resource art has painted material colours; monochrome navigation glyphs keep their tint.
	return Color(1, 1, 1, color.a) if key in PickupArt.UI_KEYS else color

static func surface(color: Color) -> Color:
	var key = color.to_html(false)
	var mapped = {"242725": SURFACE, "30372f": SURFACE, "34352c": SURFACE, "2d3029": SURFACE,
		"252d26": SURFACE, "20281f": INSET, "423127": SURFACE, "454437": LIFTED, "4f5145": EDGE,
		"e1d1ad": CANVAS, "e7d8b6": CANVAS_DARK, "eadcc2": CANVAS}
	var result: Color = mapped.get(key, color)
	result.a = color.a
	return result

static func style(background: Color = SURFACE, border: Color = Color.TRANSPARENT, radius: int = RADIUS, border_width: int = 1) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = surface(background)
	result.border_color = border
	result.set_border_width_all(border_width if border.a > 0 else 0)
	result.set_corner_radius_all(radius)
	result.corner_detail = 8
	result.shadow_color = Color("120e0c", .34)
	result.shadow_size = 9
	result.shadow_offset = Vector2(0, 4)
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result

static func brush_style(asset: String, modulate: Color = Color.WHITE, radius: int = RADIUS, draw_center: bool = true) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = draw_center
	# The generated kit is a horizontal brush strip. Preserve its painted ends
	# while allowing the blank center to stretch to any translated button label.
	# The source brush is 724x170.  Preserve its painted ends and top/bottom
	# pigment with a nine-slice; scaling the whole bitmap made long mobile bars
	# look like rubber bands and visibly bent the brush grain.
	result.texture_margin_left = 126
	result.texture_margin_right = 126
	result.texture_margin_top = 34
	result.texture_margin_bottom = 34
	result.content_margin_left = 30
	result.content_margin_right = 30
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	return result

static func card_style(asset: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = true
	# Keep the generated corners and brush splatter intact while stretching the
	# quiet center to the card's live art/text area.
	result.texture_margin_left = 58
	result.texture_margin_right = 58
	result.texture_margin_top = 58
	result.texture_margin_bottom = 58
	result.content_margin_left = 24
	result.content_margin_right = 24
	result.content_margin_top = 20
	result.content_margin_bottom = 20
	return result

static func compact_card_style(asset: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = true
	# Compact cards use their own generated horizontal tile kit. Reusing the
	# portrait sheet here compresses the tall brush border and makes character
	# tabs look like a different visual system.
	result.texture_margin_left = 66
	result.texture_margin_right = 66
	result.texture_margin_top = 40
	result.texture_margin_bottom = 40
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 14
	result.content_margin_bottom = 14
	return result

static func modal_tile_style(asset: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = true
	# Medium settings/navigation tiles use their own generated landscape plaque;
	# this keeps the cloud corners and avoids squeezing the portrait card sheet.
	result.texture_margin_left = 58
	result.texture_margin_right = 58
	result.texture_margin_top = 42
	result.texture_margin_bottom = 42
	result.content_margin_left = 16
	result.content_margin_right = 16
	result.content_margin_top = 14
	result.content_margin_bottom = 14
	return result

static func detail_brush_style(asset: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = true
	# The generated detail buttons reserve a real ink medallion at the left;
	# nine-slice the quiet center so labels never stretch the medallion.
	result.texture_margin_left = 122
	result.texture_margin_right = 22
	result.texture_margin_top = 28
	result.texture_margin_bottom = 28
	result.content_margin_left = 26
	result.content_margin_right = 26
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result

static func disk_style(asset: String, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = texture(asset)
	result.modulate_color = modulate
	result.draw_center = true
	result.texture_margin_left = 72
	result.texture_margin_right = 72
	result.texture_margin_top = 66
	result.texture_margin_bottom = 66
	result.content_margin_left = 8
	result.content_margin_right = 8
	result.content_margin_top = 8
	result.content_margin_bottom = 8
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

static func button_styles(button: Button, primary: bool = false, radius: int = RADIUS, iconful: bool = false) -> void:
	button.add_theme_font_override("font", body_font(true))
	button.add_theme_font_size_override("font_size", 20)
	# Both brush states use warm paper lettering. The reference board reserves
	# dark ink for the stroke itself; black text on cinnabar was a major drift.
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("748681"))
	button.add_theme_color_override("icon_normal_color", TEXT)
	button.add_theme_color_override("icon_hover_color", TEXT)
	button.add_theme_color_override("icon_pressed_color", TEXT)
	button.add_theme_color_override("icon_focus_color", TEXT)
	button.add_theme_color_override("icon_disabled_color", Color("71807c"))
	button.add_theme_color_override("font_outline_color", Color(BACKGROUND, .68))
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_constant_override("icon_max_width", ICON_SIZE)
	button.add_theme_constant_override("h_separation", 10)
	var long_brush = button.size.x >= button.size.y * 2.35 and button.size.y >= 44
	var ink_card = button.size.x >= 180 and button.size.y >= 120 and button.size.y >= button.size.x * .55
	var compact_card = button.size.x >= 180 and button.size.y >= 120 and button.size.y < button.size.x * .8
	var modal_tile = button.size.x >= 180 and button.size.x <= 280 and button.size.y >= 90 and button.size.y < 120
	button.set_meta("ink_brush_button", long_brush)
	button.set_meta("ink_card_button", ink_card)
	button.set_meta("ink_compact_card", compact_card)
	button.set_meta("ink_modal_tile", modal_tile)
	button.set_meta("ink_icon_button", iconful)
	var icon_only = iconful and button.size.x < button.size.y * 1.65
	button.set_meta("ink_icon_only", icon_only)
	if icon_only and texture("icon-disk-secondary") != null:
		# Icon disks are complete painted sprites, not nine-sliced strips. A
		# nine-slice on a 56px control repeats the rough edge and creates detached
		# brush fragments around the glyph.
		button.add_theme_stylebox_override("normal", style(Color(0, 0, 0, 0), Color.TRANSPARENT, radius, 0))
		button.add_theme_stylebox_override("hover", style(Color(0, 0, 0, 0), Color("e6c7a0", .36), radius, 1))
		button.add_theme_stylebox_override("pressed", style(Color(0, 0, 0, 0), Color("b74432", .64), radius, 1))
		button.add_theme_stylebox_override("disabled", style(Color(0, 0, 0, 0), Color.TRANSPARENT, radius, 0))
	elif modal_tile and texture("modal-tile-normal") != null:
		button.add_theme_stylebox_override("normal", modal_tile_style("modal-tile-normal"))
		button.add_theme_stylebox_override("hover", modal_tile_style("modal-tile-selected", Color(1.04, 1.02, .98, 1.0)))
		button.add_theme_stylebox_override("pressed", modal_tile_style("modal-tile-selected", Color(.76, .75, .72, 1.0)))
		button.add_theme_stylebox_override("disabled", modal_tile_style("modal-tile-disabled", Color(.82, .80, .76, .74)))
	elif compact_card and texture("tile-ink") != null:
		button.add_theme_stylebox_override("normal", compact_card_style("tile-ink"))
		button.add_theme_stylebox_override("hover", compact_card_style("tile-selected-cinnabar", Color(1.04, 1.02, .98, 1.0)))
		button.add_theme_stylebox_override("pressed", compact_card_style("tile-selected-cinnabar", Color(.76, .75, .72, 1.0)))
		button.add_theme_stylebox_override("disabled", compact_card_style("tile-disabled-ink", Color(.82, .80, .76, .74)))
	elif ink_card and texture("card-ink") != null:
		button.add_theme_stylebox_override("normal", card_style("card-ink"))
		button.add_theme_stylebox_override("hover", card_style("card-selected-cinnabar", Color(1.04, 1.02, .98, 1.0)))
		button.add_theme_stylebox_override("pressed", card_style("card-selected-cinnabar", Color(.76, .75, .72, 1.0)))
		button.add_theme_stylebox_override("disabled", card_style("card-disabled-ink", Color(.82, .80, .76, .74)))
	elif long_brush and texture("button-primary-brush") != null:
		var normal_asset = "button-detail-primary" if iconful and primary and texture("button-detail-primary") != null else "button-detail-secondary" if iconful and not primary and texture("button-detail-secondary") != null else "button-primary-brush" if primary else "button-secondary-brush"
		var hover_asset = "button-detail-hover" if iconful and texture("button-detail-hover") != null else "button-primary-brush" if primary else "button-hover-brush"
		var pressed_asset = "button-detail-pressed" if iconful and texture("button-detail-pressed") != null else "button-primary-brush" if primary else "button-pressed-brush"
		var disabled_asset = "button-detail-disabled" if iconful and texture("button-detail-disabled") != null else "button-secondary-brush"
		var style_factory = detail_brush_style if iconful and texture("button-detail-primary") != null else brush_style
		button.add_theme_stylebox_override("normal", style_factory.call(normal_asset))
		button.add_theme_stylebox_override("hover", style_factory.call(hover_asset, Color(1.08, 1.04, .98, 1.0)))
		button.add_theme_stylebox_override("pressed", style_factory.call(pressed_asset, Color(.78, .78, .76, 1.0)))
		# A disabled action keeps its painted silhouette so the menu rhythm does
		# not collapse into a thin line; only pigment and lettering desaturate.
		button.add_theme_stylebox_override("disabled", style_factory.call(disabled_asset, Color(.70, .68, .64, .72)))
	else:
		button.add_theme_stylebox_override("normal", style(ACCENT if primary else SURFACE, Color.TRANSPARENT, radius))
		button.add_theme_stylebox_override("hover", style(Color("cf5b46") if primary else LIFTED.lightened(.08), Color("e6c7a0", .82), radius, 1))
		button.add_theme_stylebox_override("pressed", style(Color("8f3028") if primary else Color("322a25"), Color.TRANSPARENT, radius))
		button.add_theme_stylebox_override("disabled", style(INSET, Color.TRANSPARENT, radius))
	var focus_style = style(Color(0, 0, 0, 0), ACCENT, radius, 2) if icon_only else (detail_brush_style("button-detail-focus", Color(1, 1, 1, .96)) if long_brush and iconful and texture("button-detail-focus") != null else (brush_style("button-focus-frame", Color(1, 1, 1, .96), radius, false) if long_brush and texture("button-focus-frame") != null else (modal_tile_style("modal-tile-selected", Color(1, 1, 1, .92)) if modal_tile and texture("modal-tile-selected") != null else (compact_card_style("tile-selected-cinnabar", Color(1, 1, 1, .92)) if compact_card and texture("tile-selected-cinnabar") != null else (card_style("card-selected-cinnabar", Color(1, 1, 1, .92)) if ink_card and texture("card-selected-cinnabar") != null else style(Color("6a2a23", .34) if primary else Color("554137", .64), CANVAS if primary else ACCENT, radius, 2))))))
	if focus_style is StyleBoxFlat: focus_style.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus_style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func apply_brush_material(button: Button, primary: bool) -> void:
	if not bool(button.get_meta("ink_brush_button", false)): return
	var layer = TextureRect.new()
	layer.name = "GeneratedBrushSurface"
	layer.texture = texture("button-primary-brush" if primary else "button-secondary-brush")
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.position = Vector2.ZERO
	layer.size = button.size
	layer.modulate = Color(1, 1, 1, .98)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	layer.z_index = -1
	button.add_child(layer)
	var focus = TextureRect.new()
	focus.name = "GeneratedBrushFocus"
	focus.texture = texture("button-focus-frame")
	focus.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	focus.stretch_mode = TextureRect.STRETCH_SCALE
	focus.position = Vector2(-5, -3)
	focus.size = button.size + Vector2(10, 6)
	focus.modulate = Color(1, 1, 1, .95)
	focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus.visible = false
	focus.z_index = 1
	button.add_child(focus)
	button.focus_entered.connect(func(): focus.visible = true)
	button.focus_exited.connect(func(): focus.visible = false)

static func select(button: Button) -> void:
	if bool(button.get_meta("ink_modal_tile", false)) and texture("modal-tile-selected") != null:
		button.add_theme_stylebox_override("normal", modal_tile_style("modal-tile-selected"))
		button.add_theme_stylebox_override("hover", modal_tile_style("modal-tile-selected", Color(1.06, 1.03, .98, 1.0)))
		return
	if bool(button.get_meta("ink_compact_card", false)) and texture("tile-selected-cinnabar") != null:
		button.add_theme_stylebox_override("normal", compact_card_style("tile-selected-cinnabar"))
		button.add_theme_stylebox_override("hover", compact_card_style("tile-selected-cinnabar", Color(1.06, 1.03, .98, 1.0)))
		return
	if bool(button.get_meta("ink_card_button", false)) and texture("card-selected-cinnabar") != null:
		button.add_theme_stylebox_override("normal", card_style("card-selected-cinnabar"))
		button.add_theme_stylebox_override("hover", card_style("card-selected-cinnabar", Color(1.06, 1.03, .98, 1.0)))
		return
	button.add_theme_stylebox_override("normal", style(Color("4a382f"), ACCENT, 18, 2))
	button.add_theme_stylebox_override("hover", style(Color("574137"), Color("d56b54"), 18, 2))

static func round_texture(texture: TextureRect, radius: float = 24.0) -> void:
	var shader = load("res://scripts/ui/rounded_texture.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("extent", texture.size)
	material.set_shader_parameter("radius", radius)
	texture.material = material
