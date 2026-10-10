extends Node
const Protocol = preload("res://scripts/network/protocol.gd")
const Duel = preload("res://scripts/network/duel_match.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Content = preload("res://scripts/core/content_db.gd")
var db = Content.new()
var listener = TCPServer.new()
var health_listener = TCPServer.new()
var connections: Dictionary = {}
var health_connections: Array = []
var sessions: Dictionary = {}
var rooms: Dictionary = {}
var codes: Dictionary = {}
var queue: Array = []
var settled: Dictionary = {}
var meta_store
var data_directory = ""
var bind_address = "127.0.0.1"
var port = Protocol.PORT
var max_connections = 16
var max_rooms = 2
var grace = Protocol.RECONNECT_SECONDS
var waiting_ttl = 300.0
var checkpoint_interval = 1.0
var connection_serial = 0
var snapshot_elapsed = 0.0
var checkpoint_elapsed = 0.0
var maintenance_elapsed = 0.0
var uptime = 0.0
var persistence_errors = 0
var bytes_sent = 0
var ticks = 0
var step_ms: Array = []
var process_ms: Array = []
var cleanup_elapsed = 0.0
var checkpoint_thread: Thread
var stopping = false
var storage_fault = false
var recovery_failed = false

func start(options: Dictionary = {}) -> Error:
	bind_address = str(options.get("bind", "127.0.0.1"))
	port = clampi(int(options.get("port", Protocol.PORT)), 1024, 65534)
	max_connections = clampi(int(options.get("max_connections", 16)), 2, 512)
	max_rooms = clampi(int(options.get("max_rooms", 2)), 1, 128)
	grace = clampf(float(options.get("grace", Protocol.RECONNECT_SECONDS)), 1, 300)
	waiting_ttl = clampf(float(options.get("waiting", 300)), 5, 1800)
	checkpoint_interval = clampf(float(options.get("checkpoint", 1)), .1, 10)
	data_directory = str(options.get("data_directory", "user://online-server"))
	DirAccess.make_dir_recursive_absolute(data_directory)
	meta_store = Store.new(data_directory.path_join("registry"))
	var previous = consistent_registry()
	if meta_store.read_only: return ERR_FILE_CORRUPT
	if recovery_failed: return ERR_FILE_CORRUPT
	if not previous.is_empty() and (previous.get("protocol") != Protocol.VERSION or previous.get("content") != Protocol.fingerprint()): return ERR_INVALID_DATA
	if not previous.is_empty(): recover_registry(previous)
	var error = listener.listen(port, bind_address)
	if error != OK: return error
	error = health_listener.listen(port + 1, bind_address)
	if error != OK:
		listener.stop()
		return error
	set_process(true)
	set_physics_process(true)
	print("ONLINE_READY port=%d health=%d recovered_rooms=%d protocol=%d" % [port, port + 1, rooms.size(), Protocol.VERSION])
	return OK

func monotonic() -> float:
	return Time.get_ticks_msec() / 1000.0

func wall_time() -> float:
	return Time.get_unix_time_from_system()

func _process(delta: float) -> void:
	if stopping: return
	var begin = Time.get_ticks_usec()
	finish_checkpoint(false)
	uptime += delta
	while listener.is_connection_available():
		var stream = listener.take_connection()
		if connections.size() >= max_connections:
			stream.disconnect_from_host()
			continue
		var peer = WebSocketPeer.new()
		Protocol.configure_socket(peer, true)
		if peer.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		connection_serial += 1
		connections[connection_serial] = {"peer": peer, "stream": stream, "session": "", "last_seen": monotonic(),
			"created": monotonic(), "tokens": 100.0, "refill": monotonic(), "event_ack": 0, "event_match": "", "no_delay": false}
	for connection_id in connections.keys():
		if not connections.has(connection_id): continue
		var entry = connections[connection_id]
		var peer = entry.peer
		peer.poll()
		var state = peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			disconnect_peer(connection_id)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			if monotonic() - float(entry.created) > 6: close_peer(connection_id, "handshake_timeout")
			continue
		if not entry.no_delay:
			peer.set_no_delay(true)
			entry.no_delay = true
		while peer.get_available_packet_count() > 0 and connections.has(connection_id):
			var packet = peer.get_packet()
			var now = monotonic()
			entry.tokens = minf(100, float(entry.tokens) + (now - float(entry.refill)) * 65)
			entry.refill = now
			entry.tokens -= 1
			if entry.tokens < 0:
				close_peer(connection_id, "rate_limited")
				break
			var message = Protocol.unpack(packet, true)
			if message.is_empty():
				close_peer(connection_id, "invalid_packet")
				break
			entry.last_seen = now
			handle(connection_id, message)
		if connections.has(connection_id) and monotonic() - float(entry.last_seen) > Protocol.SILENCE_SECONDS:
			close_peer(connection_id, "heartbeat_timeout")
		elif connections.has(connection_id) and str(entry.session).is_empty() and monotonic() - float(entry.created) > 6:
			close_peer(connection_id, "authentication_timeout")
	process_health()
	cleanup_elapsed += delta
	if cleanup_elapsed >= 60 and checkpoint_thread == null:
		cleanup_elapsed = 0
		cleanup_retention()
	snapshot_elapsed += delta
	if snapshot_elapsed >= 1.0 / Protocol.SNAPSHOT_RATE:
		snapshot_elapsed = 0
		if not storage_fault:
			for room in rooms.values(): broadcast(room)
	maintenance_elapsed += delta
	if maintenance_elapsed >= .2:
		maintenance_elapsed = 0
		maintenance()
		if FileAccess.file_exists(data_directory.path_join("stop")):
			DirAccess.remove_absolute(data_directory.path_join("stop"))
			shutdown()
			get_tree().quit()
	process_ms.append((Time.get_ticks_usec() - begin) / 1000.0)
	if process_ms.size() > 600: process_ms.pop_front()

func _physics_process(delta: float) -> void:
	if stopping: return
	var begin = Time.get_ticks_usec()
	ticks += 1
	for room in ([] if storage_fault else rooms.values()):
		if room.match == null or room.suspended or room.match.phase == "finished": continue
		var frames: Array = []
		for seat in 2:
			var input = room.inputs[seat]
			var fresh = monotonic() - float(input.last_seen) <= Protocol.INPUT_TIMEOUT
			frames.append(input.frame.duplicate(true) if fresh else Protocol.empty_input())
			if fresh: room.applied_seq[seat] = int(input.seq)
			for edge in ["dash", "skill", "active_item"]: input.frame[edge] = false
		room.match.advance(frames, 1.0 / Protocol.TICK_RATE)
		if room.match.phase == "finished": settle_match(room)
	checkpoint_elapsed += delta
	if checkpoint_elapsed >= checkpoint_interval:
		checkpoint_elapsed = 0
		start_checkpoint()
	step_ms.append((Time.get_ticks_usec() - begin) / 1000.0)
	if step_ms.size() > 600: step_ms.pop_front()

func send(connection_id: int, message: Dictionary, compressed: bool = false) -> bool:
	if not connections.has(connection_id): return false
	var peer = connections[connection_id].peer
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	if peer.get_current_outbound_buffered_amount() > Protocol.MAX_SERVER_BYTES:
		close_peer(connection_id, "slow_connection")
		return false
	var bytes = Protocol.packet(message, compressed)
	if bytes.size() > Protocol.MAX_SERVER_BYTES: return false
	var result = peer.put_packet(bytes)
	if result == OK: bytes_sent += bytes.size()
	return result == OK

func close_peer(connection_id: int, reason: String) -> void:
	if not connections.has(connection_id): return
	var socket = connections[connection_id].peer
	socket.close(4001 if reason == "session_replaced" else -1, reason)
	if reason == "session_replaced": socket.poll()
	disconnect_peer(connection_id)

func disconnect_peer(connection_id: int) -> void:
	if not connections.has(connection_id): return
	var entry = connections[connection_id]
	var sid = str(entry.session)
	connections.erase(connection_id)
	if not sessions.has(sid) or int(sessions[sid].peer) != connection_id: return
	var session = sessions[sid]
	session.peer = -1
	session.last_seen = wall_time()
	queue.erase(sid)
	session.queued = false
	var room = rooms.get(str(session.room))
	if room != null:
		var seat = room.players.find(sid)
		room.inputs[seat].frame = Protocol.empty_input()
		room.inputs[seat].last_seen = 0.0
		room.ready[seat] = false
		if room.match != null and room.match.phase != "finished": suspend_room(room, "disconnect")
		persist_room(room)
	persist_registry()

func handle(connection_id: int, message: Dictionary) -> void:
	var op = str(message.get("op", ""))
	var entry = connections[connection_id]
	if op == "health":
		send(connection_id, {"op": "health", "health": health()})
		return
	if str(entry.session).is_empty():
		if op != "hello": close_peer(connection_id, "authentication_required")
		else: authenticate(connection_id, message)
		return
	var sid = str(entry.session)
	if not sessions.has(sid) or int(sessions[sid].peer) != connection_id:
		close_peer(connection_id, "session_replaced")
		return
	var session = sessions[sid]
	if op == "ping":
		send(connection_id, {"op": "pong", "nonce": message.get("nonce", 0), "server_time": wall_time()})
		return
	if op == "input":
		receive_input(session, message)
		return
	if op == "events_ack":
		if Protocol.Store.integer(message.get("event")) and str(message.get("match", "")) == entry.event_match:
			entry.event_ack = maxi(int(entry.event_ack), int(message.event))
		return
	if storage_fault:
		send(connection_id, {"op": "error", "code": "storage_unavailable"})
		return
	if not Store.integer(message.get("request")) or int(message.request) < 1 or int(message.request) > 2147483647:
		send(connection_id, {"op": "error", "code": "invalid_request"})
		return
	var request_id = int(message.request)
	if request_id <= int(session.last_request):
		var cached = session.replies.get(str(request_id), {"op": "ack", "request": request_id, "ok": false, "code": "stale_request"})
		send(connection_id, cached)
		return
	var result = command(session, op, message)
	result.op = "ack"
	result.request = request_id
	session.last_request = request_id
	session.replies[str(request_id)] = result
	while session.replies.size() > 16: session.replies.erase(session.replies.keys()[0])
	if storage_fault or not persist_registry(): result = {"op": "error", "code": "storage_unavailable"}
	send(connection_id, result)
	if rooms.has(str(session.room)): broadcast(rooms[str(session.room)])

func authenticate(connection_id: int, message: Dictionary) -> void:
	if storage_fault:
		send(connection_id, {"op": "error", "code": "storage_unavailable"})
		close_peer(connection_id, "storage_unavailable")
		return
	if message.get("protocol") != Protocol.VERSION or message.get("content") != Protocol.fingerprint():
		send(connection_id, {"op": "error", "code": "version_mismatch", "protocol": Protocol.VERSION})
		connections[connection_id].peer.close(1008, "version_mismatch")
		return
	var token = str(message.get("resume", ""))
	var sid = ""
	if not token.is_empty():
		if token.length() != 48:
			send(connection_id, {"op": "error", "code": "session_expired"})
			return
		for candidate in sessions:
			if sessions[candidate].token_hash == token.sha256_text(): sid = candidate; break
		if sid.is_empty():
			send(connection_id, {"op": "error", "code": "session_expired"})
			return
	else:
		if sessions.size() >= 1024:
			send(connection_id, {"op": "error", "code": "server_full"})
			return
		sid = Protocol.nonce(16)
		token = Protocol.nonce()
		sessions[sid] = {"id": sid, "token_hash": token.sha256_text(), "name": Protocol.clean_name(message.get("name", "")),
			"room": "", "queued": false, "peer": -1, "last_seen": wall_time(), "last_request": 0, "replies": {},
			"loadout": {"character": "c_paper", "weapon": "w01", "skill": "s01"}, "wins": 0, "losses": 0, "draws": 0}
	var session = sessions[sid]
	if int(session.peer) >= 0 and int(session.peer) != connection_id:
		# Detach first: closing the old peer cannot suspend the new connection.
		var old_peer = int(session.peer)
		session.peer = -1
		close_peer(old_peer, "session_replaced")
	session.peer = connection_id
	session.last_seen = wall_time()
	session.name = Protocol.clean_name(message.get("name", session.name))
	connections[connection_id].session = sid
	if not persist_registry():
		send(connection_id, {"op": "error", "code": "storage_unavailable"})
		close_peer(connection_id, "storage_unavailable")
		return
	var room = rooms.get(str(session.room))
	var last_seq = 0
	if room != null:
		var seat = room.players.find(sid)
		last_seq = int(room.inputs[seat].seq)
		room.inputs[seat].frame = Protocol.empty_input()
		room.inputs[seat].last_seen = 0.0
		room.resume_ready[seat] = false
	send(connection_id, {"op": "welcome", "session": sid, "resume": token, "request_floor": session.last_request,
		"input_floor": last_seq, "server_time": wall_time(), "grace": grace,
		"stats": {"wins": session.wins, "losses": session.losses, "draws": session.draws}})
	if room != null: broadcast(room)

func valid_loadout(value) -> bool:
	if not value is Dictionary: return false
	var character = db.row("characters", str(value.get("character", "")))
	return not character.is_empty() and not db.row("weapons", str(value.get("weapon", ""))).is_empty() and character.skills.has(value.get("skill", ""))

func command(session: Dictionary, op: String, message: Dictionary) -> Dictionary:
	var sid = str(session.id)
	var room = rooms.get(str(session.room))
	match op:
		"loadout":
			if room != null or session.queued: return failure("busy")
			if not valid_loadout(message.get("loadout")): return failure("invalid_loadout")
			session.loadout = message.loadout.duplicate(true)
			return success()
		"queue":
			if room != null: return failure("already_in_room")
			if not valid_loadout(message.get("loadout")): return failure("invalid_loadout")
			session.loadout = message.loadout.duplicate(true)
			if not queue.has(sid): queue.append(sid)
			session.queued = true
			match_queue()
			return success({"queued": bool(session.queued)})
		"cancel_queue":
			queue.erase(sid)
			session.queued = false
			if room != null and room.get("quick", false) and room.match == null: leave_room(session)
			return success()
		"code":
			if room != null or session.queued: return failure("busy")
			if not Protocol.valid_code(message.get("code")): return failure("invalid_code")
			if not valid_loadout(message.get("loadout")): return failure("invalid_loadout")
			session.loadout = message.loadout.duplicate(true)
			var code = str(message.code)
			if codes.has(code):
				room = rooms[codes[code]]
				if room.players.size() >= 2: return failure("room_full")
				if room.match != null: return failure("room_started")
				room.players.append(sid)
				session.room = room.id
				persist_room(room)
			else:
				if rooms.size() >= max_rooms: return failure("server_full")
				room = create_room([sid], code)
			return success({"room": room.id, "code": room.code})
		"ready":
			if room == null or room.match != null: return failure("not_in_lobby")
			var seat = room.players.find(sid)
			room.ready[seat] = bool(message.get("ready", true))
			if room.players.size() == 2 and room.ready[0] and room.ready[1] and all_connected(room): begin_match(room)
			persist_room(room)
			return success()
		"choose":
			if room == null or room.match == null or room.suspended: return failure("not_choosing")
			if not Store.integer(message.get("index")) or not room.match.choose(room.players.find(sid), int(message.index)): return failure("invalid_choice")
			persist_room(room)
			return success()
		"pause":
			if room == null or room.match == null or room.match.phase == "finished": return failure("not_playing")
			suspend_room(room, "menu", room.players.find(sid))
			persist_room(room)
			return success()
		"resume":
			if room == null or not room.suspended: return failure("not_suspended")
			room.resume_ready[room.players.find(sid)] = true
			if all_connected(room) and room.resume_ready[0] and room.resume_ready[1]:
				room.suspended = false
				room.suspend_until = 0.0
				if room.match.phase == "playing": room.match.phase = "countdown"; room.match.countdown = 3.0
				room.match.push_event("resumed")
			persist_room(room)
			return success()
		"leave":
			queue.erase(sid)
			session.queued = false
			if room != null: leave_room(session)
			return success()
		"rematch":
			if room == null or room.match == null or room.match.phase != "finished": return failure("not_finished")
			room.rematch_ready[room.players.find(sid)] = true
			if room.rematch_ready[0] and room.rematch_ready[1] and all_connected(room): begin_match(room)
			persist_room(room)
			return success()
	return failure("unknown_command")

func success(extra: Dictionary = {}) -> Dictionary:
	var result = {"ok": true}
	result.merge(extra)
	return result

func failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}

