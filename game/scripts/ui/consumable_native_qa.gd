extends Node
## Render real drops at shipping size, and exercise actual collection / native save paths.
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
var app
var directory = ""
var checks: Array = []
var captures: Array = []
var baseline = false

func _ready() -> void: call_deferred("run")

func frames(count: int = 3) -> void:
	for i in count:
		app.update_hud()
		await get_tree().process_frame

func expect(id: String, passed: bool, detail = "") -> void:
	checks.append({"id": id, "passed": passed, "detail": str(detail)})
	if not passed: print("CONSUMABLE QA FAIL: ", id, " ", detail)

func digest(w = null) -> String:
	return JSON.stringify(Store.encode((app.world if w == null else w).snapshot())).sha256_text()

func arrange(theme_index: int = 0, variant: int = 0) -> void:
	app.mobile_ui = false; app.settings.touch = false; app.adapter.touch_mode = false; app.adapter.configure({})
	var seed_value = 1
	var floor_id = 6 if theme_index == 18 else (11 if theme_index == 19 else 1)
	var theme = app.world.db.expansion.biomes[theme_index]
	while Campaign.biome(app.world.db, "%012d" % seed_value, floor_id).id != theme.id:
		seed_value += 1
	app.begin_run("c_paper", seed_value, false, {"seed_text": "%012d" % seed_value})
	app.set_physics_process(false)
	app.world.run.floor = floor_id
	app.world.run.graph = Campaign.build(app.world.db, "%012d" % seed_value, floor_id)
	app.world.run.room_plan = app.world.run.graph.types.duplicate()
	app.world.run.room = 0; app.world.enter_room()
	app.world.run.graph.backgrounds["0"] = variant
	app.world.geometry.configure_biome(theme.id, variant)
	app.world.geometry.restore_objects([])
	app.world.enemies.clear(); app.world.bullets.clear(); app.world.zones.clear(); app.world.delayed.clear(); app.world.pickups.clear()
	app.world.run.opening_seen = true; app.world.run.relics = {}; app.world.run.talents = []
	app.world.run.active_item = {"id": "a01", "charge": 1.0}
	app.world.player.hp = 4; app.world.player.max_hp = 6
	app.world.player.pos = Vector2(640, 544); app.world.player.aim = Vector2.UP
	app.world.room_flags.wave_index = app.world.room_flags.wave_count
	app.world.mode = "combat"; app.world.take_events()
	app.renderer.set_process(false); app.renderer.clock = 1.25
	app.renderer.visual_effects.clear(); app.renderer.animation.clear()
	app.renderer.reduce_motion = true
	app.screen = "game"; app.paused = false; app.hud.visible = true; app.clear_modal(); app.ui_signature = ""

func drop(kind: String, value: int, point: Vector2) -> Dictionary:
	if kind == "battery": return World.Equipment.spawn(app.world, kind, "battery", point, {}, 0)
	var row = {"uid": app.world.next_uid(), "kind": kind, "pos": point, "value": value,
		"delay": 0.0, "natural": false, "magnet": false}
	app.world.pickups.append(row)
	return row

func display_drops() -> void:
	drop("heal", 2, Vector2(440, 325))
	drop("coin", 1, Vector2(640, 325))
	drop("coin", 2, Vector2(840, 325))
	drop("ash", 8, Vector2(440, 442))
	drop("ash", 30, Vector2(640, 442))
	drop("battery", 1, Vector2(840, 442))
	app.world.take_events()

func capture(name_value: String) -> void:
	var before = digest()
	app.notice_left = 0; app.renderer.queue_redraw()
	await frames(3); await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var saved = image.save_png(directory.path_join(name_value + ".png")) == OK
	var stable = before == digest()
	captures.append({"name": name_value, "saved": saved, "state_stable": stable,
		"theme": app.world.region_spec().id, "variant": app.world.run.graph.backgrounds.get("0", 0),
		"size": [image.get_width(), image.get_height()]})
	expect("capture/" + name_value, saved and stable)

func key(code: int) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)
		if pressed: app._physics_process(1.0 / 60.0)

