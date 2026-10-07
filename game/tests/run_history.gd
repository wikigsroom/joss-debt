extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Pattern = preload("res://scripts/combat/enemy_patterns.gd")
const Boss = preload("res://scripts/combat/boss_patterns.gd")
const Damage = preload("res://scripts/core/damage_record.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
var checks: Array = []
var failures: Array = []
class MemoryJournal extends RefCounted:
	var data: Dictionary = {}
	var reject = false
	func read() -> Dictionary: return data.duplicate(true)
	func write(value: Dictionary) -> bool:
		if reject: return false
		data = value.duplicate(true)
		return true

func _initialize() -> void: call_deferred("run_suite")
func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)
func digest(value) -> String: return JSON.stringify(Store.encode(value), "", true, true).sha256_text()
func fresh(seed_value: int = 9261):
	var w = World.new()
	w.start("c_paper", seed_value, 3)
	w.enemies.clear()
	w.bullets.clear()
	w.zones.clear()
	w.delayed.clear()
	w.events.clear()
	w.geometry.build("room_open_1", 1)
	w.player.pos = Vector2(640, 400)
	w.player.invulnerable = 0
	w.time = 2.0
	return w
func strike(w, source: Dictionary, damage: int = 1) -> void:
	w.player.invulnerable = 0
	w.enemy_bullet(w.player.pos - Vector2(0, 100), Vector2.DOWN, 300, damage, 7, source)
	w.update_bullets(.4)

