extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const Profile = preload("res://scripts/ui/input_profile.gd")
const Styles = preload("res://scripts/combat/projectile_styles.gd")
var checks: Array = []
var failures: Array = []
var samples: Dictionary = {}

func _initialize() -> void: call_deferred("suite")
func expect(id: String, value: bool, detail = "") -> void:
	checks.append({"id": id, "passed": value, "detail": str(detail)})
	if not value: failures.append(id); print("EQUIPMENT FAIL: ", id, " ", detail)
func fresh(seed_value: int = 924873819001):
	var w = World.new()
	w.start("c_paper", seed_value, 11, {"seed_text": str(seed_value)})
	w.geometry.restore_objects([])
	w.enemies.clear(); w.bullets.clear(); w.zones.clear(); w.pickups.clear(); w.delayed.clear(); w.take_events()
	w.room_flags.wave_index = w.room_flags.wave_count
	w.run.relics = {}; w.run.talents = []
	w.mode = "combat"; w.player.pos = Vector2(420, 390); w.player.aim = Vector2.RIGHT
	w.player.hp = 12; w.player.max_hp = 12; w.player.energy = 0; w.player.shot_cd = 0
	return w
func target(w, point: Vector2 = Vector2(550, 390)) -> Dictionary:
	var e = w.spawn_enemy("e01", point)
	e.hp = 10000; e.max_hp = 10000; e.speed = 0; e.attack_cd = 100; e.arrival = 0
	return e
func step(w, count: int) -> void:
	for i in count:
		w.time += 1.0 / 60; w.player.item_cd = maxf(0, w.player.item_cd - 1.0 / 60)
		w.update_bullets(1.0 / 60); w.update_delayed(1.0 / 60); w.update_zones(1.0 / 60)
func roundtrip(w):
	var state = Store.decode(JSON.parse_string(JSON.stringify(Store.encode(w.snapshot()))))
	var next = World.new()
	expect("roundtrip_" + str(checks.size()), next.restore(state), Migration.world(state).get("message", ""))
	return next

