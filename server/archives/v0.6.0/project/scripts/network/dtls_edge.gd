extends RefCounted
## Native UDP record gate, no decryption or custom cryptography. Godot's DTLS
## backend treats late application records after close as new handshakes. Gate
## unknown records and retire a flow on an Alert before forwarding late records.
const RECORD_BUDGET = 64
# ENet owns the authenticated peer timeout (8 seconds). Retiring its forwarding
# socket at 3.5 seconds can turn delayed encrypted traffic into a new handshake.
# Keep this allocator expiry beyond the peer timeout; authority still freezes
# missing gameplay input after its independent, much shorter safety deadline.
const IDLE_SECONDS = 20.0
const HANDSHAKE_IDLE_SECONDS = 12.0
# A public UDP tuple that has just carried a DTLS close alert must not be
# reused immediately.  Delayed/reordered records from the previous DTLS
# session can otherwise be mistaken for a new ClientHello by mbedTLS.  The
# client allocator binds a fresh source port on reconnect, so this quarantine
# does not block a normal retry while protecting the old tuple.
const RETIRED_TUPLE_QUARANTINE_SECONDS = 30.0
var front = PacketPeerUDP.new()
var flows: Dictionary = {}
var quarantine: Dictionary = {}
var target_port = 0
var capacity = 0
var started = false
var rejected = 0
var expired_established = 0
var expired_handshakes = 0
var expired_retired = 0
var outbound_alerts = 0
var quarantined = 0
var output_cursor = 0
var output_backlog_max = 0
var bytes_received = 0
var bytes_sent = 0
var admissions: Dictionary = {}
var peer_ports: Dictionary = {}
var client_mode = false
var client_socket = PacketPeerUDP.new()
var client_ip = ""
var client_port = 0
var private_client_port = 0

func start_client(address: String, port: int) -> Error:
	client_ip = address if address.is_valid_ip_address() else IP.resolve_hostname(address, IP.TYPE_ANY)
	if client_ip.is_empty(): return ERR_CANT_RESOLVE
	var error = front.bind(0, "127.0.0.1", 262144)
	if error != OK: return error
	error = client_socket.bind(0, "::" if client_ip.contains(":") else "0.0.0.0", 262144)
	if error != OK: front.close(); return error
	error = client_socket.set_dest_address(client_ip, port)
	if error != OK: front.close(); client_socket.close(); return error
	client_port = port; client_mode = true; started = true
	return OK

func poll_client() -> void:
	# Keep encrypted WAN records on a bounded, unconnected native UDP socket.
	# Godot's ENet DTLS client uses a connected socket; Windows ICMP/send errors
	# otherwise tear down its TLS context instead of acting as packet loss.
	for index in RECORD_BUDGET:
		if front.get_available_packet_count() <= 0: break
		var bytes = front.get_packet(); var port = front.get_packet_port()
		if front.get_packet_ip() != "127.0.0.1" or records(bytes).is_empty(): rejected += 1; continue
		if private_client_port == 0: private_client_port = port
		if port != private_client_port: rejected += 1; continue
		if client_socket.put_packet(bytes) == OK: bytes_sent += bytes.size()
		else: rejected += 1
	for index in RECORD_BUDGET:
		if client_socket.get_available_packet_count() <= 0: break
		var bytes = client_socket.get_packet()
		if client_socket.get_packet_ip() != client_ip or client_socket.get_packet_port() != client_port or records(bytes).is_empty(): rejected += 1; continue
		bytes_received += bytes.size()
		if private_client_port == 0: continue
		front.set_dest_address("127.0.0.1", private_client_port)
		if front.put_packet(bytes) != OK: rejected += 1

func start(address: String, port: int, internal_port: int, max_flows: int) -> Error:
	var error = front.bind(port, address, 262144)
	if error != OK: return error
	target_port = internal_port; capacity = max_flows; started = true
	return OK

