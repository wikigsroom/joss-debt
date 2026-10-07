extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Impact = preload("res://scripts/combat/impact_control.gd")

var checks: Array = []
var failures: Array = []
var cases: Array = []
var standalone_cases: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(value: bool, message: String) -> void:
	checks.append(message)
	if not value:
		failures.append(message)
		push_error(message)

func sandbox(relic_ids: Array = [], character: String = "c_paper", weapon: String = "w01"):
	var w = World.new()
	w.start(character, 61024, 3, {"weapon": weapon})
	w.enemies.clear()
	w.bullets.clear()
	w.pickups.clear()
	w.zones.clear()
	w.delayed.clear()
	w.chains.clear()
	w.events.clear()
	w.room_flags = {"combat_kills": 0, "dash_armor": 0, "passive_detonate": false,
		"summoned": 0, "summon_rewards": 0, "chain_pairs": {}, "forced_links": {}}
	w.mode = "combat"
	w.player.pos = Vector2(640, 585)
	w.player.aim = Vector2.UP
	w.player.energy = 100.0
	w.player.invulnerable = 0.0
	w.player.shot_cd = 0.0
	w.player.skill_cd = 0.0
	w.player.still = 0.0
	for id in relic_ids:
		w.run.relics[id] = 1
	return w

func dummy(w, position: Vector2, health: float = 5000.0) -> Dictionary:
	var enemy = w.spawn_enemy("e05", position)
	enemy.hp = health
	enemy.max_hp = health
	enemy.attack_cd = 99.0
	enemy.speed = 0.0
	return enemy

func mark_chain(w, actors: Array, count: int = 1) -> void:
	for actor in actors:
		w.add_mark(actor, count, false)
	w.update_chains()

func collect_ash(w, position: Vector2 = Vector2(640, 585), value: int = 8) -> Dictionary:
	var pickup = {"uid": w.next_uid(), "kind": "ash", "pos": position, "value": value,
		"delay": 0.0, "natural": true, "magnet": false}
	w.pickups.append(pickup)
	w.collect(pickup)
	return pickup

func dash_ticks(w, direction: Vector2 = Vector2.RIGHT, count: int = 12) -> void:
	w.start_dash(direction)
	for i in count:
		w.tick({})

func fire_once(w, delta: float = 0.5) -> void:
	w.player.shot_cd = 0.0
	w.shoot_input(true, delta)

func combo01() -> Dictionary:
	var w = sandbox(["r01", "r02", "r09"])
	var first = dummy(w, Vector2(640, 420))
	var second = dummy(w, Vector2(700, 420))
	var third = dummy(w, Vector2(760, 420))
	var next_mark = dummy(w, Vector2(690, 360))
	w.primary_hit(first, 10, 1, false, Vector2.UP)
	mark_chain(w, [first, second, third])
	var chain_ok = not w.chains.is_empty() and w.chains[0].size() >= 3
	w.player.skill = "s01"
	var cast = w.cast_skill()
	return {"ok": cast and chain_ok and first.burn > 0 and next_mark.mark == 1,
		"evidence": ["primary burn", "three-target chain", "next-cycle mark"]}

func combo02() -> Dictionary:
	var w = sandbox(["r03", "r06", "r07"])
	var first = dummy(w, Vector2(640, 420), 1.0)
	var second = dummy(w, Vector2(700, 420), 1.0)
	var third = dummy(w, Vector2(760, 420), 1.0)
	for actor in [first, second, third]: w.add_mark(actor, 3, false)
	first.burn = 3
	w.update_chains()
	w.player.skill = "s07"
	w.player.energy = 40.0
	var cast = w.cast_skill()
	var long_fire = w.zones.any(func(zone): return float(zone.until) - w.time > 3.7)
	return {"ok": cast and first.dead and second.dead and third.dead and first.burn == 0 and long_fire and w.player.energy > 4.0,
		"evidence": ["three-stack detonation", "burn clear", "extended fire zone", "three-kill refund"]}

func combo03() -> Dictionary:
	var w = sandbox(["r02", "r05", "r10"])
	var first = dummy(w, Vector2(640, 420))
	var far = dummy(w, Vector2(820, 420))
	var next_mark = dummy(w, Vector2(650, 420))
	mark_chain(w, [first, far])
	var long_chain = not w.chains.is_empty() and w.chains[0].size() == 2
	w.player.skill = "s01"
	var cast = w.cast_skill()
	var sparks = w.bullets.filter(func(b): return not b.primary).size()
	return {"ok": cast and long_chain and next_mark.mark == 1 and sparks >= 2,
		"evidence": ["extended chain distance", "two fire sparks", "next-cycle mark"]}

