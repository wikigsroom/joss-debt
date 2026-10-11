extends Node
const Protocol = preload("res://scripts/network/protocol.gd")
const Duel = preload("res://scripts/network/duel_match.gd")
const Cooperation = preload("res://scripts/network/cooperative_match.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Content = preload("res://scripts/core/content_db.gd")
const Battle = preload("res://scripts/network/enet_battle.gd")
const StateStream = preload("res://scripts/network/state_stream.gd")
const InputFrames = preload("res://scripts/network/input_frames.gd")
var battle = Battle.new()
var battle_port = 0
var battle_connections: Dictionary = {}
var battle_tickets: Dictionary = {}
var battle_ticket_issued = 0
var battle_ticket_revocations = 0
var battle_ticket_reissues = 0
var battle_bind_failures = 0
var battle_ticket_rejections: Dictionary = {}
var close_reasons: Dictionary = {}
var battle_waiting: Dictionary = {}
var battle_retired: Dictionary = {}
var replication_ms: Array = []
var stage_samples: Dictionary = {}
var combat_process_max_ms = 0.0
var combat_stalls_over_100ms = 0
var udp_rejected = 0
var db = Content.new()
var listener = TCPServer.new()
var health_listener = TCPServer.new()
var connections: Dictionary = {}
var closing_peers: Array = []
var health_connections: Array = []
var sessions: Dictionary = {}
var rooms: Dictionary = {}
var codes: Dictionary = {}
var queue: Array = []
var settled: Dictionary = {}
var durable_settled: Dictionary = {}
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
var snapshot_retries = 0
var snapshots_coalesced = 0
var snapshot_rooms: Dictionary = {}
var outdated_input_frames = 0
var lifetime_step: Dictionary = {"bins": {}, "count": 0, "max_ms": 0.0}
var lifetime_process: Dictionary = {"bins": {}, "count": 0, "max_ms": 0.0}
var mutation_queue: Array = []
var in_mutation = false
var mutation_copies = 0
var mutation_outbox: Array = []
var commit_outbox: Array = []
var persistence_dirty = false
var match_builds: Dictionary = {}

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
	durable_settled = settled.duplicate(true)
	battle_port = int(options.get("battle_port", port + 2))
	# Reserve bounded transport slots for retiring links; logical admissions remain
	# capped by max_connections and cannot be occupied by disconnected authority.
	var battle_error = battle.start_server(str(options.get("battle_bind", bind_address)), battle_port, max_connections * 2, options)
	if battle_error != OK: return battle_error
	var error = listener.listen(port, bind_address)
	if error != OK: battle.close(); return error
	error = health_listener.listen(port + 1, bind_address)
	if error != OK:
		listener.stop()
		battle.close()
		return error
	set_process(true)
	set_physics_process(true)
	print("ONLINE_READY port=%d health=%d recovered_rooms=%d protocol=%d" % [port, port + 1, rooms.size(), Protocol.VERSION])
	return OK

func monotonic() -> float:
	return Time.get_ticks_msec() / 1000.0

func revoke_battle_tickets(connection_id: int) -> int:
	var revoked = 0
	for ticket_hash in battle_tickets.keys():
		var ticket: Dictionary = battle_tickets[ticket_hash]
		if int(ticket.get("connection", -1)) != connection_id: continue
		battle_tickets.erase(ticket_hash)
		revoked += 1
	if revoked > 0: battle_ticket_revocations += revoked
	return revoked

func issue_battle_ticket(connection_id: int) -> String:
	if not connections.has(connection_id): return ""
	var revoked = revoke_battle_tickets(connection_id)
	if revoked > 0: battle_ticket_reissues += 1
	var ticket = Protocol.nonce()
	battle_tickets[ticket.sha256_text()] = {"connection": connection_id, "issued": monotonic(), "until": monotonic() + Protocol.BATTLE_BIND_TIMEOUT_SECONDS}
	battle_ticket_issued += 1
	return ticket

func reject_battle_bind(peer: ENetPacketPeer, reason: String) -> void:
	udp_rejected += 1
	battle_bind_failures += 1
	battle_ticket_rejections[reason] = int(battle_ticket_rejections.get(reason, 0)) + 1
	retire_battle_peer(peer)

func poll_battle() -> void:
	for event in battle.poll():
		var peer: ENetPacketPeer = event.peer
		if peer == null: continue
		var peer_id = peer.get_instance_id()
		match event.type:
			ENetConnection.EVENT_CONNECT:
				battle.edge.remember_peer(peer)
				peer.set_timeout(16, 4000, 8000)
				battle_waiting[peer_id] = {"peer": peer, "until": monotonic() + Protocol.BATTLE_BIND_TIMEOUT_SECONDS}
			ENetConnection.EVENT_DISCONNECT:
				battle.edge.retire_peer(peer)
				battle_waiting.erase(peer_id)
				battle_retired.erase(peer_id)
				var connection_id = int(battle_connections.get(peer_id, -1))
				battle_connections.erase(peer_id)
				if connections.has(connection_id):
					# UDP/ENet is a replaceable gameplay leg. Preserve the authenticated
					# WSS identity and room while the client obtains a fresh ticket;
					# ending the whole connection here turned ordinary packet loss into
					# an unrecoverable session replacement race.
					var entry = connections[connection_id]
					entry.battle_peer = null
					entry.stream_codec = null
					entry.watched_room = ""
					entry.state_pending.clear()
					entry.state_serial = 0
					entry.state_ack = 0
					var session = sessions.get(str(entry.session), {})
					var room = rooms.get(str(session.get("room", "")))
					if room != null and room.match != null and room.match.phase != "finished":
						suspend_room(room, "disconnect")
						persist_room(room)
					if entry.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
						grant_battle(connection_id)
			ENetConnection.EVENT_RECEIVE:
				if battle_retired.has(peer_id): continue
				var message = InputFrames.decode(event.bytes) if not event.bytes.is_empty() and event.bytes[0] == InputFrames.MAGIC else Protocol.unpack(event.bytes, true)
				if message.is_empty(): udp_rejected += 1; continue
				if not battle_connections.has(peer_id):
					if event.channel != Battle.CHANNEL_CONTROL or message.get("op") != "battle_bind": udp_rejected += 1; continue
					var ticket_hash = str(message.get("ticket", "")).sha256_text()
					var ticket: Dictionary = battle_tickets.get(ticket_hash, {})
					var connection_id = int(ticket.get("connection", -1))
					if ticket.is_empty() or monotonic() > float(ticket.until) or not connections.has(connection_id):
						reject_battle_bind(peer, "unknown_expired_or_disconnected"); continue
					var entry = connections[connection_id]
					if entry.link != message.get("link") or entry.battle_peer != null:
						reject_battle_bind(peer, "link_mismatch_or_already_bound"); continue
					battle_tickets.erase(ticket_hash)
					battle_waiting.erase(peer_id)
					entry.battle_peer = peer
					entry.stream_codec = StateStream.new(entry.link)
					battle_connections[peer_id] = connection_id
					entry.last_seen = monotonic()
					send(connection_id, {"op": "battle_ready", "link": entry.link})
					var room = rooms.get(str(sessions[entry.session].room))
					if room != null: send_snapshot(connection_id, room)
					continue
				var connection_id = int(battle_connections[peer_id])
				if not connections.has(connection_id): continue
				var entry = connections[connection_id]
				if message.has("match_prefix"):
					var room = rooms.get(str(sessions[entry.session].room))
					if room == null or room.match == null or not str(room.match.id).begins_with(str(message.match_prefix)): continue
					message.room = room.id
					message.match = room.match.id
				var expected = Battle.CHANNEL_INPUT if message.get("op") == "input" else (Battle.CHANNEL_FEEDBACK if message.get("op") == "state_ack" else Battle.CHANNEL_CONTROL)
				if event.channel != expected: udp_rejected += 1; continue
				var now = monotonic()
				entry.tokens = minf(100, float(entry.tokens) + (now - float(entry.refill)) * 65)
				entry.refill = now
				entry.tokens -= 1
				if entry.tokens < 0: close_peer(connection_id, "rate_limited"); continue
				entry.last_seen = now
				handle(connection_id, message)
	for peer_id in battle_waiting.keys():
		if monotonic() > float(battle_waiting[peer_id].until):
			battle_bind_failures += 1
			battle_ticket_rejections["bind_timeout"] = int(battle_ticket_rejections.get("bind_timeout", 0)) + 1
			retire_battle_peer(battle_waiting[peer_id].peer)
	for ticket_hash in battle_tickets.keys():
		if monotonic() > float(battle_tickets[ticket_hash].until): battle_tickets.erase(ticket_hash)
	for peer_id in battle_retired.keys():
		var retired = battle_retired[peer_id]
		if not retired.peer.is_active() or monotonic() >= float(retired.until):
			if retired.peer.is_active(): retired.peer.peer_disconnect_now()
			battle_retired.erase(peer_id)

func retire_battle_peer(peer: ENetPacketPeer) -> void:
	battle.edge.retire_peer(peer)
	battle_waiting.erase(peer.get_instance_id())
	battle_connections.erase(peer.get_instance_id())
	battle_retired[peer.get_instance_id()] = {"peer": peer, "until": monotonic() + 12}

func wall_time() -> float:
	return Time.get_unix_time_from_system()

func _process(delta: float) -> void:
	if stopping: return
	var begin = Time.get_ticks_usec()
	var combat_active = rooms.values().any(func(room): return room.match != null and not room.suspended and room.match.phase == "playing")
	poll_battle()
	for entry in closing_peers.duplicate():
		entry.peer.poll()
		if entry.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED or monotonic() >= float(entry.until):
			entry.stream.disconnect_from_host()
			closing_peers.erase(entry)
	finish_checkpoint(false)
	poll_match_builds()
	if checkpoint_thread == null and not mutation_queue.is_empty():
		var queued: Dictionary = mutation_queue.pop_front()
		run_mutation(int(queued.get("connection", -1)), queued.message)
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
			"created": monotonic(), "tokens": 100.0, "refill": monotonic(), "event_ack": 0, "event_match": "", "no_delay": false,
			"link": Protocol.nonce(8), "state_serial": 0, "state_ack": 0, "state_lease": 0,
			"state_progress": monotonic(), "watched_room": "", "state_pending": [], "last_snapshot": PackedByteArray(), "last_snapshot_at": 0.0,
			"battle_peer": null, "stream_codec": null, "scene_ack": -1, "scene_ack_match": ""}
	for connection_id in connections.keys():
		if not connections.has(connection_id): continue
		var entry = connections[connection_id]
		var peer = entry.peer
		peer.poll()
		var state = peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			if entry.battle_peer == null or entry.battle_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
				disconnect_peer(connection_id)
				continue
		if state != WebSocketPeer.STATE_OPEN:
			if entry.battle_peer == null:
				if monotonic() - float(entry.created) > 6: close_peer(connection_id, "handshake_timeout")
				continue
		if state == WebSocketPeer.STATE_OPEN and not entry.no_delay:
			peer.set_no_delay(true)
			entry.no_delay = true
		for packet_index in 32:
			if peer.get_available_packet_count() == 0 or not connections.has(connection_id): break
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
		# State acknowledgements measure progress; they never gate the next state.
		if connections.has(connection_id) and monotonic() - float(entry.last_seen) > Protocol.SILENCE_SECONDS:
			close_peer(connection_id, "heartbeat_timeout")
		elif connections.has(connection_id) and str(entry.session).is_empty() and monotonic() - float(entry.created) > 6:
			close_peer(connection_id, "authentication_timeout")
		elif connections.has(connection_id) and not str(entry.session).is_empty() and entry.battle_peer == null and monotonic() > float(entry.get("battle_bind_until", float(entry.created) + Protocol.BATTLE_BIND_TIMEOUT_SECONDS)):
			close_peer(connection_id, "battle_bind_timeout")
	process_health()
	cleanup_elapsed += delta
	if cleanup_elapsed >= 60 and checkpoint_thread == null:
		cleanup_elapsed = 0
		cleanup_retention()
	snapshot_elapsed += delta
	if snapshot_elapsed >= 1.0 / Protocol.SNAPSHOT_RATE:
		snapshot_elapsed = fmod(snapshot_elapsed, 1.0 / Protocol.SNAPSHOT_RATE)
		if not storage_fault:
			for room in rooms.values():
				if snapshot_rooms.has(room.id): snapshots_coalesced += 1
				snapshot_rooms[room.id] = true
	# Build each room from current authority when its turn arrives. Coalesce
	# unsent updates and spread dense rooms across frames instead of accumulating
	# stale snapshots or encoding all rooms in one unbounded frame.
	var replication_begin = Time.get_ticks_usec()
	for room_id in snapshot_rooms.keys():
		if storage_fault: snapshot_rooms.clear(); break
		if rooms.has(room_id): broadcast(rooms[room_id])
		snapshot_rooms.erase(room_id)
		if Time.get_ticks_usec() - replication_begin >= 8000: break
	maintenance_elapsed += delta
	if maintenance_elapsed >= .2:
		maintenance_elapsed = 0
		maintenance()
		if FileAccess.file_exists(data_directory.path_join("stop")):
			DirAccess.remove_absolute(data_directory.path_join("stop"))
			shutdown()
			get_tree().quit()
	var duration = (Time.get_ticks_usec() - begin) / 1000.0
	process_ms.append(duration)
	record_duration(lifetime_process, duration)
	if combat_active:
		combat_process_max_ms = maxf(combat_process_max_ms, duration)
		if duration > 100: combat_stalls_over_100ms += 1
	if process_ms.size() > 600: process_ms.pop_front()
	battle.flush()

