extends SceneTree
## Physical room-door regression: direction, threshold, reverse arrival and rejection.

const World = preload("res://scripts/combat/world.gd")

var checks: Array = []
var failures: Array = []
var directions = {
	"north": Vector2.UP,
	"south": Vector2.DOWN,
	"east": Vector2.RIGHT,
	"west": Vector2.LEFT,
}

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func fixture(direction: String) -> World:
	var world = World.new()
	world.start("c_paper", 14159, 1)
	var axis = directions[direction]
	# Room-graph Y grows downward while screen-space north is Vector2.UP.
	var destination = Vector2(axis.x, -axis.y)
	world.run.graph = {"types": ["combat", "reward"], "coords": [Vector2.ZERO, destination], "edges": [[0, 1]], "optional_boss": "", "optional_boss_room": -1, "secret_entries": [], "revealed": []}
	world.run.room_plan = ["combat", "reward"]
	world.run.room = 0
	world.run.visited = [0]
	world.run.room_history = {}
	world.mode = "clear"
	world.geometry.build("room_open_1", 1)
	world.geometry.rebuild_flow(world.player.pos)
	world.player.pos = World.door_position(direction) - axis * 42.0
	world.player.move = Vector2.ZERO
	world.player.invulnerable = 0.0
	world.events.clear()
	return world

func run_suite() -> void:
	for direction in directions.keys():
		var axis: Vector2 = directions[direction]
		var world = fixture(direction)
		var doors = world.room_doors()
		expect(doors.size() == 1 and doors[0].direction == direction and doors[0].destination == 1, "%s exposes exactly one physical frontier door" % direction)

		var wrong = fixture(direction)
		wrong.tick({"move": -axis, "aim": -axis})
		expect(wrong.run.room == 0 and wrong.mode == "clear", "%s rejects walking away from its threshold" % direction)

		world.tick({"move": axis, "aim": axis})
		var expected_arrival = World.opposite_direction(direction)
		expect(world.run.room == 1 and world.mode == "choice", "%s enters the connected room only after crossing its door" % direction)
		expect(world.player.pos.is_equal_approx(World.door_position(expected_arrival)), "%s enters from the corresponding opposite-side door" % direction)

		world.mode = "clear"
		world.choices.clear()
		var return_axis: Vector2 = directions[expected_arrival]
		world.player.pos = World.door_position(expected_arrival) - return_axis * 42.0
		world.tick({"move": return_axis, "aim": return_axis})
		expect(world.run.room == 0 and world.mode == "clear", "%s reverse door returns to the visited room" % direction)
		expect(world.player.pos.is_equal_approx(World.door_position(direction)), "%s reverse arrival preserves the matching entry side" % direction)

	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"directions_tested": directions.size(), "wrong_direction_rejections": directions.size(),
		"forward_transitions": directions.size(), "reverse_arrivals": directions.size(),
		"scope": "fixed-tick physical thresholds on all four room directions; no teleport or route-map mutation"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/route-navigation-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Route navigation: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
