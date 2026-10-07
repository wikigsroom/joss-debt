extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Trial = preload("res://scripts/core/weapon_trial.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const Session = preload("res://scripts/core/save_session.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func same(a, b) -> bool:
	return JSON.stringify(Store.encode(a), "", true, true) == JSON.stringify(Store.encode(b), "", true, true)

func shop(character: String = "c_paper"):
	var w = World.new()
	w.start(character, 8371, 3)
	w.run.room = w.run.room_plan.find("shop")
	w.enter_room()
	w.take_events()
	return w

func weapon_index(w) -> int:
	for i in w.choices.size():
		if w.choices[i].kind == "weapon": return i
	return -1

func fire(w, ticks: int = 180) -> void:
	for i in ticks: w.tick({"fire": true, "aim": Vector2.UP})

func run_suite() -> void:
	var w = shop()
	var index = weapon_index(w)
	var before = w.snapshot()
	var session = Trial.new()
	var practice = session.begin(w, index)
	expect(index >= 0 and practice != null and session.active(), "an actual generated shop weapon opens an isolated trial")
	expect(session.origin == w and practice != w and same(before, w.snapshot()), "opening retains the original world object and every wallet, stock, ID and RNG field")
	expect(practice.player.weapon == w.choices[index].id and practice.run.character == w.run.character and practice.run.training, "the trial equips the actual offered weapon for the original character")
	expect(practice.enemies.size() == 4 and practice.enemies.all(func(e): return e.speed == 0 and e.attack_cd > 90000) and practice.player.invulnerable > 90000, "the safe practice room uses stationary, nonattacking real targets")
	var duplicate = session.begin(w, index)
	expect(duplicate == null and session.origin == w, "a repeated preview request cannot overwrite the suspended shop")
	var health = practice.enemies.reduce(func(sum, e): return sum + e.hp, 0.0)
	fire(practice)
	expect(practice.stats.shots > before.stats.shots and practice.enemies.reduce(func(sum, e): return sum + e.hp, 0.0) < health, "normal attack input resolves real weapon hits and damage in the trial")
	expect(same(before, w.snapshot()), "actual firing, collision, marking and RNG consumption leave the original shop unchanged")
	var reset = session.reset()
	expect(reset != null and reset != practice and reset.player.weapon == practice.player.weapon and reset.enemies.all(func(e): return e.hp == 5000) and reset.player.charge == 0 and reset.bullets.is_empty(), "reset restores the same offered weapon and fresh targets without spending or carrying charged attacks")
	practice.run.relics.r09 = 2
	practice.run.talents.append("t_fire_1a")
	practice.run.consumed.append("r29")
	practice.run.room_history["trial-only"] = {"marker": true}
	expect(same(before, w.snapshot()), "trial inventory, consumed relics, growth and nested room history have no aliases into the original")
	expect(session.finish() == w and not session.active() and session.index == -1, "return yields the exact original world and releases the session")
	expect(session.reset() == null and session.finish() == null, "reset and repeated return are harmless after the trial closes")
	w.run.coins = 0
	practice = session.begin(w, index)
	expect(practice != null and w.run.coins == 0, "an unaffordable weapon remains available for free practice")
	session.finish()
	w.choices[index].taken = true
	expect(session.begin(w, index) == null and not session.active(), "taken stock cannot be previewed as an available shop offer")
	w.choices[index].erase("taken")
	expect(session.begin(w, -1) == null and session.begin(w, w.choices.size()) == null, "invalid shop indices preserve the original state")
	w.mode = "combat"
	expect(session.begin(w, index) == null, "the shop trial cannot replace an active combat room")
	w.mode = "shop"
	expect(session.begin(w, 0) == null, "nonweapon stock retains its normal purchase action")
	for weapon in w.db.rows("weapons"):
		w = shop()
		index = weapon_index(w)
		w.choices[index].id = weapon.id
		before = w.snapshot()
		practice = session.begin(w, index)
		health = practice.enemies.reduce(func(sum, e): return sum + e.hp, 0.0)
		fire(practice)
		expect(practice.enemies.reduce(func(sum, e): return sum + e.hp, 0.0) < health and same(before, w.snapshot()), "real practice firing deals damage without changing stock or progress: " + weapon.id)
		session.finish()
	w = shop("c_lantern")
	index = weapon_index(w)
	w.choices[index].id = "w01"
	w.run.relics = {"r09": 1, "r18": 1, "r27": 1}
	w.run.talents = ["t_ink_1a", "t_wind_1a"]
	w.player.skill = "s08"
	w.run.evolved = true
	before = w.snapshot()
	practice = session.begin(w, index)
	expect(practice.run.relics == w.run.relics and practice.run.talents == w.run.talents and practice.player.skill == "s08", "current relics, growth nodes and evolved skill are copied into the weapon practice")
	practice.shoot_input(true, .01)
	var modified_pierce = practice.bullets.any(func(b): return b.pierce > 0)
	fire(practice, 60)
	expect(practice.enemies.any(func(e): return e.mark > 0 and e.burn > 0) and modified_pierce, "character passive and growth modifiers execute through real practice attack rules")
	var journal = Session.new("user://weapon_trial_suite")
	var progress = Progress.new("", journal.view("profile"))
	journal.view("checkpoint").write(w.snapshot())
	var saved = journal.portable_bundle().duplicate(true)
	practice.run.merit += 100
	practice.stats.detonations += 500
	practice.run.bosses_defeated.append("b03")
	practice.run.result = "victory"
	expect(progress.observe(practice).is_empty() and same(saved, journal.portable_bundle()), "even trial victory, earned currency and character mastery cannot credit the real account")
	session.finish()
	var reloaded = Session.new("user://weapon_trial_suite")
	var restored = World.new()
	expect(restored.restore(reloaded.current.checkpoint) and restored.mode == "shop" and same(restored.choices, w.choices) and restored.run.coins == w.run.coins, "disk restart returns to unpaid original stock rather than a training world")
	w.run.coins = 100
	var expected = World.new()
	expected.restore(w.snapshot())
	practice = session.begin(w, index)
	fire(practice, 120)
	session.finish()
	expect(w.roll("next-loot").unit() == expected.roll("next-loot").unit(), "practice cannot advance an existing or lazily created original loot stream")
	expect(w.take_choice(index) and w.player.weapon == "w01" and w.run.coins == 65, "purchase after return uses the original stock and charges its real price once")
	expect(not w.take_choice(index) and w.run.coins == 65, "repeated purchase after a trial cannot duplicate the stock or debit")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "method": "actual generated shops, twelve weapon attack inputs, original-object isolation and real native save journal; not a human full-run acceptance"}
	var f = FileAccess.open("res://../docs/incense-debt/reports/runtime/shop-trial-tests.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("Shop trial: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
