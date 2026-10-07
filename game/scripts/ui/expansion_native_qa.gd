extends Node
## Real native viewport and real keyboard events. Scene fixtures are declared in the report.
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
const Patterns = preload("res://scripts/combat/expanded_patterns.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")
var app
var directory = ""
var checks: Array = []
var captures: Array = []
var previous_clipboard = ""

func _ready() -> void: call_deferred("run")
func frames(count: int = 3) -> void:
	for i in count: await get_tree().process_frame
func expect(id: String, condition: bool, detail: String = "") -> void:
	checks.append({"id": id, "passed": condition, "detail": detail})
	if not condition: print("EXPANSION NATIVE FAIL: ", id, " ", detail)
func key(code: int, shift: bool = false, ctrl: bool = false, unicode_value: int = 0) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.physical_keycode = code; event.keycode = code; event.pressed = pressed
		event.shift_pressed = shift; event.ctrl_pressed = ctrl; event.unicode = unicode_value
		Input.parse_input_event(event)
		await frames(2)
func target(meta: String, value: String) -> bool:
	var controls = app.keyboard.candidates(app.modal)
	for attempt in controls.size() + 2:
		var owner = app.get_viewport().gui_get_focus_owner()
		if is_instance_valid(owner) and str(owner.get_meta(meta, "")) == value: return true
		await key(KEY_TAB, false, app.screen == "route")
	expect("focus_" + meta + "_" + value, false, app.screen)
	return false
func action(value: String) -> void:
	if await target("action_label", value): await key(KEY_ENTER)