func _physics_process(delta: float) -> void:
	if stopping: return
	var begin = Time.get_ticks_usec()
	ticks += 1
	for room in ([] if storage_fault else rooms.values()):
		if room.match == null or room.suspended or room.match.phase == "finished": continue
		# Do not run the room while a peer is still loading its first absolute
		# scene. Core, metadata and NPC datagrams can arrive independently.
		var scene = input_scene(room)
		var phase = str(room.match.phase)
		if int(room.get("simulation_scene", -1)) != scene or str(room.get("simulation_phase", "")) != phase:
			room.simulation_scene = scene
			room.simulation_phase = phase
			room.input_epoch = int(room.get("input_epoch", 0)) + 1
			for input in room.inputs:
				input.frame = Protocol.empty_input(); input.queue = []; input.pending_actions = {}; input.last_seen = 0.0
			var actors: Array = room.match.world.contexts if room.get("game_mode") == "coop" else room.match.actors
			for actor in actors: actor.player.move = Vector2.ZERO
		var synchronized = room.players.all(func(sid):
			var entry: Dictionary = connections.get(int(sessions[sid].peer), {})
			return int(entry.get("scene_ack", -1)) == scene and str(entry.get("scene_ack_match", "")) == room.match.id \
				and int(entry.get("scene_ack_epoch", -1)) == int(room.input_epoch) and str(entry.get("scene_ack_phase", "")) == phase)
		if not synchronized:
			if int(room.get("sync_epoch", -1)) != int(room.input_epoch):
				room.sync_epoch = int(room.input_epoch); room.sync_until = monotonic() + 12
			if monotonic() > float(room.get("sync_until", 0)): suspend_room(room, "synchronization_timeout")
			continue
		if room.match.phase == "playing" and room.inputs.any(func(input): return float(input.last_seen) > 0 and monotonic() - float(input.last_seen) > Protocol.INPUT_PROTECT_SECONDS):
			suspend_room(room, "link_stalled")
			continue
		var frames: Array = []
		for seat in 2:
			var input = room.inputs[seat]
			var fresh = input_is_fresh(room, input)
			if not room.has("applied_actions"): room.applied_actions = [{}, {}]
			if fresh and not input.get("queue", []).is_empty():
				# Movement is a latest held state, not a FIFO of historical positions.
				# Edge IDs remain in all redundant frames until authority acknowledges
				# them, so skipping old motion does not drop a one-shot action.
				outdated_input_frames += maxi(0, input.queue.size() - 1)
				input.frame = input.queue.pop_back()
				input.queue.clear()
				room.applied_seq[seat] = int(input.frame.seq)
			var frame = input.frame.duplicate(true) if fresh else Protocol.empty_input()
			for edge in InputFrames.EDGES:
				# Edge actions have their own inbox. Selecting the latest held motion
				# must not erase an action accepted in an earlier redundant frame.
				var queued_action: Dictionary = input.get("pending_actions", {}).get(edge, {})
				if fresh and not queued_action.is_empty():
					frame[edge] = true
					if not frame.has("actions"): frame.actions = {}
					frame.actions[edge] = queued_action.id
					if edge == "dash": frame.dash_direction = queued_action.direction
				var action_id = int(frame.get("actions", {}).get(edge, frame.get("seq", 0)))
				if frame.get(edge, false) and action_id > int(room.applied_actions[seat].get(edge, 0)):
					room.applied_actions[seat][edge] = action_id
				else: frame[edge] = false
			frames.append(frame)
			input.pending_actions = {}
			if not fresh: input.frame = Protocol.empty_input(); input.queue = []
			for edge in ["dash", "skill", "active_item", "interact"]: input.frame[edge] = false
		room.match.advance(frames, 1.0 / Protocol.TICK_RATE)
		if room.match.phase == "finished": settle_match(room)
	checkpoint_elapsed += delta
	if checkpoint_elapsed >= checkpoint_interval:
		checkpoint_elapsed = 0
		start_checkpoint()
	var step_duration = (Time.get_ticks_usec() - begin) / 1000.0
	step_ms.append(step_duration)
	record_duration(lifetime_step, step_duration)
	if step_ms.size() > 600: step_ms.pop_front()

