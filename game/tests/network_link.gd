extends SceneTree
## Two actual clients against a separate native server through a TCP byte proxy.
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var clients: Array = []
var checks: Array = []
var folder = ""
var url = "ws://127.0.0.1:19181"
var mode_serial = 0
var drive = Vector2.ZERO
var match_id = ""
var maximum_ping = 0
var transitions: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
		if arg.begins_with("--url="): url = arg.trim_prefix("--url=")
	call_deferred("run")

func until(predicate: Callable, seconds: float = 8) -> bool:
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	print("TCP_LINK_", "PASS " if passed else "FAIL ", id)
	if not passed:
		print("TCP_DIAGNOSTIC ", JSON.stringify(clients.map(func(client): return {"state": client.state, "phase": client.room.get("phase", ""), "age": client.now() - client.last_state_received, "error": client.last_error, "retries": client.retry_count})))

func command(client, op: String, body: Dictionary = {}) -> bool:
	var receipts: Array = []
	var callback = func(operation, succeeded, code):
		if operation == op: receipts.append(succeeded)
		if not succeeded: print("TCP_COMMAND_REJECTED ", operation, " ", code)
	client.command_completed.connect(callback)
	var id = client.request(op, body)
	var complete = id > 0 and await until(func(): return not client.pending.has(str(id)))
	client.command_completed.disconnect(callback)
	return complete and not receipts.is_empty() and bool(receipts[-1])

func proxy_mode(mode: String, duration: float = 0) -> void:
	mode_serial += 1
	var file = FileAccess.open(folder.path_join("proxy-mode.json.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": mode_serial, "mode": mode, "seconds": duration})); file.close()
	var target = folder.path_join("proxy-mode.json")
	if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
	DirAccess.rename_absolute(folder.path_join("proxy-mode.json.tmp"), target)
	await until(func():
		var value = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("proxy-status.json"))) if FileAccess.file_exists(folder.path_join("proxy-status.json")) else {}
		return value is Dictionary and int(value.get("id", -1)) == mode_serial)

func both_playing() -> bool:
	return clients.all(func(client): return client.can_play())

func recover_and_resume() -> bool:
	if not await until(func(): return clients.all(func(client): return client.state == "room" and client.room.get("phase") == "suspended"), 12): return false
	for client in clients: await command(client, "resume")
	return await until(both_playing, 9)

func _process(_delta: float) -> bool:
	for client in clients:
		maximum_ping = maxi(maximum_ping, client.latency_ms)
		if not client.can_play() or client.presentation.size() != 2: continue
		var seat = int(client.room.seat)
		var frame = Protocol.empty_input(); frame.move = drive if seat == 0 else Vector2.ZERO
		var scene = client.room.get("scene", {})
		var monsters = scene.get("enemies", []).filter(func(enemy): return not enemy.dead)
		if not monsters.is_empty():
			var position = Vector2(client.room.actors[seat].player.pos)
			monsters.sort_custom(func(a, b): return position.distance_squared_to(a.pos) < position.distance_squared_to(b.pos))
			frame.aim = position.direction_to(monsters[0].pos); frame.fire = true
		client.submit_input(frame)
	return false

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for index in 2:
		var client = Session.new(folder.path_join("client%d" % index))
		root.add_child(client); clients.append(client)
		client.changed.connect(func(): transitions.append({"client": index, "at_ms": Time.get_ticks_msec(), "state": client.state, "phase": client.room.get("phase", "")}))
		client.connect_service(url, "TCP验证%d" % index)
	check("fragmented_tcp_handshake", await until(func(): return clients.all(func(client): return client.state == "online")))
	if not checks[-1].passed: finish(); return
	var a = clients[0]; var b = clients[1]
	for client in clients: await command(client, "code", {"code": "075328", "game_mode": "coop", "loadout": {"character": "c_mask", "weapon": "w14", "skill": "s10"}})
	check("fragmented_tcp_room_join", await until(func(): return clients.all(func(client): return client.room.get("players", []).size() == 2)))
	for client in clients: await command(client, "ready")
	check("fragmented_tcp_campaign_starts", await until(both_playing, 9))
	if not checks[-1].passed: finish(); return
	match_id = str(a.room.id)
	var initial = Vector2(a.room.actors[0].player.pos)
	drive = Vector2.RIGHT; await create_timer(.65).timeout; drive = Vector2.ZERO
	await create_timer(.3).timeout
	check("fragmented_tcp_inputs_move_real_actor", Vector2(a.room.actors[0].player.pos).x > initial.x + 20)

	await proxy_mode("delay")
	await create_timer(2.3).timeout
	check("jittered_240ms_rtt_keeps_campaign_live", both_playing() and a.room.id == match_id and b.room.id == match_id)
	check("delayed_control_ack_completes", await command(a, "pause"))
	check("delayed_pause_reaches_both_clients", await until(func(): return clients.all(func(client): return client.room.get("phase") == "suspended")))
	check("delayed_mutual_resume", await recover_and_resume())
	await proxy_mode("normal")

	await proxy_mode("stall_downstream", .8)
	await create_timer(.58).timeout
	check("short_downstream_stall_disables_stale_input", not a.can_play() and not b.can_play())
	check("short_stall_recovers_without_losing_match", await until(func(): return both_playing() and a.room.id == match_id and b.room.id == match_id, 3))

	await proxy_mode("stall_both", 3.3)
	check("long_blackhole_triggers_reconnect", await until(func(): return clients.any(func(client): return client.state == "reconnecting"), 4))
	check("long_blackhole_recovers_original_match", await until(func(): return clients.all(func(client): return client.state == "room" and client.room.get("phase") == "suspended" and client.room.id == match_id), 12))
	check("long_blackhole_requires_mutual_resume", await recover_and_resume())

	await proxy_mode("cut", .1)
	check("real_tcp_cut_detected", await until(func(): return clients.any(func(client): return client.state == "reconnecting"), 3))
	check("real_tcp_cut_keeps_anonymous_identities", await until(func(): return clients.all(func(client): return client.state == "room" and client.room.get("phase") == "suspended" and client.room.id == match_id), 10))
	check("real_tcp_cut_mutual_resume", await recover_and_resume())
	check("no_commands_stuck_after_tcp_faults", clients.all(func(client): return client.pending.is_empty()))
	await command(a, "leave")
	check("terminal_result_delivered_after_faults", await until(func(): return b.room.get("phase") == "finished" and int(b.stats.coop_losses) == 1))
	await command(b, "leave")
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	var passed = checks.all(func(value): return value.passed)
	var file = FileAccess.open(folder.path_join("network-link.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "maximum_ping_ms": maximum_ping, "transitions": transitions,
		"actual_separate_server": true, "actual_tcp_proxy": true, "world_injection": false,
		"faults": ["97-byte TCP writes", "120ms plus jitter each direction", "0.8s downstream stall", "3.3s bidirectional blackhole", "actual socket cuts"],
		"not_tested": ["physical Android network switching", "actual IP packet loss", "public WSS"], "virtualization": "none"}, "\t")); file.close()
	quit(0 if passed else 1)
