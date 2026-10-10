extends RefCounted
## Assistance changes only an input direction, never damage, RNG, range or visibility.
var locked_uid = -1
var lock_until = 0.0
var context = ""

func clear() -> void:
	locked_uid = -1
	lock_until = 0
	context = ""

func apply(direction: Vector2, origin: Vector2, enemies: Array, geometry, time: float, mode: String, radius: float, room: String, weapon_mode: String = "") -> Vector2:
	if room != context:
		clear()
		context = room
	if mode == "off" or weapon_mode == "controlled" or direction.length() < .01:
		locked_uid = -1
		return direction
	var cone = deg_to_rad(15 if mode == "light" else 45)
	var eligible = enemies.filter(func(enemy): return not enemy.dead and origin.distance_to(enemy.pos) <= radius and absf(direction.angle_to(origin.direction_to(enemy.pos))) <= cone and geometry.clear_segment(origin, enemy.pos) and time >= float(enemy.get("arrival", 0)))
	var target: Dictionary = {}
	if mode == "auto" and time < lock_until:
		for enemy in eligible:
			if enemy.uid == locked_uid: target = enemy; break
	if target.is_empty():
		var best = INF
		for enemy in eligible:
			var aim = origin.direction_to(enemy.pos)
			var angle = absf(direction.angle_to(aim))
			if mode == "light" and angle > deg_to_rad(15): continue
			var score = origin.distance_to(enemy.pos)
			if score < best:
				best = score
				target = enemy
		if not target.is_empty():
			locked_uid = target.uid
			lock_until = time + .25
	if target.is_empty():
		locked_uid = -1
		return direction
	var assisted = origin.direction_to(target.pos)
	return direction.slerp(assisted, .10 if weapon_mode == "ray" else .25).normalized() if mode == "light" else assisted
