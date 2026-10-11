extends RefCounted
## Independent absolute entity records; only metadata uses reliable reassembly.
const Protocol = preload("res://scripts/network/protocol.gd")
const MAGIC = 3
const HEADER = 22
const MAX_PACKET = 1000
const MAX_PARTS = 1024
const DYNAMIC = ["tick", "remaining", "countdown", "draft_remaining", "grace_left", "input_ack", "input_floor", "input_epoch", "action_ack", "state_seq", "lease", "event_serial"]
const ACTOR_DYNAMIC = ["player", "time", "chains", "room_flags", "stats"]
const COLLECTIONS = ["enemies", "bullets", "zones", "pickups", "delayed"]
var link = ""
var revision = 0
var scene_revision = 0
var metadata_bytes = PackedByteArray()
var schemas: Dictionary = {}
var metadata: Dictionary = {}
var view: Dictionary = {}
var entities: Dictionary = {}
var inventories: Dictionary = {}
var entity_sequences: Dictionary = {}
var auxiliary: Dictionary = {}
var auxiliary_sequences: Dictionary = {}
var scene_ready = false
var parts: Dictionary = {}
var part_revision = 0
var core_sequence = 0
var pending_core = PackedByteArray()
var rejected = 0
var rejected_baselines = 0
var baseline_packets = 0
var dynamic_packets = 0
var fragments: Dictionary = {}
var sent_metadata: Dictionary = {}
var bullet_definitions: Dictionary = {}
var bullet_definition_sequences: Dictionary = {}
var bullet_transforms: Dictionary = {}
var pending_definition_packets: Array = []
var pending_definition_bytes = 0
const BULLET_FIELDS = ["uid", "pos", "dir", "speed", "age", "travel", "returning"]
const BULLET_RECORD = 19

func append_dynamic(result: Array, bytes: PackedByteArray, reliable: bool = false) -> void:
	if bytes.size() <= MAX_PACKET:
		result.append({"reliable": reliable, "bytes": bytes})
		return
	# Oversized auxiliary or single-entity state stays independent of every other
	# entity. A missing fragment is repaired by the next absolute update.
	var body = bytes.slice(HEADER)
	var capacity = MAX_PACKET - HEADER - 9
	var count = ceili(float(body.size()) / capacity)
	if count > 36: return
	var identity = hash(body) & 0xffffffff
	for index in count:
		var fragment = PackedByteArray(); fragment.resize(9)
		fragment[0] = bytes[1]
		fragment.encode_u32(1, identity)
		fragment.encode_u16(5, index); fragment.encode_u16(7, count)
		fragment.append_array(body.slice(index * capacity, (index + 1) * capacity))
		result.append({"reliable": reliable, "bytes": packet(7, bytes.decode_u32(14), bytes.decode_u32(18), fragment)})

func append_definitions(result: Array, group: String, rows: Array, sequence: int, lease: int) -> void:
	if rows.is_empty(): return
	var value = {"group": group, "definitions": rows}
	var bytes = compressed(9, sequence, lease, value)
	if (bytes.size() > MAX_PACKET or var_to_bytes(value).size() > 24000) and rows.size() > 1:
		var middle = rows.size() >> 1
		append_definitions(result, group, rows.slice(0, middle), sequence, lease)
		append_definitions(result, group, rows.slice(middle), sequence, lease)
	else: append_dynamic(result, bytes, true)

