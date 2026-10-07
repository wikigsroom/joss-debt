extends RefCounted
const UI = preload("res://scripts/ui/game_theme.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")

static func show(app) -> void:
	app.paused = true
	app.screen = "seed_input"
	app.hud.visible = false
	app.clear_modal()
	app.dim(.92)
	var panel = app.panel(app.modal, Rect2(278, 146, 724, 434), UI.INSET, Color.TRANSPARENT)
	app.icon(panel, "shuffle", Rect2(326, 30, 64, 64), UI.JADE)
	app.label(panel, "这一次的愿种", Rect2(52, 118, 620, 58), 36)
	app.label(panel, "输入12位数字，重走同一条路。留空则随机。", Rect2(52, 182, 620, 40), 20, UI.MUTED)
	var edit = LineEdit.new()
	edit.position = Vector2(52, 242)
	edit.size = Vector2(620, 62)
	edit.max_length = 12
	edit.placeholder_text = "自动随机"
	edit.text = app.seed_draft
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_override("font", UI.body_font(true))
	edit.add_theme_font_size_override("font_size", 30)
	edit.add_theme_stylebox_override("normal", UI.style(UI.SURFACE, UI.EDGE, 20))
	edit.set_meta("nav_id", "seed_editor")
	panel.add_child(edit)
	edit.text_changed.connect(func(value): app.seed_draft = value)
	var confirm = app.icon_button(panel, "固定种子只在下一次开始时使用", "check", Rect2(376, 338, 296, 64), func():
		if not app.seed_draft.is_empty() and not Seed.valid(app.seed_draft):
			app.notice("愿种需要正好12位数字。")
			return
		app.show_menu("characters"), true, "收下")
	confirm.set_meta("nav_id", "seed_confirm")
	app.icon_button(panel, "清除固定种子并返回", "shuffle", Rect2(52, 338, 296, 64), func(): app.seed_draft = ""; app.show_menu("characters"), false, "随机")
