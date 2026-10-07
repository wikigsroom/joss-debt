extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const BossPattern = preload("res://scripts/combat/boss_patterns.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, description: String) -> void:
	checks.append(description)
	if not condition:
		failures.append(description)
		push_error(description)

func sandbox(character: String = "c_paper"):
	var w = World.new()
	w.start(character, 7145, 3)
	w.enemies.clear()
	w.player.pos = Vector2(640, 480)
	w.player.aim = Vector2.UP
	w.player.energy = 100.0
	return w

func run_suite() -> void:
	var w = sandbox()
	w.run.talents = ["t_wind_2a"]
	var struck = w.spawn_enemy("e05", Vector2(640, 420))
	struck.hp = 1000
	struck.primary_hits = 2
	w.shoot_input(true, .01)
	w.update_bullets(.1)
	expect(w.bullets.size() == 1 and not w.bullets[0].primary and w.bullets[0].age == 0.0, "a primary hit retains its new secondary projectile exactly once without advancing it in the same tick")
	var geometry_agrees = true
	var random = World.RunRng.new(88471)
	for room in w.db.rows("room_templates"):
		w.geometry.build(room.id)
		for sample in 40:
			var from = Vector2(64 + random.unit() * 1152, 72 + random.unit() * 576)
			var to = Vector2(64 + random.unit() * 1152, 72 + random.unit() * 576)
			var brute = not w.geometry.blocks.any(func(rect): return World.Geometry.segment_rect(from, to, rect))
			geometry_agrees = geometry_agrees and w.geometry.clear_segment(from, to) == brute
	expect(geometry_agrees, "720 seeded segment queries preserve collision results after broad rejection of distant obstacles")
	for skill in w.db.rows("skills"):
		w = sandbox(skill.character)
		w.player.skill = skill.id
		var target = w.spawn_enemy("e05", Vector2(640, 420))
		target.hp = 10000.0
		target.max_hp = 10000.0
		w.add_mark(target, 3)
		w.update_chains()
		expect(w.cast_skill(), "skill can cast on a valid marked target: " + skill.id)
		for i in 120:
			w.time += 1.0 / 60.0
			w.update_delayed(1.0 / 60.0)
			w.update_zones(1.0 / 60.0)
		expect(target.hp < 10000 and w.player.skill_cd == skill.cooldown_s, "skill settles damage and its authored cooldown: " + skill.id)
	w = sandbox("c_bell")
	w.player.skill = "s06"
	var original = w.spawn_enemy("e05", Vector2(640, 390))
	original.hp = 1000
	w.add_mark(original, 3)
	w.update_chains()
	w.cast_skill()
	var late = w.spawn_enemy("e05", Vector2(650, 390))
	w.add_mark(late, 3)
	var loaded = World.new()
	expect(loaded.restore(Store.decode(Store.encode(w.snapshot()))), "delayed skill state survives serialized save")
	w.time += .6
	loaded.time += .6
	w.update_delayed(0)
	loaded.update_delayed(0)
	expect(late.hp == late.max_hp and loaded.enemy_by_uid(late.uid).hp == late.max_hp, "replay excludes targets marked after its first pulse, before and after reload")
	expect(is_equal_approx(original.hp, loaded.enemy_by_uid(original.uid).hp), "saved replay preserves its fixed target damage")
	w = sandbox()
	var shield = w.spawn_enemy("e09", Vector2(640, 390))
	shield.aim = Vector2.DOWN
	var before = shield.hp
	w.primary_hit(shield, 20, 1)
	var front = before - shield.hp
	w.player.pos = Vector2(550, 390)
	before = shield.hp
	w.primary_hit(shield, 20, 2)
	expect(is_equal_approx(front, 4) and is_equal_approx(before - shield.hp, 20), "coin shield blocks frontal damage while exposing its flank")
	w = sandbox("c_mask")
	w.player.invulnerable = 0
	w.player.armor = 1
	before = w.player.hp
	w.damage_player(2)
	expect(w.player.hp == before - 1 and w.player.armor == 0, "paper armor absorbs one health point of a heavy hit")
	w = sandbox()
	w.player.hp = 1
	w.player.invulnerable = 0
	w.run.relics.r29 = 1
	w.damage_player(2)
	expect(w.player.hp == 1 and w.run.consumed.has("r29") and w.stack("r29") == 0, "revival consumes its only charge and tombstones the relic")
	loaded = World.new()
	loaded.restore(Store.decode(Store.encode(w.snapshot())))
	loaded.player.invulnerable = 0
	loaded.damage_player(2)
	expect(loaded.run.result == "defeat", "reloading cannot replenish a consumed revival")
	w = sandbox()
	original = w.spawn_enemy("e05", Vector2(640, 350))
	original.hp = 10000
	w.begin_pulse("budget-test")
	for i in 60: w.damage_enemy(original, 1, "secondary")
	expect(original.hp == 9952 and w.stats.max_proc_events == 48, "secondary damage is capped without dropping original damage")
	w.damage_enemy(original, 20, "detonate")
	expect(original.hp == 9932, "original detonation remains valid after secondary budget exhaustion")
	w = sandbox()
	w.run.talents = ["t_fire_1a"]
	var eligibility = true
	for i in 40:
		for offer in w.talent_offer():
			var row = w.db.row("talents", offer.id)
			var points = w.run.talents.filter(func(id): return w.db.row("talents", id).route == row.route).size()
			eligibility = eligibility and points >= row.min_route_points and not w.run.talents.has(offer.id)
	expect(eligibility, "all growth offers respect route prerequisites and unique ownership")
	var first = sandbox()
	var second = sandbox()
	for i in 100: first.rng.unit()
	expect(JSON.stringify(first.relic_offer(3)) == JSON.stringify(second.relic_offer(3)), "combat RNG consumption cannot change the reward stream")
	loaded = World.new()
	loaded.restore(Store.decode(Store.encode(first.snapshot())))
	expect(JSON.stringify(first.relic_offer(3)) == JSON.stringify(loaded.relic_offer(3)), "independent reward streams resume at exactly their saved position")
	for enemy_row in w.db.rows("enemies"):
		w = sandbox()
		var enemy = w.spawn_enemy(enemy_row.id, Vector2(640, 300))
		enemy.target = w.player.pos
		enemy.aim = Vector2.DOWN
		w.enemy_attack(enemy)
		expect(w.bullets.size() + w.zones.size() + w.delayed.size() > 0 or enemy.lunge > 0, "enemy has a concrete attack: " + enemy_row.id)
	for boss_row in w.db.rows("bosses"):
		w = sandbox()
		var boss = w.spawn_boss(boss_row.id)
		for phase in 3:
			boss.phase = phase
			boss.target = w.player.pos
			boss.aim = Vector2.DOWN
			BossPattern.phase_enter(w, boss, phase)
			for attack in 8: w.enemy_attack(boss)
		var adds = w.enemies.filter(func(e): return e.get("guarding_boss", -1) == boss.uid)
		expect(adds.size() <= 6 and w.room_flags.summoned <= 8 and w.bullets.size() <= 240 and w.zones.size() <= 48, "boss phases respect global attack and summon bounds: " + boss_row.id)
		w.kill_enemy(boss, "primary")
		w.enemies = w.enemies.filter(func(e): return not e.dead)
		expect(w.run.bosses_defeated.has(boss_row.id), "boss discovery is committed before dead actors are removed: " + boss_row.id)
		expect(adds.all(func(e): return e.dead), "boss death cancels all of its owned guards: " + boss_row.id)
	w = sandbox()
	w.mode = "checkpoint"
	w.run.room = 10
	w.advance_room()
	expect(w.run.floor == 2 and w.choices.size() == 2 and w.choices.all(func(c): return c.kind == "skill"), "second region always opens an exclusive two-choice evolution")
	w.skip_choice()
	expect(w.mode == "choice", "mandatory evolution cannot be silently skipped")
	loaded = World.new()
	loaded.restore(Store.decode(Store.encode(w.snapshot())))
	expect(loaded.take_choice(1) and loaded.run.room == 0 and loaded.mode == "combat" and loaded.player.skill == "s03", "restored evolution enters the first second-region combat without skipping it")
	w = sandbox()
	w.mode = "shop"
	w.run.coins = 30
	for i in range(1, 13): w.run.relics["r%02d" % i] = 1
	w.choices = [{"kind": "relic", "id": "r17", "price": 18}]
	expect(w.take_choice(0) and w.mode == "replace" and w.run.coins == 30, "full inventory opens replacement before spending currency")
	loaded = World.new()
	loaded.restore(Store.decode(Store.encode(w.snapshot())))
	expect(loaded.replace_relic("r01") and loaded.run.relics.size() == 12 and loaded.stack("r17") == 1 and loaded.run.coins == 12, "replacement survives reload and atomically swaps one slot")
	var meta = Progress.new("user://expanded_test_profile")
	meta.data.merit = 100
	meta.data.unlocks = []
	meta.data.bosses = ["b01"]
	meta.data.runs = {}
	meta.data.personal.c_paper.stage = 0
	expect(meta.purchase("u_fire_mid") and not meta.purchase("u_fire_mid") and meta.data.merit == 80, "permanent purchase debits only once")
	w = sandbox()
	w.run.id = "profile-ledger-fixture"
	w.run.merit = 7
	meta.observe(w)
	var credit = meta.data.merit
	meta.observe(w)
	expect(meta.data.merit == credit, "observing a recovered run cannot duplicate earned merit")
	var reloaded_meta = Progress.new("user://expanded_test_profile")
	reloaded_meta.observe(w)
	expect(reloaded_meta.data.merit == credit and reloaded_meta.relic_pool().has("r04"), "profile purchase and earned-credit ledger survive process-level reload")
	var report = {"count": checks.size(), "checks": checks, "failures": failures, "passed": failures.is_empty(),
		"method": "deterministic integration fixtures, not an unmodified player playthrough"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expanded-content-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Expanded content checks: %d; failures: %d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
