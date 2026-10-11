extends Node
signal changed
signal state_received(state: Dictionary)
signal events_received(events: Array)
signal problem(code: String)
signal command_completed(operation: String, succeeded: bool, code: String)
const Protocol = preload("res://scripts/network/protocol.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Actor = preload("res://scripts/network/duel_actor.gd")
const CooperativeActor = preload("res://scripts/network/cooperative_presentation.gd")
var peer = WebSocketPeer.new()
var state = "offline"
var endpoint = "ws://127.0.0.1:18777"
var nickname = "还愿人"
var loadout = {"character": "c_paper", "weapon": "w01", "skill": "s01"}
var game_mode = "coop"
var identity: Dictionary = {}
var identities: Dictionary = {}
var room: Dictionary = {}
var stats: Dictionary = {"wins": 0, "losses": 0, "draws": 0}
var pending: Dictionary = {}
var request_serial = 0
var input_serial = 0
var latest_input = Protocol.empty_input()
var pending_edges = {"dash": false, "skill": false, "active_item": false, "interact": false}
var wants_connection = false
var hello_sent = false
var authenticated = false
var instance_id = Protocol.nonce(16)
var link_id = ""
var state_sequence = 0
var authorized_room = ""
var inflight_request = ""
var command_started = 0.0
var command_sent_at = -1.0
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
		game_mode = str(data.get("game_mode", "coop")) if data.get("game_mode", "coop") in ["coop", "duel"] else "coop"
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
	reset_command_delivery()

func save_preferences() -> bool:
	var saved = preferences.read().get("identities", {})
	var current = saved.get(endpoint, {})
	if not str(identity.get("session", "")).is_empty() and current.get("session") == identity.get("session") and int(current.get("owner_generation", 0)) > int(identity.get("owner_generation", 0)):
		# An older process must not overwrite the new owner's durable credential.
		wants_connection = false
		clear_input()
		peer.close(-1)
		state = "expired"
		raise_problem("session_replaced")
		changed.emit()
		return false
	for address in saved:
		if address != endpoint: identities[address] = saved[address].duplicate(true)
	identity.pending = pending.duplicate(true)
	identity.request_serial = request_serial
	identity.input_serial = input_serial
	identity.stats = stats.duplicate(true)
	identities[endpoint] = identity.duplicate(true)
	while identities.size() > 8:
		var oldest = identities.keys()[0]
		if oldest == endpoint: oldest = identities.keys()[1]
		identities.erase(oldest)
	return preferences.write({"version": 1, "endpoint": endpoint, "nickname": nickname, "loadout": loadout, "game_mode": game_mode, "identities": identities})

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
	if not save_preferences():
		stop_for_local_storage()
		return false
	open_socket()
	return true

func stop_for_local_storage() -> void:
	if state == "expired" and last_error == "session_replaced": return
	wants_connection = false
	clear_input()
	peer.close(-1)
	state = "local_storage"
	raise_problem("local_storage_unavailable")
	changed.emit()

func open_socket() -> void:
	peer.close(-1)
	peer = WebSocketPeer.new()
	Protocol.configure_socket(peer)
	hello_sent = false
	authenticated = false
	link_id = ""
	state_sequence = 0
	authorized_room = ""
	reset_command_delivery()
	clear_input()
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
	authenticated = false
	reset_command_delivery()
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
			hello_sent = send({"op": "hello", "protocol": Protocol.VERSION, "transport": Protocol.TRANSPORT_REVISION,
				"content": Protocol.fingerprint(), "instance": instance_id, "owner_generation": int(identity.get("owner_generation", 0)),
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
			if not wants_connection or peer.get_ready_state() != WebSocketPeer.STATE_OPEN: return
		if not authenticated and now() - attempt_started > 6:
			peer.close(-1)
			schedule_retry()
			return
		if state == "room" and now() - last_state_received > Protocol.STATE_TIMEOUT:
			raise_problem("state_timeout")
			peer.close(-1)
			schedule_retry()
			return
		if not flush_pending(): return
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
			if send(input_message(frame)):
				input_history.append({"seq": input_serial, "frame": frame.duplicate(true), "seconds": seconds})
				while input_history.size() > 32: input_history.pop_front()
				for edge in pending_edges: pending_edges[edge] = false
	elif ready == WebSocketPeer.STATE_CONNECTING:
		if now() - attempt_started > 6:
			peer.close(-1)
			schedule_retry()
	elif ready == WebSocketPeer.STATE_CLOSING:
		if now() - last_received > Protocol.SILENCE_SECONDS:
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
	if pending.size() >= Protocol.MAX_PENDING_REQUESTS:
		raise_problem("too_many_pending_requests")
		return -1
	request_serial += 1
	var message = body.duplicate(true)
	message.op = op
	message.request = request_serial
	message.room = str(room.get("room", ""))
	message.match = str(room.get("id", ""))
	if op in ["pause", "resume"]: message.epoch = int(room.get("input_epoch", 0))
	pending[str(request_serial)] = message
	if not save_preferences():
		pending.erase(str(request_serial))
		if last_error != "session_replaced": raise_problem("local_storage_unavailable")
		return -1
	flush_pending()
	return request_serial

func reset_command_delivery() -> void:
	inflight_request = ""
	command_started = 0.0
	command_sent_at = -1.0

func flush_pending() -> bool:
	if not authenticated or state not in ["online", "queued", "room"] or pending.is_empty(): return true
	if inflight_request.is_empty() or not pending.has(inflight_request):
		var ids = pending.keys()
		ids.sort_custom(func(a, b): return int(a) < int(b))
		inflight_request = str(ids[0])
		command_started = now()
		command_sent_at = -1.0
	if now() - command_started > Protocol.SILENCE_SECONDS:
		raise_problem("command_timeout")
		peer.close(-1)
		schedule_retry()
		return false
	if command_sent_at < 0 or now() - command_sent_at >= Protocol.REQUEST_RETRY_SECONDS:
		# One durable command at a time: later requests cannot overtake a failed send.
		command_sent_at = now()
		send(pending[inflight_request])
	return true

func input_message(frame: Dictionary) -> Dictionary:
	return {"op": "input", "frame": frame, "link": link_id, "room": str(room.get("room", "")),
		"match": str(room.get("id", "")), "epoch": int(room.get("input_epoch", 0)),
		"scene": int(room.get("input_scene", 0)), "lease": int(room.get("lease", 0))}

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
			if message.get("transport") != Protocol.TRANSPORT_REVISION or not message.get("link") is String:
				receive({"op": "error", "code": "version_mismatch"})
				return
			authenticated = true
			link_id = str(message.link)
			state_sequence = 0
			authorized_room = str(message.get("room", ""))
			identity.session = str(message.session)
			identity.resume = str(message.resume)
			identity.owner_generation = int(message.get("owner_generation", 0))
			request_serial = maxi(request_serial, int(message.request_floor))
			input_serial = maxi(input_serial, int(message.input_floor))
			stats = message.stats.duplicate(true)
			retry_count = 0
			state = "synchronizing" if not str(message.get("room", "")).is_empty() else ("queued" if message.get("queued", false) else "online")
			if state != "synchronizing": room.clear(); presentation.clear()
			if not save_preferences(): stop_for_local_storage(); return
			flush_pending()
			changed.emit()
		"pong":
			if Protocol.Store.integer(message.get("nonce")): latency_ms = maxi(0, int(Time.get_ticks_msec()) - int(message.nonce))
		"ack":
			var key = str(int(message.request))
			if not pending.has(key): return
			var command = pending.get(key, {})
			pending.erase(key)
			if key == inflight_request: reset_command_delivery()
			if not bool(message.get("ok", false)):
				raise_problem(str(message.get("code", "request_failed")))
			var service = message.get("service", {})
			authorized_room = str(service.get("room", authorized_room))
			if service is Dictionary and str(service.get("room", "")).is_empty():
				room.clear()
				presentation.clear()
				state = "queued" if bool(service.get("queued", false)) else "online"
				clear_input()
			if not save_preferences(): stop_for_local_storage(); return
			command_completed.emit(str(command.get("op", "")), bool(message.get("ok", false)), str(message.get("code", "")))
			changed.emit()
		"service":
			if message.get("link") != link_id: return
			authorized_room = str(message.get("room", ""))
			if not authorized_room.is_empty() and str(room.get("room", "")) != authorized_room:
				clear_input()
				state = "synchronizing"
		"state":
			accept_state(message)
		"room_closed":
			authorized_room = ""
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
			if code in ["session_expired", "session_replaced", "version_mismatch"]:
				wants_connection = false
				state = "incompatible" if code == "version_mismatch" else "expired"
				clear_input()
				peer.close(-1)
				changed.emit()

func accept_state(message: Dictionary) -> void:
	if message.get("link") != link_id or not Store.integer(message.get("state_seq")) or int(message.state_seq) < 1: return
	if str(message.get("room", "")) != authorized_room or authorized_room.is_empty(): return
	if int(message.state_seq) <= state_sequence:
		acknowledge_state(message)
		return
	if not message.get("players") is Array or message.players.size() not in [1, 2] or not message.get("actors") is Array or message.actors.size() not in [0, 2]: return
	state_sequence = int(message.state_seq)
	var match_id = str(message.get("id", ""))
	var was_room = state == "room"
	if match_id != event_match:
		event_match = match_id
		# Initial recovery shows current projectiles, without replaying old FX/audio.
		last_event = int(message.get("event_serial", 0)) if message.get("phase") in ["playing", "round_result", "suspended", "finished"] else 0
		presentation.clear()
	var before = ui_state_key(room)
	if message.get("input_epoch") != room.get("input_epoch") or message.get("input_scene") != room.get("input_scene"): clear_input()
	room = message.duplicate(true)
	snapshot_serial += 1
	input_history = input_history.filter(func(input): return int(input.seq) > int(message.get("input_ack", 0)))
	last_state_received = now()
	input_serial = maxi(input_serial, int(message.get("input_floor", 0)))
	state = "room"
	stats = message.get("stats", stats).duplicate(true)
	if presentation.is_empty() and message.actors.size() == 2:
		for seat in 2:
			var actor = CooperativeActor.new() if message.get("game_mode") == "coop" else Actor.new()
			if message.get("game_mode") == "coop": actor.start(str(message.players[seat].character), 1, 11, {"weapon": message.players[seat].weapon})
			else: actor.initialize_duel(message.players[seat], message.arena, 1, seat)
			presentation.append(actor)
	for seat in presentation.size():
		var actor = presentation[seat]
		var data = message.actors[seat]
		for key in ["run", "player", "bullets", "zones", "enemies", "chains", "delayed", "room_flags", "stats"]:
			actor.set(key, data[key].duplicate(true))
		actor.time = float(data.time)
		if message.get("game_mode") == "coop":
			var scene = message.scene
			if actor.online_scene != int(scene.serial):
				actor.build_geometry(str(scene.template), scene.objects)
				actor.online_scene = int(scene.serial)
			else:
				# Destroyed urns and changing obstacles share the server's collision.
				actor.geometry.restore_objects(scene.objects)
			for key in ["enemies", "bullets", "zones", "delayed", "pickups"]: actor.set(key, scene[key].duplicate(true))
			actor.room_flags = scene.flags.duplicate(true)
			actor.room_flags.merge(data.room_flags, true)
			actor.online_stairs = bool(scene.stairs)
			actor.mode = str(scene.mode)
		else:
			actor.online_biome = message.arena.duplicate(true)
			if actor.geometry.boundary_key != str(message.arena.id) + "_a": actor.geometry.configure_biome(message.arena.id, 0)
			actor.mode = "combat"
	var incoming: Array = []
	for event in message.get("events", []):
		if int(event.get("event_id", 0)) > last_event:
			incoming.append(event)
			last_event = maxi(last_event, int(event.event_id))
	if not incoming.is_empty(): events_received.emit(incoming)
	acknowledge_state(message)
	if room.get("phase", "") != "playing": clear_input()
	state_received.emit(room)
	var after = ui_state_key(room)
	if before != after or not was_room: changed.emit()

func acknowledge_state(message: Dictionary) -> void:
	send({"op": "state_ack", "link": link_id, "state_seq": int(message.state_seq),
		"lease": int(message.get("lease", 0)), "match": str(message.get("id", "")), "event": last_event})

func ui_state_key(value: Dictionary) -> String:
	var offers = str(value.get("offers", [])) if value.get("game_mode") == "coop" and value.get("phase") == "draft" else ""
	return str(value.get("phase", "")) + str(value.get("ready", [])) + str(value.get("picked", [])) + str(value.get("connected", [])) + str(value.get("rematch_ready", [])) + str(value.get("resume_ready", [])) + str(value.get("players", [])) + str(value.get("choice_token", "")) + str(value.get("scene", {}).get("serial", 0)) + offers

func raise_problem(code: String) -> void:
	last_error = code
	problem.emit(code)

func simulate_link_loss() -> void:
	# Also used by real transport QA: no fake room state or invented resume.
	peer.close(-1)
	schedule_retry()
