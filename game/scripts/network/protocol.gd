extends RefCounted
## Bounded JSON frames: no executable Variant/Object deserialization.
const VERSION = 1
const RULESET = "duel-2"
const PORT = 18777
const TICK_RATE = 60
const SNAPSHOT_RATE = 20
const INPUT_RATE = 30
const HEARTBEAT_SECONDS = 2.0
const SILENCE_SECONDS = 8.0
const INPUT_TIMEOUT = .25
const RECONNECT_SECONDS = 90.0
const MAX_CLIENT_BYTES = 4096
const MAX_SERVER_BYTES = 512 * 1024
const MAX_BULLETS = 240
const Store = preload("res://scripts/core/save_store.gd")
static var content_hash = ""

static func fingerprint() -> String:
	if content_hash.is_empty():
		var context = HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		for path in ["catalog", "rules", "expansion", "equipment", "arena_boundaries"]:
			context.update(FileAccess.get_file_as_bytes("res://data/" + path + ".json"))
		context.update(RULESET.to_utf8_buffer())
		content_hash = context.finish().hex_encode()
	return content_hash

static func encode_tree(value):
	if value is Vector2: return {"__vector2": [value.x, value.y]}
	if value is Rect2: return {"__rect2": [value.position.x, value.position.y, value.size.x, value.size.y]}
	if value is Array:
		var result: Array = []
		for item in value: result.append(encode_tree(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = encode_tree(value[key])
		return result
	return value

static func packet(message: Dictionary, compress: bool = false) -> PackedByteArray:
	if compress:
		# Native Variant values only: this format never permits serialized Objects.
		var native_packet = PackedByteArray([2])
		native_packet.append_array(var_to_bytes(message).compress(FileAccess.COMPRESSION_DEFLATE))
		return native_packet
	var bytes = JSON.stringify(encode_tree(message), "", true, true).to_utf8_buffer()
	var result = PackedByteArray([0])
	result.append_array(bytes)
	return result

static func unpack(bytes: PackedByteArray, from_client: bool = false) -> Dictionary:
	var limit = MAX_CLIENT_BYTES if from_client else MAX_SERVER_BYTES
	if bytes.size() < 3 or bytes.size() > limit or bytes[0] > 2: return {}
	if from_client and bytes[0] != 0: return {}
	var payload = bytes.slice(1)
	if bytes[0] in [1, 2]: payload = payload.decompress_dynamic(MAX_SERVER_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if payload.is_empty() or payload.size() > limit: return {}
	if bytes[0] == 2:
		var native_value = bytes_to_var(payload)
		return native_value if native_value is Dictionary and Store.valid_tree(native_value, 0, [25000]) else {}
	var parser = JSON.new()
	if parser.parse(payload.get_string_from_utf8()) != OK or not parser.data is Dictionary: return {}
	if not Store.valid_tree(parser.data, 0, [25000]): return {}
	return Store.decode(parser.data)

static func valid_code(value) -> bool:
	if not value is String or value.length() != 6: return false
	for digit in value:
		if not digit in "0123456789": return false
	return true

static func nonce(bytes: int = 24) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()

static func clean_name(value) -> String:
	if not value is String: return "还愿人"
	var result = ""
	for character in value:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			result += character
	return result.strip_edges().left(16) if not result.strip_edges().is_empty() else "还愿人"

static func clean_input(value) -> Dictionary:
	if not value is Dictionary or not Store.integer(value.get("seq")) or int(value.seq) < 1 or int(value.seq) > 2147483647: return {}
	for field in ["move", "aim", "dash_direction"]:
		if not value.get(field, Vector2.ZERO) is Vector2 or not value.get(field, Vector2.ZERO).is_finite(): return {}
	for field in ["fire", "dash", "skill", "active_item", "charge_hold"]:
		if not value.get(field, false) is bool: return {}
	return {"seq": int(value.seq), "move": Vector2(value.get("move", Vector2.ZERO)).limit_length(1),
		"aim": Vector2(value.get("aim", Vector2.UP)).normalized(),
		"dash_direction": Vector2(value.get("dash_direction", Vector2.ZERO)).limit_length(1),
		"fire": value.get("fire", false), "dash": value.get("dash", false), "skill": value.get("skill", false),
		"active_item": value.get("active_item", false), "charge_hold": value.get("charge_hold", false),
		"device": "touch" if value.get("device", "") == "touch" else "keyboard"}

static func empty_input() -> Dictionary:
	return {"move": Vector2.ZERO, "aim": Vector2.UP, "fire": false, "dash": false, "skill": false, "active_item": false}

static func configure_socket(peer: WebSocketPeer, server_side: bool = false) -> void:
	peer.inbound_buffer_size = 65536 if server_side else 2 * MAX_SERVER_BYTES
	peer.outbound_buffer_size = 2 * MAX_SERVER_BYTES if server_side else 65536
	peer.max_queued_packets = 16
	peer.heartbeat_interval = HEARTBEAT_SECONDS