func suite() -> void:
	var w = fresh()
	expect("starter_active_fully_charged_and_empty_single_trinket", w.run.active_item.id == "a01" and w.run.active_item.charge == 3 and w.run.trinket == "")
	for row in w.db.rows("active_items"):
		var active = fresh()
		var e = target(active, Vector2(485, 390) if row.effect == "lotus_guard" else Vector2(550, 390))
		active.run.active_item = {"id": row.id, "charge": float(row.charge_rooms)}
		active.player.hp = 8
		if row.effect == "reroll_ground": World.Equipment.spawn(active, "trinket", "tr01", Vector2(480, 420), {}, 0)
		if row.effect == "ash_bell": active.pickups.append({"uid": active.next_uid(), "kind": "coin", "value": 4, "pos": Vector2(800, 260), "delay": 0, "magnet": false, "natural": false})
		if row.effect in ["mirror", "freeze"]: active.enemy_bullet(active.player.pos + Vector2(65, 0), Vector2.LEFT, 150, 1, 7, active.source_of(e, "projectile"))
		var prior_coins = active.run.coins
		expect(row.id + "_activation_consumes_charge_once", active.use_active_item() and active.run.active_item.charge == 0 and active.stats.active_uses == 1)
		expect(row.id + "_repeated_press_has_no_free_effect", not active.use_active_item() and active.stats.active_uses == 1)
		var immediate = true
		match row.effect:
			"heal": immediate = active.player.hp == 10
			"mirror": immediate = active.player.invulnerable >= 1.6 and active.bullets.all(func(b): return b.friendly)
			"ink_field": immediate = active.zones.any(func(z): return z.get("item_slow", false) and z.radius == 158)
			"lotus_guard": immediate = active.zones.any(func(z): return z.get("follows_player", false)) and active.player.invulnerable >= 1.1
			"ash_bell": immediate = active.run.coins == prior_coins + 4 and active.player.energy == 20
			"reroll_ground": immediate = active.pickups.size() == 1 and active.pickups[0].id != "tr01"
			"freeze": immediate = active.bullets.is_empty() and e.stun_until == 2
			"haste": immediate = is_equal_approx(active.stat_multiplier("move_speed"), 1.4) and is_equal_approx(active.stat_multiplier("fire_rate"), 1.25)
			"thread_beams": immediate = active.events.filter(func(event): return event.kind == "ray").size() == 5
			"seekers": immediate = active.bullets.size() == 6 and active.bullets.all(func(b): return not b.primary and b.recipe.homing)
		expect(row.id + "_real_authored_effect", immediate)
		var restored = roundtrip(active)
		step(active, 90); step(restored, 90)
		expect(row.id + "_inflight_effect_restore_deterministic", is_equal_approx(active.enemies[0].hp, restored.enemies[0].hp) and active.bullets.size() == restored.bullets.size() and active.delayed.size() == restored.delayed.size())
		if row.effect in ["bombs", "chain_lightning", "seekers", "thread_beams", "ink_field", "lotus_guard"]: expect(row.id + "_deals_real_damage", e.hp < 10000, 10000 - e.hp)
		active.time = 5
		if row.effect == "haste": expect("expired_haste_removes_all_bonuses", active.stat_multiplier("move_speed") == 1 and active.stat_multiplier("fire_rate") == 1)

	w = fresh()
	w.run.active_item = {"id": "a02", "charge": 6.0}
	expect("full_health_heal_does_not_spend_charge", not w.use_active_item() and w.run.active_item.charge == 6)
	w.run.active_item = {"id": "a09", "charge": 6.0}
	expect("empty_room_reroll_does_not_spend_charge", not w.use_active_item() and w.run.active_item.charge == 6)
	w.run.active_item = {"id": "a01", "charge": 0.0}; w.run.trinket = "tr11"
	World.Equipment.charge(w)
	expect("charge_efficiency_preserves_fractional_charge", w.run.active_item.charge == 1.5)
	var battery = World.Equipment.spawn(w, "battery", "battery", w.player.pos, {}, 0)
	expect("battery_adds_one_charge_not_amplified", World.Equipment.take(w, battery) and w.run.active_item.charge == 2.5)
	World.Equipment.charge(w)
	battery = World.Equipment.spawn(w, "battery", "battery", w.player.pos, {}, 0)
	expect("full_charge_battery_stays_on_ground", not World.Equipment.take(w, battery) and w.pickups.has(battery))
	w.run.active_item.charge = 0.5
	var drop = World.Equipment.spawn(w, "active", "a12", w.player.pos, {}, 0)
	expect("active_swap_places_actual_depleted_old_item_on_ground", World.Equipment.take(w, drop) and w.run.active_item.id == "a12" and w.pickups.any(func(p): return p.kind == "active" and p.id == "a01" and p.gear_state.charge == .5))
	var old = w.pickups.filter(func(p): return p.kind == "active")[0]; old.delay = 0
	expect("picking_old_active_does_not_refill_charge", World.Equipment.take(w, old) and w.run.active_item.id == "a01" and w.run.active_item.charge == .5)
	expect("repeat_pickup_cannot_duplicate_inventory", not World.Equipment.take(w, old))
	w = fresh(); target(w)
	w.run.active_item.charge = 0.0
	World.Equipment.spawn(w, "trinket", "tr01", w.player.pos, {}, 0)
	w.clear_room(); var once = w.run.active_item.charge
	w.clear_room()
	expect("clearing_room_charges_once_and_keeps_equipment", once == 1 and w.run.active_item.charge == once and w.pickups.any(func(p): return p.kind == "trinket"))
	var resumed = roundtrip(w)
	resumed.clear_room()
	expect("restored_room_cannot_farm_charge", resumed.run.active_item.charge == once)

	w = fresh()
	for row in w.db.rows("trinkets"):
		var previous = str(w.run.trinket)
		drop = World.Equipment.spawn(w, "trinket", row.id, w.player.pos, {}, 0)
		expect(row.id + "_one_slot_swap_and_attribute", World.Equipment.take(w, drop) and w.run.trinket == row.id and is_equal_approx(w.stat_bonus(row.stat), float(row.value)) and (previous.is_empty() or w.pickups.any(func(p): return p.kind == "trinket" and p.id == previous)))
		var clone = roundtrip(w)
		expect(row.id + "_restored_slot_and_attribute", clone.run.trinket == row.id and is_equal_approx(clone.stat_bonus(row.stat), float(row.value)))
	w = fresh()
	for i in 80:
		var id = "tr01" if i % 2 == 0 else "tr03"
		drop = World.Equipment.spawn(w, "trinket", id, w.player.pos, {}, 0)
		World.Equipment.take(w, drop)
		w.pickups.clear()
	expect("eighty_swaps_do_not_accumulate_attributes", w.stat_bonus("damage") == 0 and is_equal_approx(w.stat_bonus("move_speed"), .12))

	# Real low-rate sampler; isolated named RNG leaves encounter and ordinary loot untouched.
	w = fresh(); var ordinary_state = w.roll("loot").state
	var total = 20000
	for kind in ["normal", "elite", "boss", "room"]:
		var hits = 0
		for i in total:
			w.reward_ledger.clear(); w.room_flags.rare_drop_count = 0
			if World.Equipment.rare_drop(w, "sample", kind, Vector2(500, 420)): hits += 1
			w.pickups.clear(); w.take_events()
		var chance = float(w.db.equipment.rare_drops[kind])
		var tolerance = 5 * sqrt(total * chance * (1 - chance))
		expect(kind + "_low_probability_actual_sampling", absf(hits - total * chance) <= tolerance, str(hits) + "/" + str(total))
		samples[kind] = {"trials": total, "drops": hits, "observed": float(hits) / total, "authored": chance}
	expect("rare_rng_does_not_change_ordinary_loot", w.roll("loot").state == ordinary_state)
	w = fresh(); var summon = target(w); summon.summoned = true; summon.natural_reward = true
	for i in 100: World.Equipment.death_drop(w, summon)
	expect("summons_cannot_roll_rare_equipment", w.pickups.is_empty() and not w.streams.keys().any(func(k): return str(k).contains("rare_drops")))
	w.run.training = true
	expect("training_cannot_produce_loot", not World.Equipment.rare_drop(w, "training", "boss", w.player.pos))
	w = fresh()
	World.Equipment.rare_drop(w, "same_enemy", "boss", w.player.pos)
	var rng_before = w.roll("rare_drops/v1/boss").state
	World.Equipment.rare_drop(w, "same_enemy", "boss", w.player.pos)
	expect("same_enemy_roll_and_restored_ledger_are_once_only", w.roll("rare_drops/v1/boss").state == rng_before)
	resumed = roundtrip(w); World.Equipment.rare_drop(resumed, "same_enemy", "boss", resumed.player.pos)
	expect("restore_cannot_reroll_enemy_drop", resumed.roll("rare_drops/v1/boss").state == rng_before)
	w = fresh(); w.run.room = w.run.graph.types.find("reward"); w.enter_room()
	expect("treasure_room_authored_trinket_pedestal", w.pickups.size() == 1 and w.pickups[0].kind == "trinket")
	var cached = w.pickups.duplicate(true); World.Equipment.treasure_cache(w)
	expect("treasure_pedestal_cannot_duplicate", w.pickups == cached)
	w.take_choice(0); w.run.visited.append(int(w.run.room)); w.run.room_history[str(int(w.run.room))] = {"template": w.geometry.template_id, "pickups": w.pickups.duplicate(true), "flags": w.room_flags.duplicate(true), "objects": w.geometry.objects.duplicate(true)}
	w.enter_room()
	expect("room_return_keeps_ground_equipment_identity", w.pickups == cached)

	# Every real weapon fires into the same fixed targets with combined modifiers.
	var variants = [[], ["r55"], ["r56"], ["r55", "r56", "r57"], ["r55", "r58"], ["r56", "r59"], ["r55", "r56", "r57", "r58", "r59", "r60"], ["r58", "r61", "r62", "r63", "r64", "r65", "r66"]]
	for weapon in w.db.rows("weapons"):
		for index in variants.size():
			var sandbox = fresh(); sandbox.player.weapon = weapon.id
			for id in variants[index]: sandbox.run.relics[id] = 1
			var e = target(sandbox, Vector2(535, 390))
			var neighbor = target(sandbox, Vector2(555, 420))
			sandbox.shoot_input(true, 1.0)
			var emitted = sandbox.events.filter(func(event): return event.kind == "shot")
			var expected = 5 if index in [3, 6] else (4 if index in [2, 5] else (3 if index in [1, 4] else int(weapon.pellets)))
			expected = maxi(expected, 3 if weapon.mode == "prism" else int(weapon.pellets))
			expect(weapon.id + "/" + str(index) + "_one_composed_root_shot_count", emitted.size() == 1 and int(emitted[0].pellets) == expected)
			step(sandbox, 100)
			expect(weapon.id + "/" + str(index) + "_real_combined_damage", e.hp < 10000 or neighbor.hp < 10000, 20000 - e.hp - neighbor.hp)
			var validation = Migration.world(sandbox.snapshot())
			expect(weapon.id + "/" + str(index) + "_combined_effects_saveable", validation.ok, validation.get("message", ""))
			expect(weapon.id + "/" + str(index) + "_bounded_without_recursion", sandbox.bullets.size() <= 240 and sandbox.zones.size() <= 48 and sandbox.delayed.size() <= 120 and int(sandbox.stats.get("max_proc_events", 0)) <= 48)

	w = fresh(); w.player.weapon = "w14"; w.run.relics = {"r55": 1, "r56": 1, "r57": 1, "r58": 1}
	var e = target(w, Vector2(540, 390)); target(w, Vector2(545, 420))
	w.shoot_input(true, 1)
	expect("five_beams_not_sixty_and_payload_damage_deduplicated", w.events.filter(func(event): return event.kind == "ray").size() == 5 and w.room_flags.composition_ledger.keys().filter(func(k): return str(k).ends_with("blast/target/" + str(int(e.uid)))).size() == 1)
	w = fresh(); w.player.weapon = "w01"; w.run.relics = {"r55": 1, "r58": 1, "r64": 1, "r40": 1}; w.stats.shots = 1
	e = target(w, Vector2(550, 390)); w.shoot_input(true, 1)
	var frozen = w.bullets[0].recipe.duplicate(true)
	w.run.relics = {}; w.player.weapon = "w02"
	expect("flight_and_echo_keep_original_recipe_after_swap", w.bullets[0].recipe == frozen and w.delayed.any(func(a): return a.type == "repeat_attack" and a.recipe.pellets == 3 and a.recipe.explosive and not a.recipe.primary))
	resumed = roundtrip(w); step(w, 30); step(resumed, 30)
	expect("combined_split_explosion_echo_resume_identical_damage", is_equal_approx(w.enemies[0].hp, resumed.enemies[0].hp))
	w = fresh(); w.player.weapon = "w15"; w.run.relics = {"r55": 1, "r61": 1, "r62": 1}; target(w)
	w.shoot_input(true, 1); w.player.aim = Vector2.UP; w.update_bullets(.12)
	expect("controlled_homing_scatter_steers_each_lane", w.bullets.size() == 3 and w.bullets.all(func(b): return b.dir.y < 0))

	# Legacy and malformed snapshots; failed restores cannot mutate live worlds.
	w = fresh(); var state = w.snapshot()
	state.run.erase("active_item"); state.run.erase("trinket"); state.run.erase("equipment_seen"); state.player.erase("item_cd"); state.player.erase("item_buffs")
	resumed = World.new()
	expect("old_v2_run_gains_safe_equipment_defaults", resumed.restore(state) and resumed.run.active_item.id == "a01" and resumed.run.trinket.is_empty())
	var corruptions = ["dual_trinket", "unknown_active", "negative_charge", "over_charge", "unknown_drop", "invalid_recipe", "invalid_ground_transaction"]
	for kind in corruptions:
		state = fresh().snapshot()
		match kind:
			"dual_trinket": state.run.trinket = ["tr01", "tr02"]
			"unknown_active": state.run.active_item.id = "a99"
			"negative_charge": state.run.active_item.charge = -1
			"over_charge": state.run.active_item.charge = 99
			"unknown_drop": state.pickups.append({"uid": 900, "kind": "trinket", "id": "tr99", "value": 1, "pos": Vector2(500, 420), "delay": 0, "natural": false, "magnet": false, "gear_state": {}})
			"invalid_recipe":
				var recipe = World.Composer.recipe(w, w.db.row("weapons", "w01")); recipe.pellets = 100
				state.delayed.append({"type": "composition_fire", "time": 1, "weapon": "w01", "damage": 10, "pos": Vector2(500, 420), "aim": Vector2.UP, "crit": false, "burst_part": false, "recipe": recipe})
			"invalid_ground_transaction": state.run.replacement = {"index": -1, "choice": {"kind": "relic", "id": "r55", "price": 0}, "return_mode": "combat", "ground_uid": 990}
		expect(kind + "_rejected_atomically", not Migration.world(state).ok)

	w = fresh(); var sigs: Dictionary = {}; var sizes: Dictionary = {}; var shapes: Dictionary = {}
	for table in ["enemies", "bosses"]:
		for row in w.db.rows(table):
			var source = {"id": row.id, "table": table, "kind": "projectile"}
			w.enemy_bullet(Vector2(550, 320), Vector2.DOWN, 130, 1, 7, source)
			var b = w.bullets[-1]; var profile = b.visual_profile
			sigs[profile.signature] = true; sizes[str(b.radius)] = true; shapes[profile.shape] = true
			expect(row.id + "_bullet_profile_and_real_wall_radius", profile.id == row.id and b.radius >= 3.5 and b.radius <= 16 and w.geometry.contains_floor(b.pos, b.radius))
			w.bullets.clear()
	expect("395_unique_source_signatures_and_16_shapes", sigs.size() == 395 and sizes.size() == 395 and shapes.size() == 16)
	samples.projectile_signatures = sigs.size(); samples.projectile_shapes = shapes.size(); samples.projectile_radii = sizes.size()
	var adapter = Adapter.new(); adapter.configure({})
	var press = InputEventKey.new(); press.physical_keycode = KEY_F; press.pressed = true
	adapter.event(press)
	expect("keyboard_active_press_is_single_edge", adapter.sample(Vector2.ZERO, Vector2.ZERO).active_item and not adapter.sample(Vector2.ZERO, Vector2.ZERO).active_item)
	for scale_value in [.75, 1.0, 1.25]:
		adapter.configure({"control_scale": scale_value})
		expect("five_touch_targets_nonoverlap_" + str(scale_value), adapter.valid_layout() and is_equal_approx(adapter.control_scale, scale_value))
	var profile = Profile.new(); var old_bindings = Profile.defaults(); old_bindings.keyboard.erase("active_item"); old_bindings.controller.erase("active_item"); old_bindings.keyboard.interact = {"type": "key", "code": KEY_F}; old_bindings.controller.interact = {"type": "button", "code": JOY_BUTTON_X}
	profile.load_data(old_bindings)
	expect("legacy_f_and_x_bindings_keep_custom_action_and_get_free_active", profile.bindings.keyboard.interact.code == KEY_F and profile.bindings.keyboard.active_item.code != KEY_F and profile.bindings.controller.interact.code == JOY_BUTTON_X and profile.bindings.controller.active_item.code != JOY_BUTTON_X)
	profile.load_data({"keyboard": {"interact": "broken"}})
	expect("malformed_legacy_binding_recovers_without_crash", profile.bindings == Profile.defaults())
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples, "scope": "real active effects, one-slot swaps, once-only low-rate loot, composed attacks across all 32 weapons, old and current saves, actual projectile radii and input edges"}
	FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/equipment-polish/gameplay.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Equipment and attack composition: ", checks.size(), " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
