extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Adapter = preload("res://scripts/ui/input_adapter.gd")
var failures: Array = []
var checks: Array = []
var playthroughs: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(value: bool, description: String) -> void:
	checks.append(description)
	if not value:
		failures.append(description)
		push_error(description)

func touch(adapter, id: int, position: Vector2, pressed: bool = true) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id
	event.position = position
	event.pressed = pressed
	adapter.event(event)

func drag(adapter, id: int, position: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = id
	event.position = position
	adapter.event(event)

func run_suite() -> void:
	var adapter = Adapter.new()
	touch(adapter, 7, Vector2(130, 570))
	touch(adapter, 8, Vector2(870, 570))
	touch(adapter, 9, adapter.skill_center())
	drag(adapter, 7, Vector2(200, 570))
	drag(adapter, 8, Vector2(940, 570))
	var frame = adapter.sample(Vector2.ZERO, Vector2.ZERO)
	expect(frame.move == Vector2.RIGHT and frame.aim == Vector2.RIGHT and frame.fire and frame.skill, "three fingers independently move, aim/fire, and cast")
	touch(adapter, 7, Vector2(200, 570), false)
	frame = adapter.sample(Vector2.ZERO, Vector2.ZERO)
	expect(frame.move == Vector2.ZERO and frame.fire and not frame.skill, "releasing movement preserves the aim finger and consumes one action pulse")
	adapter.clear()
	frame = adapter.sample(Vector2.ZERO, Vector2.ZERO)
	expect(not frame.fire and frame.move == Vector2.ZERO and adapter.fingers.is_empty(), "pause/background clear removes held touch state")
	adapter.mirror = true
	touch(adapter, 11, Vector2(1140, 570))
	drag(adapter, 11, Vector2(1070, 570))
	expect(adapter.sample(Vector2.ZERO, Vector2.ZERO).move == Vector2.LEFT, "mirrored touch layout maps right-side movement")
	for character in ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]:
		var world = World.new()
		world.start(character, 6327)
		var pending = 0
		for tick in 36000:
			if world.mode == "result":
				break
			if world.mode == "choice":
				world.take_choice(0)
			elif world.mode in ["shop", "debt"]:
				if world.mode == "shop" and world.player.hp < world.player.max_hp and world.run.coins >= 10:
					world.take_choice(2)
				world.skip_choice()
			elif world.mode == "clear":
				world.advance_room()
			else:
				var enemy = world.nearest_enemy(world.player.pos)
				if enemy.is_empty():
					world.tick({})
					continue
				var aim = world.player.pos.direction_to(enemy.pos)
				var weapon = world.db.row("weapons", world.player.weapon)
				var desired = minf(float(weapon.range) * 0.67, 290)
				var distance = world.player.pos.distance_to(enemy.pos)
				var move = aim * clampf((distance - desired) / 100, -1, 1) + aim.orthogonal() * .65
				var danger = false
				for bullet in world.bullets:
					if not bullet.friendly:
						var soon = bullet.pos + bullet.dir * bullet.speed * .16
						var gap = world.player.pos.distance_to(soon)
						if gap < 80:
							move += soon.direction_to(world.player.pos) * (1 - gap / 80) * 2.5
							danger = danger or gap < 40
				for zone in world.zones:
					if not zone.friendly and world.player.pos.distance_to(zone.pos) < zone.radius + 50:
						move += zone.pos.direction_to(world.player.pos) * 2
						if world.player.pos.distance_to(zone.pos) < zone.radius:
							danger = true
				for foe in world.enemies:
					if foe.windup > 0 and foe.id == "e02":
						move += foe.aim.orthogonal() * 1.1
				var marks = world.enemies.filter(func(e): return e.mark >= 2).size()
				var skill = marks >= 2 or (enemy.boss and enemy.mark >= 3) or (world.enemies.size() == 1 and enemy.mark >= 3)
				world.tick({"move": move.limit_length(), "aim": aim, "fire": true, "dash": danger, "skill": skill})
			world.take_events()
		var report = {"character": character, "result": world.run.result, "rooms": world.run.cleared,
			"health": world.player.hp, "combat_seconds": snappedf(world.stats.elapsed, .1), "stats": world.stats,
			"method": "unmodified shared simulation; movement/aim bot, no invulnerability or damage cheats"}
		playthroughs.append(report)
		print("Bot run %s: %s, rooms %d, %.1fs" % [character, world.run.result, world.run.cleared, world.stats.elapsed])
		expect(world.run.result in ["victory", "defeat"], "complete run reaches a real terminal result: " + character)
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/input-and-run-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "playthroughs": playthroughs,
		"limitations": ["Bots do not replace human feel testing", "Touch events are synthetic; no physical mobile device tested"]}, "\t"))
	file.close()
	print("Input/run checks: %d; failures: %d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
