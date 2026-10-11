extends RefCounted
## Bounded native input records. Each frame is one fixed 60 Hz simulation tick.
const Protocol = preload("res://scripts/network/protocol.gd")
const MAGIC = 4
const HEADER = 30
const FRAME_BYTES = 50
const EDGES = ["dash", "skill", "active_item", "interact"]
const FLAGS = ["fire", "dash", "skill", "active_item", "interact", "charge_hold"]

static func encode(message: Dictionary) -> PackedByteArray:
	var frames: Array = message.get("frames", [message.get("frame", {})])
	frames = frames.slice(maxi(0, frames.size() - 6))
	var bytes = PackedByteArray()
	bytes.resize(HEADER + frames.size() * FRAME_BYTES)
	bytes[0] = MAGIC
	var link = str(message.get("link", "")).hex_decode()
	var match_id = str(message.get("match", "")).hex_decode()
	if link.size() != 8 or match_id.size() < 8: return PackedByteArray()
	for i in 8: bytes[1 + i] = link[i]; bytes[9 + i] = match_id[i]
	bytes.encode_u32(17, int(message.get("epoch", 0)))
	bytes.encode_u32(21, int(message.get("scene", 0)))
	bytes.encode_u32(25, int(message.get("lease", 0)))
	bytes[29] = frames.size()
	for index in frames.size():
		var frame: Dictionary = frames[index]
		var offset = HEADER + index * FRAME_BYTES
		bytes.encode_u32(offset, int(frame.get("seq", 0)))
		for v in 3:
			var point = Vector2(frame.get(["move", "aim", "dash_direction"][v], Vector2.ZERO))
			bytes.encode_float(offset + 4 + v * 8, point.x)
			bytes.encode_float(offset + 8 + v * 8, point.y)
		var flags = 64 if frame.get("device") == "touch" else 0
		for bit in FLAGS.size():
			if frame.get(FLAGS[bit], false): flags |= 1 << bit
		bytes.encode_u16(offset + 28, flags)
		for edge in EDGES.size(): bytes.encode_u32(offset + 30 + edge * 4, int(frame.get("actions", {}).get(EDGES[edge], frame.get("seq", 0))))
		bytes.encode_u32(offset + 46, int(frame.get("shot", 0)))
	return bytes

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER or bytes[0] != MAGIC: return {}
	var count = int(bytes[29])
	if count < 1 or count > 6 or bytes.size() != HEADER + count * FRAME_BYTES: return {}
	var result = {"op": "input", "link": bytes.slice(1, 9).hex_encode(), "match_prefix": bytes.slice(9, 17).hex_encode(),
		"epoch": bytes.decode_u32(17), "scene": bytes.decode_u32(21), "lease": bytes.decode_u32(25), "frames": []}
	for index in count:
		var offset = HEADER + index * FRAME_BYTES
		var frame = {"seq": bytes.decode_u32(offset), "actions": {}}
		frame.shot = bytes.decode_u32(offset + 46)
		for v in 3: frame[["move", "aim", "dash_direction"][v]] = Vector2(bytes.decode_float(offset + 4 + v * 8), bytes.decode_float(offset + 8 + v * 8))
		var flags = bytes.decode_u16(offset + 28)
		for bit in FLAGS.size(): frame[FLAGS[bit]] = (flags & (1 << bit)) != 0
		frame.device = "touch" if (flags & 64) != 0 else "keyboard"
		for edge in EDGES.size(): frame.actions[EDGES[edge]] = bytes.decode_u32(offset + 30 + edge * 4)
		var cleaned = Protocol.clean_input(frame)
		if cleaned.is_empty(): return {}
		cleaned.actions = frame.actions
		result.frames.append(cleaned)
	result.frame = result.frames[-1]
	return result