func send(connection_id: int, message: Dictionary, compressed: bool = false) -> bool:
	if in_mutation:
		mutation_outbox.append({"connection": connection_id, "message": message.duplicate(true), "compressed": compressed})
		return true
	var entry = connections.get(connection_id, {})
	if entry.get("battle_peer") != null and message.get("op") != "welcome":
		var bytes = Protocol.packet(message, compressed)
		var success = battle.send(entry.battle_peer, bytes, Battle.CHANNEL_CONTROL)
		if success: bytes_sent += bytes.size()
		return success
	return send_bytes(connection_id, Protocol.packet(message, compressed))

func send_bytes(connection_id: int, bytes: PackedByteArray) -> bool:
	if not connections.has(connection_id): return false
	var peer = connections[connection_id].peer
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	if peer.get_current_outbound_buffered_amount() > Protocol.MAX_SERVER_BYTES:
		close_peer(connection_id, "slow_connection")
		return false
	if bytes.size() > Protocol.MAX_SERVER_BYTES: return false
	var result = peer.put_packet(bytes)
	if result == OK: bytes_sent += bytes.size()
	else: close_peer(connection_id, "slow_connection")
	return result == OK

func send_snapshot(connection_id: int, room: Dictionary, shared = null) -> void:
	if not connections.has(connection_id): return
	var entry = connections[connection_id]
	if entry.battle_peer == null: return
	if entry.watched_room != room.id:
		entry.watched_room = room.id
		entry.state_progress = monotonic()
		entry.state_pending.clear()
		entry.state_lease = 0
		if not send(connection_id, {"op": "service", "link": entry.link, "room": room.id}): return
	var begin = Time.get_ticks_usec()
	var view = room_view(room, str(entry.session), shared)
	var viewed = Time.get_ticks_usec()
	view.link = entry.link
	view.state_seq = int(entry.state_serial) + 1
	view.lease = int(Time.get_ticks_msec())
	var packets = entry.stream_codec.encode(view)
	var encoded = Time.get_ticks_usec()
	for item in packets:
		if item.bytes.size() > StateStream.MAX_PACKET:
			# Never turn an unbounded world into one fragmented unreliable message.
			if item.bytes[1] == 5: continue # oversized decoration only
			push_warning("Battle packet exceeds budget: kind=%d bytes=%d" % [item.bytes[1], item.bytes.size()])
			close_peer(connection_id, "snapshot_too_large")
			return
		var channel = Battle.CHANNEL_BASELINE if item.reliable else Battle.CHANNEL_STATE
		if item.bytes[1] == 9 or (item.bytes[1] == 7 and item.bytes[StateStream.HEADER] == 9): channel = Battle.CHANNEL_DEFINITIONS
		if battle.send(entry.battle_peer, item.bytes, channel, item.reliable): bytes_sent += item.bytes.size()
	entry.state_serial = view.state_seq
	entry.state_lease = view.lease
	entry.state_pending.append({"seq": view.state_seq, "lease": view.lease, "match": str(view.get("id", "")), "event": int(view.get("event_serial", 0))})
	while entry.state_pending.size() > Protocol.STATE_RECEIPT_HISTORY: entry.state_pending.pop_front()
	entry.last_snapshot_at = monotonic()
	replication_ms.append((Time.get_ticks_usec() - begin) / 1000.0)
	measure_stage("view", (viewed - begin) / 1000.0)
	measure_stage("encode", (encoded - viewed) / 1000.0)
	measure_stage("enqueue", (Time.get_ticks_usec() - encoded) / 1000.0)
	if replication_ms.size() > 600: replication_ms.pop_front()

func measure_stage(label: String, milliseconds: float) -> void:
	if not stage_samples.has(label): stage_samples[label] = []
	stage_samples[label].append(milliseconds)
	if stage_samples[label].size() > 600: stage_samples[label].pop_front()

func acknowledge_state(entry: Dictionary, message: Dictionary) -> void:
	if message.get("link") != entry.link or not Store.integer(message.get("state_seq")) or not Store.integer(message.get("lease")): return
	var sequence = int(message.state_seq)
	if sequence <= int(entry.state_ack) or sequence > int(entry.state_serial): return
	var index = entry.state_pending.find_custom(func(value): return int(value.seq) == sequence and int(value.lease) == int(message.lease))
	if index < 0: return
	var snapshot = entry.state_pending[index]
	entry.state_ack = sequence
	entry.state_progress = monotonic()
	var room = rooms.get(str(sessions.get(str(entry.session), {}).get("room", "")))
	if room != null and room.match != null and bool(message.get("scene_ready", false)) and str(message.get("match", "")) == room.match.id and int(message.get("scene", -1)) == input_scene(room):
		entry.scene_ack = input_scene(room); entry.scene_ack_match = room.match.id
		if Store.integer(message.get("epoch")) and int(message.epoch) == int(room.input_epoch) and str(message.get("phase", "")) == str(room.match.phase):
			entry.scene_ack_epoch = int(message.epoch); entry.scene_ack_phase = str(message.phase)
	entry.state_pending = entry.state_pending.filter(func(value): return int(value.seq) > sequence)
	if str(message.get("match", "")) == snapshot.match and snapshot.match == entry.event_match and Store.integer(message.get("event")):
		entry.event_ack = maxi(int(entry.event_ack), mini(int(snapshot.event), int(message.event)))