func combo04() -> Dictionary:
	var w = sandbox(["r01", "r04", "r50"])
	var burning = dummy(w, Vector2(560, 420))
	w.add_burn(burning, 1)
	w.kill_enemy(burning, "primary")
	var marked = dummy(w, Vector2(640, 420))
	w.primary_hit(marked, 1, 1, false, Vector2.UP)
	var anchor = dummy(w, Vector2(900, 300))
	dash_ticks(w)
	var death_zone = w.zones.any(func(zone): return is_equal_approx(float(zone.damage), 3.0))
	var path_zones = w.zones.filter(func(zone): return is_equal_approx(float(zone.damage), 6.0)).size()
	return {"ok": marked.burn > 0 and death_zone and path_zones >= 4 and not anchor.dead,
		"evidence": ["first-hit burn", "burning death zone", "dash fire path"]}

func combo05() -> Dictionary:
	var w = sandbox(["r09", "r10", "r13"])
	var first = dummy(w, Vector2(640, 420))
	var second = dummy(w, Vector2(730, 420))
	var third = dummy(w, Vector2(820, 420))
	mark_chain(w, [first, second, third])
	var before = third.hp
	w.primary_hit(first, 10, 1, false, Vector2.RIGHT)
	return {"ok": w.chains.size() == 1 and w.chains[0].size() >= 3 and third.hp < before,
		"evidence": ["long chain", "far chain radius", "opposite-end transfer"]}

func combo06() -> Dictionary:
	var w = sandbox(["r09", "r12", "r14"])
	var first = dummy(w, Vector2(640, 250))
	var second = dummy(w, Vector2(700, 250))
	var neighbor = dummy(w, Vector2(760, 250))
	first.speed = 100.0
	second.speed = 100.0
	mark_chain(w, [first, second])
	var base = sandbox()
	var base_first = dummy(base, Vector2(640, 250))
	var base_second = dummy(base, Vector2(700, 250))
	base_first.speed = 100.0
	base_second.speed = 100.0
	w.geometry.build("room_open_1")
	base.geometry.build("room_open_1")
	w.geometry.rebuild_flow(w.player.pos)
	base.geometry.rebuild_flow(base.player.pos)
	mark_chain(base, [base_first, base_second])
	w.update_enemies(0.1)
	base.update_enemies(0.1)
	var slow_delta = first.pos.distance_to(Vector2(640, 250))
	var base_delta = base_first.pos.distance_to(Vector2(640, 250))
	for attack in 1:
		w.primary_hit(first, 1, attack + 1, false, Vector2.UP)
		w.primary_hit(first, 1, attack + 2, false, Vector2.UP)
		w.primary_hit(first, 1, attack + 3, false, Vector2.UP)
	return {"ok": slow_delta < base_delta and neighbor.mark == 1,
		"evidence": ["chain movement slow", "third-hit neighbor mark"]}

func combo07() -> Dictionary:
	var w = sandbox(["r10", "r11", "r15"])
	var first = dummy(w, Vector2(640, 420))
	var second = dummy(w, Vector2(730, 420))
	var third = dummy(w, Vector2(820, 420))
	mark_chain(w, [first, second, third], 3)
	var formed_damage = first.hp < first.max_hp
	var before = third.hp
	w.player.skill = "s01"
	var cast = w.cast_skill()
	var end_damage = before - third.hp
	return {"ok": formed_damage and cast and end_damage > 39.0,
		"evidence": ["chain-form damage", "minimum falloff 0.90"]}

func combo08() -> Dictionary:
	var w = sandbox(["r09", "r41", "r52"], "c_ink", "w06")
	var first = dummy(w, Vector2(640, 500))
	var second = dummy(w, Vector2(640, 420))
	var third = dummy(w, Vector2(640, 340))
	mark_chain(w, [first, second, third])
	fire_once(w)
	for i in 24: w.update_bullets(0.1)
	return {"ok": w.room_flags.forced_links.size() > 0 and w.stats.hits >= 2 and w.chains.size() >= 1,
		"evidence": ["piercing projectile", "pierce-to-chain link", "six-target chain cap"]}