func connected(sid: String) -> bool:
	return sessions.has(sid) and connections.has(int(sessions[sid].peer))

func all_connected(room: Dictionary) -> bool:
	return room.players.size() == 2 and room.players.all(func(sid): return connected(sid) and str(sessions[sid].room) == room.id)

func create_room(players: Array, code: String = "", quick: bool = false) -> Dictionary:
	var room_id = Protocol.nonce(16)
	var room = {"id": room_id, "code": code, "quick": quick, "players": players.duplicate(),
		"ready": [false, false], "resume_ready": [false, false], "rematch_ready": [false, false],
		"created": wall_time(), "match": null, "suspended": false, "suspend_reason": "", "suspend_until": 0.0,
		"inputs": [{"seq": 0, "frame": Protocol.empty_input(), "last_seen": 0.0}, {"seq": 0, "frame": Protocol.empty_input(), "last_seen": 0.0}],
		"applied_seq": [0, 0], "store": Store.new(data_directory.path_join("rooms").path_join(room_id))}
	rooms[room_id] = room
	if not code.is_empty(): codes[code] = room_id
	for sid in players:
		sessions[sid].room = room_id
		sessions[sid].queued = false
		queue.erase(sid)
	persist_room(room)
	return room

func match_queue() -> void:
	queue = queue.filter(func(sid): return sessions.has(sid) and connected(sid) and str(sessions[sid].room).is_empty())
	while queue.size() >= 2 and rooms.size() < max_rooms:
		var players = [queue.pop_front(), queue.pop_front()]
		var room = create_room(players, "", true)
		broadcast(room)

