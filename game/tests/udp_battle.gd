extends SceneTree
const Server = preload("res://scripts/network/server_runtime.gd")
const Session = preload("res://scripts/network/online_session.gd")
class ImpairedSession:
	extends Session
	var withhold_acks = false
	func send(message: Dictionary) -> bool:
		if withhold_acks and message.get("op") == "state_ack": return true
		return super.send(message)
var server
var clients: Array = []
var checks: Array = []
var output = ""
var options: Dictionary = {}
var commands = 0
var command_acks = 0
var gaps: Array = []
var ages: Array = []
var previous_state_at = 0.0
var previous_sequence = 0
var fresh_frames = 0
var frames = 0
var errors: Array = []
var combat_observation: Dictionary = {}
var command_results: Array = []
var reconnect_observation: Dictionary = {}
var command_contexts: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair = arg.substr(2).split("=", true, 1)
			options[pair[0]] = pair[1]
	output = str(options.get("output", ""))
	call_deferred("run")

func check(name: String, value: bool) -> void:
	checks.append({"id": name, "passed": value})
	print("UDP_BATTLE_", "PASS " if value else "FAIL ", name)

func until(predicate: Callable, timeout: float = 10) -> bool:
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func command(client, op: String, data: Dictionary = {}) -> bool:
	commands += 1
	var context = {"op": op, "client_epoch": client.room.get("input_epoch"), "phase": client.room.get("phase")}
	var authority = server.rooms.get(str(client.room.get("room", "")), {})
	context.server_epoch = authority.get("input_epoch")
	context.server_suspended = authority.get("suspended")
	context.server_reason = authority.get("suspend_reason")
	command_contexts.append(context)
	var id = client.request(op, data)
	var success = id > 0 and await until(func(): return not client.pending.has(str(id)))
	if success: command_acks += 1
	return success

