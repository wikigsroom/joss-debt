extends RefCounted
## Short event feedback with priority and a wall-clock cooldown; pause cancels it.
var enabled = true
var last_at = -1000.0
var last_priority = -1

static func pattern(kind: String) -> Dictionary:
	return {"player_hurt": {"ms": 65, "weak": .18, "strong": .55, "priority": 3},
		"skill": {"ms": 35, "weak": .35, "strong": .18, "priority": 2},
		"deflect": {"ms": 25, "weak": .3, "strong": .25, "priority": 2},
		"dash": {"ms": 15, "weak": .15, "strong": .08, "priority": 1}}.get(kind, {})

func select(events: Array, time: float) -> Dictionary:
	if not enabled: return {}
	var best: Dictionary = {}
	for event in events:
		var value = pattern(str(event.kind))
		if not value.is_empty() and (best.is_empty() or value.priority > best.priority): best = value
	if best.is_empty() or (time - last_at < .10 and best.priority <= last_priority): return {}
	last_at = time
	last_priority = best.priority
	return best

func accept(events: Array, device: String) -> void:
	var request = select(events, Time.get_ticks_msec() / 1000.0)
	if request.is_empty(): return
	if device == "touch" and OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(int(request.ms), maxf(request.weak, request.strong))
	elif device == "controller" and not Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(Input.get_connected_joypads()[0], request.weak, request.strong, request.ms / 1000.0)

func stop() -> void:
	for pad in Input.get_connected_joypads(): Input.stop_joy_vibration(pad)
	last_at = -1000.0
	last_priority = -1