func capture(name_value: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var path = directory.path_join(name_value + ".png")
	captures.append({"name": name_value, "saved": image.save_png(path) == OK, "screen": app.screen,
		"mode": app.world.mode, "floor": int(app.world.run.get("floor", 0)), "room": int(app.world.run.get("room", 0))})

func arrange(seed_text: String, floor_id: int) -> void:
	app.begin_run("c_paper", seed_text.to_int(), false, {"seed_text": seed_text})
	app.set_physics_process(false)
	app.world.run.floor = floor_id
	app.world.run.graph = Campaign.build(app.world.db, seed_text, floor_id)
	app.world.run.room_plan = app.world.run.graph.types.duplicate()
	app.world.run.room = 0
	app.world.enter_room()
	app.world.take_events()
	app.screen = "game"; app.paused = false; app.hud.visible = true; app.clear_modal()
	app.renderer.visual_effects.clear(); app.renderer.animation.clear()
	app.world.player.hp = 12; app.world.player.max_hp = 12
	app.world.player.pos = Vector2(640, 516)
	app.world.player.aim = Vector2.UP

func tick(count: int, frame: Dictionary = {}) -> void:
	for i in count:
		app.world.tick(frame, 1.0 / 60.0)
		app.flush_events()
		await frames(1)

func run() -> void:
	previous_clipboard = DisplayServer.clipboard_get()
	await frames(5)
	await key(KEY_ENTER); await key(KEY_ENTER)
	expect("three_layers_to_main", app.menu_page == "title" and app.save_slot == 1)
	await key(KEY_ENTER)
	if await target("nav_id", "seed_input"): await key(KEY_ENTER)
	expect("seed_keyboard_entry", app.screen == "seed_input")
	if await target("nav_id", "seed_editor"):
		for digit in "000123456789": await key(digit.unicode_at(0), false, false, digit.unicode_at(0))
	expect("seed_native_digits_keep_leading_zeroes", app.seed_draft == "000123456789", app.seed_draft)
	if await target("nav_id", "seed_confirm"): await key(KEY_ENTER)
	expect("seed_confirm_returns_character", app.screen == "menu" and app.menu_page == "characters")
	if await target("nav_id", "begin_run"): await key(KEY_ENTER)
	app.set_physics_process(false)
	expect("normal_keyboard_start_eleven_floors_one_shot_seed", app.world.run.floor_limit == 11 and app.world.run.seed_text == "000123456789" and app.seed_draft.is_empty() and app.screen == "cinematic")
	await capture("story-opening")
	await key(KEY_F1)
	expect("cinematic_keyboard_help", app.screen == "focus_help")
	await key(KEY_ESCAPE)
	expect("cinematic_help_returns_cinematic", app.screen == "cinematic")
	await key(KEY_ENTER)
	expect("opening_cursor_persisted", int(app.world.run.get("cinematic_cursor", 0)) == 1)
	await key(KEY_ESCAPE)
	expect("cinematic_escape_pauses", app.screen == "pause")
	if await target("nav_id", "copy_seed"): await key(KEY_ENTER)
	expect("pause_keyboard_seed_copy", DisplayServer.clipboard_get() == "000123456789")
	await capture("pause-seed")
	await action("存下这页 · 回主菜单")
	expect("opening_saved_to_main", app.screen == "menu" and app.menu_page == "title")
	if await target("nav_id", "continue"): await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	expect("opening_resumes_saved_cursor", app.screen == "cinematic" and int(app.world.run.get("cinematic_cursor", 0)) == 1)
	await key(KEY_ENTER); await key(KEY_ENTER)
	expect("opening_keyboard_to_tutorial", app.screen == "tutorial")
	await key(KEY_ENTER)
	expect("tutorial_keyboard_to_combat", app.screen == "game" and app.world.mode == "combat")

	# Final graph + long legal-size build fixture. Every item is browsed by input.
	arrange("123456789012", 11)
	app.world.run.room = app.world.run.graph.types.find("boss")
	app.world.enemies.clear(); app.world.mode = "clear"
	for row in app.world.db.rows("relics").slice(0, 12): app.world.run.relics[row.id] = 1
	app.world.run.talents = app.world.db.rows("talents").slice(0, 18).map(func(row): return row.id)
	for i in 100: app.world.record_growth_choice("relic", "r%02d" % (1 + i % 12), "room", "qa", 0, 1, "chosen")
	await key(KEY_TAB)
	expect("final_map_keyboard_open", app.screen == "route" and app.world.run.graph.types.size() >= 30)
	var entry_count = int(app.modal.get_meta("map_entry_count", 0))
	expect("map_full_build_not_truncated", entry_count >= 32, str(entry_count))
	await capture("map-final-build")
	if await target("nav_id", "map_build_0"):
		await key(KEY_F1); await key(KEY_ESCAPE)
		expect("map_help_returns_original_map", app.screen == "route" and app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "map_build_0")
	if await target("nav_id", "map_build_" + str(entry_count - 1)):
		expect("map_last_build_keyboard_visible", app.get_viewport().gui_get_focus_owner().get_global_rect().intersection(Rect2(0, 0, 1280, 720)).get_area() > 0)
		await capture("map-build-last")
	await action("所有历史选择")
	expect("map_full_history_not_truncated", int(app.modal.get_meta("map_entry_count", 0)) == app.world.run.growth_log.size())
	if await target("nav_id", "map_history_99"):
		await capture("map-history-last")
		await key(KEY_PAGEUP); await key(KEY_END)
	await key(KEY_TAB)
	expect("tab_closes_map_without_changing_room", app.screen == "game" and app.world.run.room == app.world.run.graph.types.find("boss"))

	# All ten transitions pass the same keyboard, save and restore path.
	for floor_id in range(2, 12):
		arrange("123456789012", floor_id - 1)
		app.world.mode = "checkpoint"; app.world.advance_room(); app.flush_events(); app.sync_game_modal()
		expect("transition_%d_is_cinematic" % floor_id, app.screen == "cinematic" and app.world.run.floor == floor_id - 1)
		await capture("transition-%02d" % floor_id)
		await action("收起播片，继续还愿")
		if floor_id == 2:
			app.sync_game_modal(); await frames(3); await key(KEY_2)
			expect("evolution_number_keyboard", app.world.run.evolved and app.world.mode == "combat")
		expect("transition_%d_enters_correct_floor" % floor_id, app.world.run.floor == floor_id and app.screen == "game")

	var samples: Dictionary = {}
	for seed_value in range(1, 180):
		for floor_id in range(1, 6):
			var biome = Campaign.biome(app.world.db, app.Seed.text(seed_value), floor_id)
			if not samples.has(biome.id): samples[biome.id] = [app.Seed.text(seed_value), floor_id]
	samples.m19 = ["123456789012", 6]; samples.m20 = ["123456789012", 11]
	for biome in app.world.db.expansion.biomes:
		arrange(samples[biome.id][0], samples[biome.id][1])
		for variant in 2:
			app.world.run.graph.backgrounds["0"] = variant
			app.world.enter_room(); app.world.take_events()
			expect("boundary_%s_%d_matches_background" % [biome.id,variant],app.world.geometry.boundary_key==biome.id+("_a" if variant==0 else "_b"))
			await capture("environment-%s-%s" % [biome.id, "a" if variant == 0 else "b"])
		expect("environment_" + biome.id, app.world.region_spec().id == biome.id)
		app.world.enemies.clear(); app.world.geometry.restore_objects([])
		app.world.player.pos = Vector2(640,500)
		var mixed = app.world.encounter_ids(10,"native_mix")
		for i in mixed.size():
			var enemy = app.world.spawn_enemy(mixed[i],Vector2(330+i%5*155,270+(i/5)*145))
			enemy.attack_cd=20
		expect("native_%s_six_local_four_guests" % biome.id,app.world.enemies.filter(func(e): return app.world.guest_spec().enemy_ids.has(e.id)).size()==4)
		await capture("mixed-"+biome.id)
		app.world.enemies.clear(); app.world.geometry.restore_objects([])
		app.world.player.pos = Vector2(640, 578)
		app.world.player.invulnerable = 1000
		for i in biome.enemy_ids.size():
			var enemy = app.world.spawn_enemy(str(biome.enemy_ids[i]), Vector2(270 + i % 4 * 246, 225 + (i / 4) * 147))
			enemy.attack_cd = 10
		await capture("themed-" + biome.id + "-roster")
		expect("native_"+biome.id+"_twelve_themed_mobs", app.world.enemies.size()==12 and app.world.enemies.all(func(e): return app.world.db.row("enemies", e.id).get("theme", "") == biome.id))

	# Inspect two distinct chambers per early floor, with one live boss each.
	for floor_id in range(1,6):
		arrange("123456789012",floor_id)
		var early_rooms = app.world.run.graph.boss_assignments.keys()
		for room in early_rooms:
			app.world.run.room=int(room); app.world.enter_room(); app.flush_events()
			expect("early_%d_room_%s_one_live_boss" % [floor_id,room],app.world.enemies.filter(func(e): return e.boss).size()==1)
			await capture("early-%d-boss-%s" % [floor_id,room])
		app.world.mode="clear"; await key(KEY_TAB)
		await capture("early-%d-two-boss-chambers-map" % floor_id)
		await key(KEY_TAB)

	# Generated VFX shown at fixed times in the real renderer, including wall clipping.
	arrange("123456789012",3)
	app.world.enemies.clear(); app.world.geometry.restore_objects([])
	app.renderer.set_process(false)
	for index in 32:
		var elapsed = index*.025
		app.world.time=elapsed
		app.renderer.clock=elapsed
		app.renderer.visual_effects.clear()
		for i in 4:
			var origin = Vector2(380,225+i*72)
			var end = app.world.geometry.clipped_ray(origin,origin+Vector2.RIGHT*600,14)
			app.renderer.visual_effects.append({"kind":"ray","pos":origin,"end":end,"dir":Vector2.RIGHT,"range":origin.distance_to(end),"width":14,"style":["beam_amber","beam_ink","beam_thread","beam_prism"][i],"total":.8,"left":.8-elapsed})
			app.renderer.visual_effects.append({"kind":"burst","pos":Vector2(330+i*210,510),"radius":74,"style":["blast_flame","blast_ink","blast_lotus","shockwave"][i],"total":.8,"left":.8-elapsed})
		app.renderer.queue_redraw()
		await capture("motion-revision-fx-%02d" % index)
	app.renderer.visual_effects.clear()
	var wall_point = app.world.geometry.doorway("west",25)
	app.world.zones=[{"pos":wall_point,"radius":165.0,"friendly":false,"born":0.0,"active":1.0,"until":2.0,"damage":1.0}]
	for phase in [0.0,.35,.75,1.05,1.5]:
		app.world.time=phase; app.renderer.clock=phase; app.renderer.queue_redraw()
		await capture("revision-wall-area-"+str(phase))
	app.world.zones.clear(); app.renderer.set_process(true)

	arrange("123456789012", 3)
	app.world.enemies.clear(); app.world.geometry.restore_objects([])
	for group_id in 4:
		app.world.enemies.clear()
		for i in 8:
			var id = "e%02d" % (25 + group_id * 8 + i)
			var enemy = app.world.spawn_enemy(id, Vector2(268 + i % 4 * 240, 254 + i / 4 * 230))
			enemy.attack_cd = 20
			Patterns.move(app.world, enemy, .08)
		await capture("enemies-group-%d" % group_id)
	for spec in app.world.db.rows("bosses"):
		if spec.has("theme"):
			arrange(samples[spec.theme][0], samples[spec.theme][1])
			app.world.geometry.restore_objects([])
		app.world.enemies.clear(); app.world.bullets.clear(); app.world.zones.clear()
		app.world.player.hp = 12; app.world.player.invulnerable = 1000; app.world.mode = "combat"
		var boss = app.world.spawn_boss(str(spec.id), Vector2(640, 305))
		boss.phase = 2; boss.attack_cd = 0.01
		await tick(92)
		expect("boss_" + spec.id + "_visible_attack", app.world.events.is_empty() and app.world.enemies.any(func(e): return e.id == spec.id))
		await capture("boss-" + spec.id)

	for spec in app.world.db.rows("weapons"):
		app.world.enemies.clear(); app.world.bullets.clear(); app.world.zones.clear(); app.world.delayed.clear()
		app.world.mode = "combat"; app.world.player.weapon = spec.id; app.world.player.shot_cd = 0; app.world.player.hp = 12
		app.world.player.pos = Vector2(640, 516); app.world.player.aim = Vector2.UP
		var enemy = app.world.spawn_enemy("e49", Vector2(640, 347))
		enemy.hp = 500; enemy.max_hp = 500; enemy.attack_cd = 30; enemy.speed = 0
		await tick(42, {"aim": Vector2.UP, "fire": true})
		await capture("weapon-" + spec.id)
		expect("weapon_" + spec.id + "_rendered", app.world.player.weapon == spec.id)
		if int(str(spec.id).trim_prefix("w")) >= 17:
			for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
				app.world.player.aim = direction
				await capture("equipment-%s-%s" % [spec.id, app.renderer.facing(direction)])

	arrange("123456789012", 7)
	app.world.enemies.clear(); app.world.bullets.clear(); app.world.player.pos = Vector2(760, 430)
	for i in 12:
		await tick(6, {"aim": Vector2.LEFT, "fire": true})
		await capture("motion-scenery-%02d" % i)
	app.world.geometry.restore_objects([])
	var twin_room = app.world.run.graph.room_roles.keys().filter(func(room): return app.world.run.graph.room_roles[room] == "double_boss")[0]
	app.world.run.room = int(twin_room); app.world.enter_room(); app.world.take_events()
	app.world.player.pos = Vector2(640, 510)
	await capture("double-boss-room")
	for i in 32:
		await tick(6)
		await capture("motion-dual-%02d" % i)
	expect("two_native_bosses_two_health_bars", app.world.enemies.filter(func(e): return e.boss).size() == 2)

	arrange("123456789012", 11)
	app.world.run.result = "victory"; app.world.run.bosses_defeated = ["b36", "b37"]
	app.world.mode = "epilogue"; app.world.enemies.clear(); app.sync_game_modal()
	for i in 5:
		await capture("ending-scene-%02d" % i)
		await key(KEY_ENTER)
	expect("full_epilogue_keyboard_to_mandatory_ending", app.world.run.epilogue_seen and app.screen == "endings")
	await key(KEY_ENTER)
	expect("keyboard_final_ending_commit", not app.world.run.ending.is_empty())
	await capture("ending-result")
	DisplayServer.clipboard_set(previous_clipboard)
	var failures = checks.filter(func(check): return not check.passed)
	var report = {"passed": failures.is_empty() and captures.all(func(item): return item.saved), "checks": checks,
		"failures": failures, "captures": captures, "scope": "native keyboard interactions + arranged scene visual fixtures; full combat campaign evidence is a separate simulation report"}
	FileAccess.open(directory.path_join("expansion-native.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Expansion native: ", checks.size(), " checks; ", failures.size(), " failures; ", captures.size(), " captures")
	get_tree().quit(0 if report.passed else 1)
