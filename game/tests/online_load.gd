extends SceneTree
## Independent native traffic generator. No local combat or fabricated snapshots.
const Protocol = preload("res://scripts/network/protocol.gd")
var url = "ws://127.0.0.1:18977"
var room_count = 2
var weapons: Array = ["w01", "w04", "w07", "w11", "w16", "w21", "w25", "w30"]
var seconds = 45.0
var output = "user://online-load.json"
var clients: Array = []
var started = 0.0
var battle_started = -1.0
var input_elapsed = 0.0
var errors: Array = []
var latencies: Array = []
var intervals: Array = []
var states = 0
var rounds = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="): url = arg.trim_prefix("--url=")
		if arg.begins_with("--rooms="): room_count = int(arg.trim_prefix("--rooms="))
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--weapons="): weapons = Array(arg.trim_prefix("--weapons=").split(",", false))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec() / 1000.0
	for index in room_count * 2:
		var socket = WebSocketPeer.new()
		Protocol.configure_socket(socket)
		socket.connect_to_url(url)
		clients.append({"peer": socket, "hello": false, "request": 0, "seq": 0, "view": {}, "actions": {}, "last_state": 0.0, "last_ping": 0.0, "index": index})

func send(client: Dictionary, message: Dictionary) -> void:
	if client.peer.put_packet(Protocol.packet(message)) != OK: errors.append("send_failed")

func command(client: Dictionary, op: String, body: Dictionary = {}) -> void:
	client.request += 1
	body.op = op; body.request = client.request
	send(client, body)

func once(client: Dictionary, key: String, op: String, body: Dictionary = {}) -> void:
	if client.actions.has(key): return
	client.actions[key] = true
	command(client, op, body)

func _process(delta: float) -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	input_elapsed += delta
	var input_due = input_elapsed >= 1.0 / Protocol.INPUT_RATE
	if input_due: input_elapsed = 0
	for client in clients:
		client.peer.poll()
		if client.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			if now - started > 12: errors.append("connection_closed")
			continue
		if not client.hello:
			client.hello = true; client.peer.set_no_delay(true)
			send(client, {"op": "hello", "protocol": Protocol.VERSION, "content": Protocol.fingerprint(), "name": "压力验证%d" % client.index, "resume": ""})
		while client.peer.get_available_packet_count() > 0:
			var message = Protocol.unpack(client.peer.get_packet())
			if message.is_empty(): errors.append("invalid_snapshot"); continue
			match message.get("op"):
				"welcome":
					var loadout = {"character": "c_paper", "weapon": weapons[(client.index / 2) % weapons.size()], "skill": "s01"}
					command(client, "code", {"code": "%06d" % (300000 + client.index / 2), "loadout": loadout})
				"ack":
					if not message.get("ok", false): errors.append(str(message.get("code")))
				"error": errors.append(str(message.get("code")))
				"pong": latencies.append(maxf(0, (now * 1000 - int(message.nonce))))
				"state":
					client.view = message
					if battle_started >= 0 and client.last_state > 0: intervals.append((now - float(client.last_state)) * 1000)
					client.last_state = now; states += 1
					if not message.get("events", []).is_empty(): send(client, {"op": "events_ack", "match": str(message.get("id", "")), "event": int(message.events.back().event_id)})
		var view = client.view
		if view.is_empty(): continue
		var match_key = str(view.get("id", "room"))
		var round_key = match_key + "/" + str(view.get("round", 1))
		match view.get("phase"):
			"lobby": once(client, "ready", "ready")
			"draft": once(client, round_key, "choose", {"index": client.index % 4})
			"finished": once(client, match_key + "rematch", "rematch")
			"suspended": errors.append("unexpected_suspension")
			"playing":
				if input_due:
					client.seq += 1
					var frame = Protocol.empty_input()
					var seat = int(view.seat)
					var own = Vector2(view.actors[seat].player.pos)
					var other = Vector2(view.actors[1 - seat].player.pos)
					frame.seq = client.seq
					frame.move = Vector2(sin(now * .8 + client.index), cos(now * .7 + client.index))
					frame.aim = own.direction_to(other); frame.fire = fmod(now, 1.5) < 1.2
					frame.dash = client.seq % 90 == 0; frame.skill = client.seq % 150 == 0
					send(client, {"op": "input", "frame": frame})
		if now - float(client.last_ping) > 2:
			client.last_ping = now
			send(client, {"op": "ping", "nonce": int(now * 1000)})
	if battle_started < 0 and clients.all(func(client): return client.view.get("phase") == "playing"):
		battle_started = now
	if battle_started >= 0 and now - battle_started >= seconds or now - started > seconds + 60 or errors.size() > 100:
		finish(now)
	return false

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted = values.duplicate(); sorted.sort()
	return sorted[int((sorted.size() - 1) * fraction)]

func finish(now: float) -> void:
	var active_seconds = now - battle_started if battle_started >= 0 else 0
	var report = {"passed": errors.is_empty() and active_seconds >= seconds and states > room_count * seconds * 10,
		"rooms": room_count, "clients": clients.size(), "weapons": weapons, "battle_seconds": active_seconds, "snapshots": states,
		"ping_p95_ms": percentile(latencies, .95), "snapshot_interval_p95_ms": percentile(intervals, .95),
		"snapshot_interval_p99_ms": percentile(intervals, .99), "snapshot_interval_max_ms": intervals.max() if not intervals.is_empty() else 0.0,
		"errors": errors.slice(0, 40)}
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	for client in clients: client.peer.close(1000, "load_test_complete")
	print("ONLINE_LOAD_RESULT " + JSON.stringify(report))
	quit(0 if report.passed else 1)
