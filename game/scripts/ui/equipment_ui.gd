extends RefCounted
const UI = preload("res://scripts/ui/game_theme.gd")

static func art(kind: String, id: String) -> String:
	var table = {"active": "active_items", "trinket": "trinkets", "relic": "relics"}.get(kind, kind)
	return "res://assets/%s/%s.png" % [table, id]

static func ground_hint(app) -> void:
	var drop = app.world.nearby_pickup()
	if drop.is_empty(): return
	var table = {"active": "active_items", "trinket": "trinkets", "relic": "relics"}.get(drop.kind, "")
	var row = app.world.db.row(table, str(drop.id)) if not table.is_empty() else {"name": "火芯", "behavior": "主动道具充能 +1"}
	var width = 330.0
	var height = maxf(70, app.mobile_button_height) if app.mobile_ui else 64.0
	var key = app.adapter.profile.hint("interact", "controller" if app.adapter.last_device == "controller" else "keyboard")
	var action = app.button(app.modal, "", Rect2(475, 558, width, height), func(): app.world.interact_pickup(); app.flush_events(); app.ui_signature = "")
	action.add_theme_stylebox_override("normal", UI.style(UI.INSET, UI.JADE, 26, 1))
	action.set_meta("nav_id", "ground_pickup")
	action.set_meta("ground_uid", int(drop.uid))
	action.tooltip_text = str(row.behavior) + ("\n当前饰品会掉在脚边" if drop.kind == "trinket" else "")
	action.accessibility_name = "拾取 " + str(row.name)
	if drop.kind == "battery": app.icon(action, "zap", Rect2(18, 18, 30, 30), UI.GOLD)
	else: app.add_art(action, art(drop.kind, drop.id), Rect2(9, 5, 54, 54))
	app.label(action, str(row.name), Rect2(71, 10, 184, 28), 21)
	app.label(action, "换装" if drop.kind in ["active", "trinket"] else "拾取", Rect2(73, 36, 174, 23), 14, UI.MUTED)
	var badge = app.panel(action, Rect2(width - 65, 12, 48, 40), UI.SURFACE, Color.TRANSPARENT)
	var hint = app.label(badge, "取" if app.mobile_ui else key, Rect2(2, 3, 44, 32), 19, UI.JADE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
