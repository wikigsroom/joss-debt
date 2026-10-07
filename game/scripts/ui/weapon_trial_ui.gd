extends RefCounted
const UI = preload("res://scripts/ui/game_theme.gd")

static func controls(app) -> void:
	var size = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var width = 462 + (size - 56) * 2
	var tray = app.panel(app.modal, Rect2((1280 - width) * .5, 88, width, size + 24), UI.INSET, Color.TRANSPARENT)
	app.icon_button(tray, "回灯摊", "arrow-left", Rect2(12, 12, size, size), app.end_shop_trial)
	app.add_art(tray, "res://assets/weapons/" + app.world.player.weapon + ".png", Rect2(26 + size, 10, 60, 60))
	app.label(tray, app.world.db.name_of("weapons", app.world.player.weapon), Rect2(104 + size, 10, 218, 34), 23)
	app.label(tray, "试射 · 不扣纸钱", Rect2(106 + size, 46, 216, 25), 16, UI.MUTED)
	app.icon_button(tray, "重置试射", "refresh-cw", Rect2(width - size - 12, 12, size, size), app.reset_training)
