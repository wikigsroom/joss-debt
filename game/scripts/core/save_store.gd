extends RefCounted
## Two complete generations. A corrupt newest copy cannot destroy the previous one.

var folder: String
var revision: int = 0
const SCHEMA = 2
const NUMBER_ENCODING = "ieee754-f64-v1"
const MAX_BYTES = 8 * 1024 * 1024
var read_only = false
var read_status = "empty"
var legacy_schema = false

func _init(path: String = "user://saves") -> void:
	folder = path
	DirAccess.make_dir_recursive_absolute(folder)
	# A newly opened writer must continue the highest committed generation.
	read()

static func encode(value):
	if value is float and is_finite(value) and absf(value) <= 1e15 and value == floorf(value): return int(value)
	if value is float and is_finite(value):
		# The native decimal parser may change the last bit of a fractional timer.
		# Preserve its actual double bits rather than weakening save comparisons.
		var bits = PackedByteArray()
		bits.resize(8)
		bits.encode_double(0, value)
		return {"__float64": bits.hex_encode()}
	if value is StringName: return str(value)
	if value is Vector2:
		return {"__vector2": [value.x, value.y]}
	if value is Rect2:
		return {"__rect2": [value.position.x, value.position.y, value.size.x, value.size.y]}
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(encode(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = encode(value[key])
		return result
	return value

static func decode(value):
	if value is Dictionary:
		if value.has("__float64"):
			return value.__float64.hex_decode().decode_double(0)
		if value.has("__vector2"):
			return Vector2(value.__vector2[0], value.__vector2[1])
		if value.has("__rect2"):
			return Rect2(value.__rect2[0], value.__rect2[1], value.__rect2[2], value.__rect2[3])
		var result: Dictionary = {}
		for key in value:
			result[key] = decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(decode(item))
		return result
	return value

static func number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 1e15

static func integer(value) -> bool:
	return number(value) and float(value) == floorf(float(value))

static func valid_tree(value, depth: int = 0, budget: Array = [200000]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 48: return false
	if value is Dictionary:
		if value.size() > 8192: return false
		if value.has("__float64"):
			var bits = value.__float64
			if value.size() != 1 or not bits is String or bits.length() != 16: return false
			for c in bits:
				if not c in "0123456789abcdefABCDEF": return false
			return number(bits.hex_decode().decode_double(0))
		for tag in ["__vector2", "__rect2"]:
			if value.has(tag):
				var items = value[tag]
				return value.size() == 1 and items is Array and items.size() == (2 if tag == "__vector2" else 4) and items.all(number)
		for key in value:
			if not (key is String or key is StringName) or str(key).length() > 4096 or not valid_tree(value[key], depth + 1, budget): return false
		return true
	if value is Array:
		if value.size() > 8192: return false
		for item in value:
			if not valid_tree(item, depth + 1, budget): return false
		return true
	if value is Vector2: return number(value.x) and number(value.y)
	if value is Rect2: return valid_tree(value.position, depth + 1, budget) and valid_tree(value.size, depth + 1, budget)
	return value == null or value is bool or number(value) or ((value is String or value is StringName) and str(value).length() <= 1024 * 1024)

static func parse_envelope(text: String) -> Dictionary:
	if text.length() > MAX_BYTES: return {"state": "corrupt"}
	var parser = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {"state": "corrupt"}
	var envelope: Dictionary = parser.data
	if not integer(envelope.get("revision")) or int(envelope.revision) < 1 or not envelope.get("payload") is String: return {"state": "corrupt"}
	var payload: String = envelope.payload
	if payload.sha256_text() != envelope.get("sha256", ""): return {"state": "corrupt"}
	if not integer(envelope.get("schema")) or int(envelope.schema) not in [1, SCHEMA]: return {"state": "unsupported", "revision": int(envelope.revision)}
	if envelope.get("number_encoding", "decimal-json") not in ["decimal-json", NUMBER_ENCODING]: return {"state": "unsupported", "revision": int(envelope.revision)}
	if parser.parse(payload) != OK or not parser.data is Dictionary or not valid_tree(parser.data, 0, [200000]): return {"state": "corrupt"}
	return {"state": "ok", "schema": int(envelope.schema), "revision": int(envelope.revision), "snapshot": decode(parser.data)}

func write(snapshot: Dictionary) -> bool:
	read()
	if read_only or not valid_tree(snapshot, 0, [200000]): return false
	var next_revision = revision + 1
	var payload = JSON.stringify(encode(snapshot), "", true, true)
	var envelope = {"schema": SCHEMA, "number_encoding": NUMBER_ENCODING, "revision": next_revision, "sha256": payload.sha256_text(), "payload": payload}
	var serialized = JSON.stringify(envelope, "", true, true)
	if serialized.to_utf8_buffer().size() > MAX_BYTES: return false
	var target = folder.path_join("checkpoint_%d.json" % (next_revision % 2))
	var temporary = target + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	file.flush()
	file.close()
	if parse_envelope(FileAccess.get_file_as_string(temporary)).get("state") != "ok": return false
	# The opposite generation stays valid throughout this replacement on Windows.
	if FileAccess.file_exists(target):
		if DirAccess.remove_absolute(target) != OK:
			return false
	if DirAccess.rename_absolute(temporary, target) != OK: return false
	revision = next_revision
	read_status = "ok"
	legacy_schema = false
	return true

func read() -> Dictionary:
	var best: Dictionary = {}
	var damaged = false
	read_only = false
	legacy_schema = false
	for slot in 2:
		var path = folder.path_join("checkpoint_%d.json" % slot)
		if not FileAccess.file_exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			damaged = true
			continue
		var candidate = parse_envelope(file.get_as_text())
		if candidate.state == "unsupported": read_only = true
		elif candidate.state != "ok": damaged = true
		elif int(candidate.revision) > int(best.get("revision", 0)): best = candidate
	read_status = "unsupported" if read_only else ("recovered" if damaged and not best.is_empty() else ("corrupt" if damaged else ("empty" if best.is_empty() else "ok")))
	if best.is_empty():
		read_only = read_only or damaged
		return {}
	revision = int(best.revision)
	legacy_schema = int(best.schema) == 1
	return best.snapshot
