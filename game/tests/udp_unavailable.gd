extends SceneTree
const Server = preload("res://scripts/network/server_runtime.gd")
const Session = preload("res://scripts/network/online_session.gd")
var checks: Array = []
var output = ""
var issues: Array = []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")
func check(label: String, passed: bool) -> void:
	checks.append({"id": label, "passed": passed}); print("UDP_UNAVAILABLE_", "PASS " if passed else "FAIL ", label)
func until(predicate: Callable, seconds: float) -> bool:
	var begin = Time.get_ticks_msec()
	while Time.get_ticks_msec() - begin < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func run() -> void:
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var server = Server.new(); root.add_child(server)
	check("native_authority", server.start({"bind": "127.0.0.1", "port": 19317, "data_directory": output.get_basename() + "-private/server"}) == OK)
	# A real bound UDP sink drops every incoming datagram. It models filtering
	# without generating an ICMP port-unreachable or using a virtual network.
	var sink = PacketPeerUDP.new()
	check("native_udp_filter_fixture", sink.bind(19329, "127.0.0.1") == OK)
	var client = Session.new(output.get_basename() + "-private/client"); root.add_child(client)
	client.battle_port_override = 19329
	client.problem.connect(func(code): issues.append(code))
	client.connect_service("ws://127.0.0.1:19317")
	check("bootstrap_cannot_silently_use_tcp_battle", await until(func(): return client.authenticated and not client.battle_bound, 5) and server.battle_connections.is_empty())
	var bounded = await until(func(): return issues.has("battle_unavailable") or issues.has("battle_bind_timeout") or issues.has("battle_disconnected"), 24)
	check("filtered_udp_has_bounded_recovery_feedback", bounded and not client.can_play())
	var identity = str(client.identity.session)
	client.battle_port_override = 0
	client.connect_service("ws://127.0.0.1:19317")
	check("unblocked_udp_recovers_same_identity", await until(func(): return client.state == "online" and client.battle_bound, 12) and client.identity.session == identity)
	client.disconnect_service(); sink.close(); server.shutdown()
	var passed = checks.all(func(row): return row.passed)
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": passed, "checks": checks, "scope": "Native bootstrap and total UDP loss, bounded feedback, real recovery with the same saved identity; no TCP battle fallback."}, "\t") + "\n")
	quit(0 if passed else 1)
