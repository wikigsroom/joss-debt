extends Control
## Small icon trays leave the middle of the arena open. Values come from the live world.
const UI = preload("res://scripts/ui/game_theme.gd")
var world
var adapter
var app
var icons: Dictionary = {}
var body: Font
var strong: Font
var hint_areas: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body = UI.body_font()
	strong = UI.body_font(true)
	for kind in ["relics", "weapons", "skills", "characters", "active_items", "trinkets"]:
		for row in world.db.rows(kind):
			var path = "res://assets/heroes/" + row.id + "_down.png" if kind == "characters" else "res://assets/" + kind + "/" + row.id + ".png"
			if ResourceLoader.exists(path): icons[row.id] = load(path)
	for key in ["health", "region", "weapon", "skill", "dash", "active_item", "trinket"]:
		var area = Control.new()
		area.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(area)
		hint_areas[key] = area
	for i in 12:
		var area = Control.new()
		area.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(area)
		hint_areas["relic%d" % i] = area

func _process(_delta: float) -> void:
	if world == null or world.run.is_empty(): return
	var player = world.player
	if app != null and app.mobile_ui:
		for key in hint_areas: hint_areas[key].visible = false
		queue_redraw()
		return
	set_hint("health", Rect2(24, 20, 84 + int(player.max_hp) * 20, 64), "%s · 心火 %d / %d\n香火 %d / 100 · 护甲 %d" % [world.db.name_of("characters", world.run.character), player.hp, player.max_hp, player.energy, player.armor])
	var navigation_hint = "走到亮起的门口" if world.mode == "clear" and not world.room_doors().is_empty() else "清房后，门口会亮起"
	set_hint("region", Rect2(540, 24, 200, 44), "%s · 第%d重\n%s" % [world.region_spec().name, world.run.floor, navigation_hint])
	set_hint("weapon", Rect2(24, 638, 56, 56), world.db.name_of("weapons", player.weapon) + "\n" + world.db.row("weapons", player.weapon).behavior)
	set_hint("skill", Rect2(1172, 623, 76, 76), world.db.name_of("skills", player.skill) + "\n香火 %d · %s" % [world.skill_cost(), adapter.profile.hint("skill", "controller" if adapter.last_device == "controller" else "keyboard")], not adapter.touch_mode)
	set_hint("dash", Rect2(1094, 637, 58, 58), "身法 · " + adapter.profile.hint("dash", "controller" if adapter.last_device == "controller" else "keyboard"), not adapter.touch_mode)
	var active = world.Equipment.active_row(world)
	set_hint("active_item", Rect2(928, 637, 64, 60), str(active.get("name", "主动道具")) + "\n" + str(active.get("behavior", "")) + "\n" + adapter.profile.hint("active_item", "controller" if adapter.last_device == "controller" else "keyboard"), not adapter.touch_mode)
	var trinket = world.db.row("trinkets", str(world.run.get("trinket", "")))
	set_hint("trinket", Rect2(672 if adapter.touch_mode else 1010, 646, 44, 44), str(trinket.get("name", "饰品空槽")) + "\n" + str(trinket.get("behavior", "靠近饰品按 E 换装")))
	var ids = world.run.relics.keys()
	for i in 12:
		var valid = i < ids.size()
		set_hint("relic%d" % i, Rect2(96 + i * 45, 647, 40, 40), world.db.name_of("relics", ids[i]) + "\n" + world.db.row("relics", ids[i]).behavior if valid else "", valid)
	queue_redraw()

func set_hint(key: String, rect: Rect2, value: String, shown: bool = true) -> void:
	var area: Control = hint_areas[key]
	area.position = rect.position
	area.size = rect.size
	area.tooltip_text = value
	area.accessibility_name = value
	area.visible = shown

func plate(rect: Rect2, background: Color = UI.SURFACE, radius: int = 24) -> void:
	draw_style_box(UI.style(Color(background, .94), Color.TRANSPARENT, radius), rect)

