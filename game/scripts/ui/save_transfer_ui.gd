extends RefCounted
const Transfer = preload("res://scripts/core/save_transfer.gd")
const UI = preload("res://scripts/ui/game_theme.gd")

static func sheet(app, title: String, detail: String) -> void:
	app.paused = true
	app.hud.visible = false
	app.adapter.clear()
	app.haptics.stop()
	app.clear_modal()
	app.dim(.94)
	app.label(app.modal, title, Rect2(96, 38, 1088, 65), 42)
	app.label(app.modal, detail, Rect2(97, 110, 1086, 52), 20, app.GOLD)

static func summary(app, parent: Control, bundle: Dictionary, rect: Rect2) -> void:
	var card = app.panel(parent, rect, Color("30372f"), Color("635c44"))
	var profile: Dictionary = bundle.profile
	var run: Dictionary = bundle.checkpoint.get("run", {})
	var character = str(run.get("character", "c_paper"))
	app.add_art(card, "res://assets/portraits/" + character + ".png", Rect2(22, 15, 122, 145))
	app.label(card, "无名之愿" if str(profile.wish_name).is_empty() else str(profile.wish_name).left(24), Rect2(170, 15, rect.size.x - 192, 43), 29)
	var progress_text = "%d 位还愿人   ·   善缘 %d   ·   结局 %d / 3" % [profile.characters.size(), profile.merit, profile.endings.size()]
	app.label(card, progress_text, Rect2(170, 63, rect.size.x - 192, 36), 21, app.GOLD)
	var state = "灯下待启程"
	if not run.is_empty():
		state = "%s · 第%d章 · 第%d间" % [app.world.db.name_of("characters", character), run.floor, int(run.room) + 1]
		if run.result != "": state += " · 已结算"
		else: state += " · 从暂停页继续"
	app.label(card, state, Rect2(170, 108, rect.size.x - 192, 46), 20)

static func show(app) -> void:
	app.screen = "saves"
	app.save_current_run()
	sheet(app, "愿簿传递", "角色与当前还愿一起传递。换入前会保留一份旧愿簿。")
	summary(app, app.modal, app.save_session.portable_bundle(), Rect2(96, 178, 1088, 170))
	app.panel(app.modal, Rect2(96, 366, 526, 181), Color("30372f"), Color("635c44"))
	app.panel(app.modal, Rect2(642, 366, 542, 181), Color("30372f"), Color("635c44"))
	app.label(app.modal, "带走愿簿", Rect2(117, 380, 470, 43), 28)
	app.label(app.modal, "换入愿簿", Rect2(664, 380, 488, 43), 28)
	var export_button = app.icon_button(app.modal, "复制传递文字", "upload", Rect2(117, 434, 240, 72), func(): copy_code(app), true, "复制")
	export_button.disabled = app.save_session.read_only
	var paste_button = app.icon_button(app.modal, "粘贴并预览", "download", Rect2(664, 434, 240, 72), func(): paste_sheet(app), false, "粘贴")
	paste_button.disabled = app.save_session.read_only
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var export_file = app.icon_button(app.modal, "另存为文件", "save", Rect2(375, 434, 226, 72), func(): choose_file(app, true), false, "导出")
		export_file.disabled = app.save_session.read_only
		var import_file = app.icon_button(app.modal, "从文件导入", "folder-open", Rect2(922, 434, 241, 72), func(): choose_file(app, false), false, "导入")
		import_file.disabled = app.save_session.read_only
	else:
		app.label(app.modal, "用文字跨设备传递", Rect2(375, 447, 226, 47), 20, app.GOLD)
		app.label(app.modal, "确认后才换入进度", Rect2(922, 447, 241, 47), 20, app.GOLD)
	var detail = app.save_session.message if app.save_session.read_only else "默认保留本机操作与声音设置。"
	app.label(app.modal, detail, Rect2(97, 562, 1086, 42), 18, app.GOLD)
	var restore = app.icon_button(app.modal, "回到导入前", "rotate-ccw", Rect2(96, 620, 326, 66), func(): backup_preview(app), false, "恢复旧愿簿")
	restore.disabled = app.save_session.read_only or app.save_session.current.backup.is_empty()
	app.icon_button(app.modal, "回灯下设置", "arrow-left", Rect2(786, 620, 398, 66), func(): app.back_to_settings(), false, "返回")

static func copy_code(app) -> void:
	var code = Transfer.export_code(app.save_session.portable_bundle())
	if code.is_empty():
		app.notice("愿簿较大，请使用文件传递。")
		return
	DisplayServer.clipboard_set(code)
	app.notice("完整愿簿已复制。在另一台设备打开愿簿传递，粘贴并预览。")

