extends RefCounted
const Pattern = preload("res://scripts/combat/enemy_patterns.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")

static func eligible(enemy: Dictionary) -> bool:
	return int(str(enemy.id).substr(1)) >= (6 if enemy.boss else 25)

static func bullet(w, enemy: Dictionary, direction: Vector2, speed: float = 185, radius: float = 7, motion: String = "") -> void:
	var before = w.bullets.size()
	w.enemy_bullet(enemy.pos, direction, speed, int(enemy.damage), radius, w.source_of(enemy, "projectile"))
	if w.bullets.size() > before:
		w.bullets[-1].motion = motion
		w.bullets[-1].base_dir = direction
		w.bullets[-1].style = "jade_needle" if radius < 11 else "lotus_petal"

static func area(w, enemy: Dictionary, point: Vector2, radius: float, warning: float = .85, duration: float = .55) -> void:
	point = w.geometry.constrain_floor(point, minf(radius, 86))
	w.add_zone(point, radius, duration, enemy.damage, false, warning, w.source_of(enemy, "zone"))
	if not w.zones.is_empty(): w.zones[-1].style = "blast_lotus" if enemy.pattern in ["petals", "pulse"] else "blast_ink"

static func execute(w, enemy: Dictionary, family: String) -> void:
	var aim = Vector2(enemy.aim)
	var point = Vector2(enemy.target)
	var phase = int(enemy.phase)
	var step = int(enemy.get("attack_step", 1))
	match family:
		"dart":
			bullet(w, enemy, aim, 310, 5)
		"triple", "fan":
			Pattern.fan(w, enemy, 3 + 2 * int(enemy.boss), .20, 215)
		"spiral", "ledger":
			for i in (14 if enemy.boss else 6):
				var angle = i * TAU / (14 if enemy.boss else 6) + step * .38
				if absf(wrapf(angle - aim.angle(), -PI, PI)) < .28: continue
				bullet(w, enemy, Vector2.RIGHT.rotated(angle), 140 + phase * 20, 7, "spiral")
			if family == "ledger":
				Pattern.lane(w, enemy.pos, enemy.pos + aim * 660, 24, 1.1, .6, enemy.damage, w.source_of(enemy, "zone"))
		"ring", "coins", "orbit":
			Pattern.ring(w, enemy, 14 if enemy.boss else 8, 160)
			if family == "coins": bullet(w, enemy, aim, 240, 13, "accelerate")
		"beam", "lane":
			var end = w.geometry.clipped_ray(enemy.pos, enemy.pos + aim * (740 if enemy.boss else 550))
			Pattern.lane(w, enemy.pos, end, 22 if enemy.boss else 12, .95, .45, enemy.damage, w.source_of(enemy, "zone"))
		"cross":
			for turn in [0, PI * .5]:
				var axis = Vector2.RIGHT.rotated(turn + .22 * (step % 2))
				Pattern.lane(w, enemy.pos - axis * 530, enemy.pos + axis * 530, 22, 1.05, .6, enemy.damage, w.source_of(enemy, "zone"))
		"web", "pull":
			for angle in [-.65, 0, .65] if enemy.boss else [-.32, .32]:
				var axis = aim.rotated(angle)
				Pattern.lane(w, enemy.pos, enemy.pos + axis * 390, 13, .85, .8, enemy.damage, w.source_of(enemy, "zone"))
		"pulse", "stomp":
			area(w, enemy, enemy.pos, 150 if enemy.boss else 86, .8, .35)
		"lob", "rain", "lantern_rain":
			for i in (3 if enemy.boss else 1):
				var offset = Vector2((i - 1) * 142, -30) if enemy.boss else Vector2.ZERO
				area(w, enemy, point + offset, 65 if enemy.boss else 48, .9 + i * .12, .6)
		"ember", "candle", "mine":
			area(w, enemy, point, 77 if enemy.boss else 44, .8, 2.7)
			if enemy.boss: Pattern.fan(w, enemy, 3, .35, 165)
		"ink", "flood", "wake":
			for i in (3 if enemy.boss else 1):
				area(w, enemy, enemy.pos + aim * (110 + i * 140), 59, .7 + i * .18, 2.0)
		"petals":
			for i in (10 if enemy.boss else 5): bullet(w, enemy, aim.rotated((i - 4.5) * .4), 135, 10, "wave")
		"snake":
			for i in (5 if enemy.boss else 2): bullet(w, enemy, aim.rotated((i - 2) * .23), 200, 8, "wave")
		"grid": Pattern.bead_grid(w, enemy)
		"charge", "dash", "hop", "melee", "grab":
			enemy.lunge = .55 if enemy.boss else .3
			if family in ["grab", "melee"]:
				Pattern.lane(w, enemy.pos, enemy.pos + aim * 190, 24, .5, .3, enemy.damage, w.source_of(enemy, "zone"))
		"bounce", "reflect", "split":
			for angle in [-.3, 0, .3]:
				bullet(w, enemy, aim.rotated(angle), 195, 9)
				if not w.bullets.is_empty():
					w.bullets[-1].hostile_bounces = 1 if family in ["bounce", "reflect"] else 0
					w.bullets[-1].splits_on_wall = family == "split"
		"roots":
			for i in 4: area(w, enemy, enemy.pos + Vector2.RIGHT.rotated(i * TAU / 4) * 180, 59, 1.05, 1.4)
		"summon":
			for i in 2 if enemy.boss else 1:
				var id = w.summoned_enemy_id("boss_summon_%d" % int(enemy.uid))
				var added = w.spawn_enemy(id, w.spawn_position(i, 2, "summon_position"), false, true)
				if not added.is_empty(): added.arrival = w.time + 1.0
			Pattern.fan(w, enemy, 3, .3, 145)
		"judgment":
			area(w, enemy, point, 98, 1.1, .7)
			for axis in [Vector2.LEFT, Vector2.RIGHT]:
				Pattern.lane(w, enemy.pos + axis * 120, enemy.pos + axis * 120 + Vector2.DOWN * 330, 22, 1.1, .6, 2, w.source_of(enemy, "zone"))
		"blink":
			var next = w.spawn_position(0, 1, "blink_%d" % int(enemy.uid), enemy.radius)
			w.emit("enemy_blink", {"pos": enemy.pos, "target": next})
			enemy.pos = next
			Pattern.fan(w, enemy, 3, .3, 150)
		_: Pattern.fan(w, enemy, 1, 0, 180)