func text(value: String, point: Vector2, size: int = 18, color: Color = UI.TEXT, bold: bool = false) -> void:
	draw_string(strong if bold else body, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func glyph(key: String, rect: Rect2, color: Color = UI.TEXT) -> void:
	var texture = UI.icon(key)
	if texture != null: draw_texture_rect(texture, rect, false, color)

func image(id: String, rect: Rect2, color: Color = Color.WHITE) -> void:
	if icons.has(id): draw_texture_rect(icons[id], rect, false, color)

func _draw() -> void:
	if world == null or world.run.is_empty(): return
	if app != null and app.mobile_ui:
		draw_mobile()
		return
	var player = world.player
	var health_width = 84 + int(player.max_hp) * 20
	plate(Rect2(24, 20, health_width, 64), UI.INSET)
	draw_circle(Vector2(57, 52), 25, UI.SURFACE)
	draw_arc(Vector2(57, 52), 25, -PI * .5, -PI * .5 + TAU * clampf(player.energy / 100.0, 0, 1), 40, UI.JADE, 3, true)
	image(world.run.character, Rect2(34, 27, 46, 48))
	for i in int(player.max_hp):
		glyph("heart-solid" if i < int(player.hp) else "heart", Rect2(91 + i * 20, 31, 17, 17), UI.ACCENT if i < int(player.hp) else Color("80928b"))
	plate(Rect2(92, 61, int(player.max_hp) * 20 - 10, 4), UI.EDGE, 2)
	if player.energy > 0:
		plate(Rect2(92, 61, (int(player.max_hp) * 20 - 10) * player.energy / 100.0, 4), UI.JADE, 2)
	if player.armor > 0:
		glyph("shield", Rect2(health_width + 34, 34, 22, 22), UI.JADE)
		text(str(player.armor), Vector2(health_width + 63, 53), 18, UI.TEXT, true)
	plate(Rect2(540, 24, 200, 44), UI.INSET, 22)
	glyph("map", Rect2(557, 34, 22, 22), UI.JADE)
	text(world.region_spec().name, Vector2(591, 52), 20, UI.TEXT, true)
	if world.run.get("daily", false):
		plate(Rect2(748, 24, 82, 44), UI.INSET, 22)
		glyph("crown", Rect2(761, 34, 22, 22), UI.GOLD)
		text("每日", Vector2(790, 52), 16, UI.GOLD, true)
	for i in int(world.run.floor_limit):
		draw_circle(Vector2(640 - (int(world.run.floor_limit) - 1) * 6 + i * 12, 78), 3, UI.ACCENT if i == int(world.run.floor) - 1 else UI.EDGE)
	if world.mode == "combat" and int(world.room_flags.get("wave_count", 1)) > 1:
		plate(Rect2(592, 93, 96, 32), UI.INSET, 16)
		glyph("sword", Rect2(605, 100, 18, 18), UI.MUTED)
		text("%d / %d" % [world.room_flags.wave_index, world.room_flags.wave_count], Vector2(637, 116), 16, UI.TEXT, true)
	var nav_size = maxf(64, app.mobile_button_height) if app != null and app.mobile_ui else 56.0
	var wallet_x = 1280 - 24 - nav_size * 2 - 12 - 124
	plate(Rect2(wallet_x, 20, 112, 52), UI.INSET, 26)
	glyph("coins", Rect2(wallet_x + 18, 34, 24, 24), UI.GOLD)
	text(str(int(world.run.coins)), Vector2(wallet_x + 54, 56), 22, UI.TEXT, true)
	plate(Rect2(24, 638, 56, 56), UI.INSET, 20)
	image(player.weapon, Rect2(29, 643, 46, 46))
	var ids = world.run.relics.keys()
	for i in mini(12, ids.size()):
		plate(Rect2(96 + i * 45, 647, 40, 40), UI.INSET, 14)
		image(ids[i], Rect2(97 + i * 45, 648, 38, 38))
		if world.stack(ids[i]) > 1:
			text(str(world.stack(ids[i])), Vector2(124 + i * 45, 683), 13, UI.TEXT, true)
	var trinket_id = str(world.run.get("trinket", ""))
	var trinket_x = 672 if adapter.touch_mode else 1010
	plate(Rect2(trinket_x, 646, 44, 44), UI.INSET, 17)
	if trinket_id.is_empty(): glyph("circle-dot", Rect2(trinket_x + 11, 657, 22, 22), UI.EDGE)
	else: image(trinket_id, Rect2(trinket_x + 1, 647, 42, 42))
	if adapter.touch_mode: return
	var active = world.Equipment.active_row(world)
	if not active.is_empty():
		var amount = float(world.run.active_item.charge)
		var maximum = float(active.charge_rooms)
		var item_ready = amount >= maximum and player.item_cd <= 0
		plate(Rect2(928, 637, 64, 60), UI.INSET, 23)
		draw_arc(Vector2(960, 662), 25, -PI * .5, -PI * .5 + TAU * clampf(amount / maximum, 0, 1), 40, UI.JADE if item_ready else UI.GOLD, 2.5, true)
		image(active.id, Rect2(940, 642, 40, 40), Color.WHITE if item_ready else Color(.6, .65, .65))
		var key = adapter.profile.hint("active_item", "controller" if adapter.last_device == "controller" else "keyboard")
		text(key, Vector2(953, 694), 13, UI.JADE if item_ready else UI.MUTED, true)
		for i in int(maximum):
			plate(Rect2(934 + i * 54 / maximum, 703, 54 / maximum - 3, 3), UI.JADE if amount >= i + 1 else UI.EDGE, 2)
	var ready = player.skill_cd <= 0 and player.energy >= world.skill_cost()
	plate(Rect2(1172, 623, 76, 76), UI.INSET, 38)
	var cooldown = maxf(.01, float(world.db.row("skills", player.skill).cooldown_s))
	var fraction = 1.0 if ready else clampf(1.0 - player.skill_cd / cooldown, 0, 1)
	draw_arc(Vector2(1210, 661), 35, -PI * .5, -PI * .5 + TAU * fraction, 48, UI.JADE if ready else UI.EDGE, 3, true)
	image(player.skill, Rect2(1187, 633, 46, 46), Color.WHITE if ready else Color(.68, .68, .68))
	var device = "controller" if adapter.last_device == "controller" else "keyboard"
	var skill_key = adapter.profile.hint("skill", device).replace("右键 / ", "")
	text("%.1f" % player.skill_cd if player.skill_cd > 0 else skill_key, Vector2(1195, 689), 14, UI.MUTED, true)
	plate(Rect2(1094, 637, 58, 58), UI.INSET, 29)
	glyph("wind", Rect2(1110, 647, 26, 26), UI.TEXT if player.dash_cd <= 0 else UI.MUTED)
	var dash_key = adapter.profile.hint("dash", device)
	text("%.1f" % player.dash_cd if player.dash_cd > 0 else dash_key, Vector2(1106, 687), 12, UI.MUTED)

func draw_mobile() -> void:
	var player = world.player
	var width = app.hud.size.x
	var nav_size = app.mobile_button_height
	var health_width = 90 + int(player.max_hp) * 20
	plate(Rect2(20, 20, health_width, 72), UI.INSET)
	image(world.run.character, Rect2(28, 28, 52, 52))
	draw_arc(Vector2(54, 54), 29, -PI * .5, -PI * .5 + TAU * player.energy / 100.0, 40, UI.JADE, 3, true)
	for i in int(player.max_hp): glyph("heart-solid" if i < int(player.hp) else "heart", Rect2(94 + i * 20, 33, 17, 17), UI.ACCENT if i < player.hp else UI.EDGE)
	glyph("flame", Rect2(95, 61, 17, 17), UI.JADE)
	text(str(roundi(player.energy)), Vector2(120, 77), 17, UI.JADE, true)
	if player.armor > 0:
		glyph("shield", Rect2(169, 60, 18, 18), UI.JADE)
		text(str(player.armor), Vector2(194, 77), 17)
	plate(Rect2(20, 101, 64, 60), UI.INSET, 22)
	image(player.weapon, Rect2(28, 105, 48, 48))
	var relic_count = world.run.relics.size()
	if relic_count > 0:
		plate(Rect2(96, 105, 80, 46), UI.INSET, 22)
		glyph("layers", Rect2(108, 116, 22, 22), UI.MUTED)
		text(str(relic_count), Vector2(140, 137), 18)
	var center_x = width * .5
	plate(Rect2(center_x - 100, 24, 200, 60), UI.INSET)
	text(world.region_spec().name, Vector2(center_x - 80, 50), 21, UI.TEXT, true)
	text("第 %d 重" % int(world.run.floor), Vector2(center_x - 30, 74), 16, UI.MUTED)
	var wallet_x = width - 24 - (nav_size + 12) * 3 - 112
	plate(Rect2(wallet_x, 24, 112, 60), UI.INSET)
	glyph("coins", Rect2(wallet_x + 16, 40, 24, 24), UI.GOLD)
	text(str(int(world.run.coins)), Vector2(wallet_x + 51, 61), 22, UI.TEXT, true)