static func paste_sheet(app) -> void:
	app.screen = "save_paste"
	sheet(app, "接住另一盏灯的愿", "粘贴整份传递文字。预览不会改变进度，确认后才会换入。")
	app.panel(app.modal, Rect2(96, 179, 1088, 374), Color("30372f"), Color("635c44"))
	var text = TextEdit.new()
	text.name = "SaveTransferText"
	text.position = Vector2(118, 201)
	text.size = Vector2(1044, 330)
	text.placeholder_text = "IDEBT2:…"
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.add_theme_font_override("font", app.font)
	text.add_theme_font_size_override("font_size", 20)
	text.add_theme_color_override("font_color", app.PAPER)
	text.add_theme_color_override("background_color", app.INK)
	app.modal.add_child(text)
	app.button(app.modal, "从剪贴板粘贴", Rect2(96, 573, 326, 64), func():
		var value = DisplayServer.clipboard_get()
		if value.length() > Transfer.MAX_BYTES: app.notice("文字过长，请使用完整愿簿文件。")
		else: text.text = value)
	app.button(app.modal, "预览愿簿", Rect2(786, 573, 398, 64), func(): inspect(app, Transfer.inspect_code(text.text)), true)
	app.icon_button(app.modal, "返回 · 愿簿传递", "arrow-left", Rect2(96, 654, 1088, 64 if app.mobile_ui else 44), func(): show(app), false, "返回")
	text.grab_focus()

static func inspect(app, result: Dictionary) -> void:
	if not result.ok:
		app.notice(result.message)
		return
	app.save_import_draft = result.data
	app.save_import_settings = false
	preview(app, false)

static func backup_preview(app) -> void:
	if app.save_session.current.backup.is_empty(): return
	app.save_import_draft = app.save_session.current.backup.duplicate(true)
	preview(app, true)

static func preview(app, backup: bool = false) -> void:
	app.screen = "save_preview"
	sheet(app, "回到导入前的灯下" if backup else "这盏灯里，带来了哪些愿", "确认后整体恢复角色进度与当前还愿。" if backup else "确认后整体换入角色进度与当前还愿；你现在的愿簿会保留为备份。")
	summary(app, app.modal, app.save_import_draft, Rect2(96, 194, 1088, 178))
	app.panel(app.modal, Rect2(96, 395, 1088, 169), Color("30372f"), Color("635c44"))
	app.label(app.modal, "先看清，再换入", Rect2(117, 409, 750, 43), 28)
	app.label(app.modal, "已领取奖励、随机进程和当前房间随愿簿一起保留。\n恢复后停在角色页，继续还愿仍需要主动确认。", Rect2(118, 468, 780, 77), 21, app.GOLD)
	if not backup:
		app.button(app.modal, "带入操作设置" if app.save_import_settings else "保留本机设置", Rect2(916, 455, 245, 76), func():
			app.save_import_settings = not app.save_import_settings
			preview(app))
	app.button(app.modal, "保留现在的愿簿", Rect2(96, 620, 460, 66), func():
		app.save_import_draft = {}
		show(app))
	app.button(app.modal, "确认恢复" if backup else "确认换入愿簿", Rect2(786, 620, 398, 66), func():
		var done = app.save_session.restore_backup() if backup else app.save_session.import_bundle(app.save_import_draft, app.save_import_settings)
		if not done:
			app.notice(app.save_session.message)
			return
		app.reload_save_session()
		app.save_import_draft = {}
		app.show_menu("title")
		app.notice(app.save_session.message), true)

static func choose_file(app, exporting: bool) -> void:
	var picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.use_native_dialog = true
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	picker.mode_overrides_title = false
	picker.title = "带走愿簿" if exporting else "换入愿簿"
	picker.add_filter("*.incense.json", "香火债愿簿", "application/json")
	if exporting: picker.current_file = "IncenseDebt-%s.incense.json" % Time.get_date_string_from_system()
	app.add_child(picker)
	picker.canceled.connect(func(): picker.queue_free())
	picker.file_selected.connect(func(path):
		if exporting:
			app.notice("愿簿已保存，可在另一台设备预览换入。" if Transfer.write_file(path, app.save_session.portable_bundle()) else "文件未能写入，游戏进度没有改变。")
		else: inspect(app, Transfer.read_file(path))
		picker.queue_free())
	picker.popup_centered(Vector2i(920, 600))
