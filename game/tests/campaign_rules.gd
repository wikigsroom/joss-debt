extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Graph = preload("res://scripts/core/room_graph.gd")
const Rng = preload("res://scripts/core/run_rng.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const Story = preload("res://scripts/core/story_book.gd")
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const Store = preload("res://scripts/core/save_store.gd")
var checks: Array = []
var failures: Array = []

class RejectedStore:
	extends RefCounted
	func write(_data: Dictionary) -> bool: return false

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, description: String) -> void:
	checks.append(description)
	if not condition:
		failures.append(description)
		push_error(description)

func fixture(debt: String = "", floor_id: int = 1, room: int = 3):
	var w = World.new()
	w.start("c_paper", 8141, 3, {"optional_bosses": ["b04", "b05"]})
	w.run.floor = floor_id
	w.run.graph = Graph.build(Rng.new(401 * floor_id + 8141), floor_id, ["b04", "b05"])
	w.run.room_plan = w.run.graph.types.duplicate()
	w.run.room = room
	if not debt.is_empty(): w.run.contracts = [{"id": debt, "interest": 0}]
	w.enter_room()
	return w

func distance(graph: Dictionary, forbidden: int = -1) -> Dictionary:
	var costs = {0: 1}
	var pending = [0]
	while not pending.is_empty():
		var current = pending.pop_front()
		for edge in graph.edges:
			if not current in edge: continue
			var next = edge[1] if edge[0] == current else edge[0]
			if next == forbidden: continue
			var cost = costs[current] + int(graph.types[next] == "combat")
			if not costs.has(next) or cost < costs[next]:
				costs[next] = cost
				pending.append(next)
	return costs

