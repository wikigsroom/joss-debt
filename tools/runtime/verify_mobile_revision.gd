extends SceneTree
## Native renderer + touch regression fixtures. No emulator, browser or player saves.
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const World = preload("res://scripts/combat/world.gd")
const Assist = preload("res://scripts/ui/aim_assist.gd")
const Store = preload("res://scripts/core/save_store.gd")
var app
var checks: Array = []
var failures: Array = []
var geometry: Array = []
var report_dir = ""
var density_override = 0.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audit-output="): report_dir = argument.trim_prefix("--audit-output=")
		if argument.begins_with("--audit-dpi="): density_override = float(argument.trim_prefix("--audit-dpi="))
	DirAccess.make_dir_recursive_absolute(report_dir)
	call_deferred("run_suite")

func expect(value: bool, message: String) -> void:
	checks.append(message)
	if not value:
		failures.append(message)
		push_error(message)

func touch(adapter, index: int, point: Vector2, pressed: bool = true, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	adapter.event(event)

func drag(adapter, index: int, point: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = point
	adapter.event(event)

func sample(adapter) -> Dictionary: return adapter.sample(Vector2.ZERO, Vector2.ZERO)

func core_input() -> void:
	var a = Adapter.new()
	a.fixed_sticks = true
	touch(a, 1, a.control_center("move"))
	drag(a, 1, a.control_center("move") + Vector2.RIGHT * a.control_travel("move"))
	touch(a, 2, a.control_center("aim"))
	drag(a, 2, a.control_center("aim") + Vector2.UP * a.control_travel("aim"))
	touch(a, 3, a.skill_center())
	var f = sample(a)
	expect(f.fire and f.skill and f.move.x > .99 and f.aim.y < -.99, "three fingers independently move, aim/fire and cast")
	touch(a, 3, a.skill_center(), false)
	touch(a, 3, a.dash_center())
	f = sample(a)
	expect(f.dash and f.fire and f.move.x > .99 and a.move_id == 1 and a.aim_id == 2 and f.dash_direction.x > .99, "right-hand dash preserves the held left movement stick, right aim and movement-based dash direction")
	var w = World.new()
	w.start("c_paper", 20261009)
	w.tick(f)
	expect(w.player.dash_dir.x > .99, "the real world dashes along movement rather than the other thumb's aim")
	var defaults = Adapter.new()
	for preset in ["phone", "tablet"]:
		defaults.reset_layout(preset)
		var split = defaults.safe_rect.get_center().x
		var right_only = defaults.valid_layout() and defaults.control_center("move").x + defaults.control_radius("move") < split
		for action in ["aim", "dash", "skill", "active_item"]:
			right_only = right_only and defaults.control_center(action).x - defaults.control_radius(action) > split
		expect(right_only, "%s default leaves only movement on the left and all combat targets on the right" % preset)
	var old_phone = {"move": [.105, .80], "aim": [.895, .80], "dash": [.25, .65], "skill": [.75, .65], "active_item": [.70, .88]}
	defaults.configure(JSON.parse_string(JSON.stringify({"touch_layout": old_phone, "touch_sizes": {"skill": 1.1}, "control_opacity": .6})))
	expect(defaults.dash_center().x > 640 and defaults.skill_center().x > 640 and is_equal_approx(defaults.control_sizes.skill, 1.1) and is_equal_approx(defaults.control_opacity, .6), "saved old phone defaults upgrade after JSON reload while retaining size and opacity")
	var old_tablet = {"move": [.12, .81], "aim": [.88, .81], "dash": [.27, .66], "skill": [.73, .66]}
	defaults.configure({"touch_layout": old_tablet})
	expect(defaults.dash_center().x > 640 and defaults.skill_center().x > 640 and defaults.valid_layout(), "saved four-control tablet defaults upgrade and acquire a separated right-hand item target")
	var custom = old_phone.duplicate(true)
	custom.move = [.16, .78]
	defaults.configure({"touch_layout": custom, "touch_sizes": {"move": 1.1}})
	expect(defaults.layout == custom and is_equal_approx(defaults.control_sizes.move, 1.1), "a customized old layout and its sizes survive the update unchanged")
	var enlarged = {"move": 1.75, "aim": 1.75, "dash": 1.75, "skill": 1.75, "active_item": 1.75}
	defaults.configure({"touch_layout": old_phone, "touch_sizes": enlarged})
	expect(defaults.layout == old_phone and defaults.control_sizes == enlarged and defaults.valid_layout(), "an enlarged legacy layout is retained when migrating it would cause overlapping targets")
	a.clear()
	touch(a, 1, a.control_center("move"))
	drag(a, 1, a.control_center("move") + Vector2.RIGHT * a.control_travel("move"))
	touch(a, 2, a.control_center("aim"))
	drag(a, 2, a.control_center("aim") + Vector2.UP * a.control_travel("aim"))
	sample(a)
	touch(a, 2, a.control_center("aim"), false)
	touch(a, 2, a.dash_center())
	f = sample(a)
	expect(f.dash and f.charge_hold and not f.fire and f.move.x > .99 and a.move_id == 1 and not sample(a).dash, "two-thumb aim-to-dash transfer keeps left movement, confirms charge handoff and triggers the dash once")
	a.clear()
	touch(a, 4, Vector2(900,180))
	expect(a.aim_id == -1 and a.move_id == -1 and not sample(a).fire, "fixed sticks cannot capture an upper-playfield press")
	a.clear()
	a.fixed_sticks = false
	touch(a, 4, Vector2(500,180))
	expect(a.aim_id == -1 and a.move_id == -1, "floating sticks cannot capture menu or upper-playfield taps")
	a.clear()
	a.fixed_sticks = true
	expect(a.move_control("aim",Vector2(.42,.66)), "aim stick can be placed on the other half of the screen")
	touch(a, 5, a.control_center("aim"))
	expect(a.aim_id == 5 and a.move_id == -1, "custom position captures its visible aim stick without a half-screen rule")
	a.configure({"fixed_sticks":true,"deadzone":.35})
	touch(a, 6, a.control_center("aim"))
	drag(a, 6, a.control_center("aim") + Vector2.RIGHT * a.control_travel("aim") * .25)
	expect(not sample(a).fire, "high deadzone prevents blind fire inside the aim deadzone")
	drag(a, 6, a.control_center("aim") + Vector2.RIGHT * a.control_travel("aim") * .45)
	expect(sample(a).fire, "a deliberate outward aim starts fire")
	drag(a, 6, a.control_center("aim") + Vector2.RIGHT * a.control_travel("aim") * .37)
	expect(sample(a).fire, "fire hysteresis avoids flicker near its start threshold")
	drag(a, 6, a.control_center("aim") + Vector2.RIGHT * a.control_travel("aim") * .25)
	expect(not sample(a).fire, "returning inside the deadzone stops fire immediately")
	touch(a, 6, a.control_center("aim"), false, true)
	expect(a.aim_id == -1 and not sample(a).fire and a.aim_released_at < 0, "a canceled finger clears firing and cannot initiate charge transfer")
	a.configure({"fixed_sticks":false})
	touch(a, 7, a.control_center("aim") - Vector2(95,0))
	expect(a.aim_id == 7 and a.right_origin.distance_to(a.skill_center()) >= a.control_radius("aim") + a.control_radius("skill") + a.control_gap - .1, "floating origin leaves a separate skill-button exclusion area")
	a.set_phase("choice",false)
	touch(a, 8, a.control_center("move"))
	touch(a, 9, a.control_center("aim"))
	touch(a, 10, a.skill_center())
	expect(a.move_id == -1 and a.aim_id == -1 and not sample(a).skill, "choice overlays disable both invisible sticks and action buttons")
	a.set_phase("clear",false)
	touch(a, 11, a.dash_center())
	touch(a, 12, a.skill_center())
	f = sample(a)
	expect(f.dash and not f.skill and a.enabled("move") and not a.enabled("aim"), "cleared rooms expose only the movement and dash actions that can work")
	expect(not a.enabled("active_item"), "no equipped item means no ghost item capture area")
	a.configure({})
	var other_sizes = a.control_sizes.duplicate()
	var old_radius = a.control_radius("aim")
	expect(a.set_control_size("aim",1.25) and a.control_radius("aim") > old_radius and a.control_sizes.move == other_sizes.move and a.control_sizes.skill == other_sizes.skill, "changing the aim-stick size changes only that control")
	var saved = JSON.parse_string(JSON.stringify({"touch_layout":a.layout,"touch_sizes":a.control_sizes}))
	var restored = Adapter.new()
	restored.configure(saved)
	expect(restored.layout == a.layout and restored.control_sizes == a.control_sizes, "individual sizes and positions survive a JSON settings round trip")
	var previous = a.layout.duplicate(true)
	expect(not a.move_control("dash",(a.control_center("aim")-a.safe_rect.position)/a.safe_rect.size) and a.layout == previous, "overlapping capture targets are rejected without damaging the layout")
	a.set_phase("combat",false)
	a.clear()
	touch(a, 60, a.control_center("move"))
	drag(a, 60, a.control_center("move") + Vector2.RIGHT * a.control_travel("move"))
	var emulated = InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	a.event(emulated)
	f = sample(a)
	expect(f.device == "touch" and not f.fire and f.dash_direction.x > .99, "touch-emulated mouse events preserve touch identity and cannot fire from movement")
	expect(a.profile.from_event(emulated,"keyboard").is_empty() and not a.profile.event_matches("fire",emulated), "touch-emulated clicks cannot become mouse bindings or gameplay shortcuts")
	a.clear()
	expect(sample(a).move == Vector2.ZERO and not sample(a).fire and a.held_action_ids.is_empty(), "lifecycle reset clears every touch owner and pending action")
	w.player.dash_left = 0
	w.player.weapon = w.db.rows("weapons").filter(func(row): return row.mode == "nova")[0].id
	w.player.shot_cd = 0
	w.shoot_input(true,.4,false,true)
	var shots = w.stats.shots
	w.time += .016
	w.shoot_input(false,.016,false,true)
	expect(w.player.charge == 0 and w.stats.shots == shots, "releasing a charged touch immediately stops visible charging and never fires")
	w.time += .02
	w.shoot_input(false,.016,true,true)
	w.time += .02
	w.shoot_input(true,.05,false,true)
	expect(w.player.charge > .44 and w.stats.shots == shots, "a confirmed skill/button handoff restores partial charge inside 150 ms")
	w.shoot_input(false,.016,true,true)
	w.time += .2
	w.shoot_input(true,.05,false,true)
	expect(w.player.charge < .06, "expired transfers cannot retain charge after a long release")
	w.shoot_input(false,.016,true,true)
	w.clear_touch_charge()
	expect(w.touch_charge_transfer.is_empty() and w.player.charge == 0, "pause/lifecycle reset removes transient charge transfer")
	var assist = Assist.new()
	w.geometry.build("room_open_1",2)
	var origin = Vector2(640,360)
	var enemies = [{"uid":1,"dead":false,"pos":origin+Vector2.LEFT*100,"arrival":0.0}]
	expect(assist.apply(Vector2.RIGHT,origin,enemies,w.geometry,1,"auto",300,"qa") == Vector2.RIGHT, "automatic aim never turns manual rightward aim toward an enemy behind the player")
	enemies[0].pos = origin + Vector2(100,10)
	expect(assist.apply(Vector2.RIGHT,origin,enemies,w.geometry,1,"light",300,"qa","controlled") == Vector2.RIGHT, "controlled bullets keep their authored manual steering")

func screenshot(name: String) -> void:
	# The fixture freezes application processing. Apply the presentation flag
	# normally refreshed by main._process before asking its renderer for a frame.
	app.renderer.combat_interface_visible = app.screen == "game" and not app.paused and app.world.mode in ["combat", "clear"]
	app.renderer.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	expect(image != null and not image.is_empty(), "%s has a native rendered frame" % name)
	image.save_png(report_dir.path_join(name+".png"))

func controls(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is BaseButton or child is Range: result.append(child)
		controls(child,result)

func check_geometry(name: String) -> void:
	await process_frame
	await process_frame
	var nodes: Array = []
	controls(app.modal,nodes)
	var rectangles: Array = []
	var complete = true
	var overlap = false
	var safe = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for control in nodes:
		if not control.is_visible_in_tree(): continue
		var rect = control.get_global_rect()
		var ancestor = control.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: rect = rect.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		if rect.get_area() <= .1: continue
		complete = complete and safe.grow(.1).encloses(rect)
		for previous in rectangles:
			if rect.intersection(previous).get_area() > 2: overlap = true
		rectangles.append(rect)
	geometry.append({"screen":name,"complete":complete,"overlap":overlap,"count":rectangles.size(),"rectangles":rectangles.map(func(r):return {"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y})})
	expect(complete and not overlap, "%s touch controls fit the surface without overlapping" % name)

func run_suite() -> void:
	core_input()
	app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.qa_capture_enabled = false
	app.qa_active = true
	app.set_physics_process(false)
	app.set_process(false)
	app.audio.set_muted(true)
	if density_override > 0: app.apply_safe_area(density_override)
	app.world.start("c_paper",20261009)
	app.renderer.world = app.world
	app.renderer.hub = false
	app.world.mode = "combat"
	app.world.enemies.clear()
	app.screen = "game"
	app.paused = false
	app.clear_modal()
	app.hud.visible = true
	app.adapter.touch_mode = true
	app.adapter.set_phase("combat",false)
	app.update_hud()
	expect(app.adapter.valid_layout(), "default layout respects the expanded safe surface")
	var projection = app.renderer.arena_transform
	expect(is_equal_approx(projection.x.length(),projection.y.length()), "wide/tablet surfaces preserve battlefield aspect ratio")
	expect(app.hud.size == app.adapter.safe_rect.grow(6).size, "HUD and touch controls use the full safe surface")
	var has_map = false
	for child in app.hud.get_children():
		if child.get_meta("hud_action","") == "map": has_map = true
	expect(has_map, "a dedicated touch map button exists during combat")
	await screenshot("combat")
	var press = InputEventScreenTouch.new()
	press.index = 20
	press.position = root.get_final_transform() * app.adapter.control_center("move")
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	expect(app.adapter.move_id == 20, "the actual application input path captures the shown movement stick")
	press = InputEventScreenTouch.new()
	press.index = 20
	press.position = root.get_final_transform() * (app.hud.position + Vector2(app.hud.size.x-40,48))
	press.pressed = false
	Input.parse_input_event(press)
	await process_frame
	expect(app.adapter.move_id == -1, "release over a HUD button reaches its existing movement owner")
	press = InputEventScreenTouch.new()
	press.index = 21
	press.position = root.get_final_transform() * app.adapter.control_center("aim")
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	press = InputEventScreenTouch.new()
	press.index = 21
	press.position = root.get_final_transform() * (app.hud.position + Vector2(app.hud.size.x-40,48))
	press.pressed = false
	press.canceled = true
	Input.parse_input_event(press)
	await process_frame
	expect(app.adapter.aim_id == -1 and app.adapter.aim_released_at < 0, "a real canceled touch over the HUD clears the aim owner and invalidates charge handoff")
	app.show_tutorial()
	await check_geometry("tutorial")
	await screenshot("tutorial")
	app.clear_modal()
	app.world.mode = "choice"
	app.world.choices = [{"kind":"relic","id":"r01","price":0},{"kind":"relic","id":"r02","price":0},{"kind":"relic","id":"r03","price":0},{"kind":"relic","id":"r04","price":0}]
	app.screen = "game"
	app.mobile_choice = 0
	app.show_choices()
	var candidates = 0
	for child in app.modal.get_children():
		if child.has_meta("mobile_candidate"): candidates += 1
	expect(candidates == 4, "all four alternatives are visible together for direct comparison")
	await check_geometry("choice-four")
	await screenshot("choice-four")
	var before_choice = app.world.snapshot()
	var alternate = app.qa_find_meta(app.modal,"mobile_candidate","2")
	alternate.pressed.emit()
	expect(app.mobile_choice == 2 and app.world.snapshot() == before_choice, "touching a candidate previews it without committing a reward")
	app.world.choices.clear()
	for row in app.world.db.rows("skills").slice(0,4):
		app.world.choices.append({"kind":"skill","id":row.id,"price":0,"slot":"qa_"+row.id})
	app.mobile_choice = 0
	app.clear_modal()
	app.show_choices()
	expect(app.qa_meta_count(app.modal,"mobile_candidate") == 4 and app.qa_button(app.modal,"留在此处 · 继续") == null, "four skill candidates remain visible and mandatory evolution has no skip action")
	await check_geometry("skill-four")
	await screenshot("skill-four")
	app.world.mode = "choice"
	app.world.choices = app.world.special_room_choices("sacrifice")
	app.mobile_choice = 0
	app.clear_modal()
	app.show_choices()
	var payment = app.qa_find_meta(app.modal,"nav_id","choice_confirm")
	expect(str(app.world.choices[0].hp_cost) in payment.text and "心火" in payment.text, "the sacrifice confirmation shows its actual health payment before committing")
	await check_geometry("sacrifice")
	await screenshot("sacrifice")
	app.world.mode = "choice"
	app.world.run.relics.clear()
	for row in app.world.db.rows("relics").slice(0,12): app.world.run.relics[row.id] = 1
	app.world.choices = [{"kind":"relic","id":"r13","price":0,"slot":"qa_replace"}]
	expect(app.world.take_choice(0) and app.world.mode == "replace", "a thirteenth offering enters the real replacement state")
	app.clear_modal()
	app.show_replacement()
	await check_geometry("replacement")
	await screenshot("replacement")
	var held_before = app.world.run.relics.duplicate(true)
	var selected = app.qa_find_meta(app.modal,"nav_id","replace_r01")
	selected.pressed.emit()
	expect(app.screen == "replacement_confirm" and app.world.run.relics == held_before and app.qa_meta_count(app.modal,"replacement_preview") == 2, "selecting an old offering previews both effects and removes nothing")
	await check_geometry("replacement-confirm")
	await screenshot("replacement-confirm")
	app.go_back()
	expect(app.screen == "game" and app.world.mode == "replace" and app.world.run.relics == held_before, "Android back leaves the replacement preview without losing the old offering")
	app.qa_find_meta(app.modal,"nav_id","replace_r01").pressed.emit()
	app.qa_find_meta(app.modal,"replacement_confirm","r01").pressed.emit()
	expect(not app.world.run.relics.has("r01") and app.world.run.relics.has("r13") and app.world.run.relics.size() == 12, "an explicit touch confirmation commits exactly one offering swap")
	app.show_pause()
	await check_geometry("pause")
	await screenshot("pause")
	app.show_run_history()
	await check_geometry("growth")
	await screenshot("growth")
	app.RouteMap.show_sheet(app)
	await check_geometry("map")
	await screenshot("map")
	app.SeedUI.show(app)
	await check_geometry("seed")
	await screenshot("seed")
	var seed_edit = app.modal.find_children("*", "LineEdit", true, false)[0]
	seed_edit.grab_focus()
	app.update_mobile_keyboard(320 * root.get_screen_transform().y.length())
	expect(seed_edit.get_global_rect().end.y < root.get_visible_rect().size.y - 300 and app.mobile_keyboard_button.visible, "an on-screen keyboard moves the active text field above the keyboard and provides a close button")
	await screenshot("seed-keyboard-guard")
	app.hide_mobile_keyboard()
	expect(app.interface.position == app.mobile_interface_origin, "closing the virtual keyboard restores the normal menu position")
	app.SaveUI.paste_sheet(app)
	await check_geometry("save-paste")
	await screenshot("save-paste")
	app.ControlSettings.show_assistance(app)
	await check_geometry("assistance")
	await screenshot("assistance")
	app.ControlSettings.show_bindings(app,"controller")
	await check_geometry("controller-bindings")
	await screenshot("controller-bindings")
	app.show_settings()
	await check_geometry("settings")
	await screenshot("settings")
	app.ControlSettings.show_layout(app)
	await check_geometry("touch-layout")
	await screenshot("touch-layout")
	var sizes_before = app.adapter.control_sizes.duplicate()
	app.adapter.set_control_size("skill",1.2)
	app.persist_settings()
	expect(app.settings.touch_sizes.skill == 1.2 and app.settings.touch_sizes.aim == sizes_before.aim, "settings persist per-control sizing without changing other controls")
	app.show_audio_settings()
	await check_geometry("audio")
	await screenshot("audio")
	var trial = load("res://scripts/ui/touch_tryout.gd").new()
	trial.app = app
	app.add_child(trial)
	await screenshot("tryout")
	expect(app.screen == "touch_trial", "settings can launch a full-surface touch sandbox")
	app.go_back()
	await process_frame
	expect(app.screen == "touch_layout" and not is_instance_valid(trial), "Android system back returns from the sandbox to layout editing")
	app.world.mode = "clear"
	app.screen = "game"
	app.paused = false
	app.hud.visible = true
	app.sync_game_modal()
	app.update_hud()
	expect(app.adapter.enabled("move") and app.adapter.enabled("dash") and not app.adapter.enabled("aim"), "room transitions immediately synchronize the visible and active touch actions")
	await screenshot("clear-room")
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(.25).timeout
	var report = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"geometry":geometry,"scope":"native desktop Godot at actual viewport ratios, synthetic multi-touch, real input dispatch and settings; physical Android acceptance remains pending"}
	var file = FileAccess.open(report_dir.path_join("verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("Mobile revision: %d checks; %d failures" % [checks.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