func run() -> void:
	if output.is_empty(): quit(1); return
	var folder = output.get_basename() + "-private"
	server = Server.new(); root.add_child(server)
	var port = int(options["server-port"]) - 2
	check("native_dtls_server", server.start({"port": port, "bind": "127.0.0.1", "data_directory": folder.path_join("server")}) == OK)
	if not checks[-1].passed: finish(); return
	for seat in 2:
		var client = ImpairedSession.new(folder.path_join("client%d" % seat))
		client.battle_port_override = int(options["proxy-port"]) if seat == 0 else 0
		client.problem.connect(func(code): errors.append(code))
		client.command_completed.connect(func(operation, succeeded, code): command_results.append({"seat": seat, "op": operation, "ok": succeeded, "code": code}))
		root.add_child(client); clients.append(client)
		client.connect_service("ws://127.0.0.1:%d" % port)
	check("encrypted_sessions_bound", await until(func(): return clients.all(func(client): return client.state == "online" and client.battle_bound), 12))
	if not checks[-1].passed: finish(); return
	for client in clients: await command(client, "queue", {"game_mode": "coop", "loadout": client.loadout})
	check("shared_room", await until(func(): return clients.all(func(client): return client.room.get("phase") == "lobby")))
	for client in clients: await command(client, "ready")
	check("real_campaign_playing", await until(func(): return clients.all(func(client): return client.can_play()), 12))
	if not checks[-1].passed:
		combat_observation = {"clients": clients.map(func(client): return {"state": client.state, "phase": client.room.get("phase"), "scene_ready": client.stream_codec.scene_ready, "core": client.stream_codec.core_sequence, "revision": client.stream_codec.revision,
			"inventory_sizes": client.stream_codec.inventories.keys().map(func(key): return [key, client.stream_codec.inventories[key].alive.size(), client.stream_codec.entities.get(key, {}).size()]),
			"last_error": client.last_error, "bound": client.battle_bound})}
		finish(); return
	var room = server.rooms[clients[0].room.room]
	var world = room.match.world
	var duration = float(options.get("seconds", 8))
	for context in world.contexts: context.player.invulnerable = duration + 120.0
	for enemy in world.enemies: enemy.hp = 1000000.0; enemy.max_hp = enemy.hp
	var start_position = Vector2(world.contexts[0].player.pos)
	# Link-local wire sequences restart after reauthentication. The lifetime
	# applied-core counter measures delivery across an intentional reconnect.
	var start_sequence = clients[0].snapshot_serial
	var started = Time.get_ticks_msec()
	var burst_armed = false
	var dash_confirmed = false
	previous_state_at = clients[0].now()
	while Time.get_ticks_msec() - started < duration * 1000:
		if not burst_armed and Time.get_ticks_msec() - started >= 1500:
			burst_armed = true
			var marker = FileAccess.open(output.get_basename() + ".burst-start", FileAccess.WRITE)
			if marker != null: marker.store_string("ready")
		var frame = Session.Protocol.empty_input()
		frame.move = Vector2.RIGHT
		frame.fire = true
		frame.aim = Vector2.UP
		frame.dash = Time.get_ticks_msec() - started < 25
		clients[0].submit_input(frame)
		dash_confirmed = dash_confirmed or int(room.get("applied_actions", [{}, {}])[0].get("dash", 0)) > 0
		frames += 1
		if clients[0].can_play(): fresh_frames += 1
		if clients[0].snapshot_serial > previous_sequence:
			var now = clients[0].now()
			gaps.append((now - previous_state_at) * 1000)
			ages.append(maxf(0, Time.get_ticks_msec() - float(clients[0].room.get("lease", 0))))
			previous_state_at = now
			previous_sequence = clients[0].snapshot_serial
		await process_frame
	clients[0].clear_input()
	combat_observation = {"start_position": Session.Protocol.encode_tree(start_position), "end_position": Session.Protocol.encode_tree(world.contexts[0].player.pos),
		"shots": world.contexts[0].stats.shots, "phase": room.match.phase, "suspended": room.suspended,
		"suspend_reason": room.get("suspend_reason", ""), "received_cores": clients[0].snapshot_serial - start_sequence,
		"simulated_seconds": world.time}
	check("udp_moves_and_fires", world.contexts[0].player.pos.x > start_position.x + 40 and world.contexts[0].stats.shots > 3)
	check("one_shot_action_confirmed", dash_confirmed)
	var receiving_seconds = duration - float(options.get("burst-seconds", 0))
	if float(options.get("burst-seconds", 0)) == 0:
		check("latest_states_continue_under_loss", clients[0].snapshot_serial - start_sequence >= ceili(receiving_seconds * 20 * .625))
		check("weak_link_stays_playable", float(fresh_frames) / maxf(1, frames) >= .995 and errors.is_empty())
	else:
		# A long outage intentionally suspends the room until both players resume.
		# Its protected period has no combat snapshots. Verify initial delivery,
		# then actual movement/fire and new snapshots after mutual recovery below.
		check("burst_had_live_states_before_protection", clients[0].snapshot_serial - start_sequence >= 15)
		check("burst_returns_authority_without_expiry", await until(func(): return clients.all(func(client): return client.state == "room" and client.room.get("phase") in ["playing", "suspended"]), 12))
		if room.suspended:
			for client in clients: await command(client, "resume")
			check("burst_mutual_resume", await until(func(): return clients.all(func(client): return client.can_play())))
		var shots_before = world.contexts[0].stats.shots
		var states_before = clients[0].state_sequence
		var resumed_at = Time.get_ticks_msec()
		while Time.get_ticks_msec() - resumed_at < 1500:
			var restored = Session.Protocol.empty_input(); restored.fire = true
			clients[0].submit_input(restored)
			await process_frame
		check("burst_restores_live_combat", world.contexts[0].stats.shots > shots_before and clients[0].state_sequence > states_before + 15)
		clients[0].clear_input()
	clients[0].withhold_acks = true
	var before = clients[0].state_sequence
	await create_timer(1.0).timeout
	check("state_ack_loss_cannot_block_new_states", clients[0].state_sequence - before >= 10)
	clients[0].withhold_acks = false
	await command(clients[0], "pause")
	check("reliable_pause", await until(func(): return clients.all(func(client): return client.room.get("phase") == "suspended")))
	for client in clients: await command(client, "resume")
	check("mutual_resume", await until(func(): return clients.all(func(client): return client.can_play())))
	var original_session = str(clients[0].identity.session)
	clients[0].simulate_link_loss()
	check("disconnect_protects_team", await until(func(): return clients[1].room.get("phase") == "suspended"))
	var reconnected = await until(func(): return clients[0].state == "room" and clients[0].room.get("phase") == "suspended", 12)
	reconnect_observation = {"reconnected": reconnected, "same_identity": clients[0].identity.session == original_session,
		"state": clients[0].state, "last_error": clients[0].last_error, "battle_bound": clients[0].battle_bound, "attempts": clients[0].retry_count,
		"phase": clients[0].room.get("phase"), "authority_suspended": room.suspended, "reason": room.get("suspend_reason"),
		"gate_flows": server.battle.edge.flows.size(), "gate_rejected": server.battle.edge.rejected}
	check("reconnect_retains_identity", reconnected and clients[0].identity.session == original_session)
	check("no_duplicate_economy", world.coins == world.contexts[0].run.coins and world.contexts[0].run.growth_log.size() == world.contexts[1].run.growth_log.size())
	for client in clients: await command(client, "leave")
	check("critical_commands_succeeded", commands == command_acks and command_results.size() == commands and command_results.all(func(row): return row.ok))
	finish()

func percentile(values: Array) -> float:
	if values.is_empty(): return -1
	var sorted = values.duplicate(); sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * .95)) - 1)])

func finish() -> void:
	var health: Dictionary = server.health() if server != null else {}
	for client in clients: client.disconnect_service()
	if server != null: server.shutdown()
	var passed = not checks.is_empty() and checks.all(func(row): return row.passed)
	var report = {"passed": passed, "checks": checks, "errors": errors, "native_engine": Engine.get_version_info().string,
		"command_contexts": command_contexts,
		"combat_observation": combat_observation,
		"command_results": command_results, "reconnect_observation": reconnect_observation,
		"state_received": previous_sequence, "state_age_p95_ms": percentile(ages), "state_gap_p95_ms": percentile(gaps),
		"input_round_trip_p95_ms": percentile(clients[0].input_ack_round_trip_ms), "reliable_requests": commands, "unique_replies_received": command_acks,
		"fresh_playable_frame_ratio": float(fresh_frames) / maxf(1, frames), "server_health": health,
		"scope": "Actual development cooperative sessions, native headless, real external UDP proxy impairment. Isolated state; no WAN/Android/render acceptance. State ages use one process monotonic clock; input RTT is sample-to-authority ACK and includes input batching and snapshot cadence.", "production_modified": false}
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("UDP_BATTLE_RESULT ", passed)
	quit(0 if passed else 1)