func run_suite() -> void:
	var connected = true
	var mandatory = true
	var ordinary = true
	var coordinates = true
	for seed_id in 500:
		for floor_id in range(1, 4):
			var graph = Graph.build(Rng.new(seed_id * 401 + floor_id), floor_id, ["b04", "b05"])
			var costs = distance(graph)
			connected = connected and costs.size() == graph.types.size()
			mandatory = mandatory and not distance(graph, 2).has(10)
			ordinary = ordinary and int(costs[10]) >= 4
			coordinates = coordinates and graph.coords.all(func(point): return graph.coords.count(point) == 1)
	expect(connected, "1,500 seeded chapter graphs have reachable shops, branches, and optional bosses")
	expect(mandatory, "the early reward lies on every main-boss path")
	expect(ordinary, "every main-boss path includes at least four ordinary combats")
	expect(coordinates, "graph nodes have distinct positions, including optional content")
	var w = fixture("d01")
	w.enter_room()
	expect(w.enemies.any(func(e): return float(e.get("arrival", 0)) > w.time), "d01 adds a visibly delayed collector on the second eligible ordinary combat")
	w.run.room = 0
	w.enter_room()
	expect(not w.enemies.any(func(e): return float(e.get("arrival", 0)) > w.time), "d01 leaves the first two teaching rooms free of collectors")
	w = fixture("d02")
	w.time = 3.1
	w.take_events()
	w.update_enemies(.01)
	expect(w.delayed.any(func(d): return d.type == "debt_bullet" and is_equal_approx(d.time - w.time, .8)) and w.events.any(func(e): return e.kind == "debt_warning" and e.has("aim")), "d02 locks its shot direction behind an 800ms visible warning")
	var pair = w.room_flags.debt_pair
	w.enemy_by_uid(pair[0]).dead = true
	w.bullets.clear()
	w.time = 4.1
	w.update_delayed(.01)
	expect(w.bullets.is_empty(), "breaking either d02 partner cancels its already scheduled shot")
	w = fixture("d03")
	w.kill_enemy(w.enemies[0], "primary")
	expect(w.pickups.any(func(p): return p.kind == "ash" and is_equal_approx(p.delay, 1.1)), "d03 delays natural ash by exactly half a second")
	w = fixture("d04", 2, 7)
	expect(w.choices.any(func(c): return c.kind == "heal" and c.price == 15), "d04 shows the actual increased shop-heal price")
	w = fixture("d05", 2)
	var before_coins = w.run.coins
	w.enemies.clear()
	w.clear_room()
	expect(w.run.coins - before_coins == maxi(1, int(w.db.rules.loot.clear_coins.combat) - 1), "d05 reduces only ordinary clear coins and retains the minimum")
	w = fixture("d06", 2)
	w.start_dash(Vector2.UP)
	expect(is_equal_approx(w.player.dash_cd, 2.3), "d06 adds 300ms to dash recovery")
	w = fixture("d07", 3)
	w.player.energy = 40
	w.add_mark(w.enemies[0], 1)
	expect(w.player.energy == 40, "d07 removes the two-energy first-mark refund")
	w.run.contracts.clear()
	w.enemies[0].mark = 0
	w.add_mark(w.enemies[0], 1)
	expect(w.player.energy == 42, "removing d07 immediately restores first-mark energy")
	w = fixture("d08", 3)
	w.geometry.build("room_open_1", 3)
	w.player.pos = Vector2(640, 500)
	w.player.invulnerable = 100
	var previous = Vector2(w.player.pos)
	w.tick({"move": Vector2.RIGHT}, .01)
	var character_speed = float(w.db.row("characters", "c_paper").speed)
	expect(absf(w.player.pos.x - previous.x - character_speed * .88 * .01) < .001, "d08 slows movement only during the opening three seconds")
	w.time = 3.1
	previous = w.player.pos
	w.tick({"move": Vector2.RIGHT}, .01)
	expect(absf(w.player.pos.x - previous.x - character_speed * .01) < .001, "d08 opening penalty expires without affecting later movement")
	w = fixture("d09", 3, 10)
	var boss = w.enemies.filter(func(e): return e.boss)[0]
	for phase in [1, 2, 1]: World.BossPattern.phase_enter(w, boss, phase)
	expect(w.room_flags.total_ledger_extra == 2, "d09 adds at most two total-ledger guards across phase changes")
	for debt in w.db.rows("debt_contracts"):
		w = fixture(debt.id, maxi(1, int(debt.min_floor)))
		w.mode = "checkpoint"
		w.run.coins = 300
		var expected_price = int(debt.repay_price)
		expect(w.repay(0) and not w.repay(0) and w.run.coins == 300 - expected_price and not w.contract(debt.id), "repayment settles once and disables the penalty: " + debt.id)
	w = fixture("", 2)
	w.run.room = w.run.graph.optional_boss_room
	w.enter_room()
	for enemy in w.enemies.duplicate(): w.kill_enemy(enemy, "primary")
	w.enemies.clear()
	w.clear_room()
	while w.mode == "choice": w.skip_choice()
	expect(w.mode == "clear" and w.run.floor == 2 and w.run.bosses_defeated.has("b04"), "optional-boss victory returns to the same chapter without ending it")
	w = fixture()
	w.run.xp = 5000
	w.enemies.clear()
	w.clear_room()
	var selected: Array = []
	while w.mode == "choice":
		if w.choices.is_empty(): break
		var item = w.choices[0]
		if item.kind != "talent": w.skip_choice(); continue
		expect(not selected.has(item.id) and w.choice_reason(item).is_empty(), "queued level-up regenerates eligible unowned talents")
		selected.append(item.id)
		w.take_choice(0)
	var path = "user://campaign_rules_%d" % Time.get_ticks_usec()
	var meta = Progress.new(path)
	w = fixture()
	w.run.id = "meta-1"
	w.stats.max_chain = 3
	w.run.bosses_defeated = ["b01"]
	meta.observe(w)
	expect(meta.data.characters.has("c_bell") and meta.data.characters.has("c_lantern"), "first chain and first main boss unlock their intended characters")
	w.stats.parries = 10
	meta.observe(w)
	w.run.id = "meta-2"
	meta.observe(w)
	expect(meta.data.characters.has("c_mask") and meta.data.defenses == 20, "defensive character progress accumulates across distinct runs")
	w.stats.ash_energy = 200
	w.run.repayments = ["d01", "d01", "d01"]
	meta.observe(w)
	expect(meta.data.characters.has("c_umbrella") and meta.data.characters.has("c_ink"), "ash recovery and three successful repayments unlock the remaining characters")
	expect(not meta.ending_reason("repay").is_empty(), "three copies of one repaid debt do not unlock the three-class ending")
	w.run.repayments = ["d01", "d02", "d03"]
	w.run.name_page_ids = ["name_page_1", "name_page_2", "name_page_3"]
	w.run.interest_page = true
	meta.observe(w)
	expect(meta.optional_bosses() == ["b04", "b05"] and meta.ending_reason("repay").is_empty(), "distinct name pages and repaid classes open the optional bosses and repay ending")
	var story = Story.new()
	var personal_page = story.content.pages.filter(func(p): return p.id == "story.personal.c_paper")[0]
	expect(not story.available(personal_page, meta.data), "unfinished personal stories remain locked")
	meta.data.personal.c_paper.stage = 3
	expect(story.pages(meta.data, "c_paper").size() == 1, "character-filtered story index contains only the unlocked personal page")
	for character in meta.data.personal: meta.data.personal[character].stage = 3
	w.run.result = "victory"
	w.run.bosses_defeated.append("b03")
	expect(meta.finish(w, "rewrite") and not meta.finish(w, "burn"), "a completed final-boss run can record exactly one available ending")
	var restored = Progress.new(path)
	expect(restored.data.endings.has("rewrite") and restored.data.name_page_ids.size() == 3, "ending and distinct page discovery survive journal reload")
	var previous_merit = meta.data.merit
	meta.store = RejectedStore.new()
	w.run.id = "rejected-write"
	w.run.merit = 17
	meta.observe(w)
	expect(meta.data.merit == previous_merit and not meta.data.runs.has("rejected-write"), "a failed account write rolls back earned-credit state so a retry remains possible")
	var projected = Adapter.projected_direction(Vector2(.6, .6))
	expect(is_equal_approx(projected.length(), Vector2(.6, .6).length()) and is_equal_approx(projected.y * .84722, projected.x), "diagonal stick aim follows the projected screen angle without changing stick magnitude")
	var adapter = Adapter.new()
	adapter.safe_rect = Rect2(110, 45, 1030, 610)
	adapter.mirror = true
	expect(adapter.safe_rect.grow(-49).has_point(adapter.skill_center()) and adapter.safe_rect.grow(-49).has_point(adapter.dash_center()), "mirrored action centers stay inside a landscape notch-safe area")
	var event = InputEventScreenTouch.new()
	event.index = 7
	event.position = Vector2(33, 350)
	event.pressed = true
	adapter.event(event)
	expect(adapter.fingers.is_empty(), "touches outside the safe area cannot capture movement or aim")
	var report = {"count": checks.size(), "graph_seeds": 1500, "checks": checks, "failures": failures, "passed": failures.is_empty(), "method": "deterministic campaign/account/input fixtures; no physical mobile device"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/campaign-rules-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Campaign/account/input checks: %d; failures: %d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
