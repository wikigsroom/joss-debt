extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Graph = preload("res://scripts/core/room_graph.gd")
const Rng = preload("res://scripts/core/run_rng.gd")
const Store = preload("res://scripts/core/save_store.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func fixture(floor_id: int = 2, room: int = 5, debt: String = ""):
	var w = World.new()
	w.start("c_paper", 9172, 3)
	w.run.floor = floor_id
	w.run.graph = Graph.build(Rng.new(9172 + 401 * floor_id), floor_id, [])
	w.run.room_plan = w.run.graph.types.duplicate()
	w.run.room = room
	if not debt.is_empty(): w.run.contracts = [{"id": debt, "interest": 0}]
	w.enter_room()
	w.player.invulnerable = 100
	w.take_events()
	return w

func kill_wave(w) -> void:
	for enemy in w.enemies.duplicate(): w.kill_enemy(enemy, "primary")
	w.tick({})

func settle_choices(w) -> void:
	while w.mode == "choice": w.skip_choice()

func run_suite() -> void:
	var teaching = fixture(1, 0)
	expect(teaching.room_flags.wave_count == 1 and teaching.enemies.size() == 3 and teaching.enemies.all(func(e): return e.id == "e01" and not e.has("arrival")), "first teaching room preserves one predictable lantern wave")
	teaching = fixture(1, 1)
	expect(teaching.room_flags.wave_count == 1 and teaching.enemies.all(func(e): return e.id in ["e01", "e02"]), "second teaching room introduces only the approved pair of enemy species")
	var w = fixture()
	expect(w.room_flags.wave_count == 2 and w.room_flags.waves.all(func(ids): return ids.size() >= 3 and ids.size() <= 6), "later main-path encounters contain two bounded waves of three to six actors")
	expect(w.room_flags.waves.all(func(ids): return ids.all(func(id): return w.db.row("enemies", id).floor == 2)), "every planned wave uses the current region's actual enemy roster")
	var first_ids = w.enemies.map(func(e): return e.uid)
	var before_xp = int(w.run.xp)
	var before_merit = int(w.run.merit)
	var plan = w.room_flags.waves.duplicate(true)
	kill_wave(w)
	expect(w.mode == "combat" and w.run.cleared == 0 and w.run.xp == before_xp and w.run.merit == before_merit, "the first wave cannot grant clear XP, merit or an exit")
	expect(not w.reward_ledger.has(w.room_key() + "/clear") and w.events.any(func(e): return e.kind == "wave_incoming"), "next-wave warning replaces premature clear settlement")
	w.clear_room()
	expect(w.run.cleared == 0, "the authoritative clear API also rejects a still-planned second wave")
	w.tick({}, .4)
	expect(w.enemies.is_empty() and w.room_flags.wave_index == 1, "the inter-wave ash collection window lasts before new actors arrive")
	var journal = Store.new("user://exploration_encounters_tests")
	expect(journal.write(w.snapshot()), "an inter-wave snapshot enters the real two-generation checksum store")
	var reopened_writer = Store.new(journal.folder)
	expect(reopened_writer.revision == journal.revision and reopened_writer.write(w.snapshot()) and reopened_writer.revision == journal.revision + 1, "a newly opened journal writer commits after the newest existing generation")
	journal = reopened_writer
	var resumed = World.new()
	expect(resumed.restore(journal.read()) and resumed.room_flags.waves == plan and is_equal_approx(resumed.room_flags.wave_pending_at, w.room_flags.wave_pending_at), "restore retains exact enemy plans and absolute warning deadline")
	for i in 50:
		w.tick({})
		resumed.tick({})
	expect(w.room_flags.wave_index == 2 and resumed.room_flags.wave_index == 2 and w.enemies.map(func(e): return e.id) == resumed.enemies.map(func(e): return e.id), "a saved warning produces the same second wave without a reroll")
	expect(w.enemies.all(func(e): return not first_ids.has(e.uid) and w.player.pos.distance_to(e.pos) >= 220 and w.geometry.valid_circle(e.pos, 22)), "second-wave actors use new identities and legal distant positions")
	expect(w.enemies.all(func(e): return float(e.arrival) > w.time) and w.nearest_enemy(w.player.pos).is_empty(), "arrival silhouettes do not become selectable targets during their 800ms tell")
	var actor = w.enemies[0]
	var hp = actor.hp
	var hit_count = w.stats.hits
	w.primary_hit(actor, 999, 17)
	w.damage_enemy(actor, 999, "secondary")
	w.add_mark(actor, 3)
	w.add_burn(actor, 3)
	expect(actor.hp == hp and actor.mark == 0 and actor.burn == 0 and w.stats.hits == hit_count, "pre-arrival actors cannot take damage, marks, burn or primary procs")
	for i in 50: w.tick({})
	w.primary_hit(actor, 1, 18)
	expect(actor.hp < hp and actor.mark == 1, "the same actor becomes normally hittable after its arrival tell")
	kill_wave(w)
	expect(w.run.cleared == 1 and w.run.xp == before_xp + w.db.rules.progression.xp.combat and w.run.merit == before_merit + w.db.rules.progression.meta_currency.combat, "the final wave grants exactly one normal room settlement")
	var final_merit = w.run.merit
	w.clear_room()
	expect(w.run.cleared == 1 and w.run.merit == final_merit, "repeated terminal calls cannot farm wave clear rewards")
	var collector = fixture(2, 5, "d01")
	collector.run.contract_combats = 1
	collector.enter_room()
	expect(collector.enemies.size() <= 8 and collector.enemies.any(func(e): return e.id == "e01" and e.has("arrival")), "eligible collector contract is capped and telegraphed in the first wave")
	kill_wave(collector)
	for i in 73: collector.tick({})
	expect(collector.run.contract_combats == 2 and collector.enemies.all(func(e): return e.id != "e01"), "wave transitions do not count a new contract room or add another collector")
	var pair = fixture(2, 5, "d02")
	var old_pair = pair.room_flags.debt_pair.duplicate()
	kill_wave(pair)
	for i in 73: pair.tick({})
	expect(pair.room_flags.debt_pair.all(func(id): return not old_pair.has(id)) and pair.room_flags.debt_fire_at > pair.time + 3, "second-wave debt pairs bind new actors behind the full warning grace period")
	var legacy = fixture().snapshot()
	for key in ["waves", "wave_index", "wave_count", "wave_pending_at"]: legacy.room_flags.erase(key)
	expect(resumed.restore(legacy), "pre-wave saved rooms remain loadable without replacing live enemies")
	kill_wave(resumed)
	expect(resumed.run.cleared == 1, "a pre-wave saved room settles its existing single encounter")
	var seed_id = -1
	for seed_value in 100:
		if Graph.build(Rng.new(seed_value + 401), 1, []).types.has("secret"):
			seed_id = seed_value
			break
	w = World.new()
	w.start("c_paper", seed_id, 3)
	w.run.room = 2
	w.enter_room()
	w.skip_choice()
	var door_world = World.new()
	door_world.start("c_paper", seed_id, 3)
	door_world.run.room = 2
	door_world.enter_room()
	door_world.skip_choice()
	var physical_doors = door_world.room_doors().filter(func(door): return not door.visited)
	if not physical_doors.is_empty():
		var physical_door = physical_doors[0]
		var physical_direction = door_world.direction_vector(str(physical_door.direction))
		door_world.player.pos = physical_door.pos - physical_direction * 42
		door_world.tick({"move": physical_direction, "aim": physical_direction})
	expect(not physical_doors.is_empty() and door_world.run.room != 2 and door_world.mode != "clear", "a cleared room exposes directional doors and walking through one enters the connected map")
	var entry = w.secret_entry()
	expect(not entry.is_empty() and w.geometry.valid_circle(entry.pos, 12), "a generated concealed branch has a physically reachable inspection point")
	expect(not Graph.visible(w.run.graph, entry.room) and not w.next_rooms().has(entry.room), "undiscovered branches are absent from the visible frontier")
	w.advance_room(int(entry.room))
	expect(w.run.room == 2, "direct destination requests cannot bypass physical discovery")
	var rng_before = w.rng.state
	var streams_before = w.snapshot().streams
	w.update_secret_discovery(2)
	expect(not Graph.visible(w.run.graph, entry.room), "standing elsewhere in the room does not discover the clue")
	w.player.pos = entry.pos
	w.update_secret_discovery(.2)
	expect(not Graph.visible(w.run.graph, entry.room), "a brief pass by the rope does not immediately open the secret")
	w.player.pos = Vector2(640, 585)
	w.update_secret_discovery(.2)
	expect(w.room_flags.secret_inspect == 0, "leaving the inspection area resets partial discovery")
	w.player.pos = entry.pos
	var entry_outward = Vector2.RIGHT if int(entry.side) > 0 else Vector2.LEFT
	w.player.move = -entry_outward
	expect(not w.try_enter_secret(true), "a concealed entry rejects movement aimed away from its physical threshold")
	w.player.move = Vector2.ZERO
	w.take_events()
	w.update_secret_discovery(.46)
	expect(Graph.visible(w.run.graph, entry.room) and w.next_rooms().has(entry.room), "staying near the frayed cord reveals the branch in the actual route frontier")
	expect(w.rng.state == rng_before and w.snapshot().streams == streams_before, "physical inspection consumes neither encounter nor reward randomness")
	expect(w.events.count(w.events.filter(func(e): return e.kind == "secret_discovered")[0]) == 1, "discovery emits one physical reveal event")
	w.take_events()
	w.update_secret_discovery(5)
	expect(w.events.is_empty(), "an already opened rope does not repeatedly save or reward discovery")
	journal.write(w.snapshot())
	expect(resumed.restore(journal.read()) and Graph.visible(resumed.run.graph, entry.room), "a revealed branch remains revealed after JSON and checksum recovery")
	expect(resumed.next_rooms().has(int(entry.room)), "restored graph edges and room IDs remain mutually reachable after JSON number conversion")
	w.player.pos = Vector2(640, 585)
	expect(not w.try_enter_secret(), "the physical entry action requires proximity even after discovery")
	w.pickups = [{"uid": 9001, "kind": "heal", "pos": Vector2(640, 585), "value": 2, "delay": 0.0, "natural": false, "magnet": false}]
	w.player.hp = 2
	w.player.pos = entry.pos
	expect(w.try_enter_secret() and w.room_type() == "secret" and w.choices.any(func(c): return c.id == "interest"), "the normal interaction enters real secret rewards and the interest-page choice")
	for i in w.choices.size():
		if w.choices[i].id == "interest":
			w.take_choice(i)
			break
	var coins = w.run.coins
	var clears = w.run.cleared
	var before_return_rng = w.rng.state
	w.advance_room(2)
	expect(w.run.room == 2 and w.mode == "clear" and w.choices.is_empty() and w.run.interest_page, "returning through a cleared room retains story reward without reopening its offer")
	expect(w.run.coins == coins and w.run.cleared == clears and w.rng.state == before_return_rng, "safe return cannot respawn enemies or award currency and clear count")
	expect(w.pickups.size() == 1 and w.pickups[0].kind == "heal", "uncollected healing persists in the cleared-room history")
	w.player.pos = w.pickups[0].pos
	w.update_pickups(.1)
	expect(w.player.hp == 4 and w.pickups.is_empty(), "a returned healing pickup is collected through the normal health rule")
	w.advance_room(3)
	kill_wave(w)
	settle_choices(w)
	var returning_xp = w.run.xp
	var returning_merit = w.run.merit
	w.advance_room(2)
	expect(w.run.room == 2 and w.pickups.is_empty() and w.run.xp == returning_xp and w.run.merit == returning_merit, "multiple visits cannot regenerate consumed healing or progression rewards")
	var old_graph = w.run.graph.duplicate(true)
	old_graph.erase("revealed")
	old_graph.erase("secret_entries")
	expect(Graph.visible(old_graph, entry.room), "legacy graphs keep their originally public secret branches visible")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "shared native simulation: wave deadlines, actual checksum recovery, arrival immunity, one-time settlement, physical discovery and cleared-room memory; unit fixtures are not balance runs"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/exploration-encounters-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Exploration and waves: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
