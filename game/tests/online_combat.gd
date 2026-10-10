extends SceneTree
const Duel = preload("res://scripts/network/duel_match.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Content = preload("res://scripts/core/content_db.gd")
const Prediction = preload("res://scripts/network/motion_prediction.gd")
var checks: Array = []
var failures: Array = []
var db = Content.new()
var output = "user://online-combat.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(value: bool, id: String) -> void:
	checks.append({"id": id, "passed": value})
	if not value: failures.append(id); push_error("ONLINE_COMBAT_FAIL " + id)

func digest(value) -> String:
	return JSON.stringify(Store.encode(value), "", true, true).sha256_text()

func duel_for(character: String, weapon: String, skill: String):
	var duel = Duel.new()
	duel.begin("matrix", [{"character": character, "weapon": weapon, "skill": skill}, {"character": "c_mask", "weapon": "w01", "skill": "s10"}], 61011)
	duel.choose(0, 0); duel.choose(1, 0)
	duel.phase = "playing"
	duel.remaining = 120
	for i in 2:
		var actor = duel.actors[i]
		actor.player.hp = 10000.0; actor.player.max_hp = 10000.0
		actor.player.pos = Vector2(600 + i * 66, 360)
		actor.player.invulnerable = 0.0
		actor.run.relics.clear()
	for actor in duel.actors: actor.sync_opponent()
	return duel

func attack(duel, count: int = 180) -> void:
	for tick in count:
		var input = Protocol.empty_input()
		input.aim = Vector2.RIGHT
		input.fire = tick % 60 < 42
		duel.advance([input, Protocol.empty_input()])

func run() -> void:
	for relics in [{}, {"r33": 1, "r34": 2}]:
		var movement = duel_for("c_paper", "w01", "s01").actors[0]
		movement.run.relics = relics
		var prediction = Prediction.new()
		prediction.observe(movement, movement.player, [], true)
		var consistent = true
		for tick in 600:
			var frame = Protocol.empty_input()
			frame.move = Vector2.RIGHT if tick < 180 else Vector2(-1, sin(tick * .1)).normalized()
			frame.aim = Vector2.UP
			frame.dash = tick % 121 == 0
			if tick == 300:
				movement.player.push_left = .12; movement.player.push_remaining = Vector2(24, 15); movement.player.stun_until = movement.time + .2
				prediction.observe(movement, movement.player, [], true)
			movement.advance_actor(frame, 1.0 / 60)
			prediction.advance(movement, frame, 1.0 / 60)
			if consistent and Vector2(prediction.state.pos).distance_to(movement.player.pos) >= .01:
				print("PREDICTION_DIFF tick=%d authority=%s prediction=%s" % [tick, str(movement.player), str(prediction.state)])
			consistent = consistent and Vector2(prediction.state.pos).distance_to(movement.player.pos) < .01 and is_equal_approx(prediction.state.dash_cd, movement.player.dash_cd)
		check(consistent, "prediction_matches_authority/move_dash_wall_stun_push/" + str(relics.size()))
	for weapon in db.rows("weapons"):
		var duel = duel_for("c_paper", weapon.id, "s01")
		attack(duel)
		check(duel.actors[1].player.hp < 10000, "weapon_damage/" + str(weapon.id))
		check(duel.actors.all(func(actor): return actor.player.pos.is_finite() and actor.geometry.contains_floor(actor.player.pos, 12)), "inner_wall/" + str(weapon.id))
		var restored = Duel.new()
		check(restored.recover(duel.checkpoint()), "restore/" + str(weapon.id))
		if weapon.id == "w01":
			var debug_file = FileAccess.open(output.get_base_dir().path_join("restore-diff.json"), FileAccess.WRITE)
			if debug_file: debug_file.store_string(JSON.stringify(Store.encode({"before": duel.checkpoint(), "after": restored.checkpoint()}), "", true, true)); debug_file.close()
		check(digest(restored.checkpoint()) == digest(duel.checkpoint()), "exact_checkpoint/" + str(weapon.id))
		for tick in 30:
			var input = Protocol.empty_input(); input.aim = Vector2.RIGHT; input.fire = tick < 15
			duel.advance([input, Protocol.empty_input()]); restored.advance([input, Protocol.empty_input()])
		check(digest(restored.checkpoint()) == digest(duel.checkpoint()), "deterministic_resume/" + str(weapon.id))
	for character in db.rows("characters"):
		for skill in character.skills:
			var duel = duel_for(character.id, "w01", skill)
			duel.actors[0].enemies[0].mark = 3
			duel.actors[0].enemies[0].mark_until = 10
			var input = Protocol.empty_input(); input.aim = Vector2.RIGHT; input.skill = true
			duel.advance([input, Protocol.empty_input()])
			check(duel.actors[0].player.skill_cd > 0 and duel.actors[0].player.energy < 100, "skill_cast/" + str(skill))
			for tick in 100: duel.advance([Protocol.empty_input(), Protocol.empty_input()])
			check(duel.actors[1].player.hp < 10000 or duel.actors[0].player.guard_count > 0, "skill_effect/" + str(skill))
	for relic in Duel.DRAFT_POOL:
		check(db.row("relics", relic).get("trigger") not in ["natural_kill", "elite_clear", "room_clear", "ash_pickup", "chain_form"], "pvp_relic/" + relic)
		var duel = duel_for("c_lantern", "w14", "s07")
		duel.actors[0].run.relics[relic] = 1
		attack(duel, 90)
		check(duel.actors[1].player.hp < 10000, "relic_carrier/" + relic)
	var combined = duel_for("c_paper", "w01", "s01")
	for relic in ["r57", "r58", "r59", "r61", "r63", "r65"]: combined.actors[0].run.relics[relic] = 1
	attack(combined, 120)
	check(combined.actors[1].player.hp < 10000, "combined_five_explosive_homing_beams")
	var expired_draft = Duel.new()
	expired_draft.begin("draft-timeout", [{"character": "c_paper", "weapon": "w01", "skill": "s01"}, {"character": "c_paper", "weapon": "w01", "skill": "s01"}], 42)
	for tick in 1801: expired_draft.advance([{}, {}])
	check(expired_draft.picked == [0, 0] and expired_draft.phase == "countdown", "draft_timeout_selects_first_for_both")
	var finished = duel_for("c_paper", "w01", "s01")
	finished.finish_round(0, "test"); finished.start_round(); finished.finish_round(0, "test")
	check(finished.phase == "finished" and finished.score == [2, 0] and finished.winner == 0, "two_round_wins_settle_match")
	var parser_cases = [PackedByteArray([0, 123, 125]), PackedByteArray([2, 1, 2]), PackedByteArray([1, 1, 2]), Protocol.packet({"op": "input", "frame": {"move": "bad"}})]
	check(Protocol.unpack(parser_cases[1], true).is_empty() and Protocol.unpack(parser_cases[2], true).is_empty(), "reject_invalid_and_compressed_client_frames")
	check(Protocol.clean_input({"seq": 1, "move": Vector2(500, 500), "aim": Vector2(3, 0)}).move.length() <= 1.00001, "movement_clamped_by_server")
	check(Protocol.clean_input({"seq": 1, "move": "bad"}).is_empty(), "malformed_input_rejected")
	var packed_state = {"op": "state", "position": Vector2(351.5, 612), "time": 1.0 / 60}
	check(digest(Protocol.unpack(Protocol.packet(packed_state, true))) == digest(packed_state), "bounded_native_snapshot_preserves_values")
	check(Protocol.unpack(Protocol.packet(packed_state, true), true).is_empty(), "native_snapshot_format_never_accepted_as_client_input")
	check(Protocol.valid_code("000001") and not Protocol.valid_code("１２３４５６"), "room_codes_use_six_ascii_digits")
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "weapons": 32, "skills": 18, "draft_pool": Duel.DRAFT_POOL.size()}, "\t", true, true)); file.close()
	print("ONLINE_COMBAT_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