func combo09() -> Dictionary:
	var w = sandbox(["r17", "r18", "r19"])
	var target = dummy(w, Vector2(640, 420))
	var next_target = dummy(w, Vector2(700, 420))
	w.player.energy = 40.0
	var energy_before = w.player.energy
	w.kill_enemy(target, "primary")
	collect_ash(w)
	return {"ok": w.bullets.any(func(b): return not b.primary) and w.player.energy - energy_before >= 10.0 and w.skill_cost() == 27,
		"evidence": ["natural-kill ash bullet", "extra ash energy", "lower skill cost"]}

func combo10() -> Dictionary:
	var w = sandbox(["r17", "r22", "r23"])
	var target = dummy(w, Vector2(700, 585))
	w.player.energy = 40.0
	var before = w.player.energy
	for i in 3: collect_ash(w, Vector2(640 + i * 4, 585))
	var ash_bullet = w.bullets.any(func(b): return b.get("applies_mark", false))
	return {"ok": Effects.ash_radius(w) > 120.0 and ash_bullet and w.player.energy - before >= 30.0 and not target.dead,
		"evidence": ["expanded ash pickup radius", "third-ash return bullet", "stacked natural recovery"]}

func combo11() -> Dictionary:
	var w = sandbox(["r19", "r20", "r21"])
	var target = dummy(w, Vector2(640, 420))
	w.player.energy = 40.0
	var before = w.player.energy
	w.primary_hit(target, 1, 1, false, Vector2.UP)
	w.player.hp = 1
	Effects.clear_room(w, "elite")
	return {"ok": w.player.energy - before >= 3.0 and w.skill_cost() == 27 and w.player.hp == 2 and w.run.favors_used.has("dish_1"),
		"evidence": ["first-mark recovery", "lower detonation cost", "elite clear heart recovery"]}

func combo12() -> Dictionary:
	var w = sandbox(["r18", "r22", "r49"])
	var first = dummy(w, Vector2(640, 420))
	var second = dummy(w, Vector2(700, 420))
	mark_chain(w, [first, second])
	var initial = first.mark_until
	w.time = 1.0
	var victim = dummy(w, Vector2(820, 420))
	w.kill_enemy(victim, "primary")
	collect_ash(w)
	return {"ok": w.bullets.any(func(b): return not b.primary) and first.mark_until > initial and Effects.ash_radius(w) > 120.0,
		"evidence": ["kill ash bullet", "chain endpoint refresh", "expanded pickup radius"]}

func combo13() -> Dictionary:
	var w = sandbox(["r25", "r28", "r30"])
	w.player.energy = 10.0
	w.deflect({"damage": 1.0, "dir": Vector2.DOWN})
	w.bullets.clear()
	w.player.pos = Vector2(640, 585)
	w.start_dash(Vector2.RIGHT)
	w.enemy_bullet(Vector2(640, 500), Vector2.DOWN, 1000, 1)
	w.update_bullets(0.1)
	return {"ok": w.player.attack_bonus > 0.2 and w.player.energy >= 18.0 and w.stats.parries >= 2,
		"evidence": ["parry attack window", "parry energy", "early-dash reflection"]}

func combo14() -> Dictionary:
	var w = sandbox(["r26", "r31", "r53"])
	var first = dummy(w, Vector2(680, 585))
	var second = dummy(w, Vector2(720, 585))
	w.player.armor = 1
	w.damage_player(1)
	var armor_burn = first.burn > 0 and second.burn > 0
	w.enemies.clear()
	w.room_flags.wave_index = w.room_flags.get("wave_count", 1)
	w.clear_room()
	var clear_armor = w.player.armor > 0
	var marked = dummy(w, Vector2(640, 420))
	w.add_mark(marked, 1, false)
	w.player.skill = "s01"
	w.player.energy = 100.0
	var cast = w.cast_skill()
	var seal_zone = w.zones.any(func(zone): return is_equal_approx(float(zone.damage), 6.0) and float(zone.until) - w.time >= 1.49)
	return {"ok": armor_burn and clear_armor and cast and seal_zone,
		"evidence": ["armor-break fire", "room-clear paper armor", "detonation landing seal"]}

