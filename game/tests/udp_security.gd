extends SceneTree
const Server = preload("res://scripts/network/server_runtime.gd")
const Session = preload("res://scripts/network/online_session.gd")
const Battle = preload("res://scripts/network/enet_battle.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
class WatchedSession:
	extends Session
	var issued_ticket = ""
	func receive(message: Dictionary) -> void:
		if message.get("op") in ["welcome", "battle_grant"]: issued_ticket = str(message.battle.ticket)
		super.receive(message)
class DeferredBind:
	extends WatchedSession
	func poll_battle() -> void:
		# Establish real DTLS/ENet but deliberately withhold the application bind.
		if not battle_bound:
			battle.poll(); battle.flush(); return
		super.poll_battle()
var server
var client
var probes: Array = []
var checks: Array = []
var folder = ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	call_deferred("run")
func _process(_delta: float) -> bool:
	for probe in probes: probe.poll(); probe.flush()
	return false
func until(predicate: Callable, seconds: float = 6) -> bool:
	var at = Time.get_ticks_msec()
	while Time.get_ticks_msec() - at < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func check(label: String, passed: bool) -> void:
	checks.append({"id": label, "passed": passed}); print("UDP_SECURITY_", "PASS " if passed else "FAIL ", label)
func attacker():
	var probe = Battle.new()
	check("dtls_attacker_connect_%d" % probes.size(), probe.connect_client("127.0.0.1", 19279, "localhost", server.battle.certificate_pem) == OK)
	probes.append(probe)
	check("dtls_attacker_established_%d" % probes.size(), await until(func(): return probe.connected()))
	return probe
func run() -> void:
	if folder.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(folder)
	server = Server.new(); root.add_child(server)
	check("encrypted_authority_start", server.start({"port": 19277, "bind": "127.0.0.1", "data_directory": folder.path_join("private/server")}) == OK)
	client = WatchedSession.new(folder.path_join("private/client")); root.add_child(client)
	client.connect_service("ws://127.0.0.1:19277")
	check("valid_bootstrap_and_ticket", await until(func(): return client.state == "online" and client.battle_bound))
	if not checks[-1].passed: finish(); return
	var ticket_health = server.health().get("battle_tickets", {})
	check("ticket_lifecycle_health_is_bounded", ticket_health.has("active") and ticket_health.has("issued") and ticket_health.has("revocations") and ticket_health.has("reissues") and ticket_health.has("bind_failures") and ticket_health.has("rejections"))
	var invalid = await attacker()
	var rejected = server.udp_rejected
	invalid.send(invalid.remote, Protocol.packet({"op": "battle_bind", "ticket": Protocol.nonce(), "link": client.link_id}), Battle.CHANNEL_CONTROL)
	check("forged_ticket_rejected", await until(func(): return server.udp_rejected > rejected) and server.battle_connections.size() == 1)
	var replay = await attacker(); rejected = server.udp_rejected
	replay.send(replay.remote, Protocol.packet({"op": "battle_bind", "ticket": client.issued_ticket, "link": client.link_id}), Battle.CHANNEL_CONTROL)
	check("consumed_ticket_cannot_bind_second_peer", await until(func(): return server.udp_rejected > rejected) and server.battle_connections.size() == 1)
	var wrong = await attacker(); rejected = server.udp_rejected
	wrong.send(wrong.remote, Protocol.packet({"op": "queue", "request": 1, "game_mode": "coop", "loadout": client.loadout}), Battle.CHANNEL_CONTROL)
	check("unauthenticated_peer_has_no_economy_or_room_authority", await until(func(): return server.udp_rejected > rejected) and server.rooms.is_empty() and server.sessions.size() == 1)
	rejected = server.udp_rejected
	client.battle.send(client.battle.remote, Protocol.packet({"op": "queue", "request": 999, "game_mode": "coop", "loadout": client.loadout}), Battle.CHANNEL_INPUT)
	check("wrong_channel_cannot_execute_transaction", await until(func(): return server.udp_rejected > rejected) and server.sessions[client.identity.session].last_request == 0)
	rejected = server.udp_rejected
	client.battle.send(client.battle.remote, Protocol.packet({"op": "queue", "request": 999}, true), Battle.CHANNEL_CONTROL)
	check("client_variant_deserialization_forbidden", await until(func(): return server.udp_rejected > rejected) and server.sessions[client.identity.session].last_request == 0)
	rejected = server.udp_rejected
	client.battle.send(client.battle.remote, PackedByteArray([4, 1, 2]), Battle.CHANNEL_INPUT, false)
	check("truncated_input_rejected", await until(func(): return server.udp_rejected > rejected))
	var udp = PacketPeerUDP.new(); udp.bind(0, "127.0.0.1"); udp.set_dest_address("127.0.0.1", 19279)
	var edge_rejected = server.battle.edge.rejected
	for index in 100: udp.put_packet(PackedByteArray([23, 254, 253, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]))
	check("unknown_tls_application_records_never_allocate_handshakes", await until(func(): return server.battle.edge.rejected >= edge_rejected + 100) and server.battle_connections.size() == 1)
	udp.close()
	var request = client.request("loadout", {"loadout": {"character": "c_paper", "weapon": "w06", "skill": "s01"}})
	check("healthy_session_survives_all_rejections", await until(func(): return not client.pending.has(str(request))) and client.state == "online" and server.sessions[client.identity.session].loadout.weapon == "w06")
	var original_identity = client.identity.session
	client.peer.close(1000, "bootstrap_only")
	check("bootstrap_socket_closed_after_authenticated_bind", await until(func(): return client.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED))
	await create_timer(.4).timeout
	request = client.request("loadout", {"loadout": {"character": "c_paper", "weapon": "w14", "skill": "s01"}})
	check("healthy_battle_survives_bootstrap_loss", await until(func(): return not client.pending.has(str(request))) and client.state == "online" and client.identity.session == original_identity and server.sessions[original_identity].loadout.weapon == "w14")
	var replacement = WatchedSession.new(folder.path_join("private/client")); root.add_child(replacement)
	replacement.connect_service("ws://127.0.0.1:19277")
	check("battle_identity_revocation_without_bootstrap", await until(func(): return client.state == "expired" and not client.wants_connection and replacement.state == "online"))
	client.disconnect_service(); client = replacement
	var waiting = DeferredBind.new(folder.path_join("private/unbound")); root.add_child(waiting)
	waiting.connect_service("ws://127.0.0.1:19277")
	check("unused_ticket_fixture_has_authenticated_bootstrap", await until(func(): return waiting.authenticated and waiting.battle.connected()) and not waiting.battle_bound)
	var original_waiting_ticket = waiting.issued_ticket
	var waiting_connection = -1
	for candidate in server.connections:
		if str(server.connections[candidate].session) == waiting.identity.session: waiting_connection = int(candidate); break
	var refreshed = server.grant_battle(waiting_connection)
	check("regrant_fixture_has_single_connection_ticket", refreshed and await until(func(): return waiting.issued_ticket != original_waiting_ticket) and waiting.issued_ticket != "")
	var original_waiting_hash = original_waiting_ticket.sha256_text()
	var refreshed_hash = waiting.issued_ticket.sha256_text()
	check("superseded_ticket_revoked_before_regrant", not server.battle_tickets.has(original_waiting_hash) and server.battle_tickets.has(refreshed_hash) and server.battle_ticket_reissues >= 1)
	var stale = await attacker(); rejected = server.udp_rejected
	stale.send(stale.remote, Protocol.packet({"op": "battle_bind", "ticket": original_waiting_ticket, "link": waiting.link_id}), Battle.CHANNEL_CONTROL)
	check("superseded_ticket_cannot_rebind", await until(func(): return server.udp_rejected > rejected) and server.battle_tickets.has(refreshed_hash) and server.battle_connections.size() == 1)
	var unused_hash = refreshed_hash
	var foreign = await attacker(); rejected = server.udp_rejected
	foreign.send(foreign.remote, Protocol.packet({"op": "battle_bind", "ticket": waiting.issued_ticket, "link": Protocol.nonce(8)}), Battle.CHANNEL_CONTROL)
	check("unused_ticket_wrong_link_cannot_consume_or_take_over", await until(func(): return server.udp_rejected > rejected) and server.battle_tickets.has(unused_hash) and server.battle_connections.size() == 1)
	# Advance this isolated ticket's deadline only. The healthy connection and
	# real UDP handshake remain alive, so rejection tests expiry independently.
	if server.battle_tickets.has(unused_hash): server.battle_tickets[unused_hash].until = server.monotonic() - 1
	var expired = await attacker(); rejected = server.udp_rejected
	expired.send(expired.remote, Protocol.packet({"op": "battle_bind", "ticket": waiting.issued_ticket, "link": waiting.link_id}), Battle.CHANNEL_CONTROL)
	check("expired_unused_ticket_has_no_authority", await until(func(): return server.udp_rejected > rejected) and server.battle_connections.size() == 1)
	waiting.disconnect_service()
	finish()
func finish() -> void:
	for probe in probes: probe.close()
	if client != null: client.disconnect_service()
	if server != null: server.shutdown()
	var passed = not checks.is_empty() and checks.all(func(row): return row.passed)
	var file = FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": passed, "checks": checks, "scope": "Native encrypted sockets, wrong/replayed tickets, wrong channel, forbidden client Variant, malformed input and unknown DTLS records. Private data excluded from report."}, "\t") + "\n")
	quit(0 if passed else 1)
