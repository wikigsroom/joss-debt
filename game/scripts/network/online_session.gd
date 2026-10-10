extends Node
signal changed
signal state_received(state: Dictionary)
signal events_received(events: Array)
signal problem(code: String)
const Protocol = preload("res://scripts/network/protocol.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Actor = preload("res://scripts/network/duel_actor.gd")
var peer = WebSocketPeer.new()
var state = "offline"
var endpoint = "ws://127.0.0.1:18777"
var nickname = "还愿人"
var loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
var identity: Dictionary = {}
var identities: Dictionary = {}
var room: Dictionary = {}
var stats: Dictionary = {"wins": 0, "losses": 0, "draws": 0}
var pending: Dictionary = {}
var request_serial = 0
var input_serial = 0
var latest_input = Protocol.empty_input()
var pending_edges = {"dash": false, "skill": false, "active_item": false}
var wants_connection = false
var hello_sent = false
var retry_count = 0
var retry_at = 0.0
var last_received = 0.0
var attempt_started = 0.0
var heartbeat_elapsed = 0.0
var input_elapsed = 0.0
var ping_at = 0.0
var latency_ms = 0
var last_error = ""
var last_event = 0
var event_match = ""
var last_state_received = 0.0
var presentation: Array = []
var input_history: Array = []
var snapshot_serial = 0
var preferences
var dirty_elapsed = 0.0
var credential_folder = "user://online-client"

func _init(folder: String = "user://online-client") -> void:
	credential_folder = folder
	preferences = Store.new(folder)
	var data = preferences.read()
	if data.get("version", 1) == 1:
		endpoint = str(data.get("endpoint", endpoint))
		nickname = Protocol.clean_name(data.get("nickname", nickname))
		if data.get("loadout") is Dictionary: loadout = data.loadout.duplicate(true)
		identities = data.get("identities", {}).duplicate(true)
	load_identity()

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func load_identity() -> void:
	identity = identities.get(endpoint, {}).duplicate(true)
	pending = identity.get("pending", {}).duplicate(true)
	request_serial = int(identity.get("request_serial", 0))
	input_serial = int(identity.get("input_serial", 0))
	stats = identity.get("stats", {"wins": 0, "losses": 0, "draws": 0}).duplicate(true)

func save_preferences() -> bool:
	identity.pending = pending.duplicate(true)
	identity.request_serial = request_serial
	identity.input_serial = input_serial
	identity.stats = stats.duplicate(true)
	identities[endpoint] = identity.duplicate(true)
	while identities.size() > 8:
		var oldest = identities.keys()[0]
		if oldest == endpoint: oldest = identities.keys()[1]
		identities.erase(oldest)
	return preferences.write({"version": 1, "endpoint": endpoint, "nickname": nickname, "loadout": loadout, "identities": identities})

func valid_endpoint(value: String) -> bool:
	if value.length() > 240 or value.contains(" ") or value.contains("@") or value.contains("#") or value.contains("?"): return false
	return (value.begins_with("ws://") and value.length() > 5) or (value.begins_with("wss://") and value.length() > 6)

func connect_service(url: String = "", name_value: String = "") -> bool:
	var address = endpoint if url.is_empty() else url.strip_edges().trim_suffix("/")
	if not valid_endpoint(address):
		raise_problem("invalid_endpoint")
		return false
	if address != endpoint:
		disconnect_service()
		endpoint = address
		load_identity()
	if not name_value.is_empty(): nickname = Protocol.clean_name(name_value)
	wants_connection = true
	retry_count = 0
	last_error = ""
	room.clear()
	presentation.clear()
	save_preferences()
	open_socket()
	return true

func open_socket() -> void:
	peer.close(-1)
	peer = WebSocketPeer.new()
	Protocol.configure_socket(peer)
	hello_sent = false
	retry_at = -1.0
	attempt_started = now()
	last_received = now()
	state = "reconnecting" if not str(identity.get("resume", "")).is_empty() else "connecting"
	changed.emit()
	if peer.connect_to_url(endpoint) != OK: schedule_retry()

func disconnect_service() -> void:
	wants_connection = false
	clear_input()
	peer.close(-1)
	state = "offline"
	hello_sent = false
	room.clear()
	presentation.clear()
	changed.emit()

func forget_identity() -> void:
	disconnect_service()
	identities.erase(endpoint)
	identity.clear()
	pending.clear()
	request_serial = 0
	input_serial = 0
	stats = {"wins": 0, "losses": 0, "draws": 0}
	save_preferences()

func retry_now() -> void:
	if state in ["expired", "incompatible"]: return
	wants_connection = true
	open_socket()

func schedule_retry() -> void:
	clear_input()
	if not wants_connection: return
	retry_count += 1
	var wait = minf(8, .5 * pow(2, mini(retry_count - 1, 4)))
	var jitter = Crypto.new().generate_random_bytes(1)[0] / 255.0 * .2
	retry_at = now() + wait + jitter
	state = "reconnecting"
	changed.emit()

func _process(delta: float) -> void:
	if not wants_connection: return
	peer.poll()
	var ready = peer.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		if not hello_sent:
			peer.set_no_delay(true)
			hello_sent = true
			send({"op": "hello", "protocol": Protocol.VERSION, "content": Protocol.fingerprint(),
				"name": nickname, "resume": str(identity.get("resume", ""))})
		while peer.get_available_packet_count() > 0:
			var message = Protocol.unpack(peer.get_packet())
			if message.is_empty():
				raise_problem("invalid_server_packet")
				peer.close(-1)
				schedule_retry()
				return
			last_received = now()
			receive(message)
		heartbeat_elapsed += delta
		if heartbeat_elapsed >= Protocol.HEARTBEAT_SECONDS:
			heartbeat_elapsed = 0
			ping_at = now()
			send({"op": "ping", "nonce": int(Time.get_ticks_msec())})
		if now() - last_received > Protocol.SILENCE_SECONDS:
			peer.close(-1)
			schedule_retry()
			return
		input_elapsed += delta
		if input_elapsed >= 1.0 / Protocol.INPUT_RATE and can_play():
			var seconds = minf(.1, input_elapsed)
			input_elapsed = 0
			input_serial += 1
			var frame = latest_input.duplicate(true)
			frame.seq = input_serial
			for edge in pending_edges:
				frame[edge] = pending_edges[edge]
			if send({"op": "input", "frame": frame}):
				input_history.append({"seq": input_serial, "frame": frame.duplicate(true), "seconds": seconds})
				while input_history.size() > 32: input_history.pop_front()
				for edge in pending_edges: pending_edges[edge] = false
	elif ready == WebSocketPeer.STATE_CONNECTING:
		if now() - attempt_started > 6:
			peer.close(-1)
			schedule_retry()
	elif ready == WebSocketPeer.STATE_CLOSED:
		if peer.get_close_code() == 4001:
			wants_connection = false
			state = "expired"
			raise_problem("session_replaced")
			changed.emit()
			return
		if retry_at < 0 and state not in ["expired", "incompatible"]: schedule_retry()
		if wants_connection and state == "reconnecting" and now() >= retry_at: open_socket()

func send(message: Dictionary) -> bool:
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	if peer.get_current_outbound_buffered_amount() > 16384: return false
	return peer.put_packet(Protocol.packet(message)) == OK

func request(op: String, body: Dictionary = {}) -> int:
	if state not in ["online", "queued", "room"]: return -1
	request_serial += 1
	var message = body.duplicate(true)
	message.op = op
	message.request = request_serial
	pending[str(request_serial)] = message
	if not save_preferences():
		pending.erase(str(request_serial))
		raise_problem("local_storage_unavailable")
		return -1
	send(message)
	return request_serial

func submit_input(frame: Dictionary) -> void:
	if not can_play(): clear_input(); return
	latest_input = frame.duplicate(true)
	for edge in pending_edges: pending_edges[edge] = bool(pending_edges[edge]) or bool(frame.get(edge, false))

func clear_input() -> void:
	latest_input = Protocol.empty_input()
	for edge in pending_edges: pending_edges[edge] = false
	input_elapsed = 0
	input_history.clear()

func can_play() -> bool:
	return state == "room" and room.get("phase", "") == "playing" and now() - last_state_received < .4

func receive(message: Dictionary) -> void:
	match str(message.get("op", "")):
		"welcome":
			identity.session = str(message.session)
			identity.resume = str(message.resume)
			request_serial = maxi(request_serial, int(message.request_floor))
			input_serial = maxi(input_serial, int(message.input_floor))
			stats = message.stats.duplicate(true)
			retry_count = 0
			state = "online"
			save_preferences()
			for request_id in pending.keys(): send(pending[request_id])
			changed.emit()
		"pong":
			if Protocol.Store.integer(message.get("nonce")): latency_ms = maxi(0, int(Time.get_ticks_msec()) - int(message.nonce))
		"ack":
			var key = str(int(message.request))
			var command = pending.get(key, {})
			pending.erase(key)
			if not bool(message.get("ok", false)):
				raise_problem(str(message.get("code", "request_failed")))
			elif command.get("op") == "queue" and bool(message.get("queued", false)) and room.is_empty(): state = "queued"
			elif command.get("op") in ["leave", "cancel_queue"]:
				room.clear()
				presentation.clear()
				state = "online"
				clear_input()
			save_preferences()
			changed.emit()
		"state":
			accept_state(message)
		"room_closed":
			room.clear()
			presentation.clear()
			state = "online"
			clear_input()
			raise_problem(str(message.get("code", "room_closed")))
			changed.emit()
		"error":
			var code = str(message.get("code", "server_error"))
			raise_problem(code)
			if code == "storage_unavailable":
				state = "storage"
				clear_input()
				changed.emit()
			if code in ["session_expired", "version_mismatch"]:
				wants_connection = false
				state = "expired" if code == "session_expired" else "incompatible"
				clear_input()
				peer.close(-1)
				changed.emit()

func accept_state(message: Dictionary) -> void:
	if not message.get("players") is Array or message.players.size() not in [1, 2] or not message.get("actors") is Array or message.actors.size() not in [0, 2]: return
	var match_id = str(message.get("id", ""))
	var was_room = state == "room"
	if match_id != event_match:
		event_match = match_id
		# Initial recovery shows current projectiles, without replaying old FX/audio.
		last_event = int(message.get("event_serial", 0)) if message.get("phase") in ["playing", "round_result", "suspended", "finished"] else 0
		presentation.clear()
	var before = str(room.get("phase", "")) + str(room.get("ready", [])) + str(room.get("picked", [])) + str(room.get("connected", [])) + str(room.get("rematch_ready", [])) + str(room.get("resume_ready", [])) + str(room.get("players", []))
	room = message.duplicate(true)
	snapshot_serial += 1
	input_history = input_history.filter(func(input): return int(input.seq) > int(message.get("input_ack", 0)))
	last_state_received = now()
	input_serial = maxi(input_serial, int(message.get("input_floor", 0)))
	state = "room"
	stats = message.get("stats", stats).duplicate(true)
	if presentation.is_empty() and message.actors.size() == 2:
		for seat in 2:
			var actor = Actor.new()
			actor.initialize_duel(message.players[seat], message.arena, 1, seat)
			presentation.append(actor)
	for seat in presentation.size():
		var actor = presentation[seat]
		var data = message.actors[seat]
		for key in ["run", "player", "bullets", "zones", "enemies", "chains", "delayed", "room_flags", "stats"]:
			actor.set(key, data[key].duplicate(true))
		actor.time = float(data.time)
		actor.online_biome = message.arena.duplicate(true)
		if actor.geometry.boundary_key != str(message.arena.id) + "_a": actor.geometry.configure_biome(message.arena.id, 0)
		actor.mode = "combat"
	var incoming: Array = []
	for event in message.get("events", []):
		if int(event.get("event_id", 0)) > last_event:
			incoming.append(event)
			last_event = maxi(last_event, int(event.event_id))
	if not incoming.is_empty(): events_received.emit(incoming)
	if last_event > 0: send({"op": "events_ack", "match": match_id, "event": last_event})
	if room.get("phase", "") != "playing": clear_input()
	state_received.emit(room)
	var after = str(room.get("phase", "")) + str(room.get("ready", [])) + str(room.get("picked", [])) + str(room.get("connected", [])) + str(room.get("rematch_ready", [])) + str(room.get("resume_ready", [])) + str(room.get("players", []))
	if before != after or not was_room: changed.emit()

func raise_problem(code: String) -> void:
	last_error = code
	problem.emit(code)

func simulate_link_loss() -> void:
	# Also used by real transport QA: no fake room state or invented resume.
	peer.close(-1)
	schedule_retry()