func begin_match(room: Dictionary) -> void:
	room.match = Duel.new()
	var loadouts: Array = []
	for sid in room.players: loadouts.append(sessions[sid].loadout.duplicate(true))
	var random_seed = Crypto.new().generate_random_bytes(4).decode_u32(0) % 2147483646 + 1
	room.match.begin(Protocol.nonce(16), loadouts, random_seed)
	room.ready = [false, false]
	room.rematch_ready = [false, false]
	room.suspended = false
	room.suspend_until = 0.0
	for seat in 2:
		room.inputs[seat].frame = Protocol.empty_input()
		room.inputs[seat].last_seen = 0.0
		if connected(room.players[seat]):
			connections[sessions[room.players[seat]].peer].event_ack = 0
			connections[sessions[room.players[seat]].peer].event_match = room.match.id

func receive_input(session: Dictionary, message: Dictionary) -> void:
	if storage_fault: return
	var room = rooms.get(str(session.room))
	if room == null or room.match == null or room.suspended or room.match.phase != "playing": return
	var frame = Protocol.clean_input(message.get("frame"))
	if frame.is_empty(): return
	var seat = room.players.find(str(session.id))
	var previous = room.inputs[seat]
	if int(frame.seq) <= int(previous.seq): return
	for edge in ["dash", "skill", "active_item"]: frame[edge] = bool(frame.get(edge, false)) or bool(previous.frame.get(edge, false))
	previous.seq = int(frame.seq)
	previous.frame = frame
	previous.last_seen = monotonic()