func behavior() -> void:
	arrange()
	drop("heal", 2, app.world.player.pos)
	app.world.update_pickups(1.0 / 60.0)
	expect("heal_restores_two_and_disappears", app.world.player.hp == 6 and app.world.pickups.is_empty())
	var coins = int(app.world.run.coins)
	drop("heal", 2, app.world.player.pos); app.world.update_pickups(1.0 / 60.0)
	expect("existing_full_health_conversion_is_preserved", app.world.run.coins == coins + 3)
	coins = int(app.world.run.coins)
	for amount in [1, 2]:
		drop("coin", amount, app.world.player.pos); app.world.update_pickups(1.0 / 60.0)
	expect("single_and_pair_coins_collect_exact_values", app.world.run.coins == coins + 3 and app.world.pickups.is_empty())
	app.world.player.energy = 0
	for amount in [8, 30]:
		drop("ash", amount, app.world.player.pos); app.world.update_pickups(1.0 / 60.0)
	expect("small_and_large_ash_collect_exact_values", app.world.player.energy == 38 and app.world.pickups.is_empty())
	var healing = drop("heal", 2, app.world.player.pos + Vector2(26, 0))
	app.world.update_pickups(.02)
	expect("healing_does_not_magnet_outside_24px_radius", not healing.magnet and app.world.pickups.has(healing))
	app.world.mode = "clear"; app.world.update_pickups(.02)
	expect("clearing_room_does_not_auto_absorb_healing", not healing.magnet and app.world.pickups.has(healing))
	app.world.pickups.clear(); app.world.mode = "combat"
	var coin = drop("coin", 1, app.world.player.pos + Vector2(100, 0))
	app.world.update_pickups(.02)
	expect("coin_magnet_moves_same_ground_position", coin.magnet and coin.pos.distance_to(app.world.player.pos) < 100)
	app.world.pickups.clear()
	var guard = app.world.spawn_enemy("e01", Vector2(640, 250))
	guard.speed = 0; guard.attack_cd = 100; guard.arrival = 0
	var core = drop("battery", 1, app.world.player.pos + Vector2(30, 0))
	app.world.update_pickups(.2)
	expect("fire_core_requires_manual_interaction", app.world.pickups.has(core) and not core.magnet and app.world.run.active_item.charge == 1)
	await key(KEY_E)
	expect("keyboard_e_collects_fire_core_once", not app.world.pickups.has(core) and app.world.run.active_item.charge == 2,
		{"charge": app.world.run.active_item.charge, "remaining": app.world.pickups.size(), "screen": app.screen, "paused": app.paused})
	app.world.run.active_item.charge = 3
	core = drop("battery", 1, app.world.player.pos + Vector2(30, 0))
	await key(KEY_E)
	expect("full_charge_leaves_fire_core_on_ground", app.world.pickups.has(core) and app.world.run.active_item.charge == 3)
	arrange(); app.world.build_geometry(app.world.geometry.template_id)
	app.world.player.pos = app.world.geometry.nearest_free(app.world.player.pos, 12)
	display_drops()
	World.Equipment.spawn(app.world, "active", "a02", Vector2(520, 420), {}, 0)
	World.Equipment.spawn(app.world, "trinket", "tr01", Vector2(580, 420), {}, 0)
	World.Equipment.spawn(app.world, "relic", "r01", Vector2(700, 420), {}, 0)
	var storage = Store.new(directory.path_join("pickup-roundtrip"))
	storage.write(app.world.snapshot())
	var resumed = World.new()
	var restored = resumed.restore(storage.read())
	var saved_drops = JSON.stringify(Store.encode(app.world.pickups), "", true, true)
	var resumed_drops = JSON.stringify(Store.encode(resumed.pickups), "", true, true)
	expect("native_save_restores_every_drop_and_quantity", restored and saved_drops == resumed_drops, resumed.pickups.size())
	expect("native_save_restores_entire_simulation_exactly", restored and digest(resumed) == digest())
	if saved_drops != resumed_drops or digest(resumed) != digest():
		FileAccess.open(directory.path_join("save-before.json"), FileAccess.WRITE).store_string(JSON.stringify(Store.encode(app.world.snapshot()), "\t", true, true))
		FileAccess.open(directory.path_join("save-after.json"), FileAccess.WRITE).store_string(JSON.stringify(Store.encode(resumed.snapshot()), "\t", true, true))
	var random_before = digest()
	for index in 12:
		app.renderer.clock = index * .13
		app.renderer.reduce_motion = index % 2 == 0
		app.renderer.queue_redraw(); await frames(1)
	expect("idle_sprite_animation_never_changes_simulation_or_rng", random_before == digest())

func run() -> void:
	await frames(5)
	baseline = OS.get_cmdline_user_args().has("--qa-consumable-baseline")
	if baseline:
		for index in [0, 1, 6, 13]:
			arrange(index); display_drops(); await capture("theme-%02d-a" % (index + 1))
	else:
		for index in 20:
			for variant in 2:
				arrange(index, variant); display_drops()
				await capture("theme-%02d-%s" % [index + 1, "a" if variant == 0 else "b"])
		await behavior()
		arrange(1); display_drops(); app.world.player.pos = Vector2(810, 472)
		app.sync_game_modal(); await capture("fire-core-keyboard-hint")
		arrange(); app.world.mode = "shop"; app.world.run.coins = 20
		app.world.choices = [{"kind": "heal", "id": "heal", "price": 10}, {"kind": "relic", "id": "r01", "price": 10}]
		app.sync_game_modal(); await capture("healing-shop")
		arrange(13); display_drops()
		app.mobile_ui = true; app.settings.touch = true; app.adapter.touch_mode = true
		app.apply_safe_area(); await capture("mobile-hud")
		arrange(1); display_drops(); app.renderer.reduce_motion = false
		for frame in 24:
			app.renderer.clock = frame / 12.0
			await capture("idle-%02d" % frame)
		arrange(13); app.world.player.pos = Vector2(440, 430)
		drop("heal", 2, Vector2(440, 430)); drop("coin", 2, Vector2(535, 430)); drop("ash", 30, Vector2(610, 430))
		app.world.player.energy = 20; app.renderer.reduce_motion = false
		for frame in 24:
			app.renderer.clock = frame / 15.0
			if frame >= 6:
				app.world.player.pos.x = minf(615, 440 + (frame - 6) * 13)
				app.world.update_pickups(1.0 / 15.0); app.flush_events()
				for event in app.renderer.visual_effects.duplicate():
					event.left -= 1.0 / 15.0
					if event.left <= 0: app.renderer.visual_effects.erase(event)
			await capture("collect-%02d" % frame)
		expect("collection_clip_finished_with_real_rewards", app.world.pickups.is_empty() and app.world.player.hp == 6 and app.world.player.energy == 50)
	var passed = checks.all(func(check): return check.passed)
	var report = {"passed": passed, "baseline": baseline, "checks": checks, "captures": captures,
		"engine": Engine.get_version_info().string, "virtualization": "none", "device_tested": false,
		"manifest_sha256": FileAccess.get_sha256("res://assets/pickups/manifest.json") if not baseline else ""}
	var file = FileAccess.open(directory.path_join("native.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n"); file.close()
	print("CONSUMABLE QA: ", checks.size(), " checks, ", captures.size(), " captures, passed=", passed)
	get_tree().quit(0 if passed else 1)
