extends RefCounted
const Profile = preload("res://scripts/ui/input_profile.gd")
const Editor = preload("res://scripts/ui/touch_layout_editor.gd")
const UI = preload("res://scripts/ui/game_theme.gd")

static func sheet(app, title: String, subtitle: String) -> void:
	app.paused = true
	app.adapter.clear()
	app.haptics.stop()
	app.clear_modal()
	app.dim(.94)
	app.label(app.modal, title, Rect2(96, 38, 1088, 65), 42)
	var brief = "选动作，按新键。" if app.screen == "controls" else ("拖动触点，调整手感。" if app.screen == "touch_layout" else "按你的习惯调整。")
	var note = app.label(app.modal, brief, Rect2(97, 107, 934, 44), 18, app.GOLD)
	app.icon_button(app.modal, subtitle, "info", Rect2(1118, 50, 58, 58), func(): note.text = brief if note.text == subtitle else subtitle)

static func show_bindings(app, device: String = "keyboard", scroll_y: int = 0) -> void:
	app.screen = "controls"
	app.capture_action = ""
	app.capture_device = device
	sheet(app, "让动作顺手", "选择动作后按下新按键。重复绑定会交换；Esc取消录入或返回。")
	for i in 2:
		var tab = ["keyboard", "controller"][i]
		app.button(app.modal, ["鼠标与键盘", "手柄"][i], Rect2(96 + i * 270, 162, 250, 60), func(): show_bindings(app, tab), tab == device)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(96, 240)
	scroll.size = Vector2(1088, 324)
	app.modal.add_child(scroll)
	scroll.set_deferred("scroll_vertical", scroll_y)
	var list = VBoxContainer.new()
	list.custom_minimum_size.x = 1060
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var actions = Profile.KEYBOARD_ACTIONS if device == "keyboard" else Profile.PAD_ACTIONS
	for action in actions:
		var row = Panel.new()
		row.custom_minimum_size = Vector2(1060, 88)
		row.add_theme_stylebox_override("panel", app.box_style(Color("30372f"), Color("635c44")))
		list.add_child(row)
		app.icon(row, {"skill": "flame", "dash": "wind", "fire": "sword", "interact": "hand", "map": "map", "pause": "pause"}.get(action, "gamepad-2" if device == "controller" else "mouse"), Rect2(25, 28, 28, 28), UI.JADE)
		app.label(row, Profile.ACTION_NAMES[action], Rect2(77, 22, 489, 45), 24)
		var bind = app.button(row, app.adapter.profile.hint(action, device), Rect2(670, 10, 366, 68), func():
			app.capture_action = action
			app.capture_device = device
			app.capture_scroll = scroll.scroll_vertical
			for child in app.modal.get_children():
				if child is Label and child.position.y == 107: child.text = "现在按下「%s」的新按键；Esc取消。" % Profile.ACTION_NAMES[action])
		bind.focus_mode = Control.FOCUS_ALL
		bind.set_meta("nav_id", "binding_" + device + "_" + action)
	app.button(app.modal, "恢复此页默认", Rect2(96, 612, 326, 66), func():
		app.adapter.profile.reset_device(device)
		app.persist_settings()
		show_bindings(app, device))
	app.button(app.modal, "回灯下设置", Rect2(786, 612, 398, 66), func(): app.back_to_settings(), true)

