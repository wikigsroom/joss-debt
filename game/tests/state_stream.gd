extends SceneTree
const Stream = preload("res://scripts/network/state_stream.gd")
const Match = preload("res://scripts/network/cooperative_match.gd")
var checks: Array = []

func check(label: String, passed: bool) -> void:
	checks.append({"id": label, "passed": passed})
	print("STREAM_", "PASS " if passed else "FAIL ", label)

func _initialize() -> void:
	var world = Match.new()
	world.begin("fixture", [{"character": "c_paper", "weapon": "w01", "skill": "s01"}, {"character": "c_ink", "weapon": "w06", "skill": "s16"}], 41)
	var sender = Stream.new("1122334455667788")
	var receiver = Stream.new("1122334455667788")
	var first: Dictionary = {}
	var previous_baselines = 0
	for step in 4:
		var state = world.view(0)
		state.op = "state"; state.link = sender.link; state.room = "fixture"; state.input_scene = 1
		state.state_seq = step + 1; state.lease = 1000 + step
		if step == 2: state.phase = "suspended"
		var packets = sender.encode(state)
		check("bounded_packets_%d" % step, packets.all(func(item): return item.bytes.size() <= Stream.MAX_PACKET))
		for item in packets: receiver.decode(item.bytes)
		check("phase_%d" % step, receiver.view.get("phase") == state.phase)
		check("player_state_%d" % step, receiver.view.get("actors", []).size() == 2 and receiver.view.actors[0].player == state.actors[0].player)
		check("npc_state_%d" % step, receiver.view.get("scene", {}).get("enemies") == state.scene.enemies)
		check("complete_scene_ready_%d" % step, receiver.scene_ready)
		if step == 0: first = receiver.view.duplicate(true); previous_baselines = sender.baseline_packets
		if step == 1: check("unchanged_metadata_not_resent", sender.baseline_packets == previous_baselines)
	# Dropped entity records must not stop future player states; a later absolute
	# update repairs entities without reconstructing the dropped snapshot.
	var state = world.view(0)
	state.op = "state"; state.room = "fixture"; state.input_scene = 1; state.state_seq = 10; state.lease = 1010
	for item in sender.encode(state):
		if item.bytes[1] != 3: receiver.decode(item.bytes)
	check("latest_core_survives_missing_entities", receiver.core_sequence == 10)
	state.state_seq = 11
	for item in sender.encode(state): receiver.decode(item.bytes)
	check("absolute_entity_repair", receiver.view.scene.enemies == state.scene.enemies)
	var impostor = Stream.new("ffeeddccbbaa0099")
	check("foreign_connection_rejected", impostor.decode(sender.encode(state)[0].bytes).is_empty())
	# Dense, incompressible auxiliary fields and long single-entity records must
	# remain bounded and repairable without stalling the unrelated core.
	state.state_seq = 12
	var noise = Crypto.new().generate_random_bytes(6000).hex_encode()
	state.actors[0].room_flags.large_fixture = noise
	var oversized = sender.encode(state)
	check("oversized_dynamic_fragmented", oversized.any(func(item): return item.bytes[1] == 7) and oversized.all(func(item): return item.bytes.size() <= Stream.MAX_PACKET))
	oversized.reverse()
	for item in oversized: receiver.decode(item.bytes)
	check("out_of_order_aux_reassembled", receiver.view.actors[0].room_flags.get("large_fixture") == noise)
	state.scene.enemies.clear(); state.state_seq = 13
	for item in sender.encode(state): receiver.decode(item.bytes)
	check("dead_entities_removed", receiver.view.scene.enemies.is_empty())
	var projectile = {"uid": 777, "pos": Vector2(513.19, 302.76), "dir": Vector2(1, .7).normalized(), "speed": 271.83, "age": .327, "travel": 123.16, "returning": true, "radius": 9.0, "owner": 0, "mode": "controlled", "friendly": true}
	state.scene.bullets = [projectile]; state.state_seq = 14
	var spawn_packets = sender.encode(state)
	check("projectile_definition_reliable", spawn_packets.any(func(item): return item.bytes[1] == 9 and item.reliable))
	for item in spawn_packets:
		if item.bytes[1] != 8: receiver.decode(item.bytes)
	check("missing_projectile_transform_has_no_fabricated_position", receiver.view.scene.bullets.is_empty())
	for item in spawn_packets:
		if item.bytes[1] == 8: receiver.decode(item.bytes)
	var decoded_bullet = receiver.view.scene.bullets[0]
	check("projectile_position_precision", Vector2(decoded_bullet.pos).distance_to(projectile.pos) <= .09)
	check("projectile_direction_precision", absf(Vector2(decoded_bullet.dir).angle_to(projectile.dir)) < .0001)
	check("projectile_speed_precision", absf(decoded_bullet.speed - projectile.speed) <= .125)
	check("projectile_visual_fields_preserved", decoded_bullet.radius == 9 and decoded_bullet.mode == "controlled" and decoded_bullet.returning)
	projectile.pos += Vector2(30, -20); state.state_seq = 15
	var next_packets = sender.encode(state)
	check("unchanged_projectile_definition_not_resent", not next_packets.any(func(item): return item.bytes[1] == 9))
	for item in next_packets: receiver.decode(item.bytes)
	for item in spawn_packets: receiver.decode(item.bytes)
	check("late_projectile_cannot_rewind_position", Vector2(receiver.view.scene.bullets[0].pos).distance_to(projectile.pos) <= .09)
	state.scene.bullets.clear(); state.state_seq = 16
	for item in sender.encode(state): receiver.decode(item.bytes)
	for item in spawn_packets: receiver.decode(item.bytes)
	check("late_projectile_definition_cannot_resurrect_destroyed_bullet", receiver.view.scene.bullets.is_empty())
	# Same-room metadata loss must never block independent player state. NPC
	# column extensions may wait for their schema; existing combat cores do not.
	state.state_seq = 17; state.actors[0].run.coins += 3
	var metadata_gap = sender.encode(state)
	for item in metadata_gap:
		if item.bytes[1] != 1: receiver.decode(item.bytes)
	check("metadata_loss_does_not_block_same_scene_core", receiver.core_sequence == 17 and receiver.pending_core.is_empty())
	for item in metadata_gap:
		if item.bytes[1] == 1: receiver.decode(item.bytes)
	check("late_metadata_repairs_wallet", receiver.metadata.actors[0].run.coins == state.actors[0].run.coins)
	state.input_scene += 1; state.state_seq = 18
	var changed_scene = sender.encode(state)
	for item in changed_scene:
		if item.bytes[1] != 1: receiver.decode(item.bytes)
	check("new_scene_core_waits_for_its_own_geometry", receiver.core_sequence == 17 and not receiver.pending_core.is_empty())
	for item in changed_scene: receiver.decode(item.bytes)
	check("new_scene_baseline_releases_latest_core", receiver.core_sequence == 18 and receiver.scene_ready)
	state.input_scene += 1; state.state_seq = 19; state.scene.bullets = [projectile]
	var definition_first = sender.encode(state)
	for item in definition_first:
		if item.bytes[1] == 9 or (item.bytes[1] == 7 and item.bytes[Stream.HEADER] == 9): receiver.decode(item.bytes)
	check("future_scene_definitions_wait_for_metadata", not receiver.pending_definition_packets.is_empty())
	for item in definition_first:
		if item.bytes[1] != 9: receiver.decode(item.bytes)
	check("definitions_before_metadata_are_not_lost", receiver.scene_ready and receiver.view.scene.bullets.size() == 1)
	state.input_scene += 1; state.state_seq = 20
	var repeated_uid = sender.encode(state)
	check("new_scene_resends_identical_projectile_definition", repeated_uid.any(func(item): return item.bytes[1] == 9))
	for item in repeated_uid: receiver.decode(item.bytes)
	check("identical_projectile_uid_in_new_scene_is_visible", receiver.scene_ready and receiver.view.scene.bullets.size() == 1)
	print("STREAM_RESULT ", checks.all(func(row): return row.passed))
	quit(0 if checks.all(func(row): return row.passed) else 1)
