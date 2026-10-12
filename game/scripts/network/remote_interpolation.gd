extends RefCounted
## Per-entity timestamp buffers. These copies never participate in combat authority.
const MIN_DELAY = .05
const MAX_DELAY = .22
const MAX_EXTRAPOLATION = .10
const MAX_BUFFERED_SAMPLES = 16
var buffers: Dictionary = {}
var current: Dictionary = {}
var clock = 0.0
var clock_ready = false
var render_time = -1.0
var latest_server_time = 0.0
var delay = MIN_DELAY
var jitter = 0.0
var latency_ms = 0.0
var previous_received = 0.0
var previous_server = 0.0

func clear() -> void:
	buffers.clear(); current.clear(); clock_ready = false
	render_time = -1.0; latest_server_time = 0.0
	jitter = 0.0; latency_ms = 0.0; delay = MIN_DELAY
	previous_received = 0.0; previous_server = 0.0

func observe_clock(server_time: float, received_time: float, round_trip_ms: float = 0.0) -> void:
	if not is_finite(server_time) or not is_finite(received_time): return
	if round_trip_ms > 0 and is_finite(round_trip_ms): latency_ms = clampf(round_trip_ms, 0, 2000)
	if clock_ready:
		var variation = absf((received_time - previous_received) - (server_time - previous_server))
		jitter = lerpf(jitter, minf(.2, variation), .12)
		# Server time is monotonic. A delayed packet can contain an older timestamp;
		# never pull the presentation clock backwards when that happens.
		latest_server_time = maxf(latest_server_time, server_time)
		if server_time > clock:
			if server_time - clock > .4: clock = server_time
			else: clock = maxf(clock, lerpf(clock, server_time, .2))
	else:
		clock = server_time; latest_server_time = server_time; clock_ready = true
	update_delay()
	previous_server = server_time; previous_received = received_time

func update_delay() -> void:
	# One snapshot period plus a small RTT contribution gives the renderer a
	# complete pair of samples on ordinary WAN links without adding input lag to
	# the local prediction path. Smooth changes prevent the render target from
	# jumping when jitter rises or falls.
	var target = clampf(.05 + latency_ms / 4000.0 + 2 * jitter, MIN_DELAY, MAX_DELAY)
	delay = lerpf(delay, target, .18)

func advance(delta: float, playing: bool) -> void:
	if not clock_ready or not playing: return
	clock += delta
	# During a burst loss the clock may advance only a short distance beyond the
	# newest authoritative sample. This bounds extrapolation and avoids a large
	# catch-up teleport when the next packet arrives.
	clock = minf(clock, latest_server_time + MAX_EXTRAPOLATION + delay)

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
		while samples.size() > MAX_BUFFERED_SAMPLES: samples.pop_front()
	for uid in buffers[group].keys():
		if not uid in alive: buffers[group].erase(uid)

func sample(group: String, interpolate_time: bool = false) -> Array:
	var result: Array = []
	var desired = clock - delay
	# A changing delay must never move the rendered timeline backwards. Keeping
	# this monotonic is what removes the visible back-and-forth when one old UDP
	# snapshot arrives after a newer one.
	render_time = desired if render_time < 0 else maxf(render_time, desired)
	var target = render_time
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
		if target > float(after.time) and value.get("pos") is Vector2:
			var seconds = minf(MAX_EXTRAPOLATION, target - float(after.time))
			if group.ends_with("bullets"):
				value.pos += Vector2(value.get("dir", Vector2.ZERO)) * float(value.get("speed", 0)) * seconds
			elif samples.size() >= 2 and (group == "opponent" or group.ends_with("/enemies")):
				var previous: Dictionary = samples[-2]
				var span = float(after.time) - float(previous.time)
				if span > .0001 and previous.data.get("pos") is Vector2:
					var velocity = (Vector2(after.data.pos) - Vector2(previous.data.pos)) / span
					value.pos += velocity * seconds
		if interpolate_time: value._presentation_time = target
		result.append(value)
	return result
