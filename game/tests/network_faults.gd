extends SceneTree
## Native WebSocket regressions. Drops here are deliberate application faults,
## not a claim that TCP delivers unordered or lossy application frames.
const Server = preload("res://scripts/network/server_runtime.gd")
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
class FaultClient:
	extends Session
	var rejected_sends = 0
	var withheld_ack = -1
	var withhold_states = false
	var withhold_state_acks = false
	var withhold_inputs = false
	var welcomed = 0
	var withhold_welcome = false
	var welcome_ids: Array = []
	var completed: Array = []
	func send(message: Dictionary) -> bool:
		if message.has("request") and rejected_sends > 0:
			rejected_sends -= 1
			return false
		if withhold_state_acks and message.get("op") == "state_ack": return true
		if withhold_inputs and message.get("op") == "input": return true
		return super.send(message)
	func receive(message: Dictionary) -> void:
		if message.get("op") == "ack" and int(message.get("request", -2)) == withheld_ack: return
		if withhold_states and message.get("op") == "state": return
		if message.get("op") == "welcome":
			welcomed += 1; welcome_ids.append(str(message.session))
			if withhold_welcome: return
		super.receive(message)
	func deliver(message: Dictionary) -> bool:
		return super.send(message)

var server
var clients: Array = []
var checks: Array = []
var folder = ""
var a
var b
var room
var sequence = 1000000

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	if folder.is_empty(): folder = "user://network-faults-%d" % Time.get_ticks_usec()
	call_deferred("run")

func until(predicate: Callable, seconds: float = 6) -> bool:
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	print("NETWORK_FAULT_", "PASS " if passed else "FAIL ", id)

func command(client, op: String, body: Dictionary = {}) -> bool:
	var id = client.request(op, body)
	return id > 0 and await until(func(): return not client.pending.has(str(id)))

func add_client(index: int):
	var client = FaultClient.new(folder.path_join("client%d" % index))
	client.command_completed.connect(func(op, succeeded, code): client.completed.append({"op": op, "ok": succeeded, "code": code}))
	root.add_child(client); clients.append(client)
	client.connect_service("ws://127.0.0.1:19077", "弱网验证%d" % index)
	await until(func(): return client.state == "online")
	return client

func resume_team() -> bool:
	await until(func(): return a.room.get("phase") == "suspended" and b.room.get("phase") == "suspended")
	await command(a, "resume"); await command(b, "resume")
	return await until(func(): return a.can_play() and b.can_play(), 7)

func next_input() -> Dictionary:
	sequence += 1
	a.input_serial = sequence
	var frame = Protocol.empty_input()
	frame.seq = sequence; frame.move = Vector2.RIGHT
	return a.input_message(frame)

func reject_input(id: String, packet: Dictionary) -> void:
	var previous = int(room.inputs[0].seq)
	a.deliver(packet)
	await create_timer(.12).timeout
	check(id, int(room.inputs[0].seq) == previous)