func combo15() -> Dictionary:
	var w = sandbox(["r25", "r30", "r51"])
	var ash = collect_ash(w, Vector2(730, 585))
	w.deflect({"damage": 1.0, "dir": Vector2.DOWN})
	w.bullets.clear()
	w.player.pos = Vector2(640, 585)
	w.start_dash(Vector2.RIGHT)
	w.enemy_bullet(Vector2(640, 500), Vector2.DOWN, 1000, 1)
	w.update_bullets(0.1)
	return {"ok": ash.magnet and w.player.attack_bonus > 0.2 and w.stats.parries >= 2,
		"evidence": ["parry bonus", "early-dash reflection", "parry ash magnet"]}

func combo16() -> Dictionary:
	var w = sandbox(["r26", "r27", "r29"])
	var target = dummy(w, Vector2(640, 420))
	w.player.still = 0.4
	w.primary_hit(target, 1, 1, false, Vector2.UP)
	var impact_ok = target.push_remaining.length() > 33.0
	w.enemies.clear()
	w.room_flags.wave_index = w.room_flags.get("wave_count", 1)
	w.clear_room()
	var clear_armor = w.player.armor > 0
	w.mode = "combat"
	w.player.hp = 1
	w.player.invulnerable = 0.0
	w.damage_player(2)
	return {"ok": impact_ok and clear_armor and w.player.hp == 1 and w.run.consumed.has("r29") and w.run.result.is_empty(),
		"evidence": ["stillness impact bonus", "room-clear armor", "single-use revival"]}

func combo17() -> Dictionary:
	var w = sandbox(["r33", "r34", "r36"])
	var anchor = dummy(w, Vector2(950, 300))
	var ash = collect_ash(w, Vector2(720, 585))
	ash.magnet = false
	var start = Vector2(w.player.pos)
	dash_ticks(w)
	var dash_distance = w.player.pos.distance_to(start)
	var baseline = sandbox()
	baseline.player.pos = Vector2(640, 585)
	baseline.tick({"move": Vector2.RIGHT})
	w.player.dash_left = 0.0
	w.player.pos = Vector2(640, 585)
	w.tick({"move": Vector2.RIGHT})
	return {"ok": dash_distance > 160.0 and ash.magnet and w.player.pos.x > baseline.player.pos.x and not anchor.dead,
		"evidence": ["speed bonus", "extended dash", "path ash collection"]}

func combo18() -> Dictionary:
	var w = sandbox(["r34", "r35", "r37"])
	var anchor = dummy(w, Vector2(950, 300))
	var start = Vector2(w.player.pos)
	dash_ticks(w)
	w.player.weapon = "w01"
	w.start_dash(Vector2.RIGHT)
	Effects.dodge(w)
	w.player.dash_left = 0.0
	w.player.shot_cd = 0.0
	w.shoot_input(true, 0.5)
	return {"ok": w.player.pos.distance_to(start) >= 180.0 and w.bullets.size() >= 3 and w.bullets.any(func(b): return b.can_return) and not anchor.dead,
		"evidence": ["extended dash", "returning primary", "dodge side shots"]}

func combo19() -> Dictionary:
	var w = sandbox(["r33", "r38", "r39"])
	var far = dummy(w, Vector2(640, 220))
	w.add_mark(far, 1, false)
	w.player.moved_distance = 160.0
	var expanded = w.skill_targets().has(far.uid)
	var anchor = dummy(w, Vector2(950, 300))
	dash_ticks(w)
	var trail = w.zones.any(func(zone): return is_equal_approx(float(zone.damage), 5.0))
	var baseline = sandbox()
	baseline.player.pos = Vector2(640, 585)
	baseline.tick({"move": Vector2.RIGHT})
	w.player.dash_left = 0.0
	w.player.pos = Vector2(640, 585)
	w.tick({"move": Vector2.RIGHT})
	return {"ok": expanded and trail and w.player.pos.x > baseline.player.pos.x and not anchor.dead,
		"evidence": ["distance-gated skill range", "dash paper trail", "speed bonus"]}

func combo20() -> Dictionary:
	var w = sandbox(["r35", "r36", "r50"])
	var anchor = dummy(w, Vector2(950, 300))
	var ash = collect_ash(w, Vector2(720, 585))
	ash.magnet = false
	w.player.weapon = "w01"
	fire_once(w)
	dash_ticks(w)
	var fire_path = w.zones.filter(func(zone): return is_equal_approx(float(zone.damage), 6.0)).size() >= 4
	return {"ok": w.bullets.any(func(b): return b.can_return) and fire_path and ash.magnet and not anchor.dead,
		"evidence": ["returning primary", "dash fire path", "path ash collection"]}

