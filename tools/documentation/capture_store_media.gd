extends SceneTree
## Native viewport recording from the published executable's embedded resources.
## The harness drives existing combat/UI classes and owns an isolated profile.

class CaptureApp:
	extends "res://scripts/main.gd"
	var capture_root = ""
	var renderer_script = ""
	func _ready() -> void:
		qa_active = true
		font = UI.body_font()
		title_font = UI.display_font()
		save_slots = SaveSlots.new(capture_root.path_join("isolated-profile"))
		save_session = SaveSession.new(save_slots.base_path(1), save_slots.legacy_profile_path(1), save_slots.legacy_run_path(1))
		store = save_session.view("checkpoint")
		progress = Progress.new("", save_session.view("profile"))
		# The current source renderer contains the stale-chain presentation fix.
		# World, UI, audio and artwork remain the published embedded resources.
		renderer = load(renderer_script).new() if not renderer_script.is_empty() else Renderer.new()
		renderer.world = world
		renderer.adapter = adapter
		add_child(renderer)
		renderer.set_process(false)
		audio = Audio.new()
		add_child(audio)
		audio.set_levels(.8, .65, .7)
		var layer = CanvasLayer.new()
		add_child(layer)
		interface = Control.new()
		interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(interface)
		var theme = Theme.new()
		UI.install(theme)
		interface.theme = theme
		hud = Control.new()
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		interface.add_child(hud)
		modal = Control.new()
		modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		interface.add_child(modal)
		orientation_overlay = Control.new()
		orientation_overlay.visible = false
		interface.add_child(orientation_overlay)
		build_hud()
		set_process(false)
		set_physics_process(false)
	func capture_events() -> void:
		var events = world.take_events()
		renderer.accept(events)
		audio.accept(events)
		# Public capture does not observe achievements or write a player save slot.
	func _unhandled_input(_event: InputEvent) -> void: pass

var output = ""
var scenario = "gameplay"
var seconds = 120.0
var bot
var app
var report: Dictionary = {}
var movie_frame = 0
var mode_key = ""
var mode_frames = 0
var physics_tick = 0
var choice_delay = 1.4
var seed_cache: Dictionary = {}
var renderer_script = ""

func _initialize() -> void:
	# Exported project uses a 1280x720 logical canvas. Keep that layout while
	# recording a native 1920x1080 framebuffer, rather than enlarging screenshots.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1920, 1080)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--scenario="): scenario = argument.trim_prefix("--scenario=")
		if argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		if argument.begins_with("--bot-script="): bot = load(argument.trim_prefix("--bot-script="))
		if argument.begins_with("--renderer-script="): renderer_script = argument.trim_prefix("--renderer-script=")
	if output.is_empty() or bot == null: quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("record")

func seed_for(biome_id: String, floor_id: int = 1) -> int:
	var key = biome_id + str(floor_id)
	if seed_cache.has(key): return seed_cache[key]
	for value in range(6327, 20000):
		var text = "%012d" % value
		if app.world.Campaign.biome(app.world.db, text, floor_id).id == biome_id:
			seed_cache[key] = value
			return value
	return 6327

func arrange(character: String, seed_value: int, floor_id: int = 1, role: String = "combat", weapon: String = "", relics: Dictionary = {}) -> void:
	app.world.start(character, seed_value, 11, {"seed_text": "%012d" % seed_value})
	if floor_id != 1:
		app.world.run.floor = floor_id
		app.world.run.graph = app.world.Campaign.build(app.world.db, app.world.run.seed_text, floor_id)
		app.world.run.room_plan = app.world.run.graph.types.duplicate()
	if role != "combat": app.world.run.room = maxi(0, app.world.run.room_plan.find(role))
	app.world.enter_room()
	app.world.run.opening_seen = true
	if not weapon.is_empty():
		app.world.player.weapon = weapon
		app.world.record_growth_choice("weapon", weapon, "weapon", weapon, 0, 0, "choice")
	for id in relics:
		app.world.run.relics[id] = relics[id]
		app.world.record_growth_choice("relic", id, "relic", id, 0, 0, "choice")
	app.screen = "game"
	app.paused = false
	app.hud.visible = true
	app.renderer.hub = false
	app.renderer.visual_effects.clear()
	app.renderer.animation.clear()
	app.renderer.clock = 0.0
	app.clear_modal()
	app.ui_signature = ""
	mode_key = ""
	mode_frames = 0
	physics_tick = 0
	app.capture_events()
	app.sync_game_modal()

func travel() -> Dictionary:
	var w = app.world
	if w.player.hp < w.player.max_hp:
		for pickup in w.pickups:
			if pickup.kind == "heal":
				w.geometry.rebuild_flow(pickup.pos)
				return {"move": w.geometry.toward(w.player.pos, pickup.pos)}
	var doors = w.room_doors()
	var target_room = int(w.run.room) + 1
	for door in doors:
		if door.destination != target_room: continue
		if w.player.pos.distance_to(door.pos) < 14: return {"move": w.direction_vector(door.direction)}
		w.geometry.rebuild_flow(door.pos)
		return {"move": w.geometry.toward(w.player.pos, door.pos)}
	for door in doors:
		if not door.visited:
			w.geometry.rebuild_flow(door.pos)
			return {"move": w.geometry.toward(w.player.pos, door.pos)}
	return {}