func suspend_room(room: Dictionary, cause: String, initiator: int = -1) -> void:
	if not room.suspended:
		room.suspend_until = wall_time() + grace
		room.suspend_reason = cause
		room.suspend_by = initiator
		room.resume_ready = [false, false]
	room.suspended = true
	for input in room.inputs:
		input.frame = Protocol.empty_input()
		input.last_seen = 0.0

func room_view(room: Dictionary, sid: String) -> Dictionary:
	var seat = room.players.find(sid)
	var peer_id = int(sessions[sid].peer)
	var entry = connections.get(peer_id, {})
	var view = {"phase": "lobby", "actors": [], "offers": [], "picked": [-1, -1], "score": [0, 0], "events": [], "event_serial": 0, "players": []}
	if room.match != null:
		if entry.get("event_match", "") != room.match.id:
			entry.event_match = room.match.id
			entry.event_ack = 0
		view = room.match.view(seat, int(entry.get("event_ack", 0)))
	view.op = "state"
	view.room = room.id
	view.code = room.code
	view.quick = room.quick
	view.seat = seat
	view.ready = room.ready.duplicate()
	view.connected = room.players.map(func(player): return connected(player) and str(sessions[player].room) == room.id)
	view.resume_ready = room.resume_ready.duplicate()
	view.rematch_ready = room.rematch_ready.duplicate()
	view.input_ack = room.applied_seq[seat]
	view.input_floor = room.inputs[seat].seq
	view.names = room.players.map(func(player): return str(sessions[player].name))
	view.stats = {"wins": sessions[sid].wins, "losses": sessions[sid].losses, "draws": sessions[sid].draws}
	if room.match == null:
		view.players = room.players.map(func(player): return sessions[player].loadout.duplicate(true))
	if room.suspended:
		view.resume_phase = view.phase
		view.phase = "suspended"
		view.suspend_reason = room.suspend_reason
		view.grace_left = maxf(0, float(room.suspend_until) - wall_time())
	return view

