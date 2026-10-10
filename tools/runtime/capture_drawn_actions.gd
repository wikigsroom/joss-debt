extends SceneTree
## Capture the actual shipping actor/equipment/FX render path, cropped after drawing.
var app
var folder = ""
var states = ["idle","run","cast","dash","hurt","death"]
var actors = ["c_paper","c_bell","c_lantern","c_mask","c_umbrella","c_ink"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--action-output="): folder = argument.trim_prefix("--action-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("capture_actions")

func capture_actions() -> void:
	app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.qa_capture_enabled = false
	app.qa_active = true
	app.set_physics_process(false)
	app.set_process(false)
	app.renderer.set_process(false)
	app.audio.set_muted(true)
	app.renderer.hub = false
	app.renderer.combat_interface_visible = false
	app.hud.visible = false
	app.paused = false
	app.screen = "game"
	app.clear_modal()
	for actor in actors:
		app.world.start(actor,20261009)
		app.world.enemies.clear()
		app.world.events.clear()
		app.world.mode = "combat"
		app.world.player.pos = Vector2(640,420)
		for state in states:
			for column in 6:
				var fps = app.renderer.animation.CHARACTER_FPS[state]
				var age = (column + .05)/float(fps)
				if state == "cast":
					var weapon = app.world.db.row("weapons", app.world.player.weapon)
					age = age / .333 * minf(.334, float(weapon.interval_s) * .85)
				app.world.time = age if state in ["idle","run"] else 5 + age
				app.world.player.hp = 0 if state == "death" else 6
				app.world.player.move = Vector2.RIGHT if state == "run" else Vector2.ZERO
				app.world.player.aim = Vector2.DOWN
				app.world.player.facing_direction = Vector2.DOWN
				app.world.player.visual_cast_at = -999
				app.world.player.visual_hurt_at = 5 if state == "hurt" else -999
				app.world.player.dash_left = maxf(.001,.2-age) if state == "dash" else 0
				app.renderer.clock = app.world.time
				app.renderer.player_death_clock = 5
				app.renderer.visual_effects.clear()
				app.renderer.weapon_motion.clear()
				if state == "cast":
					app.renderer.weapon_motion.accept([{"kind":"shot","weapon":app.world.player.weapon,"at":5,"dir":Vector2.DOWN}],app.world)
					app.renderer.visual_effects.append({"kind":"shot","pos":app.world.player.pos,"mode":"orb","dir":Vector2.DOWN,"left":.334-age,"total":.334})
				if state == "hurt": app.renderer.visual_effects.append({"kind":"player_hurt","pos":app.world.player.pos,"left":.334-age,"total":.334})
				app.renderer.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var image = root.get_texture().get_image()
				var ground = app.renderer.stage * app.world.player.pos
				var bounds = Rect2i(Vector2i(ground)-Vector2i(96,144),Vector2i(192,192))
				image.get_region(bounds).save_png(folder.path_join("%s-%s-%d.png"%[actor,state,column]))
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(.25).timeout
	print("Captured 216 native action/equipment/FX frames.")
	quit()
