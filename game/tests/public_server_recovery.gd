extends SceneTree
## Two real WSS clients survive a graceful restart of the deployed service.
const Session = preload("res://scripts/network/online_session.gd")
var clients: Array = []
var folder = ""
var checks: Array = []

func _initialize() -> void: call_deferred("run")
func until(predicate: Callable, seconds: float = 15) -> bool:
	var end = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func check(id: String, result: bool) -> void:
	checks.append({"id": id, "passed": result})
	print("PUBLIC_RECOVERY ", id, " ", result)
func saved_state(view: Dictionary) -> String:
	# Checkpoint JSON round-trips integral numbers as floats. Compare canonical
	# wire values rather than treating 100 and 100.0 as lost health or currency.
	var wire = JSON.stringify({"id": view.id, "scene": view.scene.serial, "actors": view.actors, "builds": view.builds, "score": view.score})
	return JSON.stringify(JSON.parse_string(wire)).sha256_text()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 2:
		var client = Session.new(folder.path_join("client%d" % i))
		root.add_child(client); clients.append(client)
		client.connect_service(Session.OFFICIAL_ENDPOINT, "恢复验证%d" % i)
	check("both_authenticated_over_public_wss", await until(func(): return clients.all(func(client): return client.state == "online")))
	if not checks.back().passed: finish(); return
	var code_value = "%06d" % (500000 + randi() % 400000)
	clients[0].request("code", {"code": code_value, "loadout": clients[0].loadout, "game_mode": "coop"})
	check("first_creates_room", await until(func(): return clients[0].room.get("phase") == "lobby"))
	clients[1].request("code", {"code": code_value, "loadout": clients[1].loadout, "game_mode": "coop"})
	check("second_joins_same_room", await until(func(): return clients.all(func(client): return client.room.get("players", []).size() == 2)))
	for client in clients: client.request("ready")
	check("playing_before_restart", await until(func(): return clients.all(func(client): return client.can_play()), 20))
	clients[0].request("pause")
	check("mutual_pause_observed", await until(func(): return clients.all(func(client): return client.room.get("phase") == "suspended")))
	if not checks.all(func(item): return item.passed): finish(); return
	await create_timer(2).timeout
	var digest = saved_state(clients[0].room)
	var before_file = FileAccess.open(folder.path_join("state-before.json"), FileAccess.WRITE)
	before_file.store_string(JSON.stringify(clients[0].room)); before_file.close()
	var marker = FileAccess.open(folder.path_join("restart-ready"), FileAccess.WRITE)
	marker.store_string("own isolated verification clients ready"); marker.close()
	check("both_automatically_reconnect_after_service_restart", await until(func(): return clients.all(func(client): return client.state == "room" and client.room.get("suspend_reason") == "server_restarted"), 50))
	if not checks.back().passed: finish(); return
	var after_file = FileAccess.open(folder.path_join("state-after.json"), FileAccess.WRITE)
	after_file.store_string(JSON.stringify(clients[0].room)); after_file.close()
	check("checkpoint_preserves_room_actors_and_growth", saved_state(clients[0].room) == digest)
	check("restart_requires_both_confirmations", clients.all(func(client): return client.room.phase == "suspended" and not client.room.resume_ready[0] and not client.room.resume_ready[1]))
	clients[0].request("resume")
	check("one_confirmation_cannot_resume_battle", await until(func(): return clients.all(func(client): return client.room.resume_ready[0] and client.room.phase == "suspended")))
	clients[1].request("resume")
	check("both_confirmations_resume_real_battle", await until(func(): return clients.all(func(client): return client.can_play()), 12))
	finish()
func finish() -> void:
	for client in clients:
		if client.state == "room": client.request("leave")
	await create_timer(1).timeout
	for client in clients: client.disconnect_service()
	var passed = checks.all(func(item): return item.passed)
	var file = FileAccess.open(folder.path_join("public-recovery.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "real_public_wss": true}, "\t", true, true)); file.close()
	quit(0 if passed else 1)