func encode_bullets(result: Array, group: String, rows: Array, sequence: int, lease: int) -> Array:
	if not bullet_definitions.has(group): bullet_definitions[group] = {}
	var definitions: Array = []; var ids: Array = []
	var group_index = schemas.keys().find(group)
	var capacity = (MAX_PACKET - HEADER - 3) / BULLET_RECORD
	for start in range(0, rows.size(), capacity):
		var count = mini(capacity, rows.size() - start)
		var body = PackedByteArray(); body.resize(3 + count * BULLET_RECORD)
		body[0] = group_index; body.encode_u16(1, count)
		for i in count:
			var entity: Dictionary = rows[start + i]
			var uid = int(entity.uid); ids.append(uid)
			var base = entity.duplicate(false)
			for key in BULLET_FIELDS + ["recipe", "hits", "pulse", "attack"]: base.erase(key)
			if base != bullet_definitions[group].get(uid):
				bullet_definitions[group][uid] = base.duplicate(true)
				definitions.append({"uid": uid, "fields": base})
			var offset = 3 + i * BULLET_RECORD
			body.encode_u32(offset, uid)
			# Room coordinates are 1280x720. Presentation precision is 1/8 pixel;
			# direction and speed quantization never enter authoritative physics.
			body.encode_s16(offset + 4, clampi(roundi(entity.pos.x * 8), -32768, 32767))
			body.encode_s16(offset + 6, clampi(roundi(entity.pos.y * 8), -32768, 32767))
			body.encode_u16(offset + 8, roundi(fposmod(Vector2(entity.dir).angle(), TAU) / TAU * 65535))
			body.encode_u16(offset + 10, clampi(roundi(float(entity.get("speed", 0)) * 4), 0, 65535))
			body.encode_float(offset + 12, float(entity.get("age", 0)))
			body.encode_u16(offset + 16, clampi(roundi(float(entity.get("travel", 0)) * 4), 0, 65535))
			body[offset + 18] = int(entity.get("returning", false)) | (2 if Vector2(entity.dir).is_zero_approx() else 0)
		result.append({"reliable": false, "bytes": packet(8, sequence, lease, body)})
	append_definitions(result, group, definitions, sequence, lease)
	for uid in bullet_definitions[group].keys():
		if not uid in ids: bullet_definitions[group].erase(uid)
	return ids

func append_rows(result: Array, group: String, rows: Array, sequence: int, lease: int) -> void:
	if rows.is_empty(): return
	var bytes = compressed(3, sequence, lease, {"group": group, "rows": rows})
	if bytes.size() > MAX_PACKET and rows.size() > 1:
		var middle = rows.size() >> 1
		append_rows(result, group, rows.slice(0, middle), sequence, lease)
		append_rows(result, group, rows.slice(middle), sequence, lease)
	else: append_dynamic(result, bytes)

func _init(connection_link: String = "") -> void:
	link = connection_link