static func show_assistance(app, scroll_y: int = 0) -> void:
	app.screen = "assistance"
	sheet(app, "瞄准与反馈", "辅助只调整触屏与手柄方向，攻击距离、遮挡和伤害照常结算。")
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(96, 176)
	scroll.size = Vector2(1088, 386)
	app.modal.add_child(scroll)
	scroll.set_deferred("scroll_vertical", scroll_y)
	var list = VBoxContainer.new()
	list.custom_minimum_size.x = 1060
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var options = [
		{"name": "瞄准辅助", "key": "aim_mode", "values": ["off", "light", "auto"], "labels": ["关闭", "轻度吸附", "自动锁定"], "detail": "轻度：15度扇区、25%修正；自动：保持目标0.25秒。"},
		{"name": "触觉反馈", "key": "haptics", "values": [true, false], "labels": ["开启", "关闭"], "detail": "受伤、焚债、招架和身法使用短促反馈。"},
		{"name": "摇杆起点", "key": "fixed_sticks", "values": [false, true], "labels": ["随手指浮动", "固定布局"], "detail": "固定模式使用触控布局中保存的位置。"},
		{"name": "摇杆死区", "key": "deadzone", "values": [.12, .18, .25, .32], "labels": ["12%", "18%", "25%", "32%"], "detail": "加大死区可以减少摇杆漂移。"},
		{"name": "主攻击按法", "key": "fire_toggle", "values": [false, true], "labels": ["按住攻击", "按一下切换"], "detail": "切换用于鼠键和手柄；暂停会停止攻击。"},
		{"name": "数字弹字", "key": "damage_numbers", "values": [true, false], "labels": ["显示", "隐藏"], "detail": "命中、余烬和危险提示仍保留。"},
		{"name": "震屏强度", "key": "shake_scale", "values": [1.0, .5, 0.0], "labels": ["标准", "轻微", "关闭"], "detail": "只调整表现，减弱动态也可以统一关闭。"},
		{"name": "命中顿帧", "key": "hitstop", "values": [true, false], "labels": ["开启", "关闭"], "detail": "只短暂停留受击纸偶，模拟时间持续运行。"},
		{"name": "闪光强度", "key": "flash_scale", "values": [1.0, .5, 0.0], "labels": ["标准", "轻微", "关闭"], "detail": "降低受击亮度，保留轮廓与警告环。"},
		{"name": "纸屑密度", "key": "particle_scale", "values": [1.0, .5, .0], "labels": ["标准", "减半", "关闭"], "detail": "危险弹、地面范围和债线不会被关闭。"},
		{"name": "动态性能", "key": "performance_mode", "values": ["auto", "high", "battery"], "labels": ["自动平衡", "高画质", "省电"], "detail": "移动端根据实时帧时自动收敛纸屑和短特效；高画质保持完整表现，省电固定使用低负载档。"},
		{"name": "色觉提示", "key": "shape_cues", "values": [false, true], "labels": ["标准", "加强形状"], "detail": "敌弹增加白边与尾线，友弹仍为暖色圆形。"},
		{"name": "战斗文字", "key": "combat_text_scale", "values": [1.0, 1.25, 1.5], "labels": ["标准", "125%", "150%"], "detail": "调整弹字与首领名称，界面层级保持一致。"},
		{"name": "愿页文字", "key": "story_text_scale", "values": [1.0, 1.25, 1.5], "labels": ["标准", "125%", "150%"], "detail": "故事与庭中短句放大后可滚动，收起按钮始终可见。"},
		{"name": "自动拾取范围", "key": "pickup_radius_scale", "values": [1.0, 1.25, .5], "labels": ["标准", "扩大25%", "缩小50%"], "detail": "调整余烬和纸钱；续心香仍需靠近，清房照常收齐。"},
	]
	for option in options:
		var row = Panel.new()
		row.custom_minimum_size = Vector2(1060, 94)
		row.set_meta("setting_key", option.key)
		row.add_theme_stylebox_override("panel", app.box_style(Color("30372f"), Color("635c44")))
		list.add_child(row)
		app.icon(row, {"aim_mode": "crosshair", "haptics": "hand", "fixed_sticks": "gamepad-2", "deadzone": "circle-dot", "fire_toggle": "sword", "damage_numbers": "target", "shake_scale": "wind", "hitstop": "pause", "flash_scale": "sun", "particle_scale": "sparkles", "performance_mode": "sparkles", "shape_cues": "eye", "combat_text_scale": "pencil", "story_text_scale": "book-open", "pickup_radius_scale": "coins"}.get(option.key, "settings-2"), Rect2(24, 31, 28, 28), UI.JADE)
		app.label(row, option.name, Rect2(76, 25, 538, 42), 24)
		var detail = app.label(row, option.detail, Rect2(24, 103, 1012, 56), 18, app.GOLD)
		detail.set_meta("setting_detail", option.key)
		detail.visible = false
		var current = option.values.find(app.settings[option.key])
		current = maxi(0, current)
		var control = app.button(row, option.labels[current], Rect2(718, 16, 318, 70), func():
			var index = maxi(0, option.values.find(app.settings[option.key]))
			app.settings[option.key] = option.values[(index + 1) % option.values.size()]
			app.apply_control_settings()
			app.persist_settings()
			show_assistance(app, scroll.scroll_vertical))
		control.add_theme_font_size_override("font_size", 22)
		control.set_meta("nav_id", "assistance_" + str(option.key))
		control.tooltip_text = option.detail
		app.icon_button(row, option.detail, "info", Rect2(635, 18, 58, 58), func():
			detail.visible = not detail.visible
			row.custom_minimum_size.y = 169 if detail.visible else 94)
	app.button(app.modal, "回灯下设置", Rect2(786, 612, 398, 66), func(): app.back_to_settings(), true)