func close_peer(connection_id: int, reason: String) -> void:
	if not connections.has(connection_id): return
	close_reasons[reason] = int(close_reasons.get(reason, 0)) + 1
	var socket = connections[connection_id].peer
	if reason == "session_replaced":
		# Identity revocation must reach the authenticated battle link even if
		# the independent bootstrap connection has already disappeared.
		var old_battle_peer = connections[connection_id].get("battle_peer")
		if old_battle_peer != null:
			# close_peer can run inside a durable mutation. Its outbox is flushed
			# after authority detaches, so this terminal transport notice must be
			# queued directly before retiring the old peer.
			battle.send(old_battle_peer, Protocol.packet({"op": "error", "code": "session_replaced"}), Battle.CHANNEL_CONTROL)
		battle.flush()
		# Retain the stream until the close handshake flushes. Dropping it after
		# one poll can lose code 4001 and make the old client retry a takeover.
		while closing_peers.size() >= max_connections:
			closing_peers.pop_front().stream.disconnect_from_host()
		closing_peers.append({"peer": socket, "stream": connections[connection_id].stream, "until": monotonic() + 2})
	socket.close(4001 if reason == "session_replaced" else -1, reason)
	if reason == "session_replaced": socket.poll()
	disconnect_peer(connection_id)

func disconnect_peer(connection_id: int) -> void:
	if not connections.has(connection_id): return
	var entry = connections[connection_id]
	revoke_battle_tickets(connection_id)
	if entry.battle_peer != null:
		# Remove authority immediately, retain the DTLS mapping while old records
		# drain. The client closes TLS after its bounded transport linger period.
		retire_battle_peer(entry.battle_peer)
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
	if message.get("op") in ["input", "state_ack", "ping", "health"]:
		handle_now(connection_id, message)
		return
	if checkpoint_thread != null or not mutation_queue.is_empty():
		if mutation_queue.size() >= 64 or mutation_queue.filter(func(item): return int(item.get("connection", -1)) == connection_id).size() >= 8:
			close_peer(connection_id, "mutation_queue_full")
			return
		mutation_queue.append({"connection": connection_id, "message": message.duplicate(true)})
	else: run_mutation(connection_id, message)

func run_mutation(connection_id: int, message: Dictionary) -> void:
	if connection_id >= 0 and not connections.has(connection_id): return
	in_mutation = true; mutation_copies = 0; mutation_outbox = []
	if message.get("op") == "__settle":
		if rooms.has(message.room):
			rooms[message.room].erase("settlement_pending")
			settle_match(rooms[message.room])
	elif message.get("op") == "__match_ready":
		if rooms.has(message.room): apply_match_ready(rooms[message.room], message.match)
	else: handle_now(connection_id, message)
	in_mutation = false
	if mutation_copies > 0:
		commit_outbox = mutation_outbox
		mutation_outbox = []
		start_checkpoint(clampi(mutation_copies, 1, 4))
	else:
		var outgoing = mutation_outbox; mutation_outbox = []
		for item in outgoing: send(item.connection, item.message, item.compressed)

func handle_now(connection_id: int, message: Dictionary) -> void:
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
		var pong = {"op": "pong", "nonce": message.get("nonce", 0), "server_time": wall_time()}
		# Keep the probe out of the reliable control queue. This makes the
		# reported gameplay RTT reflect the current path even while a snapshot or
		# transaction is being retried.
		if entry.get("battle_peer") != null:
			var bytes = Protocol.packet(pong)
			if battle.send(entry.battle_peer, bytes, Battle.CHANNEL_CONTROL, false): bytes_sent += bytes.size()
		else:
			send(connection_id, pong)
		return
	if op == "keepalive":
		# The WSS bootstrap socket remains open only as a proxy/NAT keepalive
		# after the encrypted ENet battle link is bound. It must not produce a
		# second pong, because that reply is routed through ENet and would skew
		# the gameplay RTT measurement.
		return
	if op == "input":
		receive_input(session, message)
		return
	if op == "state_ack":
		acknowledge_state(entry, message)
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
		send_reply(connection_id, session, cached)
		return
	var result = command(session, op, message)
	result.op = "ack"
	result.request = request_id
	session.last_request = request_id
	session.replies[str(request_id)] = result
	while session.replies.size() > 16: session.replies.erase(session.replies.keys()[0])
	if storage_fault or not persist_registry(): result = {"op": "error", "code": "storage_unavailable"}
	send_reply(connection_id, session, result)
	if rooms.has(str(session.room)): broadcast(rooms[str(session.room)])

func send_reply(connection_id: int, session: Dictionary, reply: Dictionary) -> void:
	var current = reply.duplicate(true)
	if current.get("op") == "ack": current.service = {"room": str(session.room), "queued": bool(session.queued)}
	send(connection_id, current)

func grant_battle(connection_id: int) -> bool:
	# The WSS identity stream owns the session; this ticket only authorizes a
	# fresh DTLS/ENet transport. Keeping the two grants independent lets a
	# transient UDP disconnect rebind without creating a second player identity.
	if not connections.has(connection_id): return false
	var entry = connections[connection_id]
	var sid = str(entry.get("session", ""))
	if sid.is_empty() or not sessions.has(sid): return false
	var session = sessions[sid]
	var room = rooms.get(str(session.room))
	var last_seq = 0
	if room != null:
		var seat = room.players.find(sid)
		if seat >= 0: last_seq = int(room.inputs[seat].seq)
	var ticket = issue_battle_ticket(connection_id)
	if ticket.is_empty(): return false
	entry.battle_bind_until = monotonic() + Protocol.BATTLE_BIND_TIMEOUT_SECONDS
	return send(connection_id, {"op": "battle_grant", "transport": Protocol.TRANSPORT_REVISION, "link": entry.link,
		"battle": {"port": battle_port, "certificate": battle.certificate_pem, "ticket": ticket},
		"owner_generation": int(session.get("owner_generation", 0)),
		"room": str(session.room), "queued": bool(session.queued), "session": sid,
		"request_floor": session.last_request,
		"input_floor": last_seq, "server_time": wall_time(), "grace": grace,
		"stats": session_stats(session)})

