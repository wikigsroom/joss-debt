extends SceneTree
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var folder = ""
var stage = "prepare"
var url = "ws://127.0.0.1:18877"
var clients: Array = []
var checks: Array = []
var expected: Dictionary = {}
var mode = "restore"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="): folder = arg.trim_prefix("--folder=")
		if arg.begins_with("--stage="): stage = arg.trim_prefix("--stage=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--url="): url = arg.trim_prefix("--url=")
	call_deferred("run")

func check(value: bool, id: String) -> void:
	checks.append({"id": id, "passed": value})
	print("RECOVERY_%s %s" % ["PASS" if value else "FAIL", id])

func until(predicate: Callable, seconds: float = 7) -> bool:
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func command(client, operation: String, body: Dictionary = {}) -> int:
	var serial = client.request(operation, body)
	await until(func(): return not client.pending.has(str(serial)))
	return serial

func read_expected() -> void:
	expected = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json")))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 2:
		var client = Session.new(folder.path_join("client-%d" % i))
		root.add_child(client)
		clients.append(client)
		client.connect_service(url, "Recovery %d" % i)
	var connected = await until(func(): return clients.all(func(c): return c.state in ["online", "room"]), 9)
	check(connected, "independent_process_credentials_connect")
	if not connected: finish(); return
	var a = clients[0]
	var b = clients[1]
	if stage == "prepare":
		var loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
		await command(a, "code", {"code": "006125", "loadout": loadout})
		await command(b, "code", {"code": "006125", "loadout": loadout})
		await command(a, "ready"); await command(b, "ready")
		check(await until(func(): return a.room.get("phase") == "draft"), "draft_ready")
		var choice_id = await command(a, "choose", {"index": 3})
		await command(b, "choose", {"index": 1})
		check(await until(func(): return a.can_play() and b.can_play(), 7), "live_match_started")
		if a.presentation.size() != 2: finish(); return
		var start = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 2100:
			var frame = Protocol.empty_input(); frame.aim = Vector2.RIGHT; frame.fire = true
			frame.move = Vector2.RIGHT if a.presentation[0].player.pos.x < 730 else Vector2.ZERO
			a.submit_input(frame); await process_frame
		await command(a, "pause")
		check(await until(func(): return a.room.get("phase") == "suspended"), "durable_pause")
		expected = {"match": str(a.room.id), "room": str(a.room.room), "tick": int(a.room.tick), "hp": [a.presentation[0].player.hp, a.presentation[1].player.hp],
			"positions": [Protocol.encode_tree(a.presentation[0].player.pos), Protocol.encode_tree(a.presentation[1].player.pos)], "score": a.room.score,
			"builds": a.room.builds, "choice_request": choice_id, "input_floor": a.input_serial}
		var file = FileAccess.open(folder.path_join("expected.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(expected, "\t", true, true)); file.close()
		# Simulate losing a receipt after the server durably confirmed it.
		a.pending[str(choice_id)] = {"op": "choose", "request": choice_id, "index": 3}
		check(a.save_preferences(), "pending_choice_durable_on_client")
	elif stage == "restore":
		read_expected()
		check(await until(func(): return a.room.get("phase") == "suspended" and b.room.get("phase") == "suspended"), "restart_recovers_suspended_room")
		if a.presentation.size() != 2: finish(); return
		check(str(a.room.id) == expected.match and str(a.room.room) == expected.room, "same_match_and_room_after_process_restart")
		check([a.presentation[0].player.hp, a.presentation[1].player.hp] == expected.hp and a.room.score == expected.score, "same_health_and_score_after_restart")
		var replayed = await until(func(): return not a.pending.has(str(int(expected.choice_request))))
		check(a.room.builds == expected.builds and replayed, "lost_receipt_replay_does_not_duplicate_choice")
		check([a.presentation[0].player.pos, a.presentation[1].player.pos] == Protocol.Store.decode(expected.positions), "same_positions_after_restart")
		check(a.input_serial >= int(expected.input_floor), "sequence_floor_restored")
		if mode == "expiry":
			var replacement = Session.new(folder.path_join("client-0"))
			root.add_child(replacement)
			replacement.connect_service(url, "Recovery 0")
			check(await until(func(): return replacement.state == "room" and a.state == "expired"), "one_token_has_one_live_connection")
			check(not a.wants_connection, "old_client_does_not_start_takeover_loop")
			a.disconnect_service(); clients[0] = replacement; a = replacement
			await command(a, "resume"); await command(b, "resume")
			check(await until(func(): return a.can_play() and b.can_play(), 7), "restart_confirmation_resumes_battle")
			var position: Vector2 = a.presentation[0].player.pos
			await create_timer(.35).timeout
			check(a.presentation[0].player.pos.distance_to(position) < 1, "old_held_movement_not_replayed")
			b.disconnect_service()
			check(await until(func(): return a.room.get("phase") == "suspended"), "second_loss_suspends")
			check(await until(func(): return a.room.get("phase") == "finished", 15), "grace_expiry_finishes_match")
			check(int(a.room.winner) == 0 and int(a.stats.wins) == 1, "remaining_player_wins_once")
			b.connect_service(url, "Recovery 1")
			check(await until(func(): return b.room.get("phase") == "finished"), "late_reconnect_shows_terminal_result")
			check(not b.can_play() and int(b.stats.losses) == 1, "late_reconnect_cannot_revive_finished_battle")
			await command(a, "leave"); await command(b, "leave")
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	var failures = checks.filter(func(c): return not c.passed)
	var file = FileAccess.open(folder.path_join(stage + "-" + mode + "-report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t", true, true)); file.close()
	print("RECOVERY_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
