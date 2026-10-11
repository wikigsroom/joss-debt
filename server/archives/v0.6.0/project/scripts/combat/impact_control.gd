extends RefCounted
## Physical impact is integrated by the fixed-tick world, never by the renderer.
const Store = preload("res://scripts/core/save_store.gd")

static func distance(w, source: String, crit: bool = false, weapon_id: String = "") -> float:
	var rules = w.db.rules.combat.control
	if source == "burn": return 0.0
	var weapon = w.db.row("weapons", weapon_id if not weapon_id.is_empty() else w.player.weapon)
	var heavy = source == "detonate" or (source == "primary" and (crit or weapon.mode in ["cone", "arc", "explosive", "charged_line"]))
	var amount = float(rules.heavy_push_distance if heavy else rules.light_push_distance)
	if source == "secondary": amount *= float(rules.secondary_push_scale)
	if source == "primary" and w.stack("r27") > 0 and w.player.still >= .4: amount *= 1.3
	if source == "detonate" and w.player.skill in ["s12", "s15"]: amount = 85.0 if w.player.skill == "s12" else 50.0
	return amount

static func push(w, enemy: Dictionary, direction: Vector2, distance: float) -> void:
	if enemy.dead or w.time < float(enemy.get("arrival", 0)) or enemy.get("sigil", false) or distance <= 0 or not direction.is_finite() or direction.length_squared() < .0001: return
	var rules = w.db.rules.combat.control
	var scale = (1.0 - float(w.db.rules.combat.boss_control_resistance)) if enemy.boss else (float(rules.elite_scale) if enemy.elite else 1.0)
	var step = direction.normalized() * minf(distance, rules.push_distance_cap) * scale
	var remaining: Vector2 = enemy.get("push_remaining", Vector2.ZERO)
	enemy.push_remaining = (remaining + step).limit_length(float(rules.push_distance_cap) * scale)
	enemy.push_left = float(rules.push_duration_s) if enemy.push_remaining.length_squared() > .000001 else 0.0
	w.emit("impact", {"uid": enemy.uid, "pos": enemy.pos, "dir": direction.normalized(), "distance": step.length()})

static func tick(w, enemy: Dictionary, delta: float) -> bool:
	var left = float(enemy.get("push_left", 0))
	if left <= 0: return false
	var portion = 1.0 - pow(maxf(0, left - delta) / left, 2)
	var remaining: Vector2 = enemy.get("push_remaining", Vector2.ZERO)
	var step = remaining * portion
	enemy.pos = w.geometry.slide(enemy.pos, step, enemy.radius)
	enemy.push_remaining = remaining - step
	enemy.push_left = maxf(0.0, left - delta)
	if enemy.push_left <= .000001:
		enemy.push_left = 0.0
		enemy.push_remaining = Vector2.ZERO
	return true

static func root(w, enemy: Dictionary, duration: float) -> void:
	if enemy.dead or enemy.boss or w.time < float(enemy.get("arrival", 0)): return
	var rules = w.db.rules.combat.control
	var cap = float(rules.elite_root_cap_s if enemy.elite else rules.ordinary_root_cap_s)
	enemy.stun_until = maxf(enemy.stun_until, w.time + clampf(duration, 0, cap))

static func valid_state(enemy: Dictionary, rules: Dictionary) -> bool:
	if not enemy.has("push_left") and not enemy.has("push_remaining"): return true
	if not Store.number(enemy.get("push_left")) or not enemy.get("push_remaining") is Vector2: return false
	var remaining: Vector2 = enemy.push_remaining
	return remaining.is_finite() and enemy.push_left >= 0 and enemy.push_left <= float(rules.push_duration_s) + .00001 and remaining.length() <= float(rules.push_distance_cap) + .0001 and (enemy.push_left > 0 or remaining.is_zero_approx())
