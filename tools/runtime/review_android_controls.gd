extends SceneTree
## Audit observations describe the current behavior; they are not repair assertions.
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const World = preload("res://scripts/combat/world.gd")
const Assist = preload("res://scripts/ui/aim_assist.gd")
var app
var observations: Array = []
var report_dir = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audit-output="): report_dir = argument.trim_prefix("--audit-output=")
	DirAccess.make_dir_recursive_absolute(report_dir)
	call_deferred("review")

func note(id: String, data: Dictionary) -> void:
	observations.append({"id": id, "observed": data})

func touch(a, id: int, point: Vector2, pressed: bool = true) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = pressed
	a.event(event)

func drag(a, id: int, point: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = id
	event.position = point
	a.event(event)

func sample(a) -> Dictionary:
	return a.sample(Vector2.ZERO, Vector2.ZERO)

func record_frame(f: Dictionary) -> Dictionary:
	return {"move": [f.move.x, f.move.y], "aim": [f.aim.x, f.aim.y], "fire": f.fire,
		"dash": f.dash, "skill": f.skill, "active_item": f.active_item,
		"charge_hold": f.charge_hold, "dash_direction": [f.dash_direction.x, f.dash_direction.y]}

func two_thumb_setup(a) -> void:
	a.fixed_sticks = true
	touch(a, 1, a.control_center("move"))
	drag(a, 1, a.control_center("move") + Vector2.RIGHT * a.control_travel("move"))
	touch(a, 2, a.control_center("aim"))
	drag(a, 2, a.control_center("aim") + Vector2.UP * a.control_travel("aim"))
	sample(a)

func input_observations() -> void:
	var a = Adapter.new()
	two_thumb_setup(a)
	touch(a, 1, a.control_center("move"), false)
	touch(a, 1, a.dash_center())
	note("left_thumb_dash", {"frame":record_frame(sample(a)),
		"center_distance": a.control_center("move").distance_to(a.dash_center())})
	a = Adapter.new()
	two_thumb_setup(a)
	touch(a, 2, a.control_center("aim"), false)
	touch(a, 2, a.skill_center())
	note("right_thumb_skill", {"frame":record_frame(sample(a)),
		"center_distance": a.control_center("aim").distance_to(a.skill_center())})
	a.aim_released_at -= 151
	note("right_thumb_skill_after_151ms", {"frame":record_frame(sample(a))})
	a = Adapter.new()
	two_thumb_setup(a)
	touch(a, 2, a.control_center("aim"), false)
	touch(a, 2, a.control_center("active_item"))
	note("right_thumb_item", {"frame":record_frame(sample(a)),
		"center_distance": a.control_center("aim").distance_to(a.control_center("active_item"))})
	a = Adapter.new()
	two_thumb_setup(a)
	touch(a, 1, a.control_center("move"), false)
	a.recent_move_at -= 251
	touch(a, 1, a.dash_center())
	var f = sample(a)
	var w = World.new()
	w.start("c_paper", 20261009)
	w.tick(f)
	note("dash_direction_after_251ms", {"frame":record_frame(f), "world_direction":[w.player.dash_dir.x,w.player.dash_dir.y]})
	a = Adapter.new()
	a.fixed_sticks = true
	a.fire_toggle = true
	touch(a, 2, a.control_center("aim"))
	drag(a, 2, a.control_center("aim") + Vector2.RIGHT * a.control_travel("aim"))
	var held = sample(a).fire
	touch(a, 2, a.control_center("aim"), false)
	note("touch_fire_toggle", {"configured":true, "held_fire":held, "released_fire":sample(a).fire})
	a = Adapter.new()
	a.layout.move = [.40,.80]
	a.layout.aim = [.55,.80]
	var valid = a.valid_layout()
	touch(a, 1, a.control_center("move"))
	touch(a, 2, a.control_center("aim") - Vector2(90,0))
	note("custom_floating_stick_overlap", {"nominal_layout_valid":valid,
		"both_sticks_captured":a.move_id==1 and a.aim_id==2,
		"origin_distance":a.left_origin.distance_to(a.right_origin),
		"required_separation":a.control_radius("move")+a.control_radius("aim")+a.control_gap})
	w = World.new()
	w.start("c_paper", 20261009)
	w.player.weapon = "w32"
	w.shoot_input(true,.4,false,true)
	var partial = w.player.charge
	w.shoot_input(false,.016,true,true)
	w.time += .16
	w.shoot_input(true,.02,false,true)
	note("charge_transfer_expiry", {"before_release":partial, "after_160ms_return":w.player.charge,
		"shots":w.stats.shots, "fully_charged_auto_release_seconds":.65})
	var helper = Assist.new()
	var origin = Vector2(640,360)
	var target = {"uid":99,"dead":false,"pos":origin+Vector2(100,0).rotated(deg_to_rad(30)),"arrival":0.0}
	var effective_touch_mode = "light"
	var touch_auto = helper.apply(Vector2.RIGHT,origin,[target],w.geometry,1,effective_touch_mode,560,"audit","ray")
	var direct_auto = helper.apply(Vector2.RIGHT,origin,[target],w.geometry,1,"auto",560,"audit","ray")
	note("touch_auto_becomes_light_during_manual_fire", {"configured_mode":"auto",
		"effective_mode_in_main":"light","target_angle_degrees":30,
		"touch_result_degrees":rad_to_deg(touch_auto.angle()),"direct_auto_degrees":rad_to_deg(direct_auto.angle())})
	target.pos = origin+Vector2(100,0).rotated(deg_to_rad(10))
	var ray_angles: Dictionary = {}
	for mode in ["ray","tether","lightning","prism","controlled","guided_swarm"]:
		ray_angles[mode] = rad_to_deg(helper.apply(Vector2.RIGHT,origin,[target],w.geometry,1,"light",560,"audit",mode).angle())
	note("weapon_assist_policy_angles", {"target_angle_degrees":10,"result_angles":ray_angles})

func snap(name: String) -> void:
	app.renderer.combat_interface_visible = app.screen=="game" and not app.paused and app.world.mode in ["combat","clear"]
	app.renderer.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(report_dir.path_join(name+".png"))

func review() -> void:
	input_observations()
	app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.qa_capture_enabled = false
	app.qa_active = true
	app.set_physics_process(false)
	app.set_process(false)
	app.audio.set_muted(true)
	app.world.start("c_paper",20261009)
	app.renderer.world = app.world
	app.renderer.hub = false
	app.world.mode = "combat"
	app.world.player.pos = Vector2(640,360)
	app.world.player.weapon = "w32"
	app.world.player.charge = .32
	app.world.player.energy = 10
	app.world.player.skill_cd = 0
	app.world.player.dash_cd = .5
	app.screen = "game"
	app.paused = false
	app.hud.visible = true
	app.clear_modal()
	app.adapter.set_phase("combat",false)
	app.update_hud()
	await snap("combat-with-enemies")
	var ray_modes: Array = []
	for row in app.world.db.rows("weapons"):
		if str(row.mode) in ["ray","tether","lightning","prism","controlled","guided_swarm","charged_line","charged_arc","nova"]:
			ray_modes.append({"id":row.id,"name":row.name,"mode":row.mode})
	note("weapon_modes_requiring_distinct_controls", {"weapons":ray_modes})
	app.ControlSettings.show_layout(app)
	await process_frame
	var editor = app.modal.find_children("*", "Control", true, false).filter(func(c):return c.get_meta("keyboard_editor",false))[0]
	var radii: Dictionary = {}
	for action in ["move","aim","dash","skill","active_item"]:
		radii[action] = app.adapter.control_radius(action)*editor.size.x/app.adapter.safe_rect.size.x
	note("editor_pick_radii", {"editor_size":[editor.size.x,editor.size.y],
		"drawn_radii":radii,"selection_search_radius":52.0,"touch_minimum_in_current_menu":app.mobile_button_height})
	note("editor_preview_scale_mismatch", {
		"horizontal_scale":editor.size.x/app.adapter.safe_rect.size.x,
		"vertical_scale":editor.size.y/app.adapter.safe_rect.size.y,
		"relative_distortion":(editor.size.x/app.adapter.safe_rect.size.x)/(editor.size.y/app.adapter.safe_rect.size.y)})
	var resized = app.adapter.set_control_size("aim",1.75)
	var aim_preview_radius = app.adapter.control_radius("aim")*editor.size.x/app.adapter.safe_rect.size.x
	var aim_preview_center = (app.adapter.control_center("aim")-app.adapter.safe_rect.position)/app.adapter.safe_rect.size*editor.size
	var pick = InputEventScreenTouch.new()
	pick.index = 90
	pick.position = aim_preview_center+Vector2(65,0)
	pick.pressed = true
	editor._gui_input(pick)
	note("large_editor_control_outer_ring_cannot_drag", {"resize_accepted":resized,
		"drawn_radius":aim_preview_radius,"press_radius":65.0,"dragged_action":editor.dragged})
	pick.pressed = false
	editor._gui_input(pick)
	app.adapter.set_control_size("aim",1.0)
	await snap("layout-editor")
	app.go_back()
	app.adapter.layout.move = [.40,.80]
	app.adapter.layout.aim = [.55,.80]
	app.adapter.fixed_sticks = false
	app.adapter.clear()
	var nominal_valid = app.adapter.valid_layout()
	app.screen = "game"
	app.paused = false
	app.hud.visible = true
	app.clear_modal()
	app.adapter.set_phase("combat",false)
	touch(app.adapter, 4, app.adapter.control_center("move"))
	touch(app.adapter, 5, app.adapter.control_center("aim")-Vector2(90,0))
	note("app_custom_floating_stick_overlap", {"nominal_layout_valid":nominal_valid,
		"both_sticks_captured":app.adapter.move_id==4 and app.adapter.aim_id==5,
		"origin_distance":app.adapter.left_origin.distance_to(app.adapter.right_origin),
		"required_separation":app.adapter.control_radius("move")+app.adapter.control_radius("aim")+app.adapter.control_gap})
	await snap("floating-sticks-overlap")
	app.adapter.reset_layout()
	app.ControlSettings.show_layout(app)
	app.adapter.set_control_size("skill",1.2)
	var edited = app.adapter.control_sizes.skill
	app.go_back()
	note("editor_back_commits_changes", {"edited_skill_size":edited,
		"settings_skill_size":app.settings.touch_sizes.skill,
		"saved_skill_size":app.progress.store.read().get("settings",{}).get("touch_sizes",{}).get("skill",null)})
	var trial = load("res://scripts/ui/touch_tryout.gd").new()
	trial.app = app
	app.add_child(trial)
	await process_frame
	var before_puppet = trial.puppet
	touch(app.adapter, 6, app.adapter.control_center("move"))
	drag(app.adapter, 6, app.adapter.control_center("move")+Vector2(30,0))
	touch(app.adapter, 7, app.adapter.dash_center())
	trial._process(.001)
	note("layout_trial_dash", {"last_action":trial.last_action,
		"puppet_displacement":before_puppet.distance_to(trial.puppet),
		"world_dash_left":app.world.player.dash_left,"world_charge":app.world.player.charge})
	await snap("trial-label-only-dash")
	trial.finish()
	await process_frame
	for page in ["splash","files","title","characters","challenges","stats"]:
		app.show_menu(page)
		await snap("menu-"+page)
	app.show_hub("wishes")
	await snap("hub-wishes")
	app.show_menu("files")
	var desktop_hints: Array = []
	for label in app.modal.find_children("*","Label",true,false):
		if label.text.contains("Enter") or label.text.contains("Esc"): desktop_hints.append(label.text)
	note("mobile_file_menu_desktop_hint", {"labels":desktop_hints})
	app.adapter.reset_layout()
	app.adapter.layout.move = [.18,.80]
	app.adapter.set_control_size("aim",1.25)
	var layout_before = app.adapter.layout.duplicate(true)
	var sizes_before = app.adapter.control_sizes.duplicate(true)
	app.apply_safe_area(480)
	note("high_density_reset_of_user_layout", {"before_layout":layout_before,"after_layout":app.adapter.layout,
		"before_sizes":sizes_before,"after_sizes":app.adapter.control_sizes,
		"resulting_default_still_valid":app.adapter.valid_layout()})
	var screen_scale = root.get_screen_transform().x.length()
	note("menu_font_density_conversion", {"density_override":480,
		"menu_scale":app.interface.scale.x,"screen_scale":screen_scale,
		"nominal_20_unit_text_dp":20*app.interface.scale.x*screen_scale/(480.0/160.0),
		"minimum_button_units":app.mobile_button_height})
	var report = {"probe_completed":true,"observations":observations,
		"scope":"Native Windows Godot and synthetic touch; observed problems are not fixes and no physical Android device is claimed."}
	var file = FileAccess.open(report_dir.path_join("observations.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	app.queue_free()
	await process_frame
	quit(0)