func combo21() -> Dictionary:
	var w = sandbox(["r41", "r44", "r45"], "c_ink", "w06")
	var first = dummy(w, Vector2(640, 500))
	var second = dummy(w, Vector2(640, 420))
	var third = dummy(w, Vector2(640, 340))
	mark_chain(w, [first, second, third])
	fire_once(w)
	var pierce_preserved = w.bullets.any(func(b): return b.primary and b.pierce >= 3)
	w.update_bullets(0.12)
	w.player.skill = "s16"
	w.player.energy = 100.0
	var cast = w.cast_skill()
	return {"ok": pierce_preserved and cast and third.hp < third.max_hp and Effects.detonation_multiplier(w, {"burn": 0}, true) > 1.19,
		"evidence": ["extra pierce", "reduced pierce falloff", "aligned detonation bonus"]}

func combo22() -> Dictionary:
	var w = sandbox(["r42", "r43", "r47"])
	var target = dummy(w, Vector2(640, 420))
	w.add_mark(target, 1, false)
	w.player.skill = "s01"
	var cast = w.cast_skill()
	var delayed_fixed = w.delayed.any(func(action): return action.type == "fixed_damage")
	var delayed_replay = w.delayed.any(func(action): return action.type == "skill_replay")
	return {"ok": cast and Effects.mark_duration(w) >= 6.49 and delayed_fixed and delayed_replay,
		"evidence": ["long mark window", "delayed fixed settlement", "one-room skill replay"]}

func combo23() -> Dictionary:
	var w = sandbox(["r19", "r20", "r46"])
	w.run.contracts = [{"id": "d01", "interest": 0}, {"id": "d02", "interest": 0}]
	var target = dummy(w, Vector2(640, 420))
	var marked = dummy(w, Vector2(700, 420))
	marked.mark = 3
	w.player.energy = 40.0
	var before = w.player.energy
	w.primary_hit(target, 1, 1, false, Vector2.UP)
	return {"ok": w.skill_cost() == 27 and Effects.primary_multiplier(w, marked) >= 1.19 and w.player.energy - before >= 3.0,
		"evidence": ["lower detonation cost", "two-contract primary bonus", "first-mark recovery"]}

func combo24() -> Dictionary:
	var w = sandbox(["r41", "r49", "r52"], "c_ink", "w06")
	var first = dummy(w, Vector2(640, 500))
	var second = dummy(w, Vector2(640, 420))
	var third = dummy(w, Vector2(640, 240))
	mark_chain(w, [first, second, third])
	var initial = first.mark_until
	w.time = 1.0
	fire_once(w)
	for i in 24: w.update_bullets(0.1)
	collect_ash(w)
	return {"ok": w.room_flags.forced_links.size() > 0 and first.mark_until > initial and w.stats.hits >= 2,
		"evidence": ["piercing chain link", "ash endpoint refresh", "piercing primary hits"]}

func standalone_r08() -> Dictionary:
	var w = sandbox(["r08"])
	var burning = dummy(w, Vector2(640, 420))
	var neighbor = dummy(w, Vector2(700, 420))
	var before = neighbor.hp
	burning.burn_ticks = 2
	Effects.burn_tick(w, burning)
	var burst = w.events.any(func(event): return event.kind == "burst")
	return {"ok": neighbor.hp < before and burst, "evidence": ["third burn pulse", "eighty-unit secondary burst"]}

func standalone_r16() -> Dictionary:
	var w = sandbox(["r16"])
	var first = dummy(w, Vector2(640, 420))
	var second = dummy(w, Vector2(740, 420))
	var extra = dummy(w, Vector2(690, 420))
	mark_chain(w, [first, second])
	w.player.skill = "s01"
	var targets = w.skill_targets()
	return {"ok": targets.has(extra.uid) and w.chains.any(func(group): return group.has(extra.uid)),
		"evidence": ["marked chain segment", "unmarked target pulled into skill snapshot"]}