func broadcast(room: Dictionary) -> void:
	for sid in room.players:
		if connected(sid) and str(sessions[sid].room) == room.id: send(int(sessions[sid].peer), room_view(room, sid), true)

func settle_match(room: Dictionary) -> void:
	room.suspended = false
	room.suspend_until = 0.0
	var match_id = str(room.match.id)
	if settled.has(match_id): return
	# Commit the terminal battle state before committing its idempotent result.
	if not persist_room(room): return
	settled[match_id] = wall_time()
	for seat in room.players.size():
		var session = sessions[room.players[seat]]
		if room.match.winner < 0: session.draws += 1
		elif room.match.winner == seat: session.wins += 1
		else: session.losses += 1
	if not persist_registry():
		settled.erase(match_id)
		for seat in room.players.size():
			var session = sessions[room.players[seat]]
			if room.match.winner < 0: session.draws -= 1
			elif room.match.winner == seat: session.wins -= 1
			else: session.losses -= 1
		return

func leave_room(session: Dictionary) -> void:
	var room = rooms.get(str(session.room))
	if room == null:
		session.room = ""
		return
	var sid = str(session.id)
	var seat = room.players.find(sid)
	if room.match != null:
		room.match.finish(1 - seat, "forfeit")
		settle_match(room)
		broadcast(room)
		room.players.erase(sid)
	else:
		room.players.erase(sid)
		room.ready = [false, false]
	session.room = ""
	if room.players.is_empty(): remove_room(room)
	elif room.match != null:
		# Preserve both seat identities until the remaining player leaves.
		room.players.insert(seat, sid)
		room.departed = room.get("departed", [])
		if not room.departed.has(sid): room.departed.append(sid)
		persist_room(room)
	else: persist_room(room)

func remove_room(room: Dictionary) -> void:
	if not str(room.code).is_empty() and codes.get(str(room.code)) == room.id: codes.erase(str(room.code))
	for sid in room.players:
		if sessions.has(sid) and str(sessions[sid].room) == room.id: sessions[sid].room = ""
	rooms.erase(str(room.id))
	persist_registry()

