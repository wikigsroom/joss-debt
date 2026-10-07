extends RefCounted
## Character information is disclosed on demand; skill trials use the real simulator.
const UI = preload("res://scripts/ui/game_theme.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const ROUTE_ICONS = {"fire": "flame", "thread": "link", "ash": "sparkles", "seal": "shield", "wind": "wind", "ink": "pencil"}

static func show(app, skill_id: String = "") -> void:
	var character = app.world.db.row("characters", app.selected)
	if character.is_empty(): return
	if not character.skills.has(skill_id): skill_id = str(character.skills[0])
	var skill = app.world.db.row("skills", skill_id)
	app.paused = true
	app.screen = "character"
	app.hud.visible = false
	app.renderer.hub = false
	app.adapter.clear()
	app.clear_modal()
	app.dim(.94)
	var shell = app.panel(app.modal, Rect2(64, 48, 1152, 624), UI.INSET, Color.TRANSPARENT)
	shell.set_meta("character_detail_id", character.id)
	var action_size = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	app.icon_button(shell, "收起角色详情", "x", Rect2(1128 - action_size, 20, action_size, action_size), app.show_menu)
	var hero = app.panel(shell, Rect2(24, 24, 328, 392), Color("e1d1ad"), Color.TRANSPARENT)
	var portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture = load("res://assets/portraits/" + character.id + ".png")
	portrait.size = Vector2(328, 328)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(portrait)
	UI.round_texture(portrait)
	var weapon = app.starting_weapon(character.id)
	app.add_art(hero, "res://assets/weapons/" + weapon + ".png", Rect2(18, 332, 46, 46))
	app.label(hero, app.world.db.name_of("weapons", weapon), Rect2(79, 341, 228, 35), 21, UI.BACKGROUND)
	var stats = app.panel(shell, Rect2(24, 434, 328, 64), UI.SURFACE, Color.TRANSPARENT)
	app.icon(stats, "heart", Rect2(20, 20, 24, 24), UI.ACCENT)
	app.label(stats, str(int(character.health)), Rect2(55, 13, 78, 40), 25)
	app.icon(stats, "wind", Rect2(169, 20, 24, 24), UI.JADE)
	app.label(stats, str(int(character.speed)), Rect2(208, 13, 94, 40), 25)
	stats.accessibility_name = "心火 %d · 移速 %d" % [character.health, character.speed]
	stats.tooltip_text = stats.accessibility_name
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	app.label(shell, character.name, Rect2(384, 21, 572, 58), 40)
	for i in character.routes.size():
		var route = str(character.routes[i])
		var chip = app.panel(shell, Rect2(384 + i * 162, 92, 150, 44), UI.SURFACE, Color.TRANSPARENT)
		app.icon(chip, ROUTE_ICONS.get(route, "leaf"), Rect2(15, 12, 20, 20), UI.JADE)
		app.label(chip, app.world.db.name_of("routes", route), Rect2(46, 8, 92, 31), 19)
	var passive = app.panel(shell, Rect2(384, 152, 744, 74), UI.SURFACE, Color.TRANSPARENT)
	passive.set_meta("character_passive", character.id)
	app.icon(passive, "leaf", Rect2(18, 26, 24, 24), UI.JADE)
	app.label(passive, character.passive, Rect2(58, 15, 665, 48), 20)
	for i in character.skills.size():
		var id = str(character.skills[i])
		var form = app.world.db.row("skills", id)
		var tab = app.button(shell, "查看" + form.name, Rect2(384 + i * 252, 242, 240, 108), func(): app.show_character_details(id))
		tab.text = ""
		tab.set_meta("preview_skill_id", id)
		tab.tooltip_text = form.name + " · " + ("基础焚债" if i == 0 else "二章演化")
		tab.accessibility_description = tab.tooltip_text
		if id == skill_id: UI.select(tab)
		app.add_art(tab, "res://assets/skills/" + id + ".png", Rect2(14, 17, 74, 74))
		app.label(tab, form.name, Rect2(101, 27, 125, 33), 22)
		app.label(tab, "基础" if i == 0 else "演化", Rect2(102, 65, 123, 26), 16, UI.MUTED)
	var detail = app.panel(shell, Rect2(384, 366, 744, 134), UI.SURFACE, Color.TRANSPARENT)
	detail.set_meta("preview_detail_id", skill_id)
	app.label(detail, skill.behavior, Rect2(24, 16, 696, 63), 20)
	app.icon(detail, "flame", Rect2(24, 95, 22, 22), UI.ACCENT)
	app.label(detail, str(int(skill.energy_cost)), Rect2(56, 87, 76, 33), 22)
	app.icon(detail, "rotate-ccw", Rect2(150, 95, 22, 22), UI.MUTED)
	app.label(detail, "%.1f s" % skill.cooldown_s, Rect2(182, 87, 100, 33), 22)
	if skill.requires_marked_target:
		app.icon(detail, "circle-dot", Rect2(317, 95, 22, 22), UI.GOLD)
		app.label(detail, "先挂余烬", Rect2(351, 90, 351, 30), 18, UI.MUTED)
	detail.accessibility_name = skill.name + " · " + skill.behavior + " · 香火 %d · 冷却 %.1f 秒" % [skill.energy_cost, skill.cooldown_s]
	var unlocked = app.progress.data.characters.has(character.id)
	var condition = unlock_note(app, character.id) if not unlocked else mastery_note(app, character.id)
	app.icon(shell, "lock" if not unlocked else "book-open", Rect2(26, 521, 23, 23), UI.GOLD if not unlocked else UI.JADE)
	var note = app.label(shell, condition, Rect2(61, 516, 290, 82), 18, UI.MUTED)
	note.set_meta("character_progress_id", character.id)
	note.accessibility_name = condition
	app.icon(shell, "info", Rect2(386, 538, 21, 21), UI.MUTED)
	app.label(shell, "试演不计进度", Rect2(420, 532, 322, 36), 18, UI.MUTED)
	var trial_height = maxf(64, app.mobile_button_height) if app.mobile_ui else 64.0
	var trial = app.icon_button(shell, "试演" + skill.name, "play", Rect2(822, 516, 306, trial_height), func(): app.begin_training("", 0, skill_id), true, "试演")
	trial.set_meta("preview_trial_id", skill_id)
	trial.grab_focus()

static func unlock_note(app, character_id: String) -> String:
	match character_id:
		"c_bell": return "让 3 名敌人连债"
		"c_lantern": return "击败「%s」" % app.world.db.name_of("bosses", "b01")
		"c_mask": return "闪避 / 招架  %d / 20" % mini(20, int(app.progress.data.defenses))
		"c_umbrella": return "单局拾灰回收 200 香火"
		"c_ink": return "累计偿债  %d / 3" % mini(3, int(app.progress.data.repayments))
	return "初始还愿人"

static func mastery_note(app, character_id: String) -> String:
	var personal = app.progress.data.personal[character_id]
	var stage = int(personal.stage)
	if stage >= 3: return "个人愿页  3 / 3"
	if stage == 0:
		var mastery = Progress.MASTERY[character_id]
		return "%s\n%d / %d" % [mastery[0], mini(int(personal.progress), int(mastery[2])), mastery[2]]
	if stage == 1:
		var names: Array = []
		for route in app.world.db.row("characters", character_id).routes: names.append(app.world.db.name_of("routes", route))
		return "同局行愿\n" + " + ".join(names)
	return "击败「%s」" % app.world.db.name_of("bosses", "b37")

static func training_controls(app) -> void:
	var preview = str(app.world.run.get("training_preview_skill", ""))
	var height = maxf(80, app.mobile_button_height + 24) if app.mobile_ui else 80.0
	var size = maxf(64, app.mobile_button_height) if app.mobile_ui else 56.0
	var width = 418 + (size - 56) * 2
	var tray = app.panel(app.modal, Rect2((1280 - width) * .5, 88, width, height), UI.INSET, Color.TRANSPARENT)
	var label = "回还愿人" if not preview.is_empty() else "回铜盘"
	app.icon_button(tray, label, "arrow-left", Rect2(12, 12, size, size), func():
		if preview.is_empty(): app.show_hub("training")
		else: app.show_character_details(preview))
	app.add_art(tray, "res://assets/skills/" + app.world.player.skill + ".png", Rect2(26 + size, 10, 60, 60))
	app.label(tray, app.world.db.name_of("skills", app.world.player.skill), Rect2(105 + size, 10, 180, 34), 23)
	app.label(tray, "试演" if not preview.is_empty() else "铜盘演阵", Rect2(106 + size, 46, 184, 25), 16, UI.MUTED)
	app.icon_button(tray, "重置试演", "refresh-cw", Rect2(width - size - 12, 12, size, size), func(): app.begin_training(app.world.run.get("training_boss", ""), app.world.run.get("training_phase", 0), preview))