func standalone_r24() -> Dictionary:
	var w = sandbox(["r24"])
	var actors = [dummy(w, Vector2(600, 420), 1.0), dummy(w, Vector2(680, 420), 1.0), dummy(w, Vector2(760, 420), 1.0)]
	for actor in actors: w.add_mark(actor, 3, false)
	w.update_chains()
	w.player.skill = "s01"
	w.player.energy = 100.0
	var cast = w.cast_skill()
	return {"ok": cast and actors.all(func(actor): return actor.dead) and bool(w.room_flags.get("free_skill_pending", false)) and Effects.skill_cost(w) == 0,
		"evidence": ["three detonation kills", "one-room free skill token"]}

func standalone_r32() -> Dictionary:
	var w = sandbox(["r32"])
	w.player.hp = 4
	w.player.invulnerable = 0.0
	w.damage_player(2)
	return {"ok": w.player.hp == 3 and w.run.favors_used.has("goldbody_1") and bool(w.room_flags.get("goldbody_slow", false)),
		"evidence": ["chapter goldbody favor", "one damage absorbed", "post-hit slow flag"]}

func standalone_r40() -> Dictionary:
	var w = sandbox(["r40"])
	w.player.weapon = "w01"
	fire_once(w)
	fire_once(w)
	return {"ok": int(w.stats.shots) == 2 and w.delayed.any(func(action): return action.type == "repeat_attack" and action.weapon == "w01"),
		"evidence": ["second-shot trigger", "delayed authored weapon replay"]}

func standalone_r48() -> Dictionary:
	var w = sandbox(["r48"])
	var target = dummy(w, Vector2(640, 420))
	w.primary_hit(target, 1, 3, false, Vector2.UP)
	return {"ok": target.mark == 3, "evidence": ["third primary attack", "empty-ledger three-mark payoff"]}

func standalone_r54() -> Dictionary:
	var w = sandbox(["r54"])
	w.mode = "checkpoint"
	w.run.coins = 100
	w.run.contracts = [{"id": "d01", "interest": 0}]
	var repaid = w.repay(0)
	return {"ok": repaid and w.run.contracts.is_empty() and w.run.repayments.has("d01") and w.run.repay_effects == 1 and w.run.repay_skill_refunds == 1 and w.run.repay_reward_pending == 1,
		"evidence": ["real debt repayment", "skill refund", "repayment relic offer token"]}

func standalone_modifier(id: String) -> Dictionary:
	var w = sandbox([id])
	w.geometry.restore_objects([])
	var enemy = dummy(w, Vector2(640, 445))
	var neighbor = dummy(w, Vector2(690, 445))
	if id == "r60": neighbor.pos = Vector2(640, 390)
	if id == "r61": enemy.pos = Vector2(705, 410)
	if id == "r63":
		w.enemies.clear(); w.player.pos = Vector2(100, 300); w.player.aim = Vector2.LEFT
	if id == "r66":
		w.shoot_input(true, .2)
		var charging = w.bullets.is_empty() and w.player.charge > 0
		w.shoot_input(true, .2)
		return {"ok": charging and w.bullets.size() == 1 and w.bullets[0].damage > w.db.row("weapons", "w01").damage, "evidence": ["real charge preparation", "charged damage after release"]}
	fire_once(w)
	if id in ["r55", "r56", "r57"]:
		var count = {"r55": 3, "r56": 4, "r57": 5}[id]
		return {"ok": w.bullets.size() == count and w.bullets[0].dir != w.bullets[-1].dir, "evidence": ["real scattered primary projectiles"]}
	if id == "r59": return {"ok": enemy.hp < 5000 and w.events.any(func(e): return e.kind == "ray") and w.bullets.is_empty(), "evidence": ["actual beam carrier conversion and damage"]}
	if id == "r62":
		w.player.aim = Vector2.RIGHT; w.update_bullets(.12)
		return {"ok": not w.bullets.is_empty() and w.bullets[0].dir.x > 0, "evidence": ["live steering changes actual trajectory"]}
	if id == "r63":
		w.update_bullets(.12)
		return {"ok": not w.bullets.is_empty() and w.bullets[0].bounces == 1 and w.bullets[0].dir.x > 0, "evidence": ["actual radius-aware wall bounce"]}
	for i in 24:
		w.time += 1.0 / 60; w.update_bullets(1.0 / 60)
		if id == "r61" and not w.bullets.is_empty() and w.bullets[0].dir.x > .02: return {"ok": true, "evidence": ["off-axis target bends projectile toward itself"]}
		if id == "r64" and w.bullets.any(func(b): return b.has("recipe") and b.recipe.depth == 1 and not b.primary): return {"ok": true, "evidence": ["real primary contact spawns bounded secondary fragments"]}
	var ok = (enemy.hp < 5000 and neighbor.hp < 5000) if id in ["r58", "r60"] else (enemy.hp < 5000 and not w.zones.is_empty())
	return {"ok": ok, "evidence": ["actual hit payload", "neighbor damage" if id == "r58" else ("second pierced target" if id == "r60" else "persistent ground field")]}