func authenticate(connection_id: int, message: Dictionary) -> void:
	if storage_fault:
		send(connection_id, {"op": "error", "code": "storage_unavailable"})
		close_peer(connection_id, "storage_unavailable")
		return
	if message.get("protocol") != Protocol.VERSION or message.get("transport") != Protocol.TRANSPORT_REVISION or message.get("content") != Protocol.fingerprint():
		send(connection_id, {"op": "error", "code": "version_mismatch", "protocol": Protocol.VERSION})
		connections[connection_id].peer.close(1008, "version_mismatch")
		return
	var instance = str(message.get("instance", ""))
	if instance.length() != 32 or instance.hex_decode().size() != 16:
		close_peer(connection_id, "invalid_instance")
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
		# A lost first welcome has no resume credential on the client yet. Reuse
		# its unclaimed enrollment instead of leaking an identity on every retry.
		for candidate in sessions:
			var enrollment = sessions[candidate]
			if enrollment.get("owner_instance", "") == instance and int(enrollment.last_request) == 0 and str(enrollment.room).is_empty() and not enrollment.queued and wall_time() - float(enrollment.last_seen) <= grace:
				sid = candidate
				break
		token = Protocol.nonce()
		if sid.is_empty():
			if sessions.size() >= 1024:
				send(connection_id, {"op": "error", "code": "server_full"})
				return
			sid = Protocol.nonce(16)
			sessions[sid] = {"id": sid, "token_hash": token.sha256_text(), "name": Protocol.clean_name(message.get("name", "")),
				"room": "", "queued": false, "peer": -1, "last_seen": wall_time(), "last_request": 0, "replies": {},
				"loadout": {"character": "c_paper", "weapon": "w01", "skill": "s01"}, "game_mode": "duel", "wins": 0, "losses": 0, "draws": 0, "coop_wins": 0, "coop_losses": 0}
		else: sessions[sid].token_hash = token.sha256_text()
	var session = sessions[sid]
	var old_instance = str(session.get("owner_instance", ""))
	var generation = int(session.get("owner_generation", 0))
	if old_instance != instance and (not Store.integer(message.get("owner_generation", 0)) or int(message.get("owner_generation", 0)) != generation):
		send(connection_id, {"op": "error", "code": "session_replaced"})
		close_peer(connection_id, "session_replaced")
		return
	var owner_changed = not old_instance.is_empty() and old_instance != instance
	if owner_changed: generation += 1
	session.owner_generation = generation
	session.owner_instance = instance
	if int(session.peer) >= 0 and int(session.peer) != connection_id:
		# Detach first: closing the old peer cannot suspend the new connection.
		var old_peer = int(session.peer)
		session.peer = -1
		close_peer(old_peer, "session_replaced")
	session.peer = connection_id
	session.last_seen = wall_time()
	session.name = Protocol.clean_name(message.get("name", session.name))
	connections[connection_id].session = sid
	var room = rooms.get(str(session.room))
	var last_seq = 0
	if room != null:
		var seat = room.players.find(sid)
		last_seq = int(room.inputs[seat].seq)
		room.inputs[seat].frame = Protocol.empty_input()
		room.inputs[seat].last_seen = 0.0
		room.resume_ready[seat] = false
		if room.match != null and room.match.phase != "finished":
			# A resume may overtake the old ENet disconnect notification. Freeze
			# the shared world until the freshly bound client and partner agree;
			# a bootstrap entry alone is not proof of a playable battle link.
			if owner_changed: suspend_room(room, "identity_changed")
			elif not room.suspended: suspend_room(room, "disconnect")
	if not persist_registry() or owner_changed and not persist_registry():
		send(connection_id, {"op": "error", "code": "storage_unavailable"})
		close_peer(connection_id, "storage_unavailable")
		return
	var ticket = issue_battle_ticket(connection_id)
	if ticket.is_empty():
		close_peer(connection_id, "battle_ticket_failed")
		return
	connections[connection_id].battle_bind_until = monotonic() + Protocol.BATTLE_BIND_TIMEOUT_SECONDS
	send(connection_id, {"op": "welcome", "transport": Protocol.TRANSPORT_REVISION, "link": connections[connection_id].link,
		"battle": {"port": battle_port, "certificate": battle.certificate_pem, "ticket": ticket},
		"owner_generation": generation,
		"room": str(session.room), "queued": bool(session.queued), "session": sid, "resume": token, "request_floor": session.last_request,
		"input_floor": last_seq, "server_time": wall_time(), "grace": grace,
		"stats": session_stats(session)})
	if room != null: broadcast(room)

func valid_loadout(value) -> bool:
	if not value is Dictionary: return false
	var character = db.row("characters", str(value.get("character", "")))
	return not character.is_empty() and not db.row("weapons", str(value.get("weapon", ""))).is_empty() and character.skills.has(value.get("skill", ""))

func command(session: Dictionary, op: String, message: Dictionary) -> Dictionary:
	var sid = str(session.id)
	var room = rooms.get(str(session.room))
	if op in ["ready", "choose", "cooperative_action", "pause", "resume", "leave", "rematch"]:
		if str(message.get("room", "")) != str(session.room) or str(message.get("match", "")) != (str(room.match.id) if room != null and room.match != null else ""): return failure("stale_context")
		if op in ["pause", "resume"] and room != null and (not Store.integer(message.get("epoch")) or int(message.epoch) != int(room.get("input_epoch", 0))): return failure("stale_context")
	match op:
		"loadout":
			if room != null or session.queued: return failure("busy")
			if not valid_loadout(message.get("loadout")): return failure("invalid_loadout")
			session.loadout = message.loadout.duplicate(true)
			return success()
		"queue":
			if room != null: return failure("already_in_room")
			if message.get("game_mode", "duel") not in ["coop", "duel"]: return failure("invalid_mode")
			if not valid_loadout(message.get("loadout")): return failure("invalid_loadout")
			session.loadout = message.loadout.duplicate(true)
			session.game_mode = message.get("game_mode", "duel")
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
			if message.get("game_mode", "duel") not in ["coop", "duel"]: return failure("invalid_mode")
			session.loadout = message.loadout.duplicate(true)
			session.game_mode = message.get("game_mode", "duel")
			var code = str(message.code)
			if codes.has(code):
				room = rooms[codes[code]]
				if room.get("game_mode", "duel") != session.game_mode: return failure("room_mode_mismatch")
				if room.players.size() >= 2: return failure("room_full")
				if room.match != null: return failure("room_started")
				room.players.append(sid)
				session.room = room.id
				persist_room(room)
			else:
				if active_room_count() >= max_rooms: return failure("server_full")
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
			if room.get("game_mode") == "coop" and message.get("choice_token", "") != room.match.choice_token(room.players.find(sid)): return failure("stale_choice")
			if not Store.integer(message.get("index")) or not room.match.choose(room.players.find(sid), int(message.index)): return failure("invalid_choice")
			persist_room(room)
			return success()
		"cooperative_action":
			if room == null or room.match == null or room.get("game_mode") != "coop": return failure("not_choosing")
			if room.suspended and not (message.get("action") == "repay" and room.suspend_reason == "menu" and all_connected(room)): return failure("not_choosing")
			var seat = room.players.find(sid)
			if message.get("choice_token", "") != room.match.choice_token(seat): return failure("stale_choice")
			if not message.get("action") is String or not message.get("value", "") is String or str(message.get("value", "")).length() > 64: return failure("invalid_choice")
			if not room.match.action(seat, message.action, message.get("value", "")): return failure("invalid_choice")
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
				room.input_epoch = int(room.get("input_epoch", 0)) + 1
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

func session_stats(session: Dictionary) -> Dictionary:
	return {"wins": session.wins, "losses": session.losses, "draws": session.draws, "coop_wins": session.get("coop_wins", 0), "coop_losses": session.get("coop_losses", 0)}

