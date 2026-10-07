extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Impact = preload("res://scripts/combat/impact_control.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Transfer = preload("res://scripts/core/save_transfer.gd")
const Pattern = preload("res://scripts/combat/enemy_patterns.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Damage = preload("res://scripts/core/damage_record.gd")
var checks: Array = []
var failures: Array = []
var journal_path = ""

func _initialize() -> void: call_deferred("run_suite")
func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)
func digest(value) -> String: return JSON.stringify(Store.encode(value), "", true, true).sha256_text()
func fresh(character: String = "c_paper", seed_value: int = 6813):
	var w = World.new()
	w.start(character, seed_value, 3)
	w.enemies.clear()
	w.bullets.clear()
	w.zones.clear()
	w.delayed.clear()
	w.geometry.build("room_open_1", 1)
	w.player.pos = Vector2(640, 460)
	w.player.aim = Vector2.UP
	w.player.invulnerable = 30
	w.events.clear()
	return w
func target(w, elite: bool = false, position: Vector2 = Vector2(640, 340)) -> Dictionary:
	var e = w.spawn_enemy("e01", position, elite)
	e.hp = 10000.0
	e.max_hp = e.hp
	e.speed = 0.0
	e.attack_cd = 99.0
	return e
func settle(w, e: Dictionary, ticks: int = 12) -> void:
	for i in ticks: w.update_enemies(1.0 / 60.0)
func on_disk(w, name: String):
	var store = Store.new(journal_path.path_join(name))
	var wrote = store.write(w.snapshot())
	var data = Store.new(store.folder).read()
	var clone = World.new()
	if not wrote or not clone.restore(data):
		print("Resume diagnostic ", name, ": ", World.Migration.world(data))
		return null
	return clone
func same_continuation(w, clone, ticks: int = 60) -> bool:
	if clone == null: return false
	for i in ticks:
		var frame = {"move": Vector2.ZERO, "aim": Vector2.UP, "fire": false}
		w.tick(frame)
		clone.tick(frame)
	return digest(w.snapshot()) == digest(clone.snapshot())

func run_suite() -> void:
	journal_path = "user://impact_resume_%d" % Time.get_ticks_usec()
	var w = fresh()
	var e = target(w)
	var original = Vector2(e.pos)
	w.shoot_input(true, 1.0 / 60.0)
	w.update_bullets(.3)
	expect(e.hp < 10000 and e.pos == original and e.get("push_left", 0) > 0, "a real primary projectile deals damage and schedules impact without teleporting the enemy")
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 26) < .001 and e.push_left == 0 and e.push_remaining == Vector2.ZERO, "a light projectile moves its target twenty-six units and completes its short impulse")
	w = fresh("c_mask")
	e = target(w)
	original = e.pos
	w.player.weapon = "w04"
	w.shoot_input(true, 1.0 / 60.0)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 64) < .001 and e.hp < 10000, "the real heavy seal cone produces the designed stronger sixty-four-unit impact")
	w = fresh()
	e = target(w)
	original = e.pos
	w.primary_hit(e, 10, 1, true)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 64) < .001, "a critical primary hit has heavy impact while retaining ordinary damage and marking rules")
	w = fresh()
	e = target(w, true)
	original = e.pos
	w.primary_hit(e, 10, 1)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 13) < .001, "an elite receives half of the ordinary light physical displacement")
	w = fresh()
	e = w.spawn_boss("b01")
	e.attack_cd = 99
	e.speed = 0
	original = e.pos
	w.primary_hit(e, 10, 1)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 3.9) < .001, "a real boss retains eighty-five-percent resistance without losing all impact feedback")
	w = fresh()
	e = target(w)
	original = e.pos
	w.run.relics = {"r27": 1}
	w.player.still = .4
	w.primary_hit(e, 10, 1)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 33.8) < .001, "the threshold stone grants thirty-percent additional primary impact rather than thirty flat units")
	w = fresh()
	e = target(w)
	w.run.relics = {"r27": 1}
	w.player.still = .4
	w.shoot_input(true, 1.0 / 60.0)
	w.player.weapon = "w04"
	w.player.still = 0
	original = e.pos
	w.update_bullets(.3)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 33.8) < .001, "an already emitted projectile retains its original weapon and threshold-stone impact after equipment and stance change")
	w = fresh()
	e = target(w)
	w.primary_hit(e, 10, 7)
	var remaining = e.push_remaining
	w.primary_hit(e, 10, 7)
	expect(e.hp == 9980 and e.mark == 1 and e.push_remaining == remaining, "multiple pellets from one primary attack still damage but cannot multiply its mark or displacement impulse")
	w = fresh()
	e = target(w)
	w.damage_enemy(e, 10, "secondary")
	original = e.pos
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 13) < .001, "secondary hits provide restrained impact and do not inherit the primary-only threshold-stone bonus")
	w = fresh()
	e = target(w)
	w.damage_enemy(e, 3, "burn")
	expect(e.pos == Vector2(640, 340) and e.get("push_left", 0) == 0, "periodic burn damage does not continually shove a target")
	w = fresh()
	e = target(w)
	w.damage_enemy(e, 10, "primary", false, Vector2.LEFT)
	original = e.pos
	settle(w, e)
	expect((e.pos - original).is_equal_approx(Vector2(-26, 0)), "physical direction follows an actual traveling hit instead of the player's new position")
	w = fresh()
	e = target(w)
	var before = digest({"rng": w.rng.state, "streams": w.snapshot().streams, "uid": w.uid})
	Impact.push(w, e, Vector2.RIGHT, 64)
	settle(w, e)
	expect(before == digest({"rng": w.rng.state, "streams": w.snapshot().streams, "uid": w.uid}), "physical integration neither consumes a random draw nor creates an entity")
	w = fresh()
	e = target(w)
	Impact.push(w, e, Vector2.RIGHT, 64)
	original = e.pos
	Impact.tick(w, e, 1.0 / 60.0)
	var first_step = e.pos.x - original.x
	original = e.pos
	Impact.tick(w, e, 1.0 / 60.0)
	expect(first_step > e.pos.x - original.x and first_step > 0, "the short impact decelerates after a strong first step")
	w = fresh()
	e = target(w)
	for i in 60: Impact.push(w, e, Vector2.RIGHT, 64)
	expect(e.push_remaining.length() <= 112.001, "simultaneous chain hits have a bounded pending displacement")
	w.geometry.blocks = [Rect2(715, 260, 64, 200)]
	original = e.pos
	settle(w, e)
	expect(e.pos.x < 715 - e.radius + .001 and w.geometry.valid_circle(e.pos, e.radius) and e.pos.x > original.x, "an extreme impact cannot tunnel through a solid obstacle")
	w = fresh()
	e = target(w, false, Vector2(1185, 340))
	Impact.push(w, e, Vector2.RIGHT, 112)
	settle(w, e)
	expect(w.geometry.valid_circle(e.pos, e.radius) and e.pos.x <= World.Geometry.AREA.end.x - e.radius, "a heavy impact cannot push an actor outside the room boundary")
	w = fresh()
	e = target(w)
	e.arrival = w.time + .8
	w.primary_hit(e, 10, 1)
	Impact.push(w, e, Vector2.RIGHT, 64)
	expect(e.hp == 10000 and e.get("push_left", 0) == 0, "a telegraphed arriving enemy cannot be damaged or moved early")
	e.arrival = 0
	w.damage_enemy(e, 10001, "primary")
	Impact.push(w, e, Vector2.RIGHT, 64)
	original = e.pos
	settle(w, e)
	expect(e.dead and e.pos == original and e.push_left == 0, "death immediately cancels physical displacement and its future collision authority")
	w = fresh("c_bell")
	w.player.skill = "s05"
	var ordinary = target(w)
	var elite = target(w, true, Vector2(700, 340))
	var boss = w.spawn_boss("b01")
	for actor in [ordinary, elite, boss]: w.add_mark(actor, 3)
	w.update_chains()
	w.player.energy = 100
	w.cast_skill()
	expect(absf(ordinary.stun_until - w.time - .5) < .001 and absf(elite.stun_until - w.time - .3) < .001 and boss.stun_until == 0, "the real red-net skill binds ordinary targets for half a second, elites for three tenths and never roots a boss")
	Impact.root(w, ordinary, 4)
	Impact.root(w, elite, 4)
	Impact.root(w, boss, 4)
	expect(absf(ordinary.stun_until - w.time - .8) < .001 and absf(elite.stun_until - w.time - .3) < .001 and boss.stun_until == 0, "all root requests obey the authored ordinary and elite caps and boss immunity")
	for skill in ["s12", "s15"]:
		w = fresh("c_mask" if skill == "s12" else "c_umbrella")
		w.player.skill = skill
		w.player.energy = 100
		e = target(w)
		w.add_mark(e, 3)
		w.update_chains()
		original = e.pos
		var cast = w.cast_skill()
		settle(w, e)
		expect(cast and absf(e.pos.distance_to(original) - (85 if skill == "s12" else 50)) < .001, "the real " + skill + " special preserves its authored impact without a duplicate teleport")
	w = fresh()
	e = target(w)
	w.primary_hit(e, 10, 1)
	w.tick({})
	var clone = on_disk(w, "active-impact")
	expect(clone != null and digest(clone.snapshot()) == digest(w.snapshot()), "a partially completed physical impulse survives a real native checkpoint exactly")
	expect(same_continuation(w, clone), "restored and original physical impact continue with identical collisions, HP, drops and RNG for sixty actual ticks")
	var malformed = w.snapshot()
	malformed.enemies[0].push_left = 9.0
	expect(not World.Migration.world(malformed).ok, "a corrupt excessively long physical impulse is protected before restoration")
	malformed = w.snapshot()
	malformed.enemies[0].push_remaining = Vector2(900, 0)
	expect(not World.Migration.world(malformed).ok, "a corrupt oversized pending displacement cannot enter a resumed world")
	var legacy = w.snapshot()
	for actor in legacy.enemies:
		actor.erase("push_left")
		actor.erase("push_remaining")
	expect(World.Migration.world(legacy).ok, "old snapshots without physical impulse fields remain valid")
	# Construct pending states through real producer interfaces, not synthetic queues.
	for producer in ["e13", "e18", "e22", "elite-fan", "debt-pair", "repeat-tool"]:
		w = fresh()
		e = target(w)
		if producer == "debt-pair":
			var other = target(w, false, Vector2(740, 340))
			w.run.contracts = [{"id": "d02", "interest": 0}]
			w.room_flags.debt_pair = [e.uid, other.uid]
			w.room_flags.debt_fire_at = 0
			w.update_enemies(.01)
		elif producer == "repeat-tool":
			w.run.relics = {"r40": 1}
			for i in 2:
				w.player.shot_cd = 0
				w.shoot_input(true, .01)
		else:
			e.id = "e01" if producer == "elite-fan" else producer
			if producer == "elite-fan": e.elite_id = "x01"
			Pattern.attack(w, e)
		expect(not w.delayed.is_empty(), "the real " + producer + " producer creates a pending attack state")
		clone = on_disk(w, producer)
		expect(clone != null and same_continuation(w, clone, 90), "the real " + producer + " deferred attack resumes from disk and matches ninety uninterrupted ticks")
	w = fresh()
	e = target(w)
	e.id = "e18"
	Pattern.attack(w, e)
	var bundle = {"version": 2, "content_version": w.db.catalog.version, "profile": World.Migration.profile({}).data, "checkpoint": w.snapshot()}
	var inspected = Transfer.inspect_code(Transfer.export_code(bundle))
	expect(inspected.ok and digest(inspected.data.checkpoint) == digest(w.snapshot()), "offline transfer also preserves a real pending enemy fan")
	var bad = w.snapshot()
	bad.delayed[0].count = 99999
	expect(not World.Migration.world(bad).ok, "invalid fan counts are rejected before replay allocation")
	bad = w.snapshot()
	bad.delayed[0].aim = "lost-vector"
	expect(not World.Migration.world(bad).ok, "a malformed optional saved fan aim cannot reach the combat loop")
	bad = w.snapshot()
	bad.delayed[0].type = "future-delayed-type"
	expect(not World.Migration.world(bad).ok, "unknown future delayed attacks still receive protection instead of silent substitution")
	w = fresh()
	e = target(w)
	e.id = "e18"
	Pattern.attack(w, e)
	e.dead = true
	clone = on_disk(w, "canceled-emitter")
	var canceled_matches = same_continuation(w, clone, 90)
	expect(clone != null and canceled_matches and clone.bullets.is_empty(), "a saved canceled emitter stays canceled after reload without resurrecting its pending attack")
	w = fresh()
	clone = on_disk(w, "unopened-loot-stream")
	var lazy_stream_absent = not w.streams.has("f1/r0/loot")
	var offer = w.relic_offer(3)
	var resumed_offer = clone.relic_offer(3) if clone != null else []
	expect(lazy_stream_absent and clone != null and digest(offer) == digest(resumed_offer) and digest(w.snapshot().streams) == digest(clone.snapshot().streams), "a not-yet-created loot stream uses the same numeric seed after real JSON restoration")
	w = fresh()
	w.run.relics = {"r32": 1}
	w.player.invulnerable = 0
	w.damage_player(1)
	clone = on_disk(w, "spent-goldbody")
	if clone != null:
		clone.player.invulnerable = 0
		clone.damage_player(1)
	expect(clone != null and clone.player.hp == clone.player.max_hp - 1 and clone.run.favors_used.size() == 1, "JSON restoration cannot renew an already-spent chapter gold-body protection by changing the floor's numeric string")
	w.run.favors_used = {"goldbody_1.0": true}
	clone = on_disk(w, "legacy-decimal-goldbody")
	if clone != null:
		clone.player.invulnerable = 0
		clone.damage_player(1)
	expect(clone != null and clone.player.hp == clone.player.max_hp - 1 and clone.run.favors_used.has("goldbody_1.0"), "a genuine legacy decimal chapter key remains spent without rewriting or granting the protection again")
	w = fresh()
	w.run.relics = {"r21": 1}
	w.run.talents = ["t_seal_3b"]
	w.player.hp = 2
	Effects.clear_room(w, "elite")
	clone = on_disk(w, "spent-elite-favors")
	if clone != null: Effects.clear_room(clone, "elite")
	expect(clone != null and clone.player.hp == w.player.hp and clone.run.favors_used.size() == w.run.favors_used.size(), "actual elite-clear heal and armor favors retain their same once-per-chapter identity across disk reload")
	w.run.favors_used = {"dish_1.0": true, "copper_1.0": true}
	clone = on_disk(w, "legacy-decimal-elite-favors")
	if clone != null: Effects.clear_room(clone, "elite")
	expect(clone != null and clone.player.hp == w.player.hp and clone.run.favors_used.size() == 2, "legacy decimal elite-favor keys remain consumed across native reload")
	var elite_sources_valid = true
	var elite_runtime_valid = true
	var elite_runtime_rows: Array = []
	for variant in w.db.rows("elite_variants"):
		w = fresh()
		e = w.spawn_enemy(variant.base_enemy, Vector2(640, 300), true, false, variant.id)
		var source = w.source_of(e, "projectile")
		var base = w.db.row("enemies", variant.base_enemy)
		var expected_tell = maxf(0.35, float(base.telegraph_ms) / 1000.0 * float(variant.telegraph_multiplier))
		w.kill_enemy(e, "projectile")
		var ash_rows = w.pickups.filter(func(p): return p.kind == "ash")
		var ash_value = int(ash_rows[0].value) if not ash_rows.is_empty() else -1
		elite_sources_valid = elite_sources_valid and Damage.valid_source(source, w.db) and Damage.name_of(w.db, source) == variant.name
		var row_valid = is_equal_approx(e.max_hp, float(base.health) * float(variant.health_multiplier)) and is_equal_approx(e.tell, expected_tell) and e.damage == int(base.damage) + int(variant.damage_bonus) and ash_value == int(variant.natural_ash) and e.elite_id == variant.id
		elite_runtime_valid = elite_runtime_valid and row_valid
		elite_runtime_rows.append({"id": variant.id, "health": e.max_hp, "expected_health": float(base.health) * float(variant.health_multiplier), "tell": e.tell, "expected_tell": expected_tell, "damage": e.damage, "expected_damage": int(base.damage) + int(variant.damage_bonus), "ash": ash_value, "expected_ash": int(variant.natural_ash), "passed": row_valid})
	expect(elite_sources_valid, "all six actual elite variants retain their authored identity through source validation and review naming")
	expect(elite_runtime_valid, "all six elite variants consume authored health, telegraph, damage and natural ash values in the real spawn and death paths")
	w = fresh()
	e = target(w)
	Impact.push(w, e, Vector2.ZERO, 64)
	expect(e.get("push_left", 0) == 0, "a directionless hit cannot create a hidden movement lock")
	w = fresh()
	e = w.spawn_enemy("e09", Vector2(640, 340))
	e.hp = 10000
	e.speed = 0
	e.attack_cd = 99
	e.aim = Vector2.DOWN
	original = e.pos
	w.primary_hit(e, 20, 1)
	settle(w, e)
	expect(absf(e.pos.distance_to(original) - 5.2) < .001, "a real frontal copper shield reduces physical impact together with the blocked damage")
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/impact-resume-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "elite_runtime": elite_runtime_rows,
		"scope": "real primary/skill/collision interfaces, decelerating fixed-tick integration, root resistance, native checkpoint and compressed transfer of actual deferred producers; human impact feel remains a separate playtest"}, "\t"))
	file.close()
	print("Impact and pending-attack resume: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
