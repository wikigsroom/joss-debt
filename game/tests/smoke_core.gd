extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
var failures: Array = []
var checks: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error("FAIL: " + name)

func sandbox(character: String = "c_paper"):
	var world = World.new()
	world.start(character, 9001)
	world.enemies.clear()
	world.events.clear()
	return world

func run_suite() -> void:
	var a = World.new()
	var b = World.new()
	a.start("c_paper", 745)
	b.start("c_paper", 745)
	for i in 420:
		var frame = {"move": Vector2(sin(i * 0.04), cos(i * 0.04)), "aim": Vector2.UP, "fire": true, "dash": i == 120, "skill": i == 300}
		a.tick(frame)
		b.tick(frame)
	expect(JSON.stringify(Store.encode(a.snapshot())) == JSON.stringify(Store.encode(b.snapshot())), "same seed and action frames produce identical combat")
	var world = sandbox()
	world.geometry.build("room_open_1")
	world.player.pos = Vector2(640, 500)
	world.player.invulnerable = 0.0
	world.start_dash(Vector2.RIGHT)
	for i in 12:
		world.tick({})
	expect(absf(world.player.pos.x - 800) < 0.1, "dash travels 160 units in 0.2 seconds")
	world = sandbox()
	var target = world.spawn_enemy("e01", Vector2(640, 380))
	world.add_mark(target, 4)
	expect(target.mark == 3, "mark stacks cap at three")
	var energy = world.player.energy
	world.add_mark(target, 1)
	expect(world.player.energy == energy, "existing mark grants no duplicate first-mark energy")
	world.time += 5.1
	world.update_enemies(0.0)
	expect(target.mark == 0, "marks expire after five seconds")
	world = sandbox("c_bell")
	for i in 6:
		var enemy = world.spawn_enemy("e05", Vector2(300 + i * 60, 350))
		world.add_mark(enemy, 1)
	world.update_chains()
	expect(world.chains[0].size() == 4, "bell class links four targets by default")
	world.run.relics.r09 = 2
	world.update_chains()
	expect(world.chains[0].size() == 6, "chain group never exceeds six with upgrades")
	world = sandbox()
	world.player.pos = Vector2(640, 400)
	world.run.relics.r02 = 1
	var marked = world.spawn_enemy("e05", Vector2(640, 300))
	var unmarked = world.spawn_enemy("e05", Vector2(690, 300))
	world.add_mark(marked, 1)
	world.update_chains()
	var before = unmarked.hp
	expect(world.cast_skill(), "marked target permits a skill cast")
	expect(unmarked.hp == before and unmarked.mark == 1, "new fire-spark mark stays outside the current detonation snapshot")
	world = sandbox()
	world.run.relics.r18 = 1
	var first = world.spawn_enemy("e02", Vector2(500, 320))
	var second = world.spawn_enemy("e02", Vector2(600, 320))
	world.kill_enemy(first, "primary")
	var count = world.bullets.size()
	world.kill_enemy(first, "primary")
	expect(world.bullets.size() == count and world.stats.kills == 1, "enemy reward ledger rejects a repeated death")
	world.kill_enemy(second, "secondary")
	expect(world.bullets.size() == count, "a secondary kill cannot create another gray bullet")
	world = sandbox()
	world.run.room = 7
	world.enter_room()
	world.run.coins = 200
	world.choices = [{"kind": "relic", "id": "r09", "price": 18}]
	expect(world.take_choice(0), "shop purchase succeeds once")
	var coins = world.run.coins
	expect(not world.take_choice(0) and world.run.coins == coins and world.stack("r09") == 1, "repeated purchase cannot debit money or grant another item")
	var snapshot = world.snapshot()
	var restored = World.new()
	expect(restored.restore(Store.decode(Store.encode(snapshot))), "complete run snapshot restores")
	expect(restored.run.coins == coins and not restored.take_choice(0), "restored shop ledger preserves the spent slot")
	world = sandbox()
	world.player.hp = 1
	world.run.heal_misses = 2
	expect(world.generate_heal() and world.run.heal_misses == 0, "third low-health miss forces a heal and resets pity")
	for row in world.db.rows("room_templates"):
		world.geometry.build(row.id)
		world.geometry.rebuild_flow(Vector2(640, 585))
		expect(world.geometry.flow.has(world.geometry.key(world.geometry.cell_of(Vector2(640, 105)))), "room geometry connects entrance and exit: " + row.id)
	var store = Store.new("user://test_saves")
	expect(store.write({"value": 1, "pos": Vector2(1, 2)}) and store.write({"value": 2}), "two checksum generations write successfully")
	var newest = store.folder.path_join("checkpoint_%d.json" % (store.revision % 2))
	var file = FileAccess.open(newest, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	expect(store.read().get("value", 0) == 1, "corrupt newest save falls back to the previous complete generation")
	var report = {"checks": checks, "count": checks.size(), "failures": failures, "passed": failures.is_empty(), "engine": Engine.get_version_info().string}
	var path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/core-tests.json")
	var report_file = FileAccess.open(path, FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("Core tests: %d checks, %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