func maintenance() -> void:
	if storage_fault: return
	var now = wall_time()
	for room in rooms.values().duplicate():
		if room.match != null and room.match.phase == "finished":
			settle_match(room)
			var departed: Array = room.get("departed", [])
			if departed.size() >= room.players.size() or now - float(room.created) > 3600: remove_room(room)
		elif room.suspended and now >= float(room.suspend_until):
			var live: Array = []
			for seat in room.players.size():
				if connected(room.players[seat]): live.append(seat)
			room.suspended = false
			var winner = int(live[0]) if live.size() == 1 else -1
			if live.size() == 2:
				if room.resume_ready[0] != room.resume_ready[1]: winner = 0 if room.resume_ready[0] else 1
				elif room.suspend_reason == "menu" and int(room.get("suspend_by", -1)) in [0, 1]: winner = 1 - int(room.suspend_by)
			room.match.finish(winner, "reconnect_timeout")
			settle_match(room)
			broadcast(room)
		elif room.match == null and (now - float(room.created) > waiting_ttl or not room.players.any(func(sid): return connected(sid)) and now - room.players.map(func(sid): return float(sessions[sid].last_seen)).max() > grace):
			for sid in room.players:
				if connected(sid): send(int(sessions[sid].peer), {"op": "room_closed", "code": "room_expired"})
			remove_room(room)
	match_queue()
	var expired = sessions.keys().filter(func(sid): return not connected(sid) and str(sessions[sid].room).is_empty() and now - float(sessions[sid].last_seen) > 14 * 86400)
	for sid in expired: sessions.erase(sid)
	if not expired.is_empty(): persist_registry()

func persist_registry() -> bool:
	finish_checkpoint(true)
	var result = meta_store.write(registry_snapshot())
	if not result:
		persistence_errors += 1
		mark_storage_fault()
	else: prune_archives()
	return result

func registry_snapshot() -> Dictionary:
	var values: Dictionary = {}
	var revisions: Dictionary = {}
	for sid in sessions:
		var value = sessions[sid].duplicate(true)
		value.erase("peer")
		values[sid] = value
	for room in rooms.values(): revisions[room.id] = int(room.get("checkpoint_revision", 0))
	return {"protocol": Protocol.VERSION, "content": Protocol.fingerprint(), "sessions": values,
		"room_ids": rooms.keys(), "room_revisions": revisions,
		"settled": settled.duplicate(true), "saved_at": wall_time()}

func persist_room(room: Dictionary) -> bool:
	finish_checkpoint(true)
	var result = write_room_generation(room.store, room_snapshot(room))
	if result: room.checkpoint_revision = int(room.store.revision)
	else:
		persistence_errors += 1
		mark_storage_fault()
	return result

func room_snapshot(room: Dictionary) -> Dictionary:
	var data: Dictionary = {}
	for key in room:
		if key not in ["match", "store", "inputs", "checkpoint_revision"]: data[key] = room[key]
	data.input_seqs = room.inputs.map(func(input): return int(input.seq))
	data.match = room.match.checkpoint() if room.match != null else {}
	return data.duplicate(true)

static func write_room_generation(writer, data: Dictionary) -> bool:
	var result = writer.write(data)
	if result:
		var revision = int(writer.revision)
		var source = writer.folder.path_join("checkpoint_%d.json" % (revision % 2))
		var archive = writer.folder.path_join("revision_%016d.json" % revision)
		result = DirAccess.copy_absolute(source, archive) == OK
	return result

func start_checkpoint() -> void:
	finish_checkpoint(false)
	if checkpoint_thread != null: return
	var job = {"registry": registry_snapshot(), "writer": meta_store, "rooms": []}
	for room in rooms.values():
		if storage_fault or int(room.get("checkpoint_revision", 0)) == 0 or room.match != null and not room.suspended and room.match.phase != "finished":
			job.rooms.append({"id": room.id, "writer": room.store, "data": room_snapshot(room)})
	checkpoint_thread = Thread.new()
	if checkpoint_thread.start(write_checkpoint_job.bind(job)) != OK:
		checkpoint_thread = null
		mark_storage_fault()
		persistence_errors += 1

static func write_checkpoint_job(job: Dictionary) -> Dictionary:
	var revisions: Dictionary = {}
	var success = true
	for room in job.rooms:
		var saved = write_room_generation(room.writer, room.data)
		success = saved and success
		if saved:
			revisions[room.id] = int(room.writer.revision)
			job.registry.room_revisions[room.id] = int(room.writer.revision)
	if success: success = job.writer.write(job.registry)
	return {"ok": success, "revisions": revisions}

func finish_checkpoint(wait_for_commit: bool) -> void:
	if checkpoint_thread == null or not wait_for_commit and checkpoint_thread.is_alive(): return
	var result = checkpoint_thread.wait_to_finish()
	checkpoint_thread = null
	for room_id in result.revisions:
		if rooms.has(room_id): rooms[room_id].checkpoint_revision = int(result.revisions[room_id])
	if not result.ok:
		mark_storage_fault()
		persistence_errors += 1
	else:
		storage_fault = false
		prune_archives()