func tick_world() -> void:
	var w = app.world
	var before = "%d/%d" % [w.run.floor, w.run.room]
	match str(w.mode):
		"combat":
			var input = bot.frame(w)
			input.active_item = w.Equipment.use_reason(w).is_empty() and (w.enemies.size() >= 3 or w.enemies.any(func(e): return e.boss))
			w.tick(input, 1.0 / 60)
		"clear": w.tick(travel(), 1.0 / 60)
		"choice":
			if mode_frames >= int(choice_delay * 30):
				if not w.take_choice(bot.choose(w, 0)):
					var available = -1
					for i in w.choices.size():
						if w.choice_reason(w.choices[i]).is_empty(): available = i; break
					if available >= 0: w.take_choice(available)
					else: w.skip_choice()
		"shop", "debt":
			if mode_frames >= 45:
				if w.mode == "shop" and w.player.hp < w.player.max_hp: w.take_choice(2)
				w.skip_choice()
		"replace":
			if mode_frames >= 45: w.replace_relic(w.run.relics.keys()[0])
		"checkpoint":
			if mode_frames >= 45: w.advance_room()
		"transition":
			if mode_frames >= 60: w.continue_transition()
		"epilogue":
			if mode_frames >= 60: w.finish_epilogue()
		"result":
			if scenario == "gameplay" and mode_frames >= 75:
				report.restarts += 1
				arrange("c_paper", 6327 + int(report.restarts))
	if before != "%d/%d" % [w.run.floor, w.run.room]:
		report.transitions.append({"movie_time": movie_frame / 30.0, "from": before, "to": "%d/%d" % [w.run.floor, w.run.room]})
	physics_tick += 1
	app.capture_events()

func refresh() -> void:
	var key = "%s/%d/%d/%s" % [app.world.mode, app.world.run.floor, app.world.run.room, JSON.stringify(app.world.choices)]
	if key != mode_key:
		mode_key = key
		mode_frames = 0
		if app.screen == "game": app.sync_game_modal()
	else: mode_frames += 1
	app.renderer.combat_interface_visible = app.screen == "game" and not app.paused and app.world.mode in ["combat", "clear"]
	app.renderer._process(1.0 / 30)
	app.update_hud()
	app.audio.set_paused(app.paused)
	app.audio.observe(app.world, app.screen)

func screenshot(name_value: String, description: String, staged = true) -> void:
	app.notice_left = 0
	app.update_hud()
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	var path = output.path_join(name_value + ".png")
	var im = root.get_texture().get_image()
	var saved = im.save_png(path) == OK
	report.screenshots.append({"filename": name_value + ".png", "description": description, "saved": saved,
		"size": [im.get_width(), im.get_height()], "character": app.world.run.character,
		"theme": app.world.region_spec().id, "floor": app.world.run.floor, "mode": app.world.mode,
		"method": "Native embedded rendering and UI; prepared in-engine showcase" if staged else "Native normal run"})
	print("Store screenshot: ", name_value)

func animate(frames_count: int) -> void:
	for i in frames_count:
		for j in 2: tick_world()
		refresh()
		await process_frame

func capture_attack(name_value: String, description: String, effect_kind: String) -> void:
	for i in 180:
		for j in 2: tick_world()
		refresh()
		await process_frame
		if app.world.mode == "combat" and app.renderer.visual_effects.any(func(e): return e.kind == effect_kind and e.left > .06):
			await screenshot(name_value, description)
			return
	await screenshot(name_value, description)

func capture_boss_action() -> void:
	for i in 210:
		for j in 2: tick_world()
		refresh()
		await process_frame
		if app.world.bullets.filter(func(b): return not b.friendly).size() >= 5 or app.world.zones.filter(func(z): return not z.friendly).size() >= 2:
			await screenshot("08-magistrate-boss", "守名判殿·首领战")
			return
	await screenshot("08-magistrate-boss", "守名判殿·首领战")

