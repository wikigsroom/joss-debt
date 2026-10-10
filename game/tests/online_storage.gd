extends SceneTree
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var folder = ""
var url = "ws://127.0.0.1:18877"
var clients: Array = []
var checks: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="): folder = arg.trim_prefix("--folder=")
		if arg.begins_with("--url="): url = arg.trim_prefix("--url=")
	call_deferred("run")

func check(value: bool, id: String) -> void:
	checks.append({"id": id, "passed": value})
	print("STORAGE_%s %s" % ["PASS" if value else "FAIL", id])

func until(predicate: Callable, seconds: float = 8) -> bool:
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func marker(name: String) -> void:
	var file = FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	if file: file.store_string("ready"); file.close()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 2:
		var client = Session.new(folder.path_join("client-%d" % i))
		root.add_child(client); clients.append(client)
		client.connect_service(url, "Storage %d" % i)
	check(await until(func(): return clients.all(func(c): return c.state == "online")), "two_real_clients_connected")
	if clients.any(func(c): return c.state != "online"): finish(); return
	for client in clients: client.request("code", {"code": "001922", "loadout": client.loadout})
	await until(func(): return clients.all(func(c): return c.room.get("players", []).size() == 2))
	for client in clients: client.request("ready")
	await until(func(): return clients.all(func(c): return c.room.get("phase") == "draft"))
	for client in clients: client.request("choose", {"index": 0})
	check(await until(func(): return clients.all(func(c): return c.can_play())), "live_match_started")
	var frame = Protocol.empty_input(); frame.move = Vector2.RIGHT
	clients[0].submit_input(frame)
	marker("fault-ready")
	check(await until(func(): return clients.all(func(c): return c.state == "storage")), "write_failure_notifies_both_without_user_action")
	check(clients.all(func(c): return not c.can_play() and c.latest_input.move == Vector2.ZERO), "fault_stops_play_and_clears_input")
	var ticks = clients.map(func(c): return c.room.tick)
	await create_timer(.45).timeout
	check(clients.map(func(c): return c.room.tick) == ticks, "fault_keeps_battle_frozen")
	marker("fault-observed")
	check(await until(func(): return clients.all(func(c): return c.can_play()), 10), "repaired_storage_resumes_original_room")
	var position: Vector2 = clients[0].presentation[0].player.pos
	await create_timer(.35).timeout
	check(clients[0].presentation[0].player.pos.distance_to(position) < 1, "old_held_move_not_replayed_after_repair")
	clients[0].request("leave")
	await until(func(): return clients[1].room.get("phase") == "finished")
	clients[1].request("leave")
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	var failures = checks.filter(func(c): return not c.passed)
	var file = FileAccess.open(folder.path_join("storage-report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t")); file.close()
	quit(0 if failures.is_empty() else 1)
