extends SceneTree
## Isolated transport probe. No production rooms, saves, credentials or deployment.
var server = ENetConnection.new()
var client = ENetConnection.new()
var server_peer: ENetPacketPeer
var client_peer: ENetPacketPeer
var output = ""
var startup = 0.0
var started = -1.0
var duration = 6.0
var state_at = 0.0
var input_at = 0.0
var control_at = 0.0
var state_sent = 0
var input_sent = 0
var control_sent = 0
var state_received = 0
var latest_state = 0
var last_state_at = -1.0
var state_gaps: Array = []
var state_ages: Array = []
var input_rtts: Array = []
var controls: Dictionary = {}
var replies: Dictionary = {}
var failure = ""
var dtls = true

func clock() -> float:
	return Time.get_ticks_usec() / 1000000.0

func _initialize() -> void:
	var options: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var pieces = argument.substr(2).split("=", true, 1)
			options[pieces[0]] = pieces[1]
	output = str(options.get("output", ""))
	if output.is_empty(): failure = "Missing --output"; finish(); return
	var result = server.create_host_bound("127.0.0.1", int(options["server-port"]), 1, 3)
	if result != OK: failure = "Server bind failed"; finish(); return
	result = client.create_host_bound("127.0.0.1", 0, 1, 3)
	if result != OK: failure = "Client bind failed"; finish(); return
	dtls = str(options.get("dtls", "true")) == "true"
	if dtls:
		var crypto = Crypto.new()
		var key = crypto.generate_rsa(2048)
		var certificate = crypto.generate_self_signed_certificate(key, "CN=localhost,O=IncenseDebt Transport Probe", "20260101000000", "20300101000000")
		result = server.dtls_server_setup(TLSOptions.server(key, certificate))
		if result != OK: failure = "Server DTLS setup failed"; finish(); return
		result = client.dtls_client_setup("localhost", TLSOptions.client(certificate))
		if result != OK: failure = "Client DTLS setup failed"; finish(); return
	client_peer = client.connect_to_host("127.0.0.1", int(options["proxy-port"]), 3)
	if client_peer == null: failure = "Client connect failed"; finish(); return
	startup = clock()

func packet(serial: int, size: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(size)
	bytes.encode_u32(0, serial)
	bytes.encode_u64(4, Time.get_ticks_usec())
	return bytes

func poll_host(host: ENetConnection, server_side: bool) -> void:
	for budget in 128:
		var event = host.service(0)
		match int(event[0]):
			ENetConnection.EVENT_NONE: return
			ENetConnection.EVENT_ERROR:
				failure = "ENet service error"
				return
			ENetConnection.EVENT_DISCONNECT:
				failure = "Disconnected during probe"
				return
			ENetConnection.EVENT_CONNECT:
				if server_side: server_peer = event[1]
				else: client_peer = event[1]
			ENetConnection.EVENT_RECEIVE:
				var peer: ENetPacketPeer = event[1]
				var bytes: PackedByteArray = peer.get_packet()
				if bytes.size() < 12: failure = "Short probe packet"; return
				var serial = bytes.decode_u32(0)
				var channel = int(event[3])
				if server_side:
					if channel == 1: peer.send(1, bytes, 0)
					elif channel == 2:
						controls[serial] = true
						peer.send(2, bytes, ENetPacketPeer.FLAG_RELIABLE)
				elif channel == 0 and serial > latest_state:
					latest_state = serial
					state_received += 1
					state_ages.append((Time.get_ticks_usec() - bytes.decode_u64(4)) / 1000.0)
					if last_state_at >= 0: state_gaps.append((clock() - last_state_at) * 1000.0)
					last_state_at = clock()
				elif channel == 1:
					input_rtts.append((Time.get_ticks_usec() - bytes.decode_u64(4)) / 1000.0)
				elif channel == 2: replies[serial] = true

func _process(_delta: float) -> bool:
	if not failure.is_empty(): finish(); return true
	poll_host(server, true)
	poll_host(client, false)
	if not failure.is_empty(): finish(); return true
	if started < 0:
		if server_peer != null and client_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			started = clock()
			state_at = started
			input_at = started
			control_at = started
		elif clock() - startup > 15: failure = "DTLS/ENet handshake deadline"; finish(); return true
		return false
	var now = clock()
	if now - started < duration:
		if now >= state_at:
			state_at += .05
			state_sent += 1
			server_peer.send(0, packet(state_sent, 760), 0)
		if now >= input_at:
			input_at += 1.0 / 30.0
			input_sent += 1
			client_peer.send(1, packet(input_sent, 64), 0)
		if now >= control_at:
			control_at += .2
			control_sent += 1
			client_peer.send(2, packet(control_sent, 32), ENetPacketPeer.FLAG_RELIABLE)
	server.flush()
	client.flush()
	if now - started >= duration + 4:
		finish()
		return true
	return false

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return -1.0
	var sorted = values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * fraction)) - 1)])

func finish() -> void:
	var passed = failure.is_empty() and state_received > 30 and controls.size() == control_sent and replies.size() == control_sent and control_sent > 0
	var report = {"passed": passed, "failure": failure, "native_engine": Engine.get_version_info().string,
		"dtls": dtls, "certificate_hostname_verified": dtls, "virtualization": "none", "duration_s": duration,
		"state_payload_bytes": 760, "input_payload_bytes": 64, "control_payload_bytes": 32,
		"state_sent": state_sent, "state_received": state_received, "input_sent": input_sent, "input_echoes": input_rtts.size(),
		"state_age_p95_ms": percentile(state_ages, .95), "state_gap_p95_ms": percentile(state_gaps, .95),
		"state_gap_max_ms": percentile(state_gaps, 1.0), "input_round_trip_p95_ms": percentile(input_rtts, .95),
		"reliable_requests": control_sent, "unique_requests_received": controls.size(), "unique_replies_received": replies.size(),
		"scope": "Native ENet/DTLS transport over loopback UDP with an external datagram proxy. Synthetic payloads; no game simulation, production traffic, Android or WAN acceptance."}
	if not output.is_empty():
		var file = FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print(JSON.stringify(report))
	server.destroy()
	client.destroy()
	quit(0 if passed else 1)