func block_preferences(client, blocked: bool) -> void:
	for slot in 2:
		var path = client.preferences.folder.path_join("checkpoint_%d.json.tmp" % slot)
		if blocked: DirAccess.make_dir_recursive_absolute(path)
		else: DirAccess.remove_absolute(path)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	server = Server.new(); root.add_child(server)
	check("server_start", server.start({"port": 19077, "max_rooms": 1, "bind": "127.0.0.1", "data_directory": folder.path_join("server")}) == OK)
	if not checks[-1].passed: finish(); return
	a = await add_client(0); b = await add_client(1)
	check("two_native_websockets_authenticated", a.authenticated and b.authenticated)
	if not checks[-1].passed: finish(); return

	# A failed first send must not let a higher durable request leapfrog it.
	a.rejected_sends = 1
	var first = a.request("loadout", {"loadout": {"character": "c_paper", "weapon": "w06", "skill": "s01"}})
	var second = a.request("loadout", {"loadout": {"character": "c_paper", "weapon": "w07", "skill": "s01"}})
	check("failed_send_and_fifo_drain", await until(func(): return a.pending.is_empty(), 3))
	var replies = server.sessions[a.identity.session].replies
	check("neither_fifo_command_is_stale", replies.get(str(first), {}).get("ok", false) and replies.get(str(second), {}).get("ok", false))
	check("fifo_keeps_last_requested_loadout", server.sessions[a.identity.session].loadout.weapon == "w07")

	# Waiting longer than the state timeout before pairing must not instantly
	# disconnect the first queued player when a room is finally allocated.
	await command(a, "queue", {"game_mode": "coop", "loadout": a.loadout})
	await create_timer(2.25).timeout
	await command(b, "queue", {"game_mode": "coop", "loadout": b.loadout})
	check("long_queue_allocation_resets_state_deadline", await until(func(): return a.room.get("players", []).size() == 2 and b.room.get("players", []).size() == 2))
	if not checks[-1].passed: finish(); return
	await command(a, "ready"); await command(b, "ready")
	check("real_cooperative_match_start", await until(func(): return a.can_play() and b.can_play(), 7))
	if not checks[-1].passed: finish(); return
	room = server.rooms[a.room.room]
	# These tests isolate transport from death RNG; actual damage/AI are covered
	# by the combat and packaged UI suites, not by fabricated network snapshots.
	for context in room.match.world.contexts: context.player.invulnerable = 1000.0
	a.withhold_inputs = true; b.withhold_inputs = true
	await create_timer(.3).timeout

	var valid = next_input()
	a.deliver(valid)
	check("scoped_fresh_input_accepted", await until(func(): return int(room.inputs[0].seq) == int(valid.frame.seq)))
	await create_timer(.4).timeout
	var position = Vector2(room.match.world.contexts[0].player.pos)
	await create_timer(.15).timeout
	check("missing_inputs_stop_movement_after_250ms", position.distance_to(room.match.world.contexts[0].player.pos) < .1)
	var crossing = next_input()
	a.deliver(crossing)
	await until(func(): return int(room.inputs[0].seq) == int(crossing.frame.seq))
	room.match.world.scene_serial += 1
	await create_timer(.08).timeout
	check("already_received_input_stops_after_scene_transition", room.inputs[0].frame.move == Vector2.ZERO and room.match.world.contexts[0].player.move == Vector2.ZERO)
	var packet = next_input(); packet.room = "another-room"
	await reject_input("input_wrong_room_rejected", packet)
	packet = next_input(); packet.match = "previous-match"
	await reject_input("input_wrong_match_rejected", packet)
	packet = next_input(); packet.epoch -= 1
	await reject_input("input_previous_pause_epoch_rejected", packet)
	packet = next_input(); packet.scene -= 1
	await reject_input("input_previous_scene_rejected", packet)
	packet = next_input(); packet.link = "previous-connection"
	await reject_input("input_previous_connection_rejected", packet)
	packet = next_input(); packet.lease = int(Time.get_ticks_msec()) - 1500
	await reject_input("input_expired_server_lease_rejected", packet)
	packet = next_input(); packet.lease = int(Time.get_ticks_msec()) + 5000
	await reject_input("input_future_lease_rejected", packet)
	packet = next_input(); packet.frame.seq = int(room.inputs[0].seq)
	await reject_input("duplicate_input_sequence_rejected", packet)

	# Retrying a pause ACK must not re-pause a subsequently resumed match.
	a.withheld_ack = a.request_serial + 1
	var pause_id = a.request("pause")
	check("pause_applies_despite_withheld_ack", await until(func(): return room.suspended))
	await create_timer(.2).timeout
	a.withheld_ack = -1
	check("lost_pause_ack_retried", await until(func(): return not a.pending.has(str(pause_id)), 2))
	var paused_epoch = int(room.input_epoch)
	check("mutual_resume_after_ack_loss", await resume_team())
	var stale_pause = {"op": "pause", "request": a.request_serial + 1, "room": room.id, "match": room.match.id, "epoch": paused_epoch}
	a.request_serial += 1
	a.deliver(stale_pause)
	await until(func(): return server.sessions[a.identity.session].replies.has(str(stale_pause.request)))
	check("late_pause_cannot_repause_resumed_battle", not room.suspended and server.sessions[a.identity.session].replies[str(stale_pause.request)].code == "stale_context")
	packet = next_input(); packet.epoch = paused_epoch
	await reject_input("buffered_pre_resume_move_rejected", packet)

	# Duplicate/stale state cannot reset the UI, replay FX or renew input freshness.
	var original = a.room.duplicate(true)
	var snapshot_count = a.snapshot_serial
	a.accept_state(original)
	check("duplicate_snapshot_does_not_apply_twice", a.snapshot_serial == snapshot_count)
	var outdated = original.duplicate(true); outdated.state_seq -= 1; outdated.phase = "finished"
	a.accept_state(outdated)
	check("older_snapshot_cannot_replace_current_phase", a.room.phase == original.phase and a.snapshot_serial == snapshot_count)
	var foreign = original.duplicate(true); foreign.link = "previous-connection"; foreign.state_seq += 100000
	a.accept_state(foreign)
	check("old_connection_snapshot_rejected", a.snapshot_serial == snapshot_count)

	# Lost state ACKs bound the server window; duplicate snapshot re-ACK unsticks
	# the queue without applying the same authoritative world twice.
	a.withhold_state_acks = true
	await create_timer(.35).timeout
	var entry = server.connections[server.sessions[a.identity.session].peer]
	check("unacked_snapshot_window_bounded", entry.state_pending.size() <= Protocol.SNAPSHOT_WINDOW and entry.state_pending.size() > 0)
	a.withhold_state_acks = false
	check("snapshot_retry_unsticks_lost_ack", await until(func(): return not room.suspended and entry.state_pending.size() < Protocol.SNAPSHOT_WINDOW and a.can_play(), 1.2))

	# State-only blackholes must not be hidden by healthy ping/pong traffic.
	a.withhold_states = true
	var started = Time.get_ticks_msec()
	await create_timer(.7).timeout
	check("stale_state_disables_client_play_before_reconnect", not a.can_play())
	check("state_blackhole_freezes_team", await until(func(): return room.suspended, 2))
	check("state_blackhole_freeze_under_3_seconds", Time.get_ticks_msec() - started < 3000)
	var frozen_tick = room.match.tick_index
	var frozen_coins = room.match.world.coins
	await create_timer(.25).timeout
	check("blackhole_freezes_simulation_and_loot", room.match.tick_index == frozen_tick and room.match.world.coins == frozen_coins)
	a.withhold_states = false
	check("blackhole_reconnect_keeps_original_match", await until(func(): return a.state == "room" and a.room.get("id") == room.match.id and a.room.phase == "suspended", 9))
	check("blackhole_reconnect_needs_both_confirmations", await resume_team())

	# Uplink state confirmation loss must also freeze the simulation, not merely
	# reset the connection while the other player's dungeon keeps running.
	a.withhold_state_acks = true
	check("uplink_state_ack_blackhole_freezes_team", await until(func(): return room.suspended, 3))
	a.withhold_state_acks = false
	check("uplink_fault_reconnect_restores_room", await until(func(): return a.state == "room" and a.room.phase == "suspended", 9))
	check("uplink_fault_mutual_resume", await resume_team())

	# Disconnect during a partially confirmed resume clears both confirmations.
	await command(a, "pause"); await command(b, "resume")
	check("one_player_confirmed_before_second_outage", room.resume_ready[1] and not room.resume_ready[0])
	a.simulate_link_loss()
	check("second_outage_clears_both_resume_confirmations", await until(func(): return not room.resume_ready[0] and not room.resume_ready[1]))
	await until(func(): return a.state == "room" and a.room.phase == "suspended", 9)
	check("second_outage_mutual_resume", await resume_team())

	# A cached successful queue ACK is historical; it cannot recreate a queue
	# removed by disconnect. Its current service state is authoritative.
	var c = await add_client(2)
	c.withheld_ack = c.request_serial + 1
	var queued_id = c.request("queue", {"game_mode": "coop", "loadout": c.loadout})
	await until(func(): return server.sessions[c.identity.session].queued)
	c.simulate_link_loss(); c.withheld_ack = -1
	check("lost_queue_ack_replayed_after_reconnect", await until(func(): return c.state == "online" and c.pending.is_empty(), 9))
	check("cached_queue_reply_cannot_create_phantom_matchmaking", not server.sessions[c.identity.session].queued and not server.queue.has(c.identity.session) and c.state == "online" and not c.pending.has(str(queued_id)))
	var last_request = int(server.sessions[c.identity.session].last_request)
	block_preferences(c, true)
	check("local_spool_failure_never_sends_command", c.request("loadout", {"loadout": c.loadout}) < 0)
	await create_timer(.15).timeout
	check("local_spool_failure_keeps_server_unchanged", int(server.sessions[c.identity.session].last_request) == last_request and c.pending.is_empty())
	block_preferences(c, false)
	c.request("queue", {"game_mode": "coop", "loadout": c.loadout})
	block_preferences(c, true)
	check("local_ack_storage_failure_stops_connection", await until(func(): return c.state == "local_storage" and not c.wants_connection))
	block_preferences(c, false)
	c.connect_service()
	check("local_storage_repair_keeps_identity", await until(func(): return c.state == "online" and c.pending.is_empty()))
	check("local_storage_repair_cannot_repeat_queue", not server.sessions[c.identity.session].queued)
	var d = FaultClient.new(folder.path_join("welcome-loss"))
	d.withhold_welcome = true
	root.add_child(d); clients.append(d)
	d.connect_service("ws://127.0.0.1:19077", "首连故障")
	await until(func(): return d.welcomed > 0)
	var enrollment_id = str(d.welcome_ids[0])
	var enrollment_count = server.sessions.size()
	await create_timer(5.8).timeout
	d.withhold_welcome = false
	check("lost_first_welcome_has_finite_authentication_deadline", await until(func(): return d.state == "online", 3))
	check("first_welcome_retry_reuses_unclaimed_identity", d.identity.get("session") == enrollment_id and server.sessions.size() == enrollment_count)

	# Repeated growth requests/ACKs are safe and survive an identity reconnect.
	var world = room.match.world
	world.enemies.clear(); world.delayed.clear()
	world.room_flags.wave_count = 1; world.room_flags.wave_index = 1
	world.contexts[0].run.xp = 100; world.contexts[1].run.xp = 100
	world.clear_room(); room.match.sync_phase(); server.broadcast(room)
	check("actual_authority_growth_modal", await until(func(): return a.room.get("phase") == "draft" and b.room.get("phase") == "draft"))
	a.withheld_ack = a.request_serial + 1
	var choose_id = a.request("choose", {"index": 0, "choice_token": a.room.choice_token})
	await until(func(): return world.contexts[0].run.talents.size() == 1)
	await create_timer(1.05).timeout
	check("lost_choose_ack_does_not_duplicate_growth", world.contexts[0].run.talents.size() == 1 and a.pending.has(str(choose_id)))
	a.withheld_ack = -1
	check("lost_choose_ack_eventually_completes", await until(func(): return not a.pending.has(str(choose_id)), 2))
	check("duplicate_choose_preserves_partner_growth", world.contexts[0].run.talents.size() == 1 and world.contexts[1].run.talents.is_empty())

	# Prevent an old process retaking the identity when its close frame was lost.
	# The old peer is deliberately discarded before polling the close handshake.
	a.set_process(false)
	var replacement = FaultClient.new(a.credential_folder)
	root.add_child(replacement); clients.append(replacement)
	replacement.connect_service()
	check("new_process_takes_over_original_identity", await until(func(): return replacement.state == "room" and replacement.identity.session == a.identity.session))
	check("identity_takeover_freezes_team", room.suspended and room.suspend_reason == "identity_changed")
	a.open_socket(); a.set_process(true)
	check("lost_close_old_process_cannot_reclaim_identity", await until(func(): return a.state == "expired" and not a.wants_connection))
	check("replacement_remains_connected_after_old_retry", replacement.state == "room" and server.sessions[replacement.identity.session].owner_instance == replacement.instance_id)
	var generation = int(replacement.identity.owner_generation)
	check("old_process_cannot_overwrite_new_owner_credential", not a.save_preferences() and int(replacement.preferences.read().identities[replacement.endpoint].owner_generation) == generation)
	a = replacement

	# Late snapshots from a departed room must not reopen it after leave ACK.
	var previous_room = a.room.duplicate(true)
	check("leave_finishes_team", await command(a, "leave"))
	check("partner_receives_terminal_result", await until(func(): return b.room.get("phase") == "finished"))
	var losses = int(server.sessions[b.identity.session].coop_losses)
	server.settle_match(room); server.settle_match(room)
	check("repeat_settlement_keeps_one_team_loss", losses == 1 and int(server.sessions[b.identity.session].coop_losses) == losses)
	previous_room.state_seq = a.state_sequence + 1000
	a.accept_state(previous_room)
	check("departed_room_snapshot_cannot_reopen_room", a.room.is_empty() and a.state == "online")
	await command(c, "code", {"code": "056932", "game_mode": "coop", "loadout": c.loadout})
	check("finished_result_does_not_consume_active_room_capacity", await until(func(): return c.room.get("phase") == "lobby") and server.active_room_count() == 1 and server.rooms.size() == 2)
	await command(a, "code", {"code": "056933", "game_mode": "coop", "loadout": a.loadout})
	check("actual_active_room_limit_still_enforced", a.last_error == "server_full" and a.room.is_empty() and server.active_room_count() == 1)
	await command(c, "leave")
	await command(b, "leave")
	check("all_pending_commands_drained", clients.all(func(client): return client.pending.is_empty()))
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	if server != null: server.shutdown()
	var passed = checks.all(func(value): return value.passed)
	var file = FileAccess.open(folder.path_join("network-faults.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "native_websockets": true,
		"fault_layer": "application frame rejection/drop and abrupt real socket closure; TCP remains reliable and ordered",
		"isolated_authority_fixtures": ["invulnerability to isolate network timing", "room clear for growth controls"],
		"transport_revision": Protocol.TRANSPORT_REVISION, "virtualization": "none"}, "\t")); file.close()
	quit(0 if passed else 1)
