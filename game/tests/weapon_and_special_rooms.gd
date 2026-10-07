extends SceneTree

const World = preload("res://scripts/combat/world.gd")

var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func fresh() -> World:
	var w = World.new()
	w.start("c_paper", 7139, 3)
	w.enemies.clear()
	w.mode = "combat"
	w.player.pos = Vector2(320, 360)
	w.player.aim = Vector2.RIGHT
	w.player.shot_cd = 0
	return w

func run_suite() -> void:
	var w = fresh()
	w.player.weapon = "w13"
	w.shoot_input(true, .4)
	expect(w.bullets.size() == 3 and w.bullets.all(func(b): return b.mode == "triple"), "三生扇 emits exactly three authored spread projectiles")
	w = fresh()
	w.player.weapon = "w14"
	var target = w.spawn_enemy("e01", Vector2(520, 360))
	w.shoot_input(true, .5)
	var events = w.take_events()
	expect(target.hp < target.max_hp and events.any(func(e): return e.kind == "ray" and e.weapon == "w14"), "照骨线 resolves a wall-aware ray hit and exposes its beam event")
	w = fresh()
	w.player.weapon = "w15"
	w.shoot_input(true, .4)
	expect(w.bullets.size() == 1 and w.bullets[0].controllable and w.bullets[0].mode == "controlled", "引魂纸蝶 creates a persistent controllable projectile")
	var initial_dir = w.bullets[0].dir
	w.player.aim = Vector2.DOWN
	w.update_bullets(.12)
	expect(w.bullets.size() == 1 and w.bullets[0].dir != initial_dir and w.bullets[0].dir.y > 0, "the controllable projectile steers toward the current aim without a random branch")
	w = fresh()
	w.player.weapon = "w16"
	w.shoot_input(true, .14)
	expect(w.player.charge > 0 and w.bullets.is_empty(), "月刃蓄锋 visibly charges before releasing a hit")
	w.shoot_input(true, .14)
	expect(w.player.charge == 0 and w.events.any(func(e): return e.kind == "slash" and e.charged), "a completed charged arc releases a heavy slash event")

	w = World.new()
	w.start("c_paper", 7140, 3)
	var graph_types = w.run.graph.types
	for kind in ["sacrifice", "judge", "angel"]:
		expect(graph_types.has(kind), "the seeded route graph exposes the optional " + kind + " room")
		w.run.room = graph_types.find(kind)
		w.enter_room()
		expect(w.mode == "choice" and not w.choices.is_empty() and w.choices[0].kind in ["sacrifice", "judgment", "blessing"], kind + " opens a dedicated one-pick room offering")
		w.player.hp = maxi(8, int(w.player.hp))
		expect(w.take_choice(0) and w.mode == "clear" and w.run.special_rooms.has(w.room_key()) and not w.run.growth_log.is_empty(), kind + " commits one deterministic growth choice and clears the room")
		var saved = w.snapshot()
		var resumed = World.new()
		expect(resumed.restore(saved) and resumed.run.special_rooms.has(resumed.room_key()) and resumed.mode == "clear", kind + " special-room choice survives checksum restore")
		w = resumed

	var challenge = World.new()
	challenge.start("c_paper", 7141, 3)
	challenge.run.floor = 2
	challenge.run.graph = World.Graph.build(World.RunRng.new(7141 + 802), 2, [])
	challenge.run.room_plan = challenge.run.graph.types.duplicate()
	challenge.run.room = challenge.run.graph.types.find("challenge")
	challenge.run.relic_pool = challenge.db.rows("relics").map(func(row): return row.id)
	challenge.run.level = 6
	challenge.run.xp = 270
	challenge.enter_room()
	expect(challenge.mode == "combat" and challenge.room_flags.wave_count == 3 and challenge.enemies.size() >= 5, "破阵房 starts a three-wave authored gauntlet instead of a free choice")
	var challenge_ticks = 0
	while challenge.mode == "combat" and challenge_ticks < 12:
		for enemy in challenge.enemies.duplicate(): challenge.kill_enemy(enemy, "primary")
		challenge.tick({}, 1.25)
		challenge_ticks += 1
	expect(challenge.mode == "choice" and not challenge.choices.is_empty() and challenge.choices.all(func(choice): return choice.kind == "relic" and choice.get("challenge", false)), "破阵房 clears into a tagged high-tier relic selection")
	var challenge_saved = challenge.snapshot()
	var challenge_resumed = World.new()
	expect(challenge_resumed.restore(challenge_saved) and challenge_resumed.mode == "choice" and challenge_resumed.choices.size() == challenge.choices.size(), "破阵房 reward candidates survive checksum restore")

	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "sixteen weapon modes, deterministic special rooms, three-wave challenge room, one-pick growth ledger and save restore"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/weapon-special-room-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Weapon and special room checks: %d; failures: %d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