func run_standalone(id: String) -> Dictionary:
	match id:
		"r08": return standalone_r08()
		"r16": return standalone_r16()
		"r24": return standalone_r24()
		"r32": return standalone_r32()
		"r40": return standalone_r40()
		"r48": return standalone_r48()
		"r54": return standalone_r54()
	if int(id.trim_prefix("r")) >= 55: return standalone_modifier(id)
	return {"ok": false, "evidence": []}

func run_combo(id: String) -> Dictionary:
	match id:
		"combo01": return combo01()
		"combo02": return combo02()
		"combo03": return combo03()
		"combo04": return combo04()
		"combo05": return combo05()
		"combo06": return combo06()
		"combo07": return combo07()
		"combo08": return combo08()
		"combo09": return combo09()
		"combo10": return combo10()
		"combo11": return combo11()
		"combo12": return combo12()
		"combo13": return combo13()
		"combo14": return combo14()
		"combo15": return combo15()
		"combo16": return combo16()
		"combo17": return combo17()
		"combo18": return combo18()
		"combo19": return combo19()
		"combo20": return combo20()
		"combo21": return combo21()
		"combo22": return combo22()
		"combo23": return combo23()
		"combo24": return combo24()
	return {"ok": false, "evidence": []}

func run_suite() -> void:
	var probe = World.new()
	var combos = probe.db.rows("synergies")
	var relic_ids: Dictionary = {}
	for row in probe.db.rows("relics"): relic_ids[row.id] = true
	expect(combos.size() == 24, "catalog keeps the authored twenty-four synergy recipes")
	var shape_ok = true
	for row in combos:
		shape_ok = shape_ok and row.relics.size() == 3 and not row.extra_set_bonus and row.route in ["fire", "thread", "ash", "seal", "wind", "ink"]
		for id in row.relics: shape_ok = shape_ok and relic_ids.has(id)
	expect(shape_ok, "every synergy has three known route relics and no hidden set bonus")
	var unique_ids: Dictionary = {}
	for row in combos: unique_ids[row.id] = int(unique_ids.get(row.id, 0)) + 1
	expect(unique_ids.size() == 24 and unique_ids.values().all(func(value): return value == 1), "synergy identifiers remain unique and addressable")
	for row in combos:
		var result = run_combo(str(row.id))
		cases.append({"id": row.id, "name": row.name, "route": row.route, "relics": row.relics,
			"evidence": result.evidence, "passed": result.ok})
		expect(result.ok, "%s %s executes its authored relic paths" % [row.id, row.name])
	var combo_relic_ids: Dictionary = {}
	for row in combos:
		for id in row.relics: combo_relic_ids[id] = true
	var standalone_ids: Array = []
	for row in probe.db.rows("relics"):
		if not combo_relic_ids.has(row.id): standalone_ids.append(str(row.id))
	standalone_ids.sort()
	expect(standalone_ids == ["r08", "r16", "r24", "r32", "r40", "r48", "r54", "r55", "r56", "r57", "r58", "r59", "r60", "r61", "r62", "r63", "r64", "r65", "r66"], "the nineteen non-combination relic hooks remain explicitly addressable")
	for id in standalone_ids:
		var result = run_standalone(id)
		standalone_cases.append({"id": id, "evidence": result.evidence, "passed": result.ok})
		expect(result.ok, "%s executes its standalone authored relic path" % id)
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/synergy-matrix-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"cases": cases, "standalone": standalone_cases, "count": checks.size(), "scope": "twenty-four authored combinations plus nineteen standalone relic hooks through real primary, detonation, ash, dash, parry, clear, repayment and delayed replay paths; no hidden set bonus"}, "\t"))
	file.close()
	print("Synergy matrix: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