func prune_archives() -> void:
	# Both registry generations retain their exact immutable room generation.
	var retained: Dictionary = {}
	for slot in 2:
		var file = meta_store.folder.path_join("checkpoint_%d.json" % slot)
		if not FileAccess.file_exists(file): continue
		var envelope = Store.parse_envelope(FileAccess.get_file_as_string(file))
		if envelope.get("state") != "ok": continue
		for room_id in envelope.snapshot.get("room_revisions", {}):
			if not retained.has(room_id): retained[room_id] = []
			retained[room_id].append(int(envelope.snapshot.room_revisions[room_id]))
	for room in rooms.values():
		for file in DirAccess.get_files_at(room.store.folder):
			if file.begins_with("revision_") and file.ends_with(".json"):
				var revision = int(file.trim_prefix("revision_").trim_suffix(".json"))
				if not retained.get(room.id, []).has(revision) and revision != int(room.get("checkpoint_revision", 0)):
					DirAccess.remove_absolute(room.store.folder.path_join(file))

func mark_storage_fault() -> void:
	if storage_fault: return
	storage_fault = true
	for room in rooms.values():
		for input in room.inputs:
			input.frame = Protocol.empty_input()
			input.last_seen = 0.0
	for connection_id in connections.keys():
		send(connection_id, {"op": "error", "code": "storage_unavailable"})

func room_generation(room_id: String, revision: int) -> Dictionary:
	var folder = data_directory.path_join("rooms").path_join(room_id)
	var candidates = [folder.path_join("revision_%016d.json" % revision), folder.path_join("checkpoint_0.json"), folder.path_join("checkpoint_1.json")]
	for file in candidates:
		if not FileAccess.file_exists(file): continue
		var envelope = Store.parse_envelope(FileAccess.get_file_as_string(file))
		if envelope.get("state") == "ok" and int(envelope.revision) == revision: return envelope.snapshot
	return {}

func cleanup_retention() -> void:
	var cutoff = wall_time() - 14 * 86400
	var active_matches: Array = []
	for room in rooms.values():
		if room.match != null: active_matches.append(room.match.id)
	var changed = false
	for match_id in settled.keys():
		if float(settled[match_id]) < cutoff and not active_matches.has(match_id): settled.erase(match_id); changed = true
	if changed: persist_registry()
	var protected_rooms = rooms.keys()
	for slot in 2:
		var file = meta_store.folder.path_join("checkpoint_%d.json" % slot)
		if not FileAccess.file_exists(file): continue
		var envelope = Store.parse_envelope(FileAccess.get_file_as_string(file))
		if envelope.get("state") == "ok": protected_rooms.append_array(envelope.snapshot.get("room_ids", []))
	var root = data_directory.path_join("rooms")
	for room_id in DirAccess.get_directories_at(root):
		if protected_rooms.has(room_id) or room_id.length() != 32: continue
		var valid_id = true
		for digit in room_id:
			if not digit in "0123456789abcdef": valid_id = false; break
		if not valid_id: continue
		var folder = root.path_join(room_id)
		if not DirAccess.get_directories_at(folder).is_empty(): continue
		var files = DirAccess.get_files_at(folder)
		var expired = not files.is_empty()
		for file in files:
			if not (file.begins_with("checkpoint_") or file.begins_with("revision_")) or FileAccess.get_modified_time(folder.path_join(file)) >= cutoff: expired = false; break
		if not expired: continue
		for file in files: DirAccess.remove_absolute(folder.path_join(file))
		if DirAccess.get_files_at(folder).is_empty(): DirAccess.remove_absolute(folder)

func consistent_registry() -> Dictionary:
	var latest = meta_store.read()
	if latest.is_empty(): return latest
	var candidates: Array = []
	for slot in 2:
		var file = meta_store.folder.path_join("checkpoint_%d.json" % slot)
		if not FileAccess.file_exists(file): continue
		var envelope = Store.parse_envelope(FileAccess.get_file_as_string(file))
		if envelope.get("state") == "ok": candidates.append(envelope)
	candidates.sort_custom(func(a, b): return int(a.revision) > int(b.revision))
	for candidate in candidates:
		var value = candidate.snapshot
		var valid = true
		for room_id in value.get("room_ids", []):
			var revision = int(value.get("room_revisions", {}).get(str(room_id), 0))
			if revision < 1 or room_generation(str(room_id), revision).is_empty(): valid = false; break
		if valid:
			if int(candidate.revision) != int(meta_store.revision): print("ONLINE_RECOVERED_FALLBACK registry_revision=%d" % int(candidate.revision))
			return value
	recovery_failed = true
	push_error("No consistent server checkpoint generation; originals have been preserved.")
	return {}

