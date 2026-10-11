extends RefCounted
## Every region introduces explicit, readable patterns. No gameplay RNG is used by presentation.

static func fan(w, enemy: Dictionary, count: int, spread: float, speed: float, radius: float = 7.0) -> void:
	for i in count: w.enemy_bullet(enemy.pos, enemy.aim.rotated((i - (count - 1) / 2.0) * spread), speed, enemy.damage, radius, w.source_of(enemy, "projectile"))

static func ring(w, enemy: Dictionary, count: int = 12, speed: float = 155) -> void:
	for i in count:
		var angle = -PI + i * TAU / count
		if absf(angle) > .4: w.enemy_bullet(enemy.pos, enemy.aim.rotated(angle), speed, enemy.damage, 7, w.source_of(enemy, "projectile"))

static func lane(w, from: Vector2, to: Vector2, width: float, warning: float = .8, duration: float = .35, damage: int = 1, source: Dictionary = {}) -> void:
	var anchor = w.geometry.constrain_floor((from + to) * .5, width)
	from = w.geometry.clipped_ray(anchor, from, width)
	to = w.geometry.clipped_ray(anchor, to, width)
	if from.distance_to(to) < 2: return
	var before = w.zones.size()
	w.add_zone((from + to) * .5, width, duration, damage, false, warning, source)
	if w.zones.size() == before: return
	var zone = w.zones[-1]
	zone.shape = "line"
	zone.from = from
	zone.to = to
	zone.width = width
	zone.style = "beam_prism"

static func bead_grid(w, enemy: Dictionary, extra: bool = false) -> void:
	var vertical = int(enemy.get("attack_step", 0)) % 2 == 0
	if vertical:
		var gap = clampi(roundi((enemy.target.x - 128) / 80), 1, 12)
		for i in 14:
			if absi(i - gap) > 1: w.enemy_bullet(Vector2(128 + i * 80, 154), Vector2.DOWN, 155, enemy.damage, 7, w.source_of(enemy, "projectile"))
		if extra: lane(w, Vector2(128, 410), Vector2(1152, 410), 16, .9, .3, enemy.damage, w.source_of(enemy, "zone"))
	else:
		var gap = clampi(roundi((enemy.target.y - 180) / 64), 1, 5)
		for i in 7:
			if absi(i - gap) > 1: w.enemy_bullet(Vector2(104, 180 + i * 64), Vector2.RIGHT, 175, enemy.damage, 7, w.source_of(enemy, "projectile"))
		if extra: lane(w, Vector2(830, 140), Vector2(830, 590), 16, .9, .3, enemy.damage, w.source_of(enemy, "zone"))

static func attack(w, enemy: Dictionary) -> void:
	enemy.attack_step = int(enemy.get("attack_step", 0)) + 1
	var step = int(enemy.attack_step)
	if enemy.get("sigil", false):
		enemy.attack_cd = 8.0
		return
	match enemy.id:
		"e01":
			if enemy.get("elite_id", "") == "x01":
				ring(w, enemy, 10)
				w.delayed.append({"type": "enemy_fan", "time": w.time + .7, "uid": enemy.uid, "count": 5, "spread": .22, "speed": 170.0})
			else: fan(w, enemy, 1, 0, 180)
		"e02", "e13", "e21", "e23":
			enemy.lunge = .45 if enemy.id != "e23" else .65
			if enemy.id == "e13" and step % 2 == 1:
				w.delayed.append({"type": "enemy_lunge", "time": w.time + .8, "uid": enemy.uid})
			if enemy.get("elite_id", "") == "x02": enemy.attack_cd = .55 if step % 3 != 0 else 2.2
			if enemy.id == "e21":
				var desired = enemy.target - enemy.aim * 130
				if w.geometry.valid_circle(desired, enemy.radius): enemy.pos = desired
			if enemy.id == "e23":
				fan(w, enemy, 3, .4, 125)
				if enemy.get("elite_id", "") == "x06": lane(w, enemy.pos, enemy.target, 32, .9, .45, enemy.damage, w.source_of(enemy, "zone"))
		"e03", "e07": fan(w, enemy, 3, .26, 225)
		"e04": fan(w, enemy, 1, 0, 240)
		"e05": w.add_zone(enemy.target, 64, .8, enemy.damage, false, .55, w.source_of(enemy, "zone"))
		"e06":
			fan(w, enemy, 2, .16, 150, 9)
			lane(w, enemy.pos, enemy.target, 14, .75, .3, enemy.damage, w.source_of(enemy, "zone"))
		"e08": w.add_zone(enemy.target, 76, 2.0, enemy.damage, false, .6, w.source_of(enemy, "zone"))
		"e09":
			lane(w, enemy.pos, enemy.pos + enemy.aim * 165, 22, .4, .3, enemy.damage, w.source_of(enemy, "zone"))
			enemy.guard_open = w.time + .55
		"e10": bead_grid(w, enemy, enemy.get("elite_id", "") == "x04")
		"e11": fan(w, enemy, 2, .3, 265)
		"e12":
			fan(w, enemy, 1, 0, 105, 18)
			w.add_zone(enemy.target, 62, .7, enemy.damage, false, .9, w.source_of(enemy, "zone"))
		"e14":
			var before = w.bullets.size()
			w.enemy_bullet(enemy.pos, enemy.aim, 235, enemy.damage, 10, w.source_of(enemy, "projectile"))
			if w.bullets.size() > before: w.bullets[-1].splits_on_wall = true
		"e15": ring(w, enemy)
		"e16":
			if w.enemies.filter(func(e): return not e.dead and not e.boss).size() < 6:
				var position = w.spawn_position(0, 1)
				w.spawn_enemy("e13", position, false, true)
			fan(w, enemy, 3, .18, 180)
			enemy.attack_cd = 3.5
		"e17": lane(w, enemy.pos, enemy.pos + enemy.aim * 230, 19, .6, .25, enemy.damage, w.source_of(enemy, "zone"))
		"e18":
			w.delayed.append({"type": "enemy_fan", "time": w.time + .65, "uid": enemy.uid, "count": 3, "spread": .2, "speed": 210.0, "pos": enemy.pos, "aim": enemy.aim})
		"e19": ring(w, enemy, 10, 145)
		"e20":
			w.add_zone(enemy.target, 80, .5, enemy.damage, false, .8, w.source_of(enemy, "zone"))
			if enemy.get("elite_id", "") == "x05": w.add_zone(enemy.target + Vector2(150, 0), 70, .5, enemy.damage, false, 1.2, w.source_of(enemy, "zone"))
		"e22":
			w.delayed.append({"type": "enemy_fan", "time": w.time + .45, "uid": enemy.uid, "count": 5, "spread": .19, "speed": 200.0})
			fan(w, enemy, 3, .24, 145)
		"e24":
			var direction = w.player.get("last_shot_direction", w.player.aim)
			lane(w, enemy.pos, enemy.pos + direction * 340, 22, .9, .35, enemy.damage, w.source_of(enemy, "zone"))
			w.enemy_bullet(enemy.pos, direction, 230, enemy.damage, 7, w.source_of(enemy, "projectile"))

static func movement(enemy: Dictionary, direction: Vector2, clock: float) -> Vector2:
	if enemy.id in ["e04", "e11"]: return direction.rotated(sin(clock * 5 + enemy.uid) * .65)
	return direction
