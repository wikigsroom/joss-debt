extends SceneTree
## The shipping Session drives four real authenticated WSS clients for a minute.
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var clients: Array = []
var folder = ""
var errors: Array = []
var gaps: Array = []
var latencies: Array = []
var snapshots = 0
var sampled_frames = 0
var fresh_frames = 0
var streaming = false
func _initialize() -> void: call_deferred("run")
func until(predicate: Callable, seconds: float = 20) -> bool:
	var end = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return predicate.call()
func _process(_delta: float) -> bool:
	if not streaming: return false
	sampled_frames += 1
	if clients.all(func(client): return client.can_play()): fresh_frames += 1
	for client in clients:
		if not client.can_play(): continue
		var own = client.presentation[int(client.room.seat)]
		var target = own.nearest_enemy(own.player.pos)
		var frame = Protocol.empty_input()
		frame.move = Vector2(sin(Time.get_ticks_msec() * .0008), cos(Time.get_ticks_msec() * .0007))
		frame.aim = own.player.pos.direction_to(target.pos) if not target.is_empty() else Vector2.RIGHT
		frame.fire = true
		client.submit_input(frame)
	return false
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 4:
		var client = Session.new(folder.path_join("client%d" % i))
		client.loadout = {"character": "c_mask", "weapon": "w14" if i < 2 else "w07", "skill": "s10"}
		client.problem.connect(func(code): errors.append(str(code)))
		client.state_received.connect(func(_view): snapshots += 1)
		root.add_child(client); clients.append(client)
		client.connect_service(Session.OFFICIAL_ENDPOINT, "公网负载%d" % i)
	if not await until(func(): return clients.all(func(client): return client.state == "online")): errors.append("authentication_timeout"); finish(0); return
	var base = 600000 + randi() % 300000
	for i in 4:
		var client = clients[i]
		client.request("code", {"code": "%06d" % (base + int(i / 2)), "loadout": client.loadout, "game_mode": "coop"})
	if not await until(func(): return clients.all(func(client): return client.room.get("players", []).size() == 2)): errors.append("pairing_timeout"); finish(0); return
	for client in clients: client.request("ready")
	if not await until(func(): return clients.all(func(client): return client.can_play())): errors.append("battle_timeout"); finish(0); return
	streaming = true
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 60000:
		for client in clients:
			latencies.append(client.latency_ms)
			gaps.append(client.now() - client.last_state_received)
			if client.room.get("phase") == "draft" and int(client.room.picked[int(client.room.seat)]) < 0 and client.pending.is_empty():
				client.request("choose", {"index": 0, "choice_token": client.room.choice_token})
		await create_timer(.5).timeout
	streaming = false
	finish((Time.get_ticks_msec() - started) / 1000.0)
func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0
	values.sort()
	return float(values[int((values.size() - 1) * fraction)])
func finish(seconds: float) -> void:
	for client in clients:
		if client.state == "room": client.request("leave")
	await create_timer(1).timeout
	for client in clients: client.disconnect_service()
	var fresh = float(fresh_frames) / maxf(1, sampled_frames)
	var passed = seconds >= 60 and errors.is_empty() and snapshots > 800 and fresh >= .9
	var file = FileAccess.open(folder.path_join("clients.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "rooms": 2, "clients": 4, "battle_seconds": seconds, "snapshots": snapshots,
		"fresh_playable_frame_ratio": fresh, "ping_p95_ms": percentile(latencies, .95), "state_age_p95_ms": percentile(gaps, .95) * 1000,
		"errors": errors, "uses_shipping_session": true}, "\t", true, true)); file.close()
	quit(0 if passed else 1)
