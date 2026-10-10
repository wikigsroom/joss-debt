extends SceneTree
## These are screenshots of the real renderer, not synthetic sprite previews.
const Actions = preload("res://scripts/combat/creature_actions.gd")
var app
var folder = ""
var selected: PackedStringArray = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--creature-output="): folder = argument.trim_prefix("--creature-output=")
		if argument.begins_with("--creature-ids="): selected = argument.trim_prefix("--creature-ids=").split(",")
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
	var count = 0
	var records: Array = []
	for identity in selected:
		var entry = app.renderer.animation.creature_actions[identity]
		for state in entry.states:
			for direction in Actions.DIRECTIONS:
				var aim = {"down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP}[direction]
				for column in range(6):
					app.world.start("c_paper", 20261009)
					app.world.enemies.clear()
					app.world.bullets.clear()
					app.world.zones.clear()
					app.world.delayed.clear()
					app.world.events.clear()
					app.world.mode = "combat"
					app.world.time = 10
					app.world.run.campaign = false
					var enemy: Dictionary
					if identity.begins_with("b"):
						enemy = app.world.spawn_boss(identity, Vector2(640, 420))
					elif identity.begins_with("x"):
						var variant = app.world.db.row("elite_variants", identity)
						enemy = app.world.spawn_enemy(variant.base_enemy, Vector2(640, 420), true, false, identity)
					else:
						enemy = app.world.spawn_enemy("e01" if identity == "sigil" else identity, Vector2(640, 420))
						if identity == "sigil":
							enemy.sigil = true
							enemy.sprite_id = "sigil"
					app.world.enemies = [enemy]
					enemy.aim = aim
					app.world.player.pos = enemy.pos + aim * 220
					enemy.target = app.world.player.pos
					enemy.hit_flash = 0
					enemy.phase = {"attack_a": 0, "attack_b": 1, "attack_c": 2}.get(state, 0)
					if state == "attack_c": enemy.attack_step = 1 if identity == "b03" else 2
					if state == "hurt":
						app.world.damage_enemy(enemy, 1, "primary")
						app.world.time += (column + .05) / Actions.HURT_FPS
						enemy.hit_flash = maxf(0, .07 - (app.world.time - 10))
					elif column < 2:
						enemy.windup = enemy.tell
						Actions.prepare(enemy, app.world.time)
						if column == 1:
							enemy.windup = float(enemy.tell) * .35
							app.world.time += float(enemy.tell) * .65
					else:
						app.world.enemy_attack(enemy)
						var lunging = float(enemy.lunge) > 0
						if lunging and column >= 3:
							var duration = float(enemy.lunge)
							app.world.player.invulnerable = 100
							app.world.time += duration + .00001
							app.world.update_enemies(duration + .00001)
						app.world.time += (column - (3 if lunging and column >= 3 else 2) + .05) * Actions.RELEASE_FRAME_TIME
					app.world.events.clear()
					app.world.bullets.clear()
					app.world.zones.clear()
					app.world.enemies = [enemy]
					app.renderer.actor_freeze.clear()
					app.renderer.visual_effects.clear()
					app.renderer.clock = app.world.time
					var pose = Actions.sample(enemy, app.world.time, app.world.player.pos)
					if pose.state != state or pose.frame != column or pose.direction != direction:
						push_error("Native capture selected the wrong creature state/frame/facing: %s / %s / %s / %d" % [identity, state, direction, column])
						quit(1)
						return
					app.world.player.pos = Vector2(-10000, -10000)
					app.renderer.queue_redraw()
					await process_frame
					await RenderingServer.frame_post_draw
					var screenshot = root.get_texture().get_image()
					var ground = app.renderer.stage * enemy.pos
					var origin = Vector2i(ground) - Vector2i(160, 248)
					origin.x = clampi(origin.x, 0, screenshot.get_width() - 320)
					origin.y = clampi(origin.y, 0, screenshot.get_height() - 320)
					var filename = "%s-%s-%s-%d.png" % [identity, state, direction, column]
					screenshot.get_region(Rect2i(origin, Vector2i(320, 320))).save_png(folder.path_join(filename))
					records.append({"file": filename, "actor": identity, "state": state, "direction": direction, "frame": column})
					count += 1
		app.renderer.animation.clear()
	var file = FileAccess.open(folder.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"actors": selected, "frames": records, "count": count, "source": "actual Godot game_renderer.draw_enemy", "virtualization": "none"}, "\t") + "\n")
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(.25).timeout
	print("Captured %d actual native creature action frames." % count)
	quit()
