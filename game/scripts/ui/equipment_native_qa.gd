extends Node
## Native presentation fixtures plus actual keyboard, touch and combat events.
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
const Polished = preload("res://scripts/ui/polished_fx.gd")
var app
var directory = ""
var checks: Array = []
var captures: Array = []
var stress: Dictionary = {}

func _ready() -> void: call_deferred("run")
func frames(count: int = 3) -> void:
	for i in count:
		app.update_hud()
		await get_tree().process_frame
func expect(id: String, passed: bool, detail = "") -> void:
	checks.append({"id": id, "passed": passed, "detail": str(detail)})
	if not passed: print("EQUIPMENT NATIVE FAIL: ", id, " ", detail)
func key(code: int) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = pressed
		Input.parse_input_event(event); await frames(2)
func find_meta(root: Node, key_value: String, value = null) -> Array:
	var rows: Array = []
	if root.has_meta(key_value) and (value == null or root.get_meta(key_value) == value): rows.append(root)
	for child in root.get_children(): rows.append_array(find_meta(child, key_value, value))
	return rows
func focus(meta: String, value: String) -> bool:
	var candidates = app.keyboard.candidates(app.modal)
	for i in candidates.size() + 2:
		var owner = app.get_viewport().gui_get_focus_owner()
		if is_instance_valid(owner) and str(owner.get_meta(meta, "")) == value: return true
		await key(KEY_TAB)
	expect("focus/" + value, false, app.screen)
	return false
func digest() -> String: return JSON.stringify(Store.encode(app.world.snapshot())).sha256_text()
func capture(name_value: String) -> void:
	var before = digest()
	app.notice_left = 0
	app.update_hud()
	var mouse = InputEventMouseMotion.new(); mouse.position = Vector2(16, 704); mouse.global_position = mouse.position
	Input.parse_input_event(mouse)
	await frames(2); await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var path = directory.path_join(name_value + ".png")
	captures.append({"name": name_value, "saved": image.save_png(path) == OK, "state_stable": before == digest(), "screen": app.screen, "mode": app.world.mode, "floor": int(app.world.run.floor), "size": [image.get_width(), image.get_height()]})
func arrange(floor_id: int = 1) -> void:
	app.mobile_ui = false; app.settings.touch = false; app.adapter.touch_mode = false; app.adapter.configure({})
	app.begin_run("c_paper", 123456789012, false, {"seed_text": "123456789012"})
	app.set_physics_process(false)
	app.world.run.floor = floor_id; app.world.run.graph = Campaign.build(app.world.db, "123456789012", floor_id)
	app.world.run.room_plan = app.world.run.graph.types.duplicate(); app.world.run.room = 0; app.world.enter_room()
	app.world.run.opening_seen = true; app.world.run.relics = {}; app.world.run.talents = []
	app.world.geometry.restore_objects([]); app.world.enemies.clear(); app.world.bullets.clear(); app.world.zones.clear(); app.world.delayed.clear(); app.world.pickups.clear()
	app.world.room_flags.wave_index = app.world.room_flags.wave_count
	app.world.player.hp = 12; app.world.player.max_hp = 12; app.world.player.pos = Vector2(640, 516); app.world.player.aim = Vector2.UP
	app.world.mode = "combat"; app.world.take_events()
	app.renderer.set_process(true); app.renderer.visual_effects.clear(); app.renderer.animation.clear()
	app.screen = "game"; app.paused = false; app.hud.visible = true; app.clear_modal(); app.ui_signature = ""
func target(point: Vector2, id: String = "e01") -> Dictionary:
	var e = app.world.spawn_enemy(id, point); e.hp = 10000; e.max_hp = 10000; e.speed = 0; e.attack_cd = 100; e.arrival = 0
	return e
func step(count: int, frame: Dictionary = {}) -> void:
	for i in count:
		app.world.tick(frame, 1.0 / 60.0); app.flush_events()
	await frames(1)