func records(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 13 or bytes.size() > 2048: return {}
	var offset = 0; var alert = false; var hello = false; var application = false
	while offset < bytes.size():
		if offset + 13 > bytes.size(): return {}
		var kind = int(bytes[offset])
		if kind not in [20, 21, 22, 23] or bytes[offset + 1] != 254 or bytes[offset + 2] not in [253, 255]: return {}
		var size = int(bytes[offset + 11]) * 256 + int(bytes[offset + 12])
		if offset + 13 + size > bytes.size(): return {}
		alert = alert or kind == 21
		application = application or kind == 23
		# ClientHello has a 12-byte handshake header and at least 34 bytes of
		# version/random. Short forged headers never reach the DTLS allocator.
		if kind == 22 and size >= 46 and bytes[offset + 3] == 0 and bytes[offset + 4] == 0 and bytes[offset + 13] == 1: hello = true
		offset += 13 + size
	return {"alert": alert, "hello": hello, "application": application}

func remember_peer(peer: ENetPacketPeer) -> void:
	peer_ports[peer.get_instance_id()] = peer.get_remote_port()

func retire_peer(peer: ENetPacketPeer) -> void:
	# The authoritative ENet peer identifies the private forwarding socket. Only
	# verified transport/authority closure retires a flow; an unauthenticated
	# inbound Alert header must not be able to disconnect somebody else's flow.
	var port = int(peer_ports.get(peer.get_instance_id(), -1))
	peer_ports.erase(peer.get_instance_id())
	if port < 0: return
	for flow in flows.values():
		if flow.socket.get_local_port() == port:
			flow.retiring = true
			var now = Time.get_ticks_msec() / 1000.0
			flow.retire_at = now + 8
			quarantine["%s/%d" % [flow.address, int(flow.port)]] = now + RETIRED_TUPLE_QUARANTINE_SECONDS

func cleanup_quarantine(now: float) -> void:
	for key in quarantine.keys():
		if now >= float(quarantine[key]): quarantine.erase(key)

func poll() -> void:
	if not started: return
	if client_mode: poll_client(); return
	var now = Time.get_ticks_msec() / 1000.0
	cleanup_quarantine(now)
	for index in RECORD_BUDGET:
		if front.get_available_packet_count() == 0: break
		var bytes = front.get_packet()
		var address = front.get_packet_ip(); var port = front.get_packet_port()
		var key = "%s/%d" % [address, port]
		var record = records(bytes)
		bytes_received += bytes.size()
		if record.is_empty(): rejected += 1; continue
		if quarantine.has(key):
			quarantined += 1
			continue
		var flow: Dictionary = flows.get(key, {})
		if not flow.is_empty() and flow.retiring:
			# Never replace a retiring flow in place.  A late record from the old
			# session is not evidence of a fresh handshake and must be discarded.
			quarantined += 1
			continue
		if not flow.is_empty() and now - float(flow.last_input) >= (IDLE_SECONDS if flow.established else HANDSHAKE_IDLE_SECONDS):
			if not record.hello: rejected += 1; continue
			flow.socket.close(); flows.erase(key); flow = {}
		if flow.is_empty():
			if not record.hello or flows.size() >= capacity: rejected += 1; continue
			if not admissions.has(address):
				if admissions.size() >= 128: rejected += 1; continue
				admissions[address] = {"tokens": 12.0, "at": now}
			var admission: Dictionary = admissions[address]
			admission.tokens = minf(12, float(admission.tokens) + (now - float(admission.at)) * 5)
			admission.at = now
			if admission.tokens < 1: rejected += 1; continue
			admission.tokens -= 1
			var socket = PacketPeerUDP.new()
			if socket.bind(0, "127.0.0.1", 65536) != OK: rejected += 1; continue
			socket.set_dest_address("127.0.0.1", target_port)
			flow = {"socket": socket, "address": address, "port": port, "last_input": now, "retiring": false, "retire_at": 0.0, "established": false}
			flows[key] = flow
		flow.last_input = now
		if flow.socket.put_packet(bytes) != OK: rejected += 1
	var output_budget = RECORD_BUDGET * 2
	var keys = flows.keys()
	# Bound work and rotate the first flow. A large reliable baseline from one
	# player must not consume every forwarding slot ahead of another's handshake
	# or ENet acknowledgement.
	for offset in keys.size():
		var key = keys[(output_cursor + offset) % keys.size()]
		var flow = flows[key]
		output_backlog_max = maxi(output_backlog_max, flow.socket.get_available_packet_count())
		for index in 8:
			if output_budget <= 0 or flow.socket.get_available_packet_count() == 0: break
			output_budget -= 1
			var bytes = flow.socket.get_packet()
			var record = records(bytes)
			if record.is_empty() or (flow.retiring and not record.alert): continue
			front.set_dest_address(flow.address, flow.port)
			if front.put_packet(bytes) == OK: bytes_sent += bytes.size()
			# An application record emitted by our DTLS engine proves handshake
			# completion. Unverified inbound bytes cannot shorten the idle timeout.
			if record.application: flow.established = true
			if record.alert:
				outbound_alerts += 1
				flow.retiring = true; flow.retire_at = now + 8
				quarantine[key] = now + RETIRED_TUPLE_QUARANTINE_SECONDS
		if (flow.retiring and now >= float(flow.retire_at)) or (not flow.retiring and now - float(flow.last_input) >= (IDLE_SECONDS if flow.established else HANDSHAKE_IDLE_SECONDS)):
			if flow.retiring: expired_retired += 1
			elif flow.established: expired_established += 1
			else: expired_handshakes += 1
			if flow.retiring: quarantine[key] = now + RETIRED_TUPLE_QUARANTINE_SECONDS
			flow.socket.close(); flows.erase(key)
	if not keys.is_empty(): output_cursor = (output_cursor + 1) % keys.size()
	for address in admissions.keys():
		if now - float(admissions[address].at) > 30: admissions.erase(address)

func close() -> void:
	client_socket.close()
	client_mode = false; private_client_port = 0
	for flow in flows.values(): flow.socket.close()
	flows.clear(); quarantine.clear(); admissions.clear(); peer_ports.clear(); front.close(); started = false
