extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Actions = preload("res://scripts/combat/creature_actions.gd")
const Paper = preload("res://scripts/ui/paper_animation.gd")
const Store = preload("res://scripts/core/save_store.gd")
const BossPattern = preload("res://scripts/combat/boss_patterns.gd")
var failures: Array = []
var checks: Array = []
var output = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--creature-report="): output = argument.trim_prefix("--creature-report=")
	call_deferred("run_suite")

func expect(value: bool, label: String) -> void:
	checks.append({"name": label, "passed": value})
	if not value:
		failures.append(label)
		push_error(label)

func reset_arena(world) -> void:
	world.enemies.clear()
	world.bullets.clear()
	world.zones.clear()
	world.delayed.clear()
	world.events.clear()
	world.room_flags.summoned = 0
	world.room_flags.summon_rewards = 0
	world.time = 10
	world.player.invulnerable = 100
	world.mode = "combat"

func digest(world) -> String:
	return JSON.stringify(Store.encode(world.snapshot()), "", true, true).sha256_text()

func verify_action(world, enemy: Dictionary, aim: Vector2) -> bool:
	world.player.pos = enemy.pos + aim * 180
	enemy.aim = aim
	enemy.target = world.player.pos
	enemy.attack_cd = 0
	world.update_enemies(1.0 / 60)
	var start = Actions.sample(enemy, world.time, world.player.pos)
	var expected_state = Actions.next_attack_state(enemy)
	var ok = start.frame == 0 and start.state == expected_state and start.direction == Actions.facing(aim)
	world.time += float(enemy.tell) * .65
	world.update_enemies(float(enemy.tell) * .65)
	var prepare = Actions.sample(enemy, world.time, world.player.pos)
	ok = ok and prepare.frame == 1 and prepare.state == expected_state
	world.time += float(enemy.windup) + .00001
	world.update_enemies(float(enemy.windup) + .00001)
	var lunging = float(enemy.lunge) > 0
	for frame in range(2, 6):
		var sampled_time = world.time + (frame - 2 + .1) * Actions.RELEASE_FRAME_TIME
		if lunging and frame == 3:
			var duration = float(enemy.lunge)
			world.time += duration + .00001
			world.update_enemies(duration + .00001)
		if lunging and frame >= 3: sampled_time = world.time + (frame - 3 + .1) * Actions.RELEASE_FRAME_TIME
		var before = digest(world)
		var pose = Actions.sample(enemy, sampled_time, world.player.pos + Vector2(60, 40))
		ok = ok and pose.frame == frame and pose.state == expected_state and pose.direction == Actions.facing(aim) and digest(world) == before
		# A subsequent phase change must not switch an already released strip.
		var original_phase = enemy.phase
		enemy.phase = (int(enemy.phase) + 1) % 3
		ok = ok and Actions.sample(enemy, sampled_time, world.player.pos).state == expected_state
		enemy.phase = original_phase
	return ok