static func show_layout(app) -> void:
	app.screen = "touch_layout"
	sheet(app, "把触点放在顺手的位置", "拖动移动、瞄准、身法和焚债。保持间距，触点自动避开屏幕边缘。")
	var preview = TextureRect.new()
	preview.position = Vector2(96, 176)
	preview.size = Vector2(800, 450)
	preview.texture = app.renderer.textures.arena
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.modulate = Color(.55, .55, .55)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.modal.add_child(preview)
	var editor = Editor.new()
	editor.position = preview.position
	editor.size = preview.size
	editor.adapter = app.adapter
	editor.font = app.font
	editor.focus_mode = Control.FOCUS_ALL
	editor.set_meta("keyboard_editor", true)
	editor.set_meta("nav_id", "layout_editor")
	editor.accessibility_name = "方向键调整触点；Enter 切换触点；Tab 离开编辑"
	app.modal.add_child(editor)
	editor.status = app.label(app.modal, "拖动微调；方向键移动，确认键切换触点。", Rect2(97, 634, 799, 43), 18, app.GOLD)
	app.label(app.modal, "触点大小", Rect2(928, 178, 255, 41), 23)
	app.button(app.modal, "%d%%" % roundi(app.adapter.control_scale * 100), Rect2(928, 230, 256, 64), func():
		var previous = app.adapter.control_scale
		app.adapter.control_scale = 1.0 if previous >= 1.25 else previous + .125
		if not app.adapter.valid_layout():
			app.adapter.control_scale = previous
			editor.status.text = "先拉开触点，再增大尺寸。"
		else:
			app.persist_settings()
			show_layout(app))
	app.label(app.modal, "触点透明度", Rect2(928, 326, 255, 41), 23)
	app.button(app.modal, "%d%%" % roundi(app.adapter.control_opacity * 100), Rect2(928, 378, 256, 64), func():
		app.adapter.control_opacity = 1.0 if app.adapter.control_opacity <= .4 else app.adapter.control_opacity - .2
		app.persist_settings()
		show_layout(app))
	app.button(app.modal, "恢复默认布局", Rect2(928, 474, 256, 64), func():
		app.adapter.layout = app.adapter.DEFAULT_LAYOUT.duplicate(true)
		app.adapter.control_scale = 1
		app.adapter.control_opacity = 1
		app.persist_settings()
		show_layout(app))
	app.button(app.modal, "保存 · 回设置", Rect2(928, 574, 256, 104), func(): app.persist_settings(); app.back_to_settings(), true)
