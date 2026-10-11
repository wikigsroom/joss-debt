extends RefCounted
## Per-entity timestamp buffers. These copies never participate in combat authority.
var buffers: Dictionary = {}
var current: Dictionary = {}
var clock = 0.0
var clock_ready = false
var delay = .05
var jitter = 0.0
var previous_received = 0.0
var previous_server = 0.0

func clear() -> void:
	buffers.clear(); current.clear(); clock_ready = false
	jitter = 0.0; delay = .05

func observe_clock(server_time: float, received_time: float) -> void:
	if clock_ready:
		var variation = absf((received_time - previous_received) - (server_time - previous_server))
		jitter = lerpf(jitter, minf(.2, variation), .12)
		delay = clampf(.05 + 2 * jitter, .05, .15)
		if absf(clock - server_time) > .4: clock = server_time
		else: clock = lerpf(clock, server_time, .2)
	else: clock = server_time; clock_ready = true
	previous_server = server_time; previous_received = received_time

func advance(delta: float, playing: bool) -> void:
	if clock_ready and playing: clock += delta

func observe(group: String, rows: Array, server_time: float, sequence: int, updated = null) -> void:
	if not buffers.has(group): buffers[group] = {}
	current[group] = rows
	var alive: Dictionary = {}
	var changed: Dictionary = {}
	if updated is Array:
		for uid in updated: changed[int(uid)] = true
	for index in rows.size():
		var entity: Dictionary = rows[index]
		var uid = int(entity.get("uid", index))
		alive[uid] = true
		if updated is Array and not changed.has(uid): continue
		if not buffers[group].has(uid): buffers[group][uid] = []
		var samples: Array = buffers[group][uid]
		if not samples.is_empty() and int(samples[-1].seq) >= sequence: continue
		samples.append({"seq": sequence, "time": server_time, "data": entity.duplicate(false)})
		while samples.size() > 8: samples.pop_front()
	for uid in buffers[group].keys():
		if not uid in alive: buffers[group].erase(uid)

func sample(group: String, interpolate_time: bool = false) -> Array:
	var result: Array = []
	var target = clock - delay
	var history: Dictionary = buffers.get(group, {})
	var rows: Array = current.get(group, [])
	for index in rows.size():
		var entity: Dictionary = rows[index]
		var samples: Array = history.get(int(entity.get("uid", index)), [])
		if samples.is_empty(): result.append(entity.duplicate(false)); continue
		var before: Dictionary = samples[0]
		var after: Dictionary = samples[-1]
		for sample in samples:
			if float(sample.time) <= target: before = sample
			if float(sample.time) >= target: after = sample; break
		var value = entity.duplicate(false)
		var interval = float(after.time) - float(before.time)
		var ratio = clampf((target - float(before.time)) / maxf(.0001, interval), 0, 1)
		for field in ["pos", "aim", "dir"]:
			if before.data.get(field) is Vector2 and after.data.get(field) is Vector2:
				value[field] = Vector2(before.data[field]).lerp(after.data[field], ratio)
		for field in ["age", "windup", "hit_flash"]:
			if before.data.has(field) and after.data.has(field): value[field] = lerpf(float(before.data[field]), float(after.data[field]), ratio)
		if target > float(after.time) and group.ends_with("bullets") and value.get("pos") is Vector2:
			value.pos += Vector2(value.get("dir", Vector2.ZERO)) * float(value.get("speed", 0)) * minf(.1, target - float(after.time))
		if interpolate_time: value._presentation_time = target
		result.append(value)
	return result
