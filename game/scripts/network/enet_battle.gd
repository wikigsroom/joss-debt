extends RefCounted
## Native encrypted battle transport. Authentication is bound to the WSS session.
const CHANNEL_STATE = 0
const CHANNEL_INPUT = 1
const CHANNEL_CONTROL = 2
const CHANNEL_BASELINE = 3
const CHANNEL_DEFINITIONS = 4
const CHANNEL_FEEDBACK = 5
const CHANNELS = 6
const EVENT_BUDGET = 256
const Edge = preload("res://scripts/network/dtls_edge.gd")
var edge = Edge.new()
var host = ENetConnection.new()
var remote: ENetPacketPeer
var certificate = X509Certificate.new()
var certificate_pem = ""
var started = false
var received_bytes = 0
var sent_bytes = 0

func start_server(address: String, port: int, capacity: int, options: Dictionary) -> Error:
	var key = CryptoKey.new()
	var certificate_path = str(options.get("battle_certificate", ""))
	var key_path = str(options.get("battle_private_key", ""))
	if not certificate_path.is_empty() and not key_path.is_empty():
		if certificate.load(certificate_path) != OK or key.load(key_path) != OK: return ERR_CANT_OPEN
		certificate_pem = FileAccess.get_file_as_string(certificate_path)
	elif address in ["127.0.0.1", "::1", "localhost"]:
		# Isolated native tests only; no key is written to disk or reused in production.
		var crypto = Crypto.new()
		key = crypto.generate_rsa(2048)
		certificate = crypto.generate_self_signed_certificate(key, "CN=localhost,O=IncenseDebt Native Test", "20260101000000", "20300101000000")
		# Godot's save_to_string currently warns on mbedTLS's trailing NUL. Export
		# only the public test certificate, trim terminators, then remove the file.
		var public_path = "user://enet-public-%d.crt" % Time.get_ticks_usec()
		if certificate.save(public_path) != OK: return ERR_CANT_OPEN
		var pem_bytes = FileAccess.get_file_as_bytes(public_path)
		while not pem_bytes.is_empty() and pem_bytes[-1] == 0: pem_bytes.resize(pem_bytes.size() - 1)
		certificate_pem = pem_bytes.get_string_from_utf8()
		DirAccess.remove_absolute(public_path)
	else:
		return ERR_UNCONFIGURED
	# The public socket forwards encrypted records to this process's loopback DTLS
	# listener. It never handles keys, plaintext, tickets or gameplay authority.
	var result = host.create_host_bound("127.0.0.1", 0, capacity, CHANNELS)
	if result != OK: return result
	result = host.dtls_server_setup(TLSOptions.server(key, certificate))
	if result != OK: host.destroy(); return result
	result = edge.start(address, port, host.get_local_port(), capacity)
	if result != OK: host.destroy(); return result
	started = true
	return OK

func connect_client(address: String, port: int, hostname: String, pem: String) -> Error:
	if pem.length() > 16384 or certificate.load_from_string(pem) != OK: return ERR_INVALID_DATA
	var result = host.create_host(1, CHANNELS)
	if result != OK: return result
	result = host.dtls_client_setup(hostname, TLSOptions.client(certificate))
	if result != OK: host.destroy(); return result
	result = edge.start_client(address, port)
	if result != OK: host.destroy(); return result
	remote = host.connect_to_host("127.0.0.1", edge.front.get_local_port(), CHANNELS)
	if remote == null: host.destroy(); edge.close(); return ERR_CANT_CONNECT
	remote.set_timeout(16, 4000, 8000)
	started = true
	return OK

func poll() -> Array:
	var result: Array = []
	if not started: return result
	edge.poll()
	for index in EVENT_BUDGET:
		var event = host.service(0)
		if int(event[0]) == ENetConnection.EVENT_NONE: break
		var item = {"type": int(event[0]), "peer": event[1], "channel": int(event[3])}
		if item.type == ENetConnection.EVENT_CONNECT and remote != null and item.peer == remote:
			# Inputs have a bounded 30 Hz budget and supersede older held motion.
			# Default probabilistic throttling can reach zero after RTT jitter,
			# starving authority of input while reliable pings still arrive.
			remote.throttle_configure(1000, 32, 0)
		if item.type == ENetConnection.EVENT_RECEIVE:
			item.bytes = event[1].get_packet()
			received_bytes += item.bytes.size()
		result.append(item)
	edge.poll()
	return result

func send(peer: ENetPacketPeer, bytes: PackedByteArray, channel: int, reliable: bool = true) -> bool:
	if not started or peer == null or peer.get_state() != ENetPacketPeer.STATE_CONNECTED: return false
	# State fragments carry their own entity sequence: a late fragment must not
	# cause unrelated, newer entities to disappear at ENet's channel ordering layer.
	var flags = ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED
	if peer.send(channel, bytes, flags) != OK: return false
	sent_bytes += bytes.size()
	return true

func flush() -> void:
	if started: host.flush(); edge.poll()

func connected() -> bool:
	return started and remote != null and remote.get_state() == ENetPacketPeer.STATE_CONNECTED

func close() -> void:
	if started: host.destroy()
	edge.close()
	started = false
	remote = null