func capture_screenshots() -> void:
	arrange("c_paper", seed_for("m01"))
	await animate(70)
	await screenshot("01-paper-child-combat", "纸童·灯市实战", false)
	app.show_menu("characters")
	await screenshot("02-character-selection", "六名还愿人·角色选择")
	arrange("c_umbrella", seed_for("m02"), 1, "challenge")
	await animate(75)
	await screenshot("03-river-returning-umbrella", "纸渡河埠·回旋纸伞")
	arrange("c_paper", seed_for("m03", 3), 3, "challenge", "w14", {"r55": 1, "r57": 1, "r58": 1})
	await capture_attack("04-treasury-composed-beams", "铜钱旧库·散射射线构筑", "ray")
	arrange("c_lantern", seed_for("m06", 2), 2, "challenge")
	await animate(60)
	await screenshot("05-opera-flame-lantern", "赤绫戏楼·流火战斗")
	arrange("c_bell", seed_for("m08", 3), 3, "challenge", "w21")
	await animate(48)
	await screenshot("06-thunder-gate-lightning", "雷鼓山门·雷霆器具")
	arrange("c_mask", seed_for("m13"), 1, "challenge", "w12")
	await animate(50)
	await screenshot("07-bamboo-melee", "竹影契林·近战灰骨刃")
	arrange("c_paper", 6327, 6, "boss", "w08", {"r09": 1, "r55": 1, "r26": 1})
	await capture_boss_action()
	arrange("c_paper", seed_for("m01"), 1, "shop")
	app.world.run.coins = 60
	app.sync_game_modal()
	await screenshot("09-lantern-shop", "灯摊·器具与供物")
	arrange("c_paper", seed_for("m03"))
	app.world.enemies.clear()
	app.world.choice_queue = [{"kind": "relic", "items": app.world.relic_offer(3)}]
	app.world.open_next_choice()
	app.sync_game_modal()
	await screenshot("10-relic-choice", "供物选择·构筑分歧")
	arrange("c_paper", 6327, 11, "challenge", "w30", {"r55": 1, "r59": 1, "r26": 1})
	await animate(30)
	await screenshot("11-celestial-prism", "万愿天穹·裂空铜镜")
	arrange("c_paper", 6327, 6, "combat", "w14", {"r55": 1, "r57": 1, "r58": 1, "r26": 1})
	app.RouteMap.show_sheet(app)
	await screenshot("12-eleven-floor-map", "十一重旧账·完整行路图")

func record() -> void:
	app = CaptureApp.new()
	app.capture_root = output
	app.renderer_script = renderer_script
	root.add_child(app)
	report = {"scenario": scenario, "fps": 30, "simulation_hz": 60, "requested_seconds": seconds,
		"screenshots": [], "transitions": [], "restarts": 0, "segments": [], "source": "published executable embedded game resources",
		"method": "Action-bot control of native game simulation; native MovieWriter with game BGM/SFX; isolated capture profile"}
	for i in 2: await process_frame
	if scenario == "screenshots":
		await capture_screenshots()
	else:
		arrange("c_paper", 6327)
		report.initial_player = app.world.player.duplicate(true)
		report.leading_frames = Engine.get_process_frames()
		var demo = [
			{"character": "c_paper", "theme": "m01", "floor": 1, "weapon": "w01", "relics": {"r01": 1, "r09": 1}},
			{"character": "c_bell", "theme": "m06", "floor": 2, "weapon": "w02", "relics": {"r09": 1}},
			{"character": "c_paper", "theme": "m03", "floor": 3, "weapon": "w14", "relics": {"r55": 1, "r57": 1, "r58": 1}},
			{"character": "c_umbrella", "theme": "m02", "floor": 2, "weapon": "w05", "relics": {"r17": 1, "r33": 1}},
			{"character": "c_paper", "theme": "m19", "floor": 6, "weapon": "w08", "relics": {"r09": 1, "r55": 1, "r26": 1}}]
		for frame_id in int(seconds * 30):
			movie_frame = frame_id
			if scenario == "showcase" and frame_id % 240 == 0:
				var scene_id = mini(demo.size() - 1, frame_id / 240)
				var d = demo[scene_id]
				arrange(d.character, seed_for(d.theme, d.floor), d.floor, "boss" if d.floor == 6 else "challenge", d.weapon, d.relics)
				report.segments.append({"start": frame_id / 30.0, "duration": 8.0, "character": d.character, "theme": d.theme, "weapon": d.weapon, "prepared_relics": d.relics})
			for j in 2: tick_world()
			refresh()
			if frame_id % 300 == 0:
				print("Store movie: ", frame_id / 30.0, "s; ", app.world.mode, "; floor ", app.world.run.floor, " room ", app.world.run.room, " hp ", app.world.player.hp)
				await RenderingServer.frame_post_draw
				var sample_name = "sample-%03d.png" % (frame_id / 30)
				root.get_texture().get_image().save_png(output.path_join(sample_name))
				report.screenshots.append({"filename": sample_name, "movie_time": frame_id / 30.0, "mode": app.world.mode, "health": app.world.player.hp, "shots": app.world.stats.shots})
			await process_frame
		report.final_stats = app.world.stats
		report.final_health = app.world.player.hp
		report.frames_driven = int(seconds * 30)
	FileAccess.open(output.path_join("capture-report.json"), FileAccess.WRITE).store_string(JSON.stringify(app.Store.encode(report), "\t"))
	app.audio.set_muted(true)
	bot.navigation = null
	root.remove_child(app)
	app.free()
	app = null
	bot = null
	await process_frame
	quit(0)
