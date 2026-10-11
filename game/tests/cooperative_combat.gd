extends SceneTree
const Match = preload("res://scripts/network/cooperative_match.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var checks: Array = []
var snapshot_metrics = {}
var loadouts = [{"character": "c_paper", "weapon": "w03", "skill": "s01"}, {"character": "c_ink", "weapon": "w06", "skill": "s16"}]

func expect(id: String, condition: bool) -> void:
	checks.append({"id": id, "passed": condition})
	print("COOPERATIVE_", "PASS " if condition else "FAIL ", id)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var encounter = Match.new()
	encounter.begin("test-cooperative", loadouts, 1741)
	for i in 181: encounter.advance([Protocol.empty_input(), Protocol.empty_input()])
	var world = encounter.world
	expect("two_independent_characters", world.contexts[0].run.character != world.contexts[1].run.character)
	expect("shared_eleven_floor_campaign", world.run.floor_limit == 11 and world.run.campaign)
	expect("real_npc_room", encounter.phase == "playing" and not world.enemies.is_empty() and world.enemies.all(func(enemy): return not enemy.get("online_actor", false)))
	var before = world.enemies.map(func(enemy): return enemy.hp)
	for seat in 2:
		world.select_player(seat)
		world.player.invulnerable = 100.0
		world.player.pos = world.geometry.nearest_free(Vector2(640, 470 + seat * 45), 12)
		world.flush()
	for i in 120:
		var frames = []
		for seat in 2:
			var frame = Protocol.empty_input()
			frame.fire = true
			frame.aim = world.contexts[seat].player.pos.direction_to(world.enemies[0].pos) if not world.enemies.is_empty() else Vector2.UP
			frames.append(frame)
		encounter.advance(frames)
	expect("both_players_fire", world.contexts.all(func(context): return context.stats.shots > 0))
	expect("team_attacks_damage_npcs", world.contexts[0].stats.hits + world.contexts[1].stats.hits > 0 or world.enemies.size() < before.size())
	expect("no_friendly_fire", world.contexts.all(func(context): return context.player.hp == context.player.max_hp))
	var view = encounter.view(0)
	expect("compact_snapshot_decodes", not Protocol.unpack(Protocol.packet(view, true)).is_empty())
	var restored = Match.new()
	expect("recover_full_cooperative_checkpoint", restored.recover(encounter.checkpoint()))
	expect("recovery_keeps_both_builds_and_hp", restored.world.contexts[1].player == world.contexts[1].player and restored.world.contexts[0].run.relics == world.contexts[0].run.relics)
	world.select_player(1)
	world.player.invulnerable = 0.0
	world.damage_player(100)
	expect("one_downed_does_not_end_team", world.contexts[1].player.downed and world.contexts[1].run.result.is_empty())
	world.select_player(0)
	world.player.pos = world.geometry.nearest_free(world.contexts[1].player.pos + Vector2(35, 0), 12)
	world.flush()
	expect("nearby_interaction_starts_rescue", world.interact_input())
	for i in 181:
		world.select_player(0)
		world.interact_input()
		world.advance_rescue(1.0 / 60)
	expect("rescue_restores_two_hearts", world.alive(1) and world.contexts[1].player.hp == 2)
	world.select_player(0)
	world.player.invulnerable = 0.0
	world.damage_player(100)
	world.select_player(1)
	world.player.invulnerable = 0.0
	world.damage_player(100)
	encounter.sync_phase()
	expect("double_down_team_defeat", encounter.phase == "finished" and encounter.reason == "team_defeat")
	await rooms_and_growth()
	var report = {"suite": "cooperative_combat", "checks": checks, "snapshot_metrics": snapshot_metrics, "passed": checks.all(func(check): return check.passed)}
	var output = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_empty():
		var file = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	quit(0 if report.passed else 1)

func fixture(kind: String, floor: int = 1):
	var result = Match.new()
	result.begin("fixture-" + kind, loadouts, 1741)
	var world = result.world
	world.select_player(0)
	world.run.floor = floor
	world.run.graph = world.Campaign.build(world.db, world.run.seed_text, floor)
	world.run.room = maxi(0, world.run.graph.types.find(kind))
	world.run.graph.types[int(world.run.room)] = kind
	world.run.room_plan = world.run.graph.types.duplicate()
	world.run.visited = []
	world.run.room_history = {}
	world.enter_room()
	result.sync_phase()
	return result

func finish_choices(encounter) -> void:
	for attempt in 12:
		if encounter.phase != "draft": return
		for seat in 2:
			if encounter.world.contexts[seat].mode not in ["choice", "shop", "debt"]: continue
			encounter.world.select_player(seat)
			var offers = encounter.world.choices
			var index = -1
			for i in offers.size():
				if encounter.world.choice_reason(offers[i]).is_empty(): index = i; break
			if index >= 0: encounter.choose(seat, index)
			else: encounter.action(seat, "skip")

func rooms_and_growth() -> void:
	var encounter = fixture("combat")
	var world = encounter.world
	world.enemies.clear()
	world.delayed.clear()
	world.room_flags.wave_count = 1
	world.room_flags.wave_index = 1
	world.clear_room()
	world.flush()
	encounter.sync_phase()
	var amount = world.coins
	world.clear_room()
	world.flush()
	expect("clear_rewards_exactly_once", world.coins == amount and world.contexts.all(func(context): return context.run.cleared == 1))
	world.select_player(1 - world.seat)
	world.clear_room()
	world.flush()
	expect("different_character_cannot_duplicate_shared_clear", world.coins == amount and world.contexts.all(func(context): return context.run.cleared == 1))
	finish_choices(encounter)
	world.select_player(0)
	var doors = world.room_doors()
	if not doors.is_empty():
		var door = doors[0]
		var original = world.run.room
		world.player.pos = world.geometry.nearest_free(door.pos, 12)
		world.flush()
		world.contexts[1].player.pos = world.geometry.nearest_free(world.geometry.bounds.get_center(), 12)
		world.check_doors()
		expect("one_player_cannot_teleport_team", world.run.room == original)
		world.contexts[1].player.pos = world.geometry.nearest_free(door.pos + Vector2(25, 0), 12)
		world.check_doors()
		expect("standing_at_door_does_not_auto_teleport", world.run.room == original)
		world.contexts[0].player.move = world.direction_vector(door.direction)
		world.check_doors()
		expect("same_physical_door_moves_both", world.contexts.all(func(context): return context.run.room == door.destination))
		expect("both_arrive_inside_authored_walls", world.contexts.all(func(context): return world.geometry.contains_floor(context.player.pos, 12)))
		var arrived = int(world.run.room)
		for index in 2: world.contexts[index].mode = "clear"
		world.select_player(0); world.mode = "clear"; world.flush()
		for tick in 30: world.check_doors()
		expect("arrival_cannot_bounce_back_without_new_input", world.run.room == arrived)
	encounter = fixture("reward")
	world = encounter.world
	expect("separate_reward_offers", encounter.phase == "draft" and world.contexts.all(func(context): return context.choices.size() == 3))
	var chosen = str(world.contexts[0].choices[0].id)
	expect("first_player_growth_choice", encounter.choose(0, 0) and world.contexts[0].run.relics.has(chosen))
	expect("waiting_for_teammate_freezes_combat", encounter.phase == "draft" and world.contexts[1].run.relics.is_empty())
	var restored = Match.new()
	expect("restore_half_finished_choice", restored.recover(encounter.checkpoint()) and restored.phase == "draft" and restored.world.contexts[0].run.relics.has(chosen) and restored.world.contexts[1].mode == "choice")
	expect("both_choices_resume_room", encounter.choose(1, 0) and encounter.phase == "playing")
	for kind in ["shop", "debt", "sacrifice", "judge", "angel"]:
		encounter = fixture(kind, 3)
		world = encounter.world
		expect(kind + "_has_real_offers", encounter.phase == "draft" and world.contexts.all(func(context): return not context.choices.is_empty()))
		world.select_player(0)
		world.run.coins = 100
		world.flush()
		var coins_before = world.coins
		var hp = world.player.hp
		var cost = int(world.choices[0].price)
		var hp_cost = int(world.choices[0].get("hp_cost", 0))
		expect(kind + "_choice_is_authoritative", encounter.choose(0, 0))
		expect(kind + "_cost_applies_once", world.coins == coins_before - cost and (hp_cost == 0 or world.contexts[0].player.hp == hp - hp_cost))
		expect(kind + "_teammate_choice_is_independent", world.contexts[1].mode in ["choice", "shop", "debt"])
		encounter.action(0, "skip")
		encounter.action(1, "skip")
		expect(kind + "_can_complete_without_purchase", encounter.phase == "playing")
	encounter = fixture("boss")
	world = encounter.world
	expect("single_boss_per_campaign_room", world.enemies.filter(func(enemy): return enemy.boss).size() == 1)
	world.enemies.clear()
	world.delayed.clear()
	world.clear_room()
	encounter.sync_phase()
	finish_choices(encounter)
	world.select_player(0)
	expect("both_players_receive_floor_exit", world.contexts.all(func(context): return context.mode == "checkpoint"))
	world.run.contracts.append({"id": "d01", "interest": 6})
	world.run.coins = 100
	world.flush()
	var shared_wallet = world.coins
	var repay_price = int(world.db.row("debt_contracts", "d01").repay_price) + 6
	expect("checkpoint_can_repay_personal_contract", encounter.action(0, "repay", "d01"))
	expect("repayment_updates_shared_wallet", world.coins == shared_wallet - repay_price and world.contexts[0].run.contracts.is_empty() and world.contexts[0].run.repayments.has("d01"))
	expect("repayment_cannot_repeat", not encounter.action(0, "repay", "d01") and world.coins == shared_wallet - repay_price)
	var stair = world.room_door_position("north")
	world.player.pos = world.geometry.nearest_free(stair, 12)
	world.flush()
	world.contexts[1].player.pos = world.geometry.nearest_free(stair + Vector2(24, 0), 12)
	world.contexts[0].player.move = Vector2.UP
	world.check_doors()
	encounter.sync_phase()
	expect("north_exit_enters_second_floor", world.contexts.all(func(context): return context.run.floor == 2))
	expect("both_characters_get_their_own_evolution", world.contexts.all(func(context): return context.mode == "choice" and context.choices.size() == 2))
	finish_choices(encounter)
	expect("evolution_preserves_shared_npc_room", encounter.phase == "playing" and not world.enemies.is_empty())
	for row in world.db.rows("weapons"):
		world.bullets.clear()
		world.zones.clear()
		world.delayed.clear()
		world.select_player(1)
		world.player.weapon = row.id
		world.player.shot_cd = 0.0
		world.player.charge = 0.0
		world.player.aim = Vector2.UP
		var shots = int(world.stats.shots)
		world.shoot_input(true, 1.0)
		world.stamp_entities()
		world.flush()
		expect("coop_weapon_" + str(row.id), world.contexts[1].stats.shots > shots)
		expect("owner_retained_" + str(row.id), (world.bullets + world.zones + world.delayed).all(func(entity): return entity.get("owner") == 1))
	expect("expanded_scene_packet_decodes", not Protocol.unpack(Protocol.packet(encounter.view(0), true)).is_empty())
	world.bullets.clear()
	for index in 240:
		world.bullets.append({"uid": index, "pos": Vector2(400, 300), "dir": Vector2.UP, "speed": 300.0, "radius": 8.0, "age": 0.1, "mode": "controlled", "owner": index % 2, "friendly": true, "primary": true, "recipe": {"hits": range(200), "repeat": range(200)}, "hits": range(200)})
	world.delayed.clear()
	for index in 128: world.delayed.append({"type": "skill_replay", "time": world.time + 1, "items": world.enemies.duplicate(true), "owner": index % 2})
	for context in world.contexts:
		var entry = context.run.growth_log[0].duplicate(true)
		context.run.growth_log.clear()
		for index in 256: context.run.growth_log.append(entry.duplicate(true))
	var dense = encounter.view(0)
	var packed = Protocol.packet(dense, true)
	snapshot_metrics = {"bullets": 240, "history_per_player": 256, "compressed_bytes": packed.size(), "expanded_bytes": var_to_bytes(dense).size()}
	expect("dense_campaign_snapshot_inside_packet_bounds", not Protocol.unpack(packed).is_empty() and var_to_bytes(dense).size() <= Protocol.MAX_SERVER_BYTES)
	expect("presentation_retains_every_bullet_and_full_history", dense.scene.bullets.size() == 240 and dense.builds.all(func(history): return history.size() == 256))
	expect("presentation_omits_simulation_recipes_only", not dense.scene.bullets[0].has("recipe") and not dense.scene.bullets[0].has("hits") and dense.scene.bullets[0].owner == 0 and world.bullets[0].has("recipe"))
	encounter = fixture("boss", 11)
	world = encounter.world
	world.enemies.clear()
	world.delayed.clear()
	world.clear_room()
	encounter.sync_phase()
	finish_choices(encounter)
	expect("eleven_floor_team_victory", encounter.phase == "finished" and encounter.winner == 2 and encounter.reason == "team_victory")