func create_room(players: Array, code: String = "", quick: bool = false) -> Dictionary:
	var room_id = Protocol.nonce(16)
	var room = {"id": room_id, "code": code, "quick": quick, "players": players.duplicate(),
		"game_mode": sessions[players[0]].get("game_mode", "duel"),
		"ready": [false, false], "resume_ready": [false, false], "rematch_ready": [false, false],
		"created": wall_time(), "match": null, "suspended": false, "suspend_reason": "", "suspend_until": 0.0,
		"input_epoch": 0,
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
	while queue.size() >= 2 and active_room_count() < max_rooms:
		var first = -1
		var second = -1
		for i in queue.size():
			for j in range(i + 1, queue.size()):
				if sessions[queue[i]].get("game_mode", "duel") == sessions[queue[j]].get("game_mode", "duel"): first = i; second = j; break
			if first >= 0: break
		if first < 0: break
		var players = [queue[first], queue[second]]
		queue.remove_at(second)
		queue.remove_at(first)
		var room = create_room(players, "", true)
		broadcast(room)

func active_room_count() -> int:
	return rooms.values().filter(func(room): return room.has("pending_start") or room.match == null or room.match.phase != "finished").size()

func begin_match(room: Dictionary) -> void:
	if room.has("pending_start"): return
	var loadouts: Array = []
	for sid in room.players: loadouts.append(sessions[sid].loadout.duplicate(true))
	var random_seed = Crypto.new().generate_random_bytes(4).decode_u32(0) % 2147483646 + 1
	# Persist the deterministic construction intent with the ready/rematch receipt.
	# A crash during construction recreates the same match rather than dropping it.
	room.pending_start = {"id": Protocol.nonce(16), "seed": random_seed, "loadouts": loadouts, "mode": room.get("game_mode", "duel")}
	start_match_build(room)

static func construct_match(intent: Dictionary) -> Dictionary:
	var begin = Time.get_ticks_usec()
	var encounter = Cooperation.new() if intent.mode == "coop" else Duel.new()
	encounter.begin(intent.id, intent.loadouts, intent.seed)
	return {"match": encounter, "milliseconds": (Time.get_ticks_usec() - begin) / 1000.0}

func start_match_build(room: Dictionary) -> void:
	if match_builds.has(room.id): return
	var thread = Thread.new()
	if thread.start(construct_match.bind(room.pending_start.duplicate(true))) != OK:
		mark_storage_fault(); return
	match_builds[room.id] = {"thread": thread, "intent": room.pending_start.id}

func poll_match_builds() -> void:
	for room in rooms.values():
		if room.has("pending_start") and not match_builds.has(room.id): start_match_build(room)
	for id in match_builds.keys():
		var job = match_builds[id]
		if job.get("queued", false): continue
		if job.thread.is_alive(): continue
		var result: Dictionary = job.thread.wait_to_finish()
		measure_stage("match_construct_worker", result.milliseconds)
		if rooms.has(id) and rooms[id].get("pending_start", {}).get("id") == job.intent:
			mutation_queue.append({"connection": -1, "message": {"op": "__match_ready", "room": id, "match": result.match}})
			job.queued = true
		else: match_builds.erase(id)

func apply_match_ready(room: Dictionary, encounter) -> void:
	if not room.has("pending_start") or room.players.size() != 2: return
	room.match = encounter
	room.erase("pending_start")
	match_builds.erase(room.id)
	room.ready = [false, false]
	room.rematch_ready = [false, false]
	room.resume_ready = [false, false]
	room.input_epoch = int(room.get("input_epoch", 0)) + 1
	room.suspended = false
	room.suspend_until = 0.0
	for seat in 2:
		room.inputs[seat].frame = Protocol.empty_input()
		room.inputs[seat].queue = []
		room.inputs[seat].pending_actions = {}
		room.inputs[seat].last_seen = 0.0
		if connected(room.players[seat]):
			connections[sessions[room.players[seat]].peer].event_ack = 0
			connections[sessions[room.players[seat]].peer].event_match = room.match.id
	if not all_connected(room): suspend_room(room, "disconnect")
	persist_registry()

func receive_input(session: Dictionary, message: Dictionary) -> void:
	if storage_fault: return
	var entry = connections.get(int(session.peer), {})
	entry.input_probe = {"at": monotonic(), "epoch": int(message.epoch) if Store.integer(message.get("epoch")) else -1,
		"scene": int(message.scene) if Store.integer(message.get("scene")) else -1,
		"lease_age_ms": int(Time.get_ticks_msec()) - int(message.lease) if Store.integer(message.get("lease")) else -1, "rejection": "phase"}
	var room = rooms.get(str(session.room))
	if room == null or room.match == null or room.suspended or room.match.phase != "playing": return
	entry.input_probe.rejection = "scope"
	if message.get("link") != entry.get("link") or str(message.get("room", "")) != room.id or str(message.get("match", "")) != room.match.id: return
	entry.input_probe.rejection = "field"
	for field in ["epoch", "scene", "lease"]:
		if not Store.integer(message.get(field)): return
	entry.input_probe.rejection = "epoch_scene"
	if int(message.epoch) != int(room.get("input_epoch", 0)) or int(message.scene) != input_scene(room): return
	var lease = int(message.lease)
	entry.input_probe.rejection = "lease"
	if lease < 1 or lease > int(entry.get("state_lease", 0)) or int(Time.get_ticks_msec()) - lease > Protocol.INPUT_LEASE_SECONDS * 1000: return
	entry.input_probe.rejection = "sequence"
	var seat = room.players.find(str(session.id))
	var previous = room.inputs[seat]
	var submitted: Array = message.get("frames", [message.get("frame", {})])
	if submitted.size() > 6: return
	if not previous.has("queue"): previous.queue = []
	for candidate in submitted:
		var frame = Protocol.clean_input(candidate)
		if frame.is_empty(): return
		if int(frame.seq) <= int(previous.seq): continue
		previous.seq = int(frame.seq)
		if not previous.has("pending_actions"): previous.pending_actions = {}
		for edge in InputFrames.EDGES:
			var action_id = int(frame.actions.get(edge, frame.seq))
			if frame.get(edge, false) and action_id > int(previous.pending_actions.get(edge, {}).get("id", 0)):
				previous.pending_actions[edge] = {"id": action_id, "direction": frame.dash_direction}
		previous.queue.append(frame)
		while previous.queue.size() > 8: previous.queue.pop_front()
	previous.epoch = int(message.epoch)
	previous.scene = int(message.scene)
	previous.lease = lease
	previous.last_seen = monotonic()
	entry.input_probe.rejection = ""

func suspend_room(room: Dictionary, cause: String, initiator: int = -1) -> void:
	if not room.suspended and cause in ["link_stalled", "synchronization_timeout"]:
		# Bounded operational evidence with no credentials, player IDs or positions.
		room.last_protection = {"reason": cause, "epoch": room.get("input_epoch", 0), "scene": input_scene(room), "phase": room.match.phase,
			"input_ages_ms": room.inputs.map(func(input): return (monotonic() - float(input.last_seen)) * 1000),
			"probes": room.players.map(func(sid): return connections.get(int(sessions[sid].peer), {}).get("input_probe", {}).duplicate(true))}
	if not room.suspended or cause != "menu":
		room.input_epoch = int(room.get("input_epoch", 0)) + 1
		room.resume_ready = [false, false]
	if not room.suspended or room.get("game_mode") == "coop" and room.suspend_reason == "menu" and cause != "menu":
		room.suspend_until = wall_time() + grace
		room.suspend_reason = cause
		room.suspend_by = initiator
		room.resume_ready = [false, false]
	room.suspended = true
	for input in room.inputs:
		input.frame = Protocol.empty_input()
		input.queue = []
		input.pending_actions = {}
		input.last_seen = 0.0

func input_scene(room: Dictionary) -> int:
	if room.match == null: return 0
	return int(room.match.world.scene_serial) if room.get("game_mode") == "coop" else int(room.match.round_index)

func input_is_fresh(room: Dictionary, input: Dictionary) -> bool:
	return monotonic() - float(input.last_seen) <= Protocol.INPUT_TIMEOUT \
		and int(input.get("epoch", -1)) == int(room.get("input_epoch", 0)) \
		and int(input.get("scene", -1)) == input_scene(room) \
		and int(Time.get_ticks_msec()) - int(input.get("lease", 0)) <= Protocol.INPUT_LEASE_SECONDS * 1000

func room_view(room: Dictionary, sid: String, shared = null) -> Dictionary:
	var seat = room.players.find(sid)
	var peer_id = int(sessions[sid].peer)
	var entry = connections.get(peer_id, {})
	var view = {"phase": "lobby", "actors": [], "offers": [], "picked": [-1, -1], "score": [0, 0], "events": [], "event_serial": 0, "players": []}
	if room.match != null:
		if entry.get("event_match", "") != room.match.id:
			entry.event_match = room.match.id
			entry.event_ack = 0
		view = room.match.view(seat, int(entry.get("event_ack", 0)), true, shared)
	view.op = "state"
	view.game_mode = room.get("game_mode", "duel")
	view.room = room.id
	view.code = room.code
	view.quick = room.quick
	view.seat = seat
	view.ready = room.ready.duplicate()
	view.connected = room.players.map(func(player): return connected(player) and str(sessions[player].room) == room.id)
	view.resume_ready = room.resume_ready.duplicate()
	view.rematch_ready = room.rematch_ready.duplicate()
	view.input_ack = room.applied_seq[seat]
	view.action_ack = room.get("applied_actions", [{}, {}])[seat].duplicate()
	view.input_floor = room.inputs[seat].seq
	view.input_epoch = int(room.get("input_epoch", 0))
	view.input_scene = input_scene(room)
	view.names = room.players.map(func(player): return str(sessions[player].name))
	view.stats = session_stats(sessions[sid])
	# Publishing a result confirms its durable statistics, not just a completed
	# simulation tick. Keep the terminal transition behind the registry commit.
	if room.match != null and view.get("phase") == "finished" and not durable_settled.has(str(room.match.id)): view.phase = "settling"
	if room.match == null:
		view.players = room.players.map(func(player): return sessions[player].loadout.duplicate(true))
	if room.suspended:
		view.resume_phase = view.phase
		view.phase = "suspended"
		view.suspend_reason = room.suspend_reason
		view.grace_left = maxf(0, float(room.suspend_until) - wall_time())
	return view

func broadcast(room: Dictionary) -> void:
	var shared: Dictionary = {}
	for sid in room.players:
		if connected(sid) and str(sessions[sid].room) == room.id: send_snapshot(int(sessions[sid].peer), room, shared)

func settle_match(room: Dictionary) -> void:
	if not in_mutation and not stopping:
		if settled.has(str(room.match.id)) or room.get("settlement_pending", false): return
		room.settlement_pending = true
		mutation_queue.append({"connection": -1, "message": {"op": "__settle", "room": room.id}})
		return
	room.suspended = false
	room.suspend_until = 0.0
	var match_id = str(room.match.id)
	if settled.has(match_id): return
	room.finished_at = wall_time()
	# Commit the terminal battle state before committing its idempotent result.
	if not persist_room(room): return
	settled[match_id] = wall_time()
	for seat in room.players.size():
		var session = sessions[room.players[seat]]
		if room.get("game_mode") == "coop":
			var stat = "coop_wins" if room.match.winner == 2 else "coop_losses"
			session[stat] = int(session.get(stat, 0)) + 1
		elif room.match.winner < 0: session.draws += 1
		elif room.match.winner == seat: session.wins += 1
		else: session.losses += 1
	if not persist_registry():
		settled.erase(match_id)
		for seat in room.players.size():
			var session = sessions[room.players[seat]]
			if room.get("game_mode") == "coop":
				var stat = "coop_wins" if room.match.winner == 2 else "coop_losses"
				session[stat] -= 1
			elif room.match.winner < 0: session.draws -= 1
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
		room.match.finish(-1 if room.get("game_mode") == "coop" else 1 - seat, "partner_left" if room.get("game_mode") == "coop" else "forfeit")
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
			if departed.size() >= room.players.size() or now - float(room.get("finished_at", room.created)) > 3600: remove_room(room)
		elif room.suspended and now >= float(room.suspend_until) and not (room.get("game_mode") == "coop" and room.suspend_reason == "menu" and all_connected(room)):
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
	var results = rooms.values().filter(func(room): return room.match != null and room.match.phase == "finished")
	results.sort_custom(func(a, b): return float(a.get("finished_at", a.created)) < float(b.get("finished_at", b.created)))
	while results.size() > maxi(8, max_rooms * 4):
		var disposable = results.find_custom(func(room): return not room.players.any(func(sid): return connected(sid) and str(sessions[sid].room) == room.id))
		if disposable < 0: break
		var expired_result = results.pop_at(disposable)
		remove_room(expired_result)
	var expired = sessions.keys().filter(func(sid): return not connected(sid) and str(sessions[sid].room).is_empty() and now - float(sessions[sid].last_seen) > 14 * 86400)
	for sid in expired: sessions.erase(sid)
	if not expired.is_empty(): persist_registry()

func persist_registry() -> bool:
	if in_mutation:
		mutation_copies += 1
		return not storage_fault
	if not stopping:
		persistence_dirty = true
		return not storage_fault
	finish_checkpoint(true)
	# Each registry generation must reference its own room files. Reusing the
	# same paused room revision in both slots defeats corruption fallback.
	for room in rooms.values():
		if not persist_room(room): return false
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
	if in_mutation:
		mutation_copies = maxi(1, mutation_copies)
		return not storage_fault
	if not stopping:
		persistence_dirty = true
		return not storage_fault
	finish_checkpoint(true)
	var result = write_room_generation(room.store, room_snapshot(room))
	if result: room.checkpoint_revision = int(room.store.revision)
	else:
		persistence_errors += 1
		mark_storage_fault()
	return result

func room_snapshot(room: Dictionary) -> Dictionary:
	var started_at = Time.get_ticks_usec()
	var data: Dictionary = {}
	for key in room:
		if key not in ["match", "store", "inputs", "checkpoint_revision", "settlement_pending"]: data[key] = room[key]
	data.input_seqs = room.inputs.map(func(input): return int(input.seq))
	data.match = room.match.checkpoint() if room.match != null else {}
	var snapshot = data.duplicate(true)
	measure_stage("checkpoint_capture", (Time.get_ticks_usec() - started_at) / 1000.0)
	return snapshot

static func write_room_generation(writer, data: Dictionary) -> bool:
	var result = writer.write(data)
	if result:
		var revision = int(writer.revision)
		var source = writer.folder.path_join("checkpoint_%d.json" % (revision % 2))
		var archive = writer.folder.path_join("revision_%016d.json" % revision)
		result = DirAccess.copy_absolute(source, archive) == OK
	return result

func start_checkpoint(copies: int = 1) -> void:
	finish_checkpoint(false)
	if checkpoint_thread != null: return
	var job = {"registry": registry_snapshot(), "writer": meta_store, "rooms": [], "copies": copies}
	persistence_dirty = false
	for room in rooms.values():
		job.rooms.append({"id": room.id, "writer": room.store, "data": room_snapshot(room)})
	checkpoint_thread = Thread.new()
	if checkpoint_thread.start(write_checkpoint_job.bind(job)) != OK:
		checkpoint_thread = null
		mark_storage_fault()
		persistence_errors += 1
		var outgoing = commit_outbox; commit_outbox = []
		for item in outgoing: send(item.connection, {"op": "error", "code": "storage_unavailable"})

static func write_checkpoint_job(job: Dictionary) -> Dictionary:
	var revisions: Dictionary = {}
	var success = true
	for generation in int(job.get("copies", 1)):
		for room in job.rooms:
			var saved = write_room_generation(room.writer, room.data)
			success = saved and success
			if saved:
				revisions[room.id] = int(room.writer.revision)
				job.registry.room_revisions[room.id] = int(room.writer.revision)
		if success: success = job.writer.write(job.registry)
		if not success: break
	return {"ok": success, "revisions": revisions, "settled": job.registry.settled}

func finish_checkpoint(wait_for_commit: bool) -> void:
	if checkpoint_thread == null or not wait_for_commit and checkpoint_thread.is_alive(): return
	var started_at = Time.get_ticks_usec()
	var result = checkpoint_thread.wait_to_finish()
	checkpoint_thread = null
	for room_id in result.revisions:
		if rooms.has(room_id): rooms[room_id].checkpoint_revision = int(result.revisions[room_id])
	if not result.ok:
		mark_storage_fault()
		persistence_errors += 1
	else:
		durable_settled = result.get("settled", {}).duplicate(true)
		if storage_fault:
			for entry in connections.values():
				entry.state_progress = monotonic()
				entry.state_pending.clear()
				entry.last_snapshot = PackedByteArray()
		storage_fault = false
		prune_archives()
	var outgoing = commit_outbox; commit_outbox = []
	for item in outgoing:
		if result.ok: send(item.connection, item.message, item.compressed)
		elif connections.has(item.connection): send(item.connection, {"op": "error", "code": "storage_unavailable"})
	measure_stage("checkpoint_commit", (Time.get_ticks_usec() - started_at) / 1000.0)

func prune_archives() -> void:
	if not DirAccess.dir_exists_absolute(data_directory.path_join("rooms")): return
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
	if not DirAccess.dir_exists_absolute(root): return
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
			var duel = Cooperation.new() if data.get("game_mode") == "coop" else Duel.new()
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

func record_duration(histogram: Dictionary, milliseconds: float) -> void:
	# Fixed 0.125 ms buckets retain whole-run percentiles with bounded memory.
	var bucket = mini(1600, ceili(milliseconds * 8))
	histogram.bins[bucket] = int(histogram.bins.get(bucket, 0)) + 1
	histogram.count += 1
	histogram.max_ms = maxf(histogram.max_ms, milliseconds)

func duration_summary(histogram: Dictionary) -> Dictionary:
	var result = {"samples": histogram.count, "max_ms": histogram.max_ms, "bucket_width_ms": .125}
	var keys = histogram.bins.keys(); keys.sort()
	for fraction in [.95, .99, .999]:
		var target = ceili(histogram.count * fraction); var cumulative = 0
		for bucket in keys:
			cumulative += int(histogram.bins[bucket])
			if cumulative >= target:
				result["p%s_ms_upper_bound" % str(roundi(fraction * 1000))] = float(bucket) / 8 if bucket < 1600 else histogram.max_ms
				break
	return result

func health() -> Dictionary:
	var samples = step_ms.duplicate()
	samples.sort()
	var network = process_ms.duplicate()
	network.sort()
	var replication = replication_ms.duplicate()
	replication.sort()
	var buffered = 0
	var unacked = 0
	var largest_window = 0
	var stages: Dictionary = {}
	for label in stage_samples:
		var values: Array = stage_samples[label].duplicate(); values.sort()
		if not values.is_empty(): stages[label] = {"p95_ms": values[int((values.size() - 1) * .95)], "p99_ms": values[int((values.size() - 1) * .99)], "max_ms": values[-1]}
	for entry in connections.values():
		buffered += entry.peer.get_current_outbound_buffered_amount()
		unacked += entry.state_pending.size()
		largest_window = maxi(largest_window, entry.state_pending.size())
	return {"service": "IncenseDebt Online", "version": str(ProjectSettings.get_setting("application/config/version", "")), "protocol": Protocol.VERSION, "transport": Protocol.TRANSPORT_REVISION, "uptime": uptime,
		"connections": connections.size(), "battle_connections": battle_connections.size(), "battle_port": battle_port, "battle_encrypted": battle.started,
		"udp_received_bytes": battle.received_bytes, "udp_sent_bytes": battle.sent_bytes, "udp_rejected": udp_rejected,
		"battle_tickets": {"active": battle_tickets.size(), "issued": battle_ticket_issued, "revocations": battle_ticket_revocations,
			"reissues": battle_ticket_reissues, "bind_failures": battle_bind_failures, "rejections": battle_ticket_rejections.duplicate()},
		"udp_edge_rejected": battle.edge.rejected, "udp_wire_received_bytes": battle.edge.bytes_received, "udp_wire_sent_bytes": battle.edge.bytes_sent,
		"udp_forwarding": {"active_flows": battle.edge.flows.size(), "expired_established": battle.edge.expired_established,
			"expired_handshakes": battle.edge.expired_handshakes, "expired_retired": battle.edge.expired_retired, "outbound_alerts": battle.edge.outbound_alerts,
			"quarantined": battle.edge.quarantined, "active_quarantine": battle.edge.quarantine.size(), "output_backlog_max": battle.edge.output_backlog_max},
		"retiring_battle_connections": battle_retired.size(), "outdated_motion_samples_skipped": outdated_input_frames,
		"connection_close_reasons": close_reasons.duplicate(),
		"last_input_protections": rooms.values().filter(func(room): return room.has("last_protection")).map(func(room): return room.last_protection),
		"enet_peers": battle.host.get_peers().map(func(peer): return {"rtt_ms": peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
			"rtt_variance": peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE), "throttle": peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
			"loss_raw": peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)}),
		"stages": stages, "combat_process_max_ms": combat_process_max_ms, "combat_stalls_over_100ms": combat_stalls_over_100ms,
		"lifetime_step": duration_summary(lifetime_step), "lifetime_process": duration_summary(lifetime_process),
		"mutation_queue": mutation_queue.size(), "match_build_workers": match_builds.size(),
		"replication_p95_ms": replication[int((replication.size() - 1) * .95)] if not replication.is_empty() else 0.0,
		"rooms": rooms.size(), "active_rooms": active_room_count(), "queued": queue.size(), "tick": ticks,
		"step_p95_ms": samples[int((samples.size() - 1) * .95)] if not samples.is_empty() else 0.0,
		"step_p99_ms": samples[int((samples.size() - 1) * .99)] if not samples.is_empty() else 0.0,
		"step_max_ms": samples.back() if not samples.is_empty() else 0.0,
		"process_p95_ms": network[int((network.size() - 1) * .95)] if not network.is_empty() else 0.0,
		"process_p99_ms": network[int((network.size() - 1) * .99)] if not network.is_empty() else 0.0,
		"process_max_ms": network.back() if not network.is_empty() else 0.0, "buffered_bytes": buffered,
		"unacked_snapshots": unacked, "largest_snapshot_window": largest_window, "snapshot_retries": snapshot_retries, "snapshots_coalesced": snapshots_coalesced,
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
	for job in match_builds.values():
		if not job.get("queued", false): job.thread.wait_to_finish()
	match_builds.clear()
	stopping = true
	listener.stop()
	health_listener.stop()
	var saved = true
	for room in rooms.values(): saved = persist_room(room) and saved
	saved = persist_registry() and saved
	for connection_id in connections.keys(): close_peer(connection_id, "server_shutdown")
	for entry in closing_peers: entry.stream.disconnect_from_host()
	closing_peers.clear()
	battle.close()
	rooms.clear()
	sessions.clear()
	print("ONLINE_STOPPED checkpoints_flushed=" + str(saved and not storage_fault))