func recover_registry(previous: Dictionary) -> void:
	if previous.get("protocol") != Protocol.VERSION or previous.get("content") != Protocol.fingerprint():
		push_error("Server checkpoints use a different protocol/content; use a separate data directory.")
		return
	sessions = previous.get("sessions", {}).duplicate(true)
	settled = previous.get("settled", {}).duplicate(true)
	for session in sessions.values():
		session.peer = -1
		session.queued = false
	for room_id in previous.get("room_ids", []):
		var writer = Store.new(data_directory.path_join("rooms").path_join(str(room_id)))
		var committed_revision = int(previous.get("room_revisions", {}).get(str(room_id), writer.revision))
		var value = room_generation(str(room_id), committed_revision)
		if value.is_empty():
			persistence_errors += 1
			push_warning("Room checkpoint unavailable; closing room " + str(room_id))
			continue
		if not value.get("players", []).all(func(sid): return sessions.has(sid)): continue
		var data = value.duplicate(true)
		data.store = writer
		data.checkpoint_revision = committed_revision
		data.match = null
		data.inputs = []
		for seat in 2: data.inputs.append({"seq": int(value.input_seqs[seat]), "frame": Protocol.empty_input(), "last_seen": 0.0})
		if not value.get("match", {}).is_empty():
			var duel = Duel.new()
			if not duel.recover(value.match): continue
			data.match = duel
			if duel.phase != "finished":
				data.suspended = false
				suspend_room(data, "server_restarted")
		data.ready = [false, false]
		rooms[str(room_id)] = data
		if not str(data.code).is_empty(): codes[str(data.code)] = room_id
	for session in sessions.values():
		if not rooms.has(str(session.room)): session.room = ""

func health() -> Dictionary:
	var samples = step_ms.duplicate()
	samples.sort()
	var network = process_ms.duplicate()
	network.sort()
	var buffered = 0
	for entry in connections.values(): buffered += entry.peer.get_current_outbound_buffered_amount()
	return {"service": "IncenseDebt Online", "protocol": Protocol.VERSION, "uptime": uptime,
		"connections": connections.size(), "rooms": rooms.size(), "queued": queue.size(), "tick": ticks,
		"step_p95_ms": samples[int((samples.size() - 1) * .95)] if not samples.is_empty() else 0.0,
		"step_p99_ms": samples[int((samples.size() - 1) * .99)] if not samples.is_empty() else 0.0,
		"step_max_ms": samples.back() if not samples.is_empty() else 0.0,
		"process_p95_ms": network[int((network.size() - 1) * .95)] if not network.is_empty() else 0.0,
		"process_p99_ms": network[int((network.size() - 1) * .99)] if not network.is_empty() else 0.0,
		"process_max_ms": network.back() if not network.is_empty() else 0.0, "buffered_bytes": buffered,
		"persistence_errors": persistence_errors, "storage_fault": storage_fault, "checkpoint_pending": checkpoint_thread != null, "bytes_sent": bytes_sent, "stopping": stopping}

func process_health() -> void:
	while health_listener.is_connection_available():
		var stream = health_listener.take_connection()
		if health_connections.size() >= 8: stream.disconnect_from_host()
		else: health_connections.append({"stream": stream, "at": monotonic(), "request": ""})
	for entry in health_connections.duplicate():
		var stream = entry.stream
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED or monotonic() - float(entry.at) > 2:
			stream.disconnect_from_host()
			health_connections.erase(entry)
			continue
		if stream.get_available_bytes() > 0:
			entry.request += stream.get_utf8_string(mini(stream.get_available_bytes(), 4096))
			if entry.request.length() > 4096:
				stream.disconnect_from_host()
				health_connections.erase(entry)
				continue
			if not entry.request.contains("\r\n\r\n"): continue
			var request = str(entry.request)
			var body = JSON.stringify(health()).to_utf8_buffer()
			var status = "200 OK" if request.begins_with("GET /health ") or request.begins_with("HEAD /health ") else "404 Not Found"
			stream.put_data(("HTTP/1.1 " + status + "\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + str(body.size()) + "\r\n\r\n").to_utf8_buffer())
			if not request.begins_with("HEAD "): stream.put_data(body)
			stream.disconnect_from_host()
			health_connections.erase(entry)

func shutdown() -> void:
	if stopping: return
	finish_checkpoint(true)
	stopping = true
	listener.stop()
	health_listener.stop()
	var saved = true
	for room in rooms.values(): saved = persist_room(room) and saved
	saved = persist_registry() and saved
	for connection_id in connections.keys(): close_peer(connection_id, "server_shutdown")
	rooms.clear()
	sessions.clear()
	print("ONLINE_STOPPED checkpoints_flushed=" + str(saved and not storage_fault))