static func attack(w, enemy: Dictionary) -> void:
	enemy.attack_step = int(enemy.get("attack_step", 0)) + 1
	if enemy.boss:
		var spec = w.db.row("bosses", str(enemy.id))
		var family = str(spec.attack_family) if int(enemy.phase) == 0 or int(enemy.attack_step) % 2 == 0 else str(spec.secondary_family)
		execute(w, enemy, family)
		if int(enemy.phase) == 2 and int(enemy.attack_step) % 3 == 0: execute(w, enemy, str(spec.secondary_family))
		enemy.attack_cd = 2.1 - int(enemy.phase) * .22
		w.emit("boss_attack", {"pos": enemy.pos, "phase": enemy.phase, "boss": enemy.id, "family": family})
	else:
		execute(w, enemy, str(enemy.pattern))
		enemy.attack_cd = 1.6 + w.roll("enemy_timing_%d" % int(enemy.uid)).unit() * .7

static func move(w, enemy: Dictionary, delta: float) -> void:
	var toward = w.geometry.toward(enemy.pos, w.player.pos,enemy.radius)
	var distance = enemy.pos.distance_to(w.player.pos)
	var direction = toward
	var style = str(enemy.get("movement", "chase"))
	var phase = w.time * (1.2 + int(enemy.uid) % 3 * .16) + float(enemy.uid)
	match style:
		"anchor": direction = Vector2(cos(phase * .4), sin(phase * .4)) * .24 if enemy.boss else Vector2.ZERO
		"retreat": direction = -toward if distance < 240 else toward if distance > 390 else toward.orthogonal() * .5
		"strafe": direction = toward.orthogonal() * .8 + toward * clampf((distance - 290) / 170, -.6, .6)
		"orbit": direction = toward.orthogonal() * .8 + toward * clampf((distance - 270) / 170, -.65, .65)
		"serpent", "sine": direction = toward * .55 + toward.orthogonal() * sin(phase) * .8
		"bounce": direction = Vector2(cos(phase * .55), sin(phase * .7))
		"blink": direction = toward.orthogonal() * .5
		"stomp": direction = toward * (.3 if sin(phase) < 0 else .9)
		"procession": direction = toward * .5 + Vector2(cos(phase * .6), sin(phase * .6)) * .6
		"pounce", "chase": direction = toward if distance > (130 if enemy.boss else 80) else -toward * .2
		"hop": direction = toward * (1.3 if fmod(w.time + float(enemy.uid), .9) < .35 else .12)
	for other in w.enemies:
		if not other.dead and other.uid != enemy.uid and enemy.pos.distance_to(other.pos) < enemy.radius + other.radius + 14:
			direction += other.pos.direction_to(enemy.pos) * .7
	var previous = Vector2(enemy.pos)
	enemy.pos = w.geometry.slide(enemy.pos, direction.limit_length() * enemy.speed * delta, enemy.radius)
	enemy.visual_motion = previous.distance_to(enemy.pos) / maxf(.0001, delta)

static func projectile(bullet_data: Dictionary, delta: float) -> void:
	var style = str(bullet_data.get("motion", ""))
	if style == "wave":
		bullet_data.dir = Vector2(bullet_data.get("base_dir", bullet_data.dir)).rotated(sin(bullet_data.age * 7) * .34)
	elif style == "spiral": bullet_data.dir = Vector2(bullet_data.dir).rotated(delta * .75)
	elif style == "accelerate": bullet_data.speed = minf(350, bullet_data.speed + delta * 80)