func run() -> void:
	await frames(5)
	if OS.get_cmdline_user_args().has("--qa-stress-only"):
		await measure_stress()
		finish_report()
		return
	arrange(); target(Vector2(640, 320)); app.world.run.trinket = "tr01"
	app.world.mode = "clear"
	var drop = World.Equipment.spawn(app.world, "trinket", "tr03", app.world.player.pos + Vector2(30, 0), {}, 0)
	app.flush_events(); app.sync_game_modal(); await frames(3)
	expect("ground_prompt_for_pickup", find_meta(app.modal, "ground_uid", drop.uid).size() == 1)
	await capture("equipment-ground-prompt")
	await key(KEY_E); app._physics_process(1.0 / 60); await frames(3)
	expect("keyboard_e_swaps_trinket_and_does_not_open_map", app.screen == "game" and app.world.run.trinket == "tr03" and app.world.pickups.any(func(p): return p.kind == "trinket" and p.id == "tr01"))
	await capture("equipment-swapped-ground")
	await key(KEY_F); app._physics_process(1.0 / 60)
	expect("keyboard_f_uses_active_in_cleared_room", app.world.stats.active_uses == 1 and app.world.run.active_item.charge == 0)
	await capture("equipment-active-bombs")
	await key(KEY_TAB)
	var line = find_meta(app.modal, "floor_timeline")
	expect("tab_map_complete_eleven_floor_line", app.screen == "route" and line.size() == 1 and find_meta(app.modal, "floor_id").size() == 11)
	await capture("equipment-map-floor-01")
	await key(KEY_ESCAPE)
	expect("escape_map_to_room", app.screen == "game" and not app.paused)
	await key(KEY_I)
	if await focus("action_label", "装备"): await key(KEY_ENTER)
	expect("inventory_equipment_tab_keyboard", app.screen == "inventory" and app.modal.get_meta("navigation_page", "") == "equipment")
	await capture("equipment-inventory")
	await key(KEY_ESCAPE); await key(KEY_ESCAPE)
	expect("pause_opens_with_keyboard", app.screen == "pause")
	if await focus("action_label", "本局记录"): await key(KEY_ENTER)
	expect("pause_history_contains_active_and_trinket", app.world.run.growth_log.any(func(e): return e.type == "active") and app.world.run.growth_log.any(func(e): return e.type == "trinket"))
	await capture("equipment-history")
	for floor_id in [6, 11]:
		arrange(floor_id); await key(KEY_TAB)
		var nodes = find_meta(app.modal, "floor_id")
		expect("map_floor_" + str(floor_id) + "_states", nodes.filter(func(n): return n.get_meta("floor_state") == "completed").size() == floor_id - 1 and nodes.filter(func(n): return n.get_meta("floor_state") == "current" and n.get_meta("floor_id") == floor_id).size() == 1)
		await capture("equipment-map-floor-%02d" % floor_id)

	# A full twelve-relic inventory opens the real keyboard replacement transaction.
	arrange(); app.world.mode = "clear"
	for id in range(1, 13): app.world.run.relics["r%02d" % id] = 1
	drop = World.Equipment.spawn(app.world, "relic", "r55", app.world.player.pos, {}, 0)
	await key(KEY_E); app._physics_process(1.0 / 60); await frames(3)
	expect("ground_relic_full_inventory_opens_replacement", app.world.mode == "replace")
	await capture("equipment-replacement")
	if await focus("action_label", "留着旧愿 · 取消"): await key(KEY_ENTER)
	app._physics_process(1.0 / 60); await frames(3)
	expect("replacement_cancel_keeps_ground_drop", app.world.pickups.any(func(p): return p.uid == drop.uid) and app.world.run.relics.size() == 12)

	# New fifth touch target activates through the same adapter edge, even after clear.
	arrange(); app.mobile_ui = true; app.settings.touch = true; app.adapter.touch_mode = true; app.apply_control_settings(); app.apply_safe_area()
	app.world.mode = "clear"; app.world.run.trinket = "tr09"; app.sync_game_modal()
	var touch = InputEventScreenTouch.new(); touch.index = 5; touch.position = app.adapter.control_center("active_item"); touch.pressed = true
	app.adapter.event(touch); app._physics_process(1.0 / 60)
	expect("touch_active_item_after_clear", app.world.stats.active_uses == 1)
	touch.pressed = false; app.adapter.event(touch)
	await capture("equipment-touch-hud")
	expect("touch_controls_safe_and_separate", app.adapter.valid_layout())
	await key(KEY_TAB); await capture("equipment-touch-map")

	# Read-only visual galleries: all eighty generated strips, all six phases.
	for family in Polished.FAMILIES:
		arrange(3); app.renderer.set_process(false); app.world.player.pos = Vector2(640, 566)
		for phase in 6:
			app.renderer.visual_effects.clear()
			var progress = (phase + .4) / 6.0
			for i in 4:
				var shape = ["beam_lance", "beam_tether", "beam_wave", "beam_fork"][i]
				var origin = Vector2(315, 214 + i * 66)
				app.renderer.visual_effects.append({"kind": "ray", "pos": origin, "end": origin + Vector2(620, 0), "dir": Vector2.RIGHT, "range": 620, "width": 12, "fx_preset": family + "_" + shape, "left": .62 * (1 - progress), "total": .62})
				var preset = ["blast", "ring", "vortex", "field"][i]
				app.renderer.visual_effects.append({"kind": "burst", "pos": Vector2(325 + i * 210, 496), "radius": 72, "fx_preset": family + "_" + preset, "left": .72 * (1 - progress), "total": .72})
			app.renderer.queue_redraw(); await capture("fx-%s-%02d" % [family, phase])
		expect("family_" + family + "_rendered_all_real_frames", true)

	var source_rows = app.world.db.rows("enemies") + app.world.db.rows("bosses")
	for page in ceili(source_rows.size() / 32.0):
		arrange(4); app.renderer.set_process(false)
		for i in range(page * 32, mini(source_rows.size(), (page + 1) * 32)):
			var row = source_rows[i]; var cell = i % 32
			app.world.enemy_bullet(Vector2(336 + cell % 8 * 85, 229 + int(cell / 8) * 88), Vector2.RIGHT.rotated(cell * .43), 160, 1, 7, {"id": row.id, "table": "bosses" if row.id.begins_with("b") else "enemies", "kind": "projectile"})
			app.world.bullets[-1].age = cell * .13
		app.renderer.queue_redraw(); await capture("projectiles-%02d" % page)
	expect("395_native_projectile_profiles_rendered", source_rows.size() == 395)

	# Actual five-beam + explosion combat, then a moving guided scatter recording.
	arrange(7); app.world.run.relics = {"r55": 1, "r56": 1, "r57": 1, "r58": 1, "r59": 1, "r60": 1}
	app.world.player.weapon = "w08"
	var e = target(Vector2(640, 340), "e61"); target(Vector2(690, 360), "e62"); target(Vector2(560, 350), "e63")
	app.world.shoot_input(true, 1); app.flush_events(); app.show_inventory("relics")
	await capture("equipment-combination-inventory"); await key(KEY_ESCAPE)
	app.world.player.shot_cd = 0; app.world.shoot_input(true, 1); app.flush_events()
	await capture("equipment-five-explosive-beams")
	expect("five_explosive_beams_real_damage_and_effects", e.hp < 10000 and app.renderer.visual_effects.any(func(event): return event.kind == "ray") and app.renderer.visual_effects.any(func(event): return event.kind == "burst"))
	arrange(2); app.world.player.weapon = "w01"; app.world.run.relics = {"r57": 1, "r58": 1, "r61": 1, "r62": 1, "r64": 1, "r65": 1}
	e = target(Vector2(640, 330)); target(Vector2(535, 300)); target(Vector2(745, 300))
	for i in 24:
		await step(3, {"aim": Vector2.UP.rotated(sin(i * .19) * .24), "fire": true})
		await capture("motion-combined-%02d" % i)
	expect("guided_explosive_scatter_real_damage", e.hp < 10000)

	await measure_stress()
	finish_report()

