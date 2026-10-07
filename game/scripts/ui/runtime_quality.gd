extends RefCounted
## Presentation-only quality governor. It never changes World state, RNG or save data.

const AUTO = "auto"
const HIGH = "high"
const BATTERY = "battery"
const LOW_PARTICLE_SCALE = .55
const LOW_EFFECT_LIMIT = 72
const FULL_PARTICLE_SCALE = 1.0
const FULL_EFFECT_LIMIT = 120

var mode = AUTO
var mobile = false
var frame_ema_ms = 16.7
var low_time = 0.0
var recovery_time = 0.0
var target_particle_scale = FULL_PARTICLE_SCALE
var target_effect_limit = FULL_EFFECT_LIMIT
var particle_scale = FULL_PARTICLE_SCALE
var effect_limit = FULL_EFFECT_LIMIT
var last_profile = "full"

func set_mode(value: String, is_mobile: bool) -> void:
	var normalized = value if value in [AUTO, HIGH, BATTERY] else AUTO
	if normalized == mode and is_mobile == mobile:
		return
	mode = normalized
	mobile = is_mobile
	frame_ema_ms = 16.7
	low_time = 0.0
	recovery_time = 0.0
	if mode == BATTERY and mobile:
		set_profile(LOW_PARTICLE_SCALE, LOW_EFFECT_LIMIT, "battery")
	else:
		set_profile(FULL_PARTICLE_SCALE, FULL_EFFECT_LIMIT, "full")

func sample(delta: float, active: bool = true) -> bool:
	var before_scale = particle_scale
	var before_limit = effect_limit
	var step = maxf(0.0, delta)
	if step <= 0.0:
		return false
	if active:
		var frame_ms = clampf(step * 1000.0, 1.0, 100.0)
		frame_ema_ms = lerpf(frame_ema_ms, frame_ms, .12)
		if mode == AUTO and mobile:
			if frame_ema_ms >= 27.0:
				low_time += step
				recovery_time = maxf(0.0, recovery_time - step * .5)
			elif frame_ema_ms <= 18.0:
				recovery_time += step
				low_time = maxf(0.0, low_time - step * .25)
			else:
				low_time = maxf(0.0, low_time - step * .2)
				recovery_time = maxf(0.0, recovery_time - step * .2)
			if low_time >= 1.4:
				set_profile(LOW_PARTICLE_SCALE, LOW_EFFECT_LIMIT, "auto-low")
			elif recovery_time >= 5.0:
				set_profile(FULL_PARTICLE_SCALE, FULL_EFFECT_LIMIT, "auto-recovered")
	if mode == HIGH or not mobile:
		set_profile(FULL_PARTICLE_SCALE, FULL_EFFECT_LIMIT, "full")
	elif mode == BATTERY:
		set_profile(LOW_PARTICLE_SCALE, LOW_EFFECT_LIMIT, "battery")
	particle_scale = move_toward(particle_scale, target_particle_scale, step * 1.8)
	effect_limit = roundi(move_toward(float(effect_limit), float(target_effect_limit), step * 220.0))
	return not is_equal_approx(before_scale, particle_scale) or before_limit != effect_limit

func set_profile(scale: float, limit: int, label: String) -> void:
	target_particle_scale = clampf(scale, .35, 1.0)
	target_effect_limit = clampi(limit, 24, FULL_EFFECT_LIMIT)
	last_profile = label

func status() -> Dictionary:
	return {"mode": mode, "mobile": mobile, "frame_ema_ms": frame_ema_ms,
		"particle_scale": particle_scale, "effect_limit": effect_limit,
		"target_particle_scale": target_particle_scale, "target_effect_limit": target_effect_limit,
		"profile": last_profile}