func collections(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if state.has("scene"):
		for name in COLLECTIONS: result["scene/" + name] = state.scene.get(name, [])
		return result # cooperative entities are shared, never duplicate per actor
	for seat in state.get("actors", []).size():
		for name in ["bullets", "zones", "enemies", "delayed"]:
			result["actors/%d/%s" % [seat, name]] = state.actors[seat].get(name, [])
	return result

func packet(kind: int, sequence: int, lease: int, payload: PackedByteArray, rev: int = -1) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(HEADER)
	bytes[0] = MAGIC
	bytes[1] = kind
	var identity = link.hex_decode()
	if identity.size() == 8:
		for i in 8: bytes[2 + i] = identity[i]
	bytes.encode_u32(10, (revision if kind == 1 else scene_revision) if rev < 0 else rev)
	bytes.encode_u32(14, sequence)
	bytes.encode_u32(18, lease)
	bytes.append_array(payload)
	return bytes

func compressed(kind: int, sequence: int, lease: int, value: Dictionary) -> PackedByteArray:
	return packet(kind, sequence, lease, var_to_bytes(value).compress(FileAccess.COMPRESSION_DEFLATE))

func encode(state: Dictionary) -> Array:
	var groups = collections(state)
	for name in groups:
		if not schemas.has(name): schemas[name] = []
		for entity in groups[name]:
			for field in entity:
				if not field in schemas[name]: schemas[name].append(field)
	var meta = state.duplicate(false)
	for key in DYNAMIC + ["events"]: meta.erase(key)
	meta.actors = []
	for actor in state.get("actors", []):
		var base = actor.duplicate(false)
		for key in ACTOR_DYNAMIC + COLLECTIONS: base.erase(key)
		for key in ["bullets", "zones", "enemies", "delayed"]: base[key] = []
		meta.actors.append(base)
	if state.has("scene"):
		meta.scene = state.scene.duplicate(false)
		for key in COLLECTIONS + ["flags", "rescue"]: meta.scene.erase(key)
	meta.schemas = schemas
	if sent_metadata.is_empty() or meta.get("id") != sent_metadata.get("id") or meta.get("input_scene") != sent_metadata.get("input_scene"):
		scene_revision += 1
		bullet_definitions.clear()
	meta.stream_scene_revision = scene_revision
	var result: Array = []
	var sequence = int(state.state_seq)
	var lease = int(state.lease)
	if meta != sent_metadata:
		sent_metadata = meta.duplicate(true)
		var encoded_metadata = var_to_bytes(meta)
		metadata_bytes = encoded_metadata
		revision += 1
		var zipped = encoded_metadata.compress(FileAccess.COMPRESSION_DEFLATE)
		var capacity = MAX_PACKET - HEADER - 4
		var count = ceili(float(zipped.size()) / capacity)
		for index in count:
			var fragment = PackedByteArray()
			fragment.resize(4)
			fragment.encode_u16(0, index)
			fragment.encode_u16(2, count)
			fragment.append_array(zipped.slice(index * capacity, (index + 1) * capacity))
			result.append({"reliable": true, "bytes": packet(1, sequence, lease, fragment)})
		baseline_packets += count
	var core: Dictionary = {}
	for key in DYNAMIC:
		if state.has(key): core[key] = state[key]
	core.actors = []
	for actor in state.get("actors", []):
		var dynamic: Dictionary = {}
		for key in ["player", "time"]:
			if actor.has(key): dynamic[key] = actor[key]
		core.actors.append(dynamic)
	if state.has("scene"): core.scene = {"rescue": state.scene.rescue}
	append_dynamic(result, compressed(2, sequence, lease, core))
	for seat in state.get("actors", []).size():
		var fields: Dictionary = {}
		for field in ["chains", "room_flags", "stats"]: fields[field] = state.actors[seat].get(field, {})
		append_dynamic(result, compressed(6, sequence, lease, {"path": "actors/%d" % seat, "fields": fields}))
	if state.has("scene"):
		append_dynamic(result, compressed(6, sequence, lease, {"path": "scene", "fields": {"flags": state.scene.flags}}))
	for name in groups:
		var ids: Array = []
		if name.ends_with("bullets"):
			ids = encode_bullets(result, name, groups[name], sequence, lease)
			append_dynamic(result, compressed(4, sequence, lease, {"group": name, "alive": ids}))
			continue
		var batch: Array = []
		var batch_bytes = 0
		for index in groups[name].size():
			var entity: Dictionary = groups[name][index]
			var uid = int(entity.get("uid", index))
			ids.append(uid)
			var indices: Array = []
			var values: Array = []
			for field in entity:
				indices.append(schemas[name].find(field))
				values.append(entity[field])
			var row = [uid, values] if indices.size() == schemas[name].size() and indices == range(schemas[name].size()) else [uid, indices, values]
			var size = var_to_bytes(row).size()
			if batch_bytes + size > 8192 and not batch.is_empty():
				append_rows(result, name, batch, sequence, lease)
				batch = []
				batch_bytes = 0
			batch.append(row)
			batch_bytes += size
		append_rows(result, name, batch, sequence, lease)
		append_dynamic(result, compressed(4, sequence, lease, {"group": name, "alive": ids}))
	# Visual/audio events remain lossy and repeat until the client's cumulative
	# event receipt; damage, growth and results remain in authoritative state.
	for event in state.get("events", []):
		result.append({"reliable": false, "bytes": compressed(5, sequence, lease, {"event": event})})
	for item in result:
		if not item.reliable: dynamic_packets += 1
	return result

func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= HEADER or bytes.size() > MAX_PACKET or bytes[0] != MAGIC or bytes.slice(2, 10).hex_encode() != link:
		rejected += 1
		return {}
	var kind = int(bytes[1])
	var rev = bytes.decode_u32(10)
	var sequence = bytes.decode_u32(14)
	var lease = bytes.decode_u32(18)
	var definition = kind == 9 or (kind == 7 and bytes.size() > HEADER and bytes[HEADER] == 9)
	if definition and rev > scene_revision:
		# Definitions use an independent reliable channel and may precede the
		# scene's metadata. Retain bounded ciphertext-decoded application packets
		# until their scene exists; never acknowledge and silently lose the spawn.
		while not pending_definition_packets.is_empty() and (pending_definition_packets.size() >= 256 or pending_definition_bytes + bytes.size() > 262144):
			pending_definition_bytes -= pending_definition_packets.pop_front().size()
		pending_definition_packets.append(bytes); pending_definition_bytes += bytes.size()
		return {}
	if kind == 7:
		if bytes.size() < HEADER + 10 or rev != scene_revision: return {}
		var original = int(bytes[HEADER])
		var identity = bytes.decode_u32(HEADER + 1)
		var index = bytes.decode_u16(HEADER + 5)
		var count = bytes.decode_u16(HEADER + 7)
		if original not in [2, 3, 4, 6, 9] or count < 2 or count > 36 or index >= count: return {}
		var key = "%d/%d/%d/%d" % [rev, sequence, original, identity]
		if not fragments.has(key):
			while fragments.size() >= 64: fragments.erase(fragments.keys()[0])
			fragments[key] = {"parts": {}, "count": count}
		var assembly: Dictionary = fragments[key]
		if int(assembly.count) != count: return {}
		assembly.parts[index] = bytes.slice(HEADER + 9)
		if assembly.parts.size() != count: return {}
		var joined = PackedByteArray()
		for i in count: joined.append_array(assembly.parts[i])
		fragments.erase(key)
		if joined.size() > 32768 or (hash(joined) & 0xffffffff) != identity: return {}
		return decode_message(packet(original, sequence, lease, joined, rev))
	return decode_message(bytes)

func decode_message(bytes: PackedByteArray) -> Dictionary:
	var kind = int(bytes[1])
	var rev = bytes.decode_u32(10)
	var sequence = bytes.decode_u32(14)
	var lease = bytes.decode_u32(18)
	if kind == 1:
		if bytes.size() < HEADER + 5 or rev < revision: return {}
		var index = bytes.decode_u16(HEADER)
		var count = bytes.decode_u16(HEADER + 2)
		if count < 1 or count > MAX_PARTS or index >= count: return {}
		if rev != part_revision: parts.clear(); part_revision = rev
		parts[index] = bytes.slice(HEADER + 4)
		if parts.size() != count: return {}
		var joined = PackedByteArray()
		for i in count:
			if not parts.has(i): return {}
			joined.append_array(parts[i])
			if joined.size() > Protocol.MAX_SERVER_BYTES: parts.clear(); return {}
		parts.clear()
		var decoded = joined.decompress_dynamic(Protocol.MAX_SERVER_BYTES, FileAccess.COMPRESSION_DEFLATE)
		var candidate = bytes_to_var(decoded) if not decoded.is_empty() else null
		if not candidate is Dictionary or not Protocol.Store.valid_tree(candidate, 0, [25000]):
			rejected_baselines += 1
			return {}
		var changed_scene = candidate.get("id") != metadata.get("id") or candidate.get("input_scene") != metadata.get("input_scene")
		metadata = candidate
		scene_revision = int(metadata.get("stream_scene_revision", 0))
		metadata.erase("stream_scene_revision")
		schemas = metadata.get("schemas", {})
		metadata.erase("schemas")
		revision = rev
		if changed_scene:
			entities.clear(); inventories.clear(); entity_sequences.clear()
			auxiliary.clear(); auxiliary_sequences.clear(); scene_ready = false
			fragments.clear()
			bullet_definitions.clear(); bullet_definition_sequences.clear(); bullet_transforms.clear()
		view = metadata.duplicate(true)
		for name in schemas: set_collection(name)
		var definitions = pending_definition_packets; pending_definition_packets = []; pending_definition_bytes = 0
		for buffered_definition in definitions:
			if buffered_definition.decode_u32(10) >= scene_revision: decode(buffered_definition)
		var result = {"kind": "baseline"}
		if not pending_core.is_empty():
			var buffered = pending_core
			pending_core = PackedByteArray()
			result = decode(buffered)
		return result
	if rev != scene_revision:
		if kind == 2 and rev > scene_revision: pending_core = bytes
		return {}
	if kind == 8:
		if bytes.size() < HEADER + 3: return {}
		var group_index = int(bytes[HEADER])
		var count = bytes.decode_u16(HEADER + 1)
		if group_index >= schemas.size() or count < 1 or bytes.size() != HEADER + 3 + count * BULLET_RECORD: return {}
		var group: String = schemas.keys()[group_index]
		if not group.ends_with("bullets"): return {}
		if not entities.has(group): entities[group] = {}; entity_sequences[group] = {}
		if not bullet_transforms.has(group): bullet_transforms[group] = {}
		var updated: Array = []
		for i in count:
			var offset = HEADER + 3 + i * BULLET_RECORD
			var uid = int(bytes.decode_u32(offset))
			if sequence <= int(entity_sequences[group].get(uid, 0)): continue
			var inventory = inventories.get(group, {})
			if int(inventory.get("seq", 0)) >= sequence and not uid in inventory.get("alive", []): continue
			var direction = Vector2.RIGHT.rotated(bytes.decode_u16(offset + 8) * TAU / 65535.0)
			var value = {"uid": uid, "pos": Vector2(bytes.decode_s16(offset + 4), bytes.decode_s16(offset + 6)) / 8.0,
				"dir": Vector2.ZERO if bytes[offset + 18] & 2 else direction, "speed": bytes.decode_u16(offset + 10) / 4.0,
				"age": bytes.decode_float(offset + 12), "travel": bytes.decode_u16(offset + 16) / 4.0, "returning": (bytes[offset + 18] & 1) != 0}
			if not is_finite(float(value.age)): return {}
			bullet_transforms[group][uid] = value
			entity_sequences[group][uid] = sequence
			if bullet_definitions.get(group, {}).has(uid):
				var entity: Dictionary = bullet_definitions[group][uid].duplicate(false)
				entity.merge(value, true); entities[group][uid] = entity; updated.append(uid)
		set_collection(group); check_scene_ready()
		return {"kind": "entities", "group": group, "sequence": sequence, "lease": lease, "updated": updated}
	var payload = bytes.slice(HEADER).decompress_dynamic(32768, FileAccess.COMPRESSION_DEFLATE)
	var data = bytes_to_var(payload) if not payload.is_empty() else null
	if not data is Dictionary or not Protocol.Store.valid_tree(data, 0, [6000]): return {}
	match kind:
		9:
			var group = str(data.get("group", ""))
			if not schemas.has(group) or not group.ends_with("bullets"): return {}
			if not entities.has(group): entities[group] = {}; entity_sequences[group] = {}
			if not bullet_definitions.has(group): bullet_definitions[group] = {}; bullet_definition_sequences[group] = {}
			var updated: Array = []
			for row in data.get("definitions", []):
				if not row is Dictionary or not row.get("fields") is Dictionary or not Protocol.Store.integer(row.get("uid")): return {}
				var uid = int(row.uid)
				if sequence <= int(bullet_definition_sequences[group].get(uid, 0)): continue
				var inventory = inventories.get(group, {})
				if int(inventory.get("seq", 0)) >= sequence and not uid in inventory.get("alive", []): continue
				bullet_definition_sequences[group][uid] = sequence
				bullet_definitions[group][uid] = row.fields
				if bullet_transforms.get(group, {}).has(uid):
					var entity: Dictionary = row.fields.duplicate(false)
					entity.merge(bullet_transforms[group][uid], true)
					entities[group][uid] = entity; updated.append(uid)
			set_collection(group); check_scene_ready()
			return {"kind": "entities", "group": group, "sequence": sequence, "lease": lease, "updated": updated}
		2:
			if sequence <= core_sequence: return {}
			core_sequence = sequence
			view.merge(data, true)
			view.actors = []
			for seat in metadata.get("actors", []).size():
				var actor = metadata.actors[seat].duplicate(false)
				actor.merge(data.actors[seat], true)
				actor.merge(auxiliary.get("actors/%d" % seat, {"chains": [], "room_flags": {}, "stats": {}}), true)
				view.actors.append(actor)
			if metadata.has("scene"):
				view.scene = metadata.scene.duplicate(false)
				view.scene.merge(data.get("scene", {}), true)
				view.scene.merge(auxiliary.get("scene", {"flags": {}}), true)
			for name in schemas: set_collection(name)
			view.events = []
			view.link = link
			view.state_seq = sequence
			view.baseline_revision = revision
			view.lease = lease
			return {"kind": "state", "view": view}
		3, 4:
			var group = str(data.get("group", ""))
			var updated: Array = []
			if not schemas.has(group): return {}
			if not entities.has(group): entities[group] = {}; entity_sequences[group] = {}
			if kind == 4:
				if sequence <= int(inventories.get(group, {}).get("seq", 0)): return {}
				inventories[group] = {"seq": sequence, "alive": Array(data.get("alive", []))}
				for uid in entities[group].keys():
					if not uid in inventories[group].alive and int(entity_sequences[group][uid]) <= sequence:
						entities[group].erase(uid); entity_sequences[group].erase(uid)
				if group.ends_with("bullets"):
					for uid in entity_sequences[group].keys():
						if not uid in inventories[group].alive and int(entity_sequences[group][uid]) <= sequence: entity_sequences[group].erase(uid)
					for cache in [bullet_definitions.get(group, {}), bullet_transforms.get(group, {}), bullet_definition_sequences.get(group, {})]:
						for uid in cache.keys():
							if not uid in inventories[group].alive and int(entity_sequences[group].get(uid, 0)) <= sequence: cache.erase(uid)
			else:
				for row in data.get("rows", []):
					if not row is Array or row.size() not in [2, 3]: return {}
					var indices = range(schemas[group].size()) if row.size() == 2 else row[1]
					var values = row[1] if row.size() == 2 else row[2]
					if not indices is Array or not values is Array or indices.size() != values.size(): return {}
					var uid = int(row[0])
					if sequence <= int(entity_sequences[group].get(uid, 0)): continue
					var inventory = inventories.get(group, {})
					if int(inventory.get("seq", 0)) >= sequence and not uid in inventory.get("alive", []): continue
					var entity: Dictionary = {}
					for i in indices.size():
						var column = int(indices[i])
						if column < 0 or column >= schemas[group].size(): return {}
						entity[schemas[group][column]] = values[i]
					entities[group][uid] = entity
					entity_sequences[group][uid] = sequence
					updated.append(uid)
			set_collection(group)
			check_scene_ready()
			return {"kind": "entities", "group": group, "sequence": sequence, "lease": lease, "updated": updated}
		5:
			return {"kind": "event", "event": data.get("event", {})}
		6:
			var path = str(data.get("path", ""))
			if path not in ["scene", "actors/0", "actors/1"] or not data.get("fields") is Dictionary: return {}
			if sequence <= int(auxiliary_sequences.get(path, 0)): return {}
			auxiliary[path] = data.fields
			auxiliary_sequences[path] = sequence
			if path == "scene" and view.has("scene"): view.scene.merge(data.fields, true)
			elif path != "scene" and view.get("actors", []).size() == 2: view.actors[int(path.get_slice("/", 1))].merge(data.fields, true)
			return {"kind": "aux", "path": path, "fields": data.fields}
	return {}

func set_collection(group: String) -> void:
	var rows: Array = []
	var source: Dictionary = entities.get(group, {})
	var inventory = inventories.get(group, {})
	for uid in inventory.get("alive", source.keys()):
		if source.has(uid): rows.append(source[uid])
	var path = group.split("/")
	if path[0] == "scene" and view.has("scene"): view.scene[path[1]] = rows
	elif path[0] == "actors" and int(path[1]) < view.get("actors", []).size(): view.actors[int(path[1])][path[2]] = rows

func check_scene_ready() -> void:
	if scene_ready: return
	for group in schemas:
		if not inventories.has(group): return
		for uid in inventories[group].alive:
			if not entities.get(group, {}).has(uid): return
	scene_ready = true