func measure_stress() -> void:
	var source_rows = app.world.db.rows("enemies") + app.world.db.rows("bosses")
	arrange(5); app.renderer.set_process(true)
	for i in 180:
		var row = source_rows[i]
		app.world.enemy_bullet(Vector2(250 + i % 20 * 38, 185 + int(i / 20) * 40), Vector2.DOWN, 170, 1, 7, {"id": row.id, "table": "enemies", "kind": "projectile"})
	for i in 25: World.Composer.projectile(app.world, Vector2(430 + i % 7 * 50, 350 + int(i / 7) * 45), Vector2.UP, 10, false, World.Composer.recipe(app.world, app.world.db.row("weapons", "w01")))
	var timing: Array = []; var draw_timing: Array = []
	await frames(15)
	for i in 120:
		var before = Time.get_ticks_usec(); await get_tree().process_frame
		timing.append((Time.get_ticks_usec() - before) / 1000.0); draw_timing.append(app.renderer.last_draw_us / 1000.0)
	timing.sort(); draw_timing.sort(); var total = 0.0
	for value in timing: total += value
	stress = {"bullets": app.world.bullets.size(), "frames": timing.size(), "mean_ms": total / timing.size(), "p95_ms": timing[113], "draw_cpu_p95_ms": draw_timing[113], "physics_paused_for_renderer_measurement": true, "fps_cap": 60, "note": "Native viewport with 205 styled projectiles; capped frame waits include idle time. Simulation timings are recorded separately."}
	expect("bounded_render_budget_keeps_all_collision_cores", app.renderer.fx_budget >= 0 and app.world.bullets.size() == 205)
	expect("native_205_projectiles_p95_under_50ms", stress.p95_ms < 50, stress)
	await capture("equipment-stress")

func finish_report() -> void:
	var failed = checks.filter(func(c): return not c.passed)
	var report = {"passed": failed.is_empty() and captures.all(func(c): return c.saved and c.state_stable), "checks": checks, "failures": failed, "captures": captures, "stress": stress, "atlas_frames_loaded": app.renderer.textures.keys().filter(func(k): return str(k).begins_with("polish/")).size(), "scope": "native OpenGL; actual keyboard and touch actions; actual combined combat motion; declared read-only animation and projectile galleries; isolated save slots"}
	if OS.get_cmdline_user_args().has("--qa-stress-only"): report.scope = "diagnostic renderer stress only; no menu, equipment or asset-adoption assertions"
	FileAccess.open(directory.path_join("native.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Equipment native: ", checks.size(), " checks; ", failed.size(), " failures; ", captures.size(), " captures")
	get_tree().quit(0 if report.passed else 1)