func run_suite() -> void:
	var world = World.new()
	world.start("c_paper", 81925)
	var roster_ok = true
	var real_attacks = 0
	for spec in world.db.rows("enemies"):
		for aim in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
			reset_arena(world)
			var enemy = world.spawn_enemy(spec.id, Vector2(640, 360))
			roster_ok = verify_action(world, enemy, aim) and roster_ok
			real_attacks += 1
	expect(roster_ok and real_attacks == 1184, "all 296 enemy identities perform continuous ready/prepare/strike/recovery in four actual attack directions without sampling changing world/RNG")
	var bosses_ok = true
	var boss_attacks = 0
	for spec in world.db.rows("bosses"):
		var scenarios = [[0, 0], [1, 0], [2, 0], [1, 1], [2, 2]]
		for scenario in scenarios:
			for aim in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
				reset_arena(world)
				var enemy = world.spawn_boss(spec.id, Vector2(640, 360))
				enemy.phase = scenario[0]
				enemy.attack_step = scenario[1]
				bosses_ok = verify_action(world, enemy, aim) and bosses_ok
				boss_attacks += 1
	expect(bosses_ok and boss_attacks == 1980, "all 99 bosses select the real primary, secondary or combined attack bank across phases and alternating attack steps")
	var elite_ok = true
	world.run.campaign = false
	for variant in world.db.rows("elite_variants"):
		for aim in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
			reset_arena(world)
			var enemy = world.spawn_enemy(variant.base_enemy, Vector2(640, 360), true, false, variant.id)
			elite_ok = elite_ok and enemy.sprite_id == variant.id and verify_action(world, enemy, aim)
	expect(elite_ok, "all six authored elite variants retain their own sprite identities and actual attacks in four directions")
	reset_arena(world)
	var boss = world.spawn_boss("b04", Vector2(640, 360))
	var clones = world.enemies.filter(func(enemy): return enemy.get("clone", false))
	var clone_ok = clones.size() == 2
	for clone in clones:
		world.enemy_attack(clone)
		clone_ok = clone_ok and Actions.sample(clone, world.time, world.player.pos).state == "attack_a"
	expect(clone_ok, "real b04 summoned doubles map enemy combat attacks to their boss appearance's attack_a bank")
	reset_arena(world)
	boss = world.spawn_boss("b01", Vector2(640, 360))
	BossPattern.sigils(world, boss, 1)
	var signs = world.enemies.filter(func(enemy): return enemy.get("sigil", false))
	world.time += 1
	world.enemy_attack(signs[0])
	expect(signs.size() == 1 and signs[0].sprite_id == "sigil" and Actions.sample(signs[0], world.time, world.player.pos).state == "attack", "actual loan-note summons receive the independent sigil action bank")
	var hurt_ok = true
	for aim in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		reset_arena(world)
		var enemy = world.spawn_enemy("e02", Vector2(640, 360))
		world.player.pos = enemy.pos + aim * 180
		enemy.aim = aim
		world.damage_enemy(enemy, 1, "primary")
		for frame in range(6):
			var pose = Actions.sample(enemy, world.time + (frame + .1) / Actions.HURT_FPS, world.player.pos)
			hurt_ok = hurt_ok and pose.state == "hurt" and pose.frame == frame and pose.direction == Actions.facing(aim)
		var healed_pose = Actions.sample(enemy, world.time + Actions.HURT_DURATION + .001, world.player.pos)
		hurt_ok = hurt_ok and healed_pose.state != "hurt"
	expect(hurt_ok, "real damage traverses all six hurt frames in four facings before returning to locomotion")
	reset_arena(world)
	var actor = world.spawn_enemy("e02", Vector2(640, 360))
	actor.aim = Vector2.LEFT
	actor.windup = actor.tell
	Actions.prepare(actor, world.time)
	var pose_before = Actions.sample(actor, world.time, world.player.pos)
	var frozen_time = world.time
	world.mode = "choice"
	for i in 120: world.tick({"fire": true})
	expect(world.time == frozen_time and Actions.sample(actor, world.time, world.player.pos) == pose_before, "an actual reward pause freezes creature anticipation and facing")
	world.mode = "combat"
	world.enemy_attack(actor)
	actor.windup = 0
	world.time += .09
	pose_before = Actions.sample(actor, world.time, world.player.pos)
	var loaded = World.new()
	var restored = loaded.restore(world.snapshot())
	expect(restored and Actions.sample(loaded.enemy_by_uid(actor.uid), loaded.time, loaded.player.pos) == pose_before, "an actual saved run restores the in-flight action bank, frame and facing")
	var bad = world.snapshot()
	bad.enemies[0].visual_attack_facing = "invalid-direction"
	expect(not loaded.restore(bad), "a malformed saved creature facing is rejected before resuming the run")
	reset_arena(world)
	actor = world.spawn_boss("b06", Vector2(640, 360))
	actor.phase = 1
	actor.attack_step = 1
	world.enemy_attack(actor)
	actor.erase("visual_attack_state")
	actor.erase("visual_attack_facing")
	expect(Actions.sample(actor, world.time + .08, world.player.pos).state == "attack_a", "older v2 saves infer the completed boss pattern from the stored attack step")
	reset_arena(world)
	actor = world.spawn_enemy("e02", Vector2(640, 360))
	world.enemy_attack(actor)
	expect(Actions.sample(actor, world.time + .4, world.player.pos).frame == 2, "real melee lunges retain their extended strike pose until collision movement ends")
	world.time += float(actor.lunge) + .00001
	world.update_enemies(float(actor.lunge) + .00001)
	expect(Actions.sample(actor, world.time + .01, world.player.pos).frame == 3, "melee follow-through starts after the actual lunge completes")
	reset_arena(world)
	actor = world.spawn_enemy("e03", Vector2(640, 360))
	world.enemy_attack(actor)
	world.damage_enemy(actor, 1, "primary")
	expect(Actions.sample(actor, world.time + .03, world.player.pos).state == "attack", "simultaneous ordinary damage does not hide a real projectile release")
	expect(Actions.sample(actor, world.time + .1, world.player.pos).state == "hurt", "the damage recoil remains visible after the release pose")
	reset_arena(world)
	actor = world.spawn_enemy("e18", Vector2(640, 360))
	actor.aim = Vector2.UP
	world.enemy_attack(actor)
	world.time += .7
	world.update_delayed(1.0 / 60)
	expect(Actions.sample(actor, world.time, world.player.pos).frame == 2 and actor.visual_attack_facing == "up", "a real delayed enemy fan restarts the strike pose when its projectiles are emitted")
	var paper = Paper.new()
	var loaded_frames = 0
	var atlas_ok = true
	var atlas_failures: Array = []
	for identity in paper.creature_actions:
		var entry = paper.creature_actions[identity]
		for state in entry.states:
			for row in range(4):
				for frame in range(6):
					var texture = paper.texture(identity, "boss" if identity.begins_with("b") else "enemy", state, 0, Actions.DIRECTIONS[row], frame)
					var expected_region = Rect2(frame * entry.frame_size, row * entry.frame_size, entry.frame_size, entry.frame_size)
					var frame_ok = texture != null and texture.region == expected_region
					atlas_ok = atlas_ok and frame_ok
					if not frame_ok:
						atlas_failures.append({"identity": identity, "state": state, "direction": Actions.DIRECTIONS[row], "frame": frame, "expected": str(expected_region), "actual": "missing" if texture == null else str(texture.region)})
					loaded_frames += 1
		paper.clear()
	expect(atlas_ok and loaded_frames > 0, "all currently installed independently drawn action poses load as actual native textures with the requested direction and frame")
	var alias = paper.texture("b01", "enemy", "attack", 0, "left", 4)
	expect(alias != null and alias.region == Rect2(1024, 256, 256, 256), "boss appearance aliases resolve the boss atlas and left-facing row for enemy-kind summons")
	var result = {"checks": checks, "failures": failures, "real_enemy_attacks": real_attacks, "real_boss_attacks": boss_attacks,
		"installed_creature_identities": paper.creature_actions.size(), "loaded_independent_poses": loaded_frames,
		"scope_complete": paper.creature_actions.size() == 402, "atlas_failures": atlas_failures, "virtualization": "none"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t") + "\n")
	print("Creature actions: %d checks; %d failures; native atlas coverage %d / 402" % [checks.size(), failures.size(), paper.creature_actions.size()])
	quit(0 if failures.is_empty() else 1)
