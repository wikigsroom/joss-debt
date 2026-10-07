extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Motion = preload("res://scripts/ui/weapon_motion.gd")
const Paper = preload("res://scripts/ui/paper_animation.gd")
const Store = preload("res://scripts/core/save_store.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("run_suite")

func expect(value: bool, message: String) -> void:
	checks.append(message)
	if not value:
		failures.append(message)
		push_error(message)

func digest(world) -> String:
	return JSON.stringify(Store.encode(world.snapshot()), "", true, true).sha256_text()

func sandbox(actor: String = "c_paper"):
	var world = World.new()
	world.start(actor, 4191)
	world.enemies.clear()
	world.events.clear()
	return world

func run_suite() -> void:
	var motion = Motion.new()
	var paper = Paper.new()
	expect(motion.manifest.actors.size() == 6 and motion.manifest.weapons.size() == 32, "all six approved identities and thirty-two held weapon textures have a rig")
	var states_ok = true
	var frame_count = 0
	for actor in motion.manifest.actors:
		for state in Paper.COUNTS.character:
			for direction in ["down", "left", "right", "up"]:
				for frame in int(Paper.COUNTS.character[state]):
					var elapsed = (frame + .1) / Paper.FPS[state]
					var body = paper.texture(actor, "weapon_body", state, elapsed, direction)
					var hands = paper.texture(actor, "weapon_hand", state, elapsed, direction)
					states_ok = states_ok and body != null and hands != null and body.get_width() == 96 and hands.get_height() == 96
					frame_count += 1
	expect(states_ok and frame_count == 576, "576 actual body/hand frame pairs load for every state and facing")
	var shots_ok = true
	var geometry_ok = true
	var combos = 0
	for actor in motion.manifest.actors:
		for weapon in motion.manifest.weapons:
			var world = sandbox(actor)
			world.player.weapon = weapon
			world.time = 4
			world.shoot_input(true, 1.0)
			var shot = world.events.filter(func(e): return e.kind == "shot")
			shots_ok = shots_ok and shot.size() == 1 and shot[0].weapon == weapon
			motion.accept(world.events, world)
			world.time += .03
			var before = digest(world)
			var pose = motion.sample(world)
			shots_ok = shots_ok and pose.weapon == weapon and pose.attack and pose.state == "cast" and digest(world) == before
			for direction in ["down", "left", "right", "up"]:
				var grips = motion.placements(actor, direction, pose)
				geometry_ok = geometry_ok and grips.size() == (2 if weapon == "w02" else 1)
				for grip in grips:
					geometry_ok = geometry_ok and grip.point.is_finite() and absf(grip.point.x) < 49 and grip.point.y >= -81 and grip.point.y < 16 and grip.size > 0
					geometry_ok = geometry_ok and grip.behind == (direction == "up") and grip.weapon == weapon
			combos += 1
	expect(combos == 192 and shots_ok, "192 real equipped-weapon attack events select the matching pose without writing combat state")
	expect(geometry_ok, "all 768 facing/equipment layouts stay on valid animated wrists with deliberate back-view depth")
	var directional_shots_ok = true
	for direction in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		var directional_world = sandbox()
		directional_world.player.shot_cd = 0
		directional_world.tick({"aim": direction, "move": direction, "fire": true})
		var directional_shot = directional_world.events.filter(func(event): return event.kind == "shot")
		directional_shots_ok = directional_shots_ok and directional_shot.size() == 1
		directional_shots_ok = directional_shots_ok and directional_world.player.facing_direction.is_equal_approx(direction)
		directional_shots_ok = directional_shots_ok and directional_world.player.last_shot_direction.is_equal_approx(direction)
		motion.accept(directional_world.events, directional_world)
		directional_world.time += .08
		var directional_pose = motion.sample(directional_world)
		directional_shots_ok = directional_shots_ok and directional_pose.aim.is_equal_approx(direction)
	expect(directional_shots_ok, "four real aim directions update the player's body facing, shot direction and held-tool pose")
	var world = sandbox()
	world.time = 5
	world.shoot_input(true, .02)
	motion.accept(world.events, world)
	world.time += .08
	var frozen = motion.sample(world)
	world.mode = "choice"
	for i in 200:
		world.tick({"fire": true})
		motion.sample(world)
	expect(motion.sample(world) == frozen and is_equal_approx(world.time, 5.08), "an actual choice pause freezes the complete primary attack pose")
	world.time += .5
	expect(not motion.sample(world).attack and motion.sample(world).state == "idle", "a primary attack returns to the neutral equipped idle pose")
	world.mode = "shop"
	world.choices = [{"kind": "weapon", "id": "w12", "price": 0, "taken": false, "slot": "rig-fixture"}]
	expect(world.take_choice(0), "the normal reward transaction equips a replacement weapon")
	motion.accept(world.events, world)
	expect(motion.sample(world).weapon == "w12" and not motion.sample(world).attack, "equipping clears the previous tool's attack immediately")
	motion.accept([{"kind": "shot", "weapon": "w01", "at": world.time, "dir": Vector2.RIGHT}], world)
	expect(not motion.sample(world).attack, "a delayed old-weapon event cannot animate the replacement")
	world.player.shot_cd = 0
	world.shoot_input(true, .02)
	motion.accept(world.events, world)
	world.time += .08
	var full_motion = motion.sample(world)
	var reduced = motion.sample(world, true)
	expect(full_motion.attack and not is_zero_approx(full_motion.angle) and reduced.angle == 0 and reduced.scale == 1, "reduce-motion keeps equipment and attack identity while removing recoil and swinging")
	world.player.visual_hurt_at = world.time
	expect(motion.sample(world).state == "hurt" and not motion.sample(world).attack, "the existing injury pose takes priority over an active primary attack")
	world.player.visual_hurt_at = -999
	world.start_dash(Vector2.RIGHT)
	motion.accept(world.events, world)
	expect(motion.sample(world).state == "dash" and motion.last_shot.is_empty(), "a real dash cancels the primary presentation and uses its matching wrist frames")
	world.player.dash_left = 0
	world.player.visual_cast_at = world.time
	expect(motion.sample(world).state == "cast" and not motion.sample(world).attack, "the signature-skill cast retains priority over a handheld attack")
	world.player.visual_cast_at = -999
	world.player.weapon = "w11"
	world.player.shot_cd = 0
	world.events.clear()
	world.shoot_input(true, .15)
	expect(world.events.is_empty() and motion.sample(world).charging, "judgment-brush preparation follows real charging before any shot exists")
	world.shoot_input(false, .016)
	expect(not motion.sample(world).charging and world.player.charge == 0, "releasing a partial charge clears the held preparation immediately")
	world.shoot_input(true, .26)
	motion.accept(world.events, world)
	expect(motion.sample(world).attack and not motion.sample(world).charging, "a completed real charge switches from preparation to its firing pose")
	var resumed = World.new()
	expect(resumed.restore(world.snapshot()), "the attack-time snapshot restores through the actual schema validator")
	expect(not motion.sample(resumed).attack and motion.last_shot.is_empty(), "loading a different world cannot replay an unsaved presentation event")
	resumed.player.hp = 0
	var death = motion.sample(resumed)
	expect(death.state == "death" and not death.held_visible and motion.placements("c_paper", "down", death).is_empty(), "death removes the separate held tool instead of leaving a floating weapon")
	resumed.player.hp = 5
	resumed.time = 10
	motion.accept([{"kind": "shot", "weapon": "w11", "at": 10, "dir": Vector2.RIGHT}], resumed)
	resumed.time = 2
	expect(not motion.sample(resumed).attack, "restoring time backward clears a stale primary pose")
	var a = World.new()
	var b = World.new()
	a.start("c_bell", 7315)
	b.start("c_bell", 7315)
	for i in 360:
		var input = {"move": Vector2(sin(i*.04),cos(i*.04)), "aim": Vector2.RIGHT.rotated(i*.016), "fire": true, "dash": i == 120, "skill": i == 260}
		a.tick(input)
		b.tick(input)
		motion.accept(a.events, a)
		motion.sample(a)
		a.events.clear()
	expect(digest(a) == digest(b), "360 real combat ticks with presentation enabled preserve damage, positions, drops, ledgers and every RNG stream")
	paper.clear()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"combinations": combos, "frame_pairs": frame_count, "scope": "shared native presentation and real combat/reward/restore interfaces; visual rig sheets reviewed separately"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/weapon-motion-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Held weapon motion: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
