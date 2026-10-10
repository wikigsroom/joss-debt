extends SceneTree
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var clients: Array = []
var checks: Array = []
var failures = 0
var folder = ""
var url = "ws://127.0.0.1:18777"
var errors: Array = [[], [], []]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="): url = arg.trim_prefix("--url=")
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	if folder.is_empty(): folder = "user://online-qa-%d" % Time.get_ticks_usec()
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures += 1
		push_error("ONLINE_QA_FAIL " + name)
	else: print("ONLINE_QA_PASS " + name)

func until(predicate: Callable, timeout: float = 5.0) -> bool:
	var start = Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < timeout:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func phase(client, value: String) -> bool:
	return str(client.room.get("phase", "")) == value

func command(client, op: String, data: Dictionary = {}) -> bool:
	var request_id = client.request(op, data)
	return request_id > 0 and await until(func(): return not client.pending.has(str(request_id)))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 3:
		var client = Session.new(folder.path_join("client-%d" % i))
		client.problem.connect(func(code): errors[i].append(code))
		root.add_child(client)
		clients.append(client)
		client.connect_service(url, "联机验证%d" % i)
	check(await until(func(): return clients.all(func(c): return c.state == "online")), "three real WebSocket handshakes")
	if failures > 0: finish(); return
	var a = clients[0]
	var b = clients[1]
	var c = clients[2]
	var loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
	check(await command(a, "queue", {"loadout": loadout}), "first player queues")
	check(a.state == "queued", "queue waits for a second player")
	check(await command(b, "queue", {"loadout": loadout}), "second player queues")
	check(await until(func(): return phase(a, "lobby") and phase(b, "lobby") and a.room.room == b.room.room), "atomic random pairing")
	check(a.room.get("seat") == 0 and b.room.get("seat") == 1, "two separate seats")
	await command(a, "ready")
	await command(b, "ready")
	check(await until(func(): return phase(a, "draft") and phase(b, "draft")), "both ready starts draft")
	check(a.room.get("offers", []).size() == 4 and b.room.get("offers", []).size() == 4, "four draft choices per player")
	await command(a, "choose", {"index": 0})
	await command(b, "choose", {"index": 0})
	check(await until(func(): return a.can_play() and b.can_play(), 6), "authoritative countdown reaches battle")
	if failures > 0: finish(); return
	var start_pos: Vector2 = a.presentation[0].player.pos
	var start_time = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_time < 1100:
		var fa = Protocol.empty_input()
		var fb = Protocol.empty_input()
		fa.move = Vector2.RIGHT; fa.aim = Vector2.RIGHT
		fb.move = Vector2.LEFT; fb.aim = Vector2.LEFT
		a.submit_input(fa); b.submit_input(fb)
		await process_frame
	check(a.presentation[0].player.pos.x > start_pos.x + 50, "real inputs move the authoritative player")
	start_time = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_time < 1700 and a.can_play():
		var fa = Protocol.empty_input()
		fa.aim = Vector2(a.presentation[0].player.pos).direction_to(b.presentation[1].player.pos)
		fa.fire = true
		a.submit_input(fa); b.submit_input(Protocol.empty_input())
		await process_frame
	check(float(b.presentation[1].player.hp) < float(b.presentation[1].player.max_hp), "real weapon projectiles damage the opponent")
	var match_id = str(a.room.id)
	b.simulate_link_loss()
	check(await until(func(): return phase(a, "suspended")), "disconnect suspends both players")
	var frozen_tick = int(a.room.tick)
	var frozen_hp = float(a.presentation[1].player.hp)
	await create_timer(.35).timeout
	check(int(a.room.tick) == frozen_tick and is_equal_approx(float(a.presentation[1].player.hp), frozen_hp), "disconnect freezes battle time and health")
	check(await until(func(): return b.state == "room" and phase(b, "suspended"), 7), "automatic retry recovers the original session")
	check(str(b.room.id) == match_id and float(b.presentation[1].player.hp) == frozen_hp, "resume keeps match identity and health")
	await command(a, "resume")
	check(phase(a, "suspended"), "one ready player cannot resume alone")
	await command(b, "resume")
	check(await until(func(): return a.can_play() and b.can_play(), 6), "both confirmations resume after countdown")
	await command(a, "pause")
	check(await until(func(): return phase(a, "suspended") and phase(b, "suspended")), "pause menu freezes both clients")
	await command(a, "leave")
	check(await until(func(): return phase(b, "finished") and int(b.room.winner) == 1), "leaving a battle settles a forfeit")
	check(int(b.stats.wins) == 1 and int(a.stats.losses) == 1, "result counted once for both players")
	await command(b, "leave")
	check(await until(func(): return a.state == "online" and b.state == "online"), "both return to the lobby")
	await command(a, "code", {"code": "001234", "loadout": loadout})
	await command(b, "code", {"code": "001234", "loadout": loadout})
	check(await until(func(): return phase(a, "lobby") and phase(b, "lobby") and a.room.room == b.room.room), "same six-digit code joins the same room")
	check(str(a.room.code) == "001234", "leading zeroes are preserved")
	await command(c, "code", {"code": "001234", "loadout": loadout})
	check(errors[2].has("room_full") and c.room.is_empty(), "third player rejected without disturbing the room")
	await command(c, "code", {"code": "12345", "loadout": loadout})
	check(errors[2].has("invalid_code"), "invalid room code rejected")
	await command(a, "leave"); await command(b, "leave")
	await command(c, "queue", {"loadout": loadout})
	await command(c, "cancel_queue")
	check(c.state == "online" and c.room.is_empty(), "cancel matching returns to online lobby")
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	var report = {"checks": checks, "failures": failures, "real_transport": true, "endpoint": url, "errors": errors}
	var file = FileAccess.open(folder.path_join("transport-report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("ONLINE_TRANSPORT_RESULT checks=%d failures=%d" % [checks.size(), failures])
	quit(0 if failures == 0 else 1)