func run_suite() -> void:
	var w = fresh()
	var e = w.spawn_enemy("e03", Vector2(640, 240))
	var rng_before = digest({"rng": w.rng.state, "streams": w.snapshot().streams, "uid": w.uid})
	var source = w.source_of(e, "projectile")
	expect(rng_before == digest({"rng": w.rng.state, "streams": w.snapshot().streams, "uid": w.uid}), "recording an attack identity does not consume RNG, a random stream or an entity ID")
	w.enemy_bullet(Vector2(640, 300), Vector2.DOWN, 300, 1, 7, source)
	w.enemies.clear()
	var journal = Store.new("user://run_history_%d" % Time.get_ticks_usec())
	var written = journal.write(w.snapshot())
	var resumed = World.new()
	var restored = resumed.restore(Store.new(journal.folder).read())
	if not restored:
		push_error("source snapshot rejected: " + str(Migration.world(w.snapshot())))
		quit(1)
		return
	resumed.update_bullets(.4)
	expect(written and resumed.run.damage_history.size() == 1 and resumed.run.damage_history[0].source.id == "e03", "a real emitted projectile preserves its removed attacker through a native journal and restored collision")
	expect(resumed.run.damage_history[0].direction.is_equal_approx(Vector2.UP) and resumed.run.damage_history[0].hp_after == resumed.run.damage_history[0].hp_before - 1, "projectile damage records the incoming direction and exact before/after HP")
	var pattern_failures: Array = []
	for row in w.db.rows("enemies"):
		var arena = fresh()
		var enemy = arena.spawn_enemy(row.id, Vector2(640, 240))
		Pattern.attack(arena, enemy)
		arena.time += 1
		arena.update_delayed(0)
		for attack in arena.bullets + arena.zones:
			if not attack.get("friendly", false) and (not Damage.valid_source(attack.get("source"), arena.db) or attack.source.id != row.id): pattern_failures.append(row.id)
	expect(pattern_failures.is_empty(), "all twenty-four normal enemy attack producers and deferred fans retain the actual attacker")
	var boss_failures: Array = []
	for row in w.db.rows("bosses"):
		for phase in 3:
			var arena = fresh()
			var boss = arena.spawn_boss(row.id)
			boss.phase = phase
			Boss.attack(arena, boss)
			for attack in arena.bullets + arena.zones:
				if not attack.get("friendly", false) and (not Damage.valid_source(attack.get("source"), arena.db) or attack.source.id != row.id or attack.source.table != "bosses"): boss_failures.append([row.id, phase])
	expect(boss_failures.is_empty(), "all fifteen boss phase attack producers attribute bullets and zones to their actual boss")
	w = fresh()
	e = w.spawn_enemy("e01", w.player.pos + Vector2(10, 0))
	e.attack_cd = 99
	w.update_enemies(.01)
	expect(w.run.damage_history.size() == 1 and w.run.damage_history[0].source.kind == "contact" and w.run.damage_history[0].source.id == "e01", "real enemy contact is recorded separately from projectiles")
	w = fresh()
	e = w.spawn_enemy("e02", w.player.pos - Vector2(5, 0))
	e.aim = Vector2.RIGHT
	e.lunge = .4
	w.update_enemies(.01)
	expect(w.run.damage_history.size() == 1 and w.run.damage_history[0].source.kind == "lunge", "real lunge collision records the charging attacker")
	w = fresh()
	e = w.spawn_boss("b03")
	Pattern.lane(w, Vector2(400, 400), Vector2(850, 400), 22, .8, .4, 1, w.source_of(e, "zone"))
	w.enemies.clear()
	w.update_zones(0)
	expect(w.run.damage_history.is_empty(), "a telegraphed hostile lane cannot record damage before its warning finishes")
	w.time += .81
	w.update_zones(0)
	expect(w.run.damage_history.size() == 1 and w.run.damage_history[0].source.id == "b03" and w.run.damage_history[0].source.kind == "zone", "an active ground lane retains its boss after the emitter is removed")
	w = fresh()
	e = w.spawn_enemy("e14", Vector2(1210, 310))
	e.aim = Vector2.RIGHT
	Pattern.attack(w, e)
	w.update_bullets(.1)
	expect(w.bullets.size() == 3 and w.bullets.all(func(b): return b.source.id == "e14" and b.source.kind == "split"), "wall collision propagates the original attacker to all three returning split bullets")
	w = fresh()
	e = w.spawn_enemy("e18", Vector2(640, 250))
	Pattern.attack(w, e)
	w.time += .7
	w.update_delayed(0)
	expect(w.bullets.size() == 3 and w.bullets.all(func(b): return b.source.id == "e18"), "a delayed fan resolves its real living emitter at emission time")
	w = fresh()
	e = w.spawn_enemy("e18", Vector2(640, 250))
	Pattern.attack(w, e)
	e.dead = true
	w.time += .7
	w.update_delayed(0)
	expect(w.bullets.is_empty(), "source metadata does not make a canceled dead-emitter fan fire")
	w = fresh()
	var a = w.spawn_enemy("e01", Vector2(440, 200))
	var b = w.spawn_enemy("e03", Vector2(840, 200))
	w.delayed.append({"type": "debt_bullet", "time": w.time, "pos": w.player.pos - Vector2(0, 100), "aim": Vector2.DOWN, "pair": [a.uid, b.uid]})
	w.update_delayed(0)
	w.update_bullets(.65)
	expect(w.run.damage_history.size() == 1 and w.run.damage_history[0].source.table == "debt_contracts" and w.run.damage_history[0].source.id == "d02" and w.run.damage_history[0].source.kind == "debt", "a real delayed debt-pair projectile attributes damage to the d02 contract")
	w = fresh()
	e = w.spawn_boss("b04")
	var clone = w.enemies.filter(func(enemy): return enemy.get("clone", false))[0]
	var clone_source = w.source_of(clone, "projectile")
	expect(clone_source.id == "b04" and clone_source.table == "bosses" and clone_source.role == "clone" and Damage.name_of(w.db, clone_source).ends_with("分身"), "an original boss clone identifies its owner and distinct clone role")
	w = fresh()
	w.player.armor = 1
	strike(w, source)
	var hit = w.run.damage_history[0]
	expect(hit.raw == 1 and hit.damage == 0 and hit.absorbed == 1 and hit.hp_after == hit.hp_before and Damage.valid_record(hit, w.db), "armor records a blocked attack without falsely reducing HP")
	var history_count = w.run.damage_history.size()
	w.damage_player(1, source)
	expect(w.run.damage_history.size() == history_count, "invulnerability does not append a second injury for a protected hit")
	w = fresh()
	w.run.relics = {"r32": 1}
	strike(w, source, 2)
	hit = w.run.damage_history[0]
	expect(hit.raw == 2 and hit.damage == 1 and hit.absorbed == 1 and w.stats.damage_taken == 1, "gold-body protection retains actual absorbed and applied damage")
	w = fresh()
	w.run.relics = {"r29": 1}
	w.player.hp = 1
	strike(w, source)
	hit = w.run.damage_history[0]
	expect(hit.revived and not hit.lethal and hit.hp_after == 1 and w.run.death_cause.is_empty() and w.run.consumed.has("r29") and Damage.valid_record(hit, w.db), "a real revival consumes the relic and records survival rather than a death cause")
	var killer = Damage.normalize({"id": "b02", "table": "bosses", "kind": "projectile"}, Vector2(640, 200))
	strike(w, killer)
	expect(w.mode == "result" and w.run.result == "defeat" and w.run.death_cause.source.id == "b02" and not w.run.death_cause.revived, "a later lethal hit records its own attacker after the consumed revival")
	var terminal = digest(w.snapshot())
	w.damage_player(1, source)
	w.tick({"fire": true, "skill": true})
	expect(terminal == digest(w.snapshot()), "a finished run cannot accumulate new hits or advance combat")
	var terminal_validation = Migration.world(w.snapshot())
	if not terminal_validation.ok: print("Terminal restore diagnostic: ", terminal_validation.message)
	var death_written = journal.write(w.snapshot())
	var death_read = journal.read()
	var death_validation = Migration.world(death_read)
	if not death_written or not death_validation.ok: print("Death journal diagnostic: ", death_written, " / ", death_validation)
	expect(terminal_validation.ok and death_written and World.new().restore(death_read), "the terminal death cause and revival history survive validated native persistence")
	w = fresh()
	w.player.hp = 50
	w.player.max_hp = 50
	for i in 15:
		w.time = 2 + i
		strike(w, source)
	expect(w.run.damage_history.size() == 12 and w.run.damage_history[0].at == 5 and w.run.damage_history[-1].at == 16, "the retained history is bounded to the twelve most recent genuine hits")
	var legacy = w.snapshot()
	legacy.run.erase("damage_history")
	legacy.run.erase("death_cause")
	w.enemy_bullet(Vector2(500, 200), Vector2.DOWN, 150)
	legacy.bullets = w.bullets.duplicate(true)
	for bullet in legacy.bullets: bullet.erase("source")
	var migrated = Migration.world(legacy)
	expect(migrated.ok and migrated.data.run.damage_history.is_empty() and migrated.data.run.death_cause.is_empty(), "legacy runs without provenance remain playable with honest empty history")
	var bad = w.snapshot()
	bad.run.damage_history[-1].source.id = "missing-attacker"
	expect(not Migration.world(bad).ok, "an unknown attacker in persisted history is protected instead of renamed")
	bad = w.snapshot()
	bad.run.damage_history[-1].absorbed = 99
	expect(not Migration.world(bad).ok, "a damaged applied/absorbed total is rejected before restore")
	bad = w.snapshot()
	bad.run.damage_history[-1].hp_after = 99
	expect(not Migration.world(bad).ok, "a mismatched before/after HP record is rejected")
	bad = w.snapshot()
	bad.run.death_cause = bad.run.damage_history[-1].duplicate(true)
	expect(not Migration.world(bad).ok, "a nonlethal injury cannot masquerade as the persisted last lethal hit")
	bad = w.snapshot()
	bad.bullets[0].source.kind = "future-attack"
	expect(not Migration.world(bad).ok, "an unsupported persisted projectile source cannot enter the simulator")
	var storage = MemoryJournal.new()
	var account = Progress.new("", storage)
	w = fresh(9272)
	w.run.merit = 7
	w.stats.detonations = 6
	w.stats.max_chain = 3
	w.run.bosses_defeated = ["b01", "b03"]
	for route in w.db.row("characters", "c_paper").routes:
		w.run.talents.append(w.db.rows("talents").filter(func(t): return t.route == route)[0].id)
	account.observe(w)
	var ledger = account.data.runs[w.run.id]
	expect(account.data.merit == 53 and ledger.merit == 7 and ledger.bonus_merit == 46 and ledger.personal_pages == [1, 2, 3] and ledger.new_bosses == ["b01", "b03"], "the run ledger distinguishes seven earned merit, sixteen first-boss bonus and thirty actually completed personal-page merit")
	expect(ledger.characters_unlocked.has("c_bell") and ledger.characters_unlocked.has("c_lantern") and Migration.profile(account.data).ok, "the ledger records only real newly unlocked characters and passes account validation")
	var paid = digest(account.data)
	account.observe(w)
	account = Progress.new("", storage)
	account.observe(w)
	expect(paid == digest(account.data), "repeat observation and a fresh account reader cannot pay or attribute the same pages twice")
	w.run.id = "later-run"
	account.observe(w)
	ledger = account.data.runs[w.run.id]
	expect(ledger.personal_pages.is_empty() and ledger.new_bosses.is_empty() and ledger.characters_unlocked.is_empty() and ledger.bonus_merit == 0 and ledger.merit == 7, "a later run does not claim already completed global pages, first bosses or unlocks")
	paid = digest(account.data)
	w.run.merit += 5
	storage.reject = true
	account.observe(w)
	expect(paid == digest(account.data), "failed native credit writes roll back the visible account and per-run earned total")
	storage.reject = false
	w.run.training = true
	account.observe(w)
	expect(paid == digest(account.data), "training does not create a committed run ledger or earn merit even when directly observed")
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/run-history-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "real native collision, emitter removal, checkpoint restore, mitigation, revival, deferred patterns and committed account ledger; presentation reviewed by native GUI captures"}, "\t"))
	file.close()
	print("Run history: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
