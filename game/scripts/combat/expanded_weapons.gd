extends RefCounted
const Geometry = preload("res://scripts/combat/room_geometry.gd")
const Scenery = preload("res://scripts/combat/interactive_scenery.gd")

static func projectile(w, weapon: Dictionary, direction: Vector2, damage: float, crit: bool, origin: Vector2 = Vector2.INF) -> Dictionary:
	if w.bullets.size() >= 240: return {}
	var point = w.player.pos if origin == Vector2.INF else origin
	var bullet = {"uid": w.next_uid(), "pos": w.geometry.constrain_floor(point + direction * 22, 12), "dir": direction.normalized(), "base_dir": direction.normalized(),
		"speed": float(weapon.projectile_speed), "range": float(weapon.range), "travel": 0.0, "damage": damage,
		"radius": 12.0 if weapon.mode in ["cloud", "wave"] else 7.0, "friendly": true, "primary": true,
		"attack": w.attack_uid, "crit": crit, "mode": weapon.mode, "weapon": weapon.id, "pierce": int(weapon.pierce),
		"hits": [], "returning": false, "bounces": 0, "age": 0.0, "target_index": 0,
		"can_return": weapon.mode == "boomerang_arc", "pulse": w.active_pulse, "impact_done": false,
		"push_distance": 30.0, "style": style(str(weapon.mode))}
	w.bullets.append(bullet)
	return bullet

static func style(mode: String) -> String:
	return {"wave": "ink_wave", "split": "paper_blade", "guided_swarm": "paper_blade", "cloud": "smoke_cloud",
		"homing_cluster": "ember_cluster", "rain": "lotus_petal", "mine": "red_seal", "orbit_blade": "lotus_petal",
		"boomerang_arc": "red_seal", "piercing": "paper_blade", "charged_line": "paper_blade", "fan": "paper_blade",
		"controlled": "lotus_petal", "seeker": "ember_cluster", "explosive": "ember_cluster", "ash": "smoke_cloud"}.get(mode, "amber_orb")

static func beam(w, weapon: Dictionary, direction: Vector2, damage: float, crit: bool, width: float = 14) -> void:
	var from = w.geometry.constrain_floor(Vector2(w.player.pos),width)
	var original_end = from + direction * float(weapon.range)
	var end = w.geometry.clipped_ray(from, original_end, width)
	for enemy in w.enemies.duplicate():
		if not enemy.dead and w.geometry.clear_segment(from, enemy.pos) and Geometry.segment_circle(from, end, enemy.pos, enemy.radius + width):
			w.primary_hit(enemy, damage, w.attack_uid, crit, direction, 30)
	Scenery.segment_hit(w, from, end + direction * (width + 4), damage)
	w.emit("ray", {"pos": from, "end": end, "dir": direction, "range": from.distance_to(end), "width": width,
		"weapon": weapon.id, "style": "beam_prism" if weapon.mode == "prism" else ("beam_thread" if weapon.mode == "tether" else "beam_amber"), "heavy": true})

static func execute(w, weapon: Dictionary, damage: float, crit: bool) -> bool:
	if int(str(weapon.id).substr(1)) < 17: return false
	var aim = Vector2(w.player.aim)
	match weapon.mode:
		"prism":
			for angle in [-.23, 0, .23]: beam(w, weapon, aim.rotated(angle), damage, crit, 12)
		"tether":
			beam(w, weapon, aim, damage, crit, 9)
			for enemy in w.enemies:
				if Geometry.segment_circle(w.player.pos, w.player.pos + aim * weapon.range, enemy.pos, 18) and w.geometry.clear_segment(w.player.pos, enemy.pos): enemy.slow_until = w.time + .4
		"lightning":
			var from = Vector2(w.player.pos)
			var hit: Array = []
			for jump in 3:
				var target = w.nearest_enemy(from + (aim * 100 if jump == 0 else Vector2.ZERO), 540 if jump == 0 else 230, hit)
				if target.is_empty() or not w.geometry.clear_segment(from, target.pos): break
				w.primary_hit(target, damage * pow(.8, jump), w.attack_uid, crit)
				w.emit("ray", {"pos": from, "end": target.pos, "dir": from.direction_to(target.pos), "range": from.distance_to(target.pos), "width": 8, "weapon": weapon.id, "style": "beam_prism"})
				hit.append(target.uid)
				from = target.pos
		"nova":
			for i in 3:
				w.delayed.append({"type": "expanded_area", "time": w.time + i * .16, "pos": w.player.pos, "radius": 90 + i * 75,
					"damage": damage / 3, "style": "shockwave", "pulse": w.active_pulse})
		"sweep":
			for enemy in w.enemies.duplicate():
				if enemy.pos.distance_to(w.player.pos) < weapon.range and aim.dot(w.player.pos.direction_to(enemy.pos)) > .05 and w.geometry.clear_segment(w.player.pos, enemy.pos):
					w.primary_hit(enemy, damage, w.attack_uid, crit, aim, 60)
			for object in w.geometry.objects:
				if object.alive and object.pos.distance_to(w.player.pos) < weapon.range and aim.dot(w.player.pos.direction_to(object.pos)) > .05: Scenery.hit(w, object, damage)
			w.emit("slash", {"pos": w.player.pos, "dir": aim, "range": weapon.range, "weapon": weapon.id, "charged": true})
		"radial":
			for i in 8: projectile(w, weapon, aim.rotated(i * TAU / 8), damage, crit)
		"burst":
			projectile(w, weapon, aim, damage, crit)
			for i in [1, 2]:
				w.delayed.append({"type": "expanded_burst", "time": w.time + i * .09, "pos": w.player.pos,
					"dir": aim, "weapon": weapon.id, "damage": damage, "attack": w.attack_uid, "crit": crit, "pulse": w.active_pulse, "last": i == 2})
		_:
			for i in int(weapon.pellets):
				var angle = (i - (weapon.pellets - 1) * .5) * float(weapon.spread)
				var bullet = projectile(w, weapon, aim.rotated(angle), damage, crit)
				if not bullet.is_empty(): bullet.motion = "wave" if weapon.mode == "wave" else ""
	return true

static func impact(w, bullet: Dictionary, point: Vector2) -> void:
	if not bullet.friendly or bullet.get("impact_done", false): return
	bullet.impact_done = true
	var mode = str(bullet.mode)
	if mode in ["explosive", "cloud", "rain", "mine", "homing_cluster"]:
		var radius = 92 if mode == "explosive" else (72 if mode in ["cloud", "rain", "mine"] else 48)
		var delay = .65 if mode == "mine" else 0.0
		for i in (3 if mode == "rain" else 1):
			w.delayed.append({"type": "expanded_area", "time": w.time + delay + i * .28, "pos": point, "radius": radius,
				"damage": bullet.damage * (.5 if mode != "mine" else 1.4), "style": "blast_lotus" if mode == "rain" else "blast_flame", "pulse": bullet.get("pulse", "")})
		if mode in ["cloud", "mine"]:
			w.add_zone(point, radius, 2.5 if mode == "cloud" else .4, bullet.damage * .45, true, delay)
			w.zones[-1].style = "blast_ink" if mode == "cloud" else "blast_flame"
	if mode == "split":
		for angle in [-.75, .75]:
			var fragment = w.secondary_bullet(point, Vector2(bullet.dir).rotated(angle), bullet.damage * .55)
			if not fragment.is_empty(): fragment.style = "paper_blade"

static func tick(w, bullet: Dictionary, delta: float) -> void:
	if bullet.returning: return
	if bullet.mode in ["homing_cluster"] and bullet.age > .12:
		var target = w.nearest_enemy(bullet.pos, 500)
		if not target.is_empty(): bullet.dir = Vector2(bullet.dir).slerp(bullet.pos.direction_to(target.pos), minf(1, delta * 4))
	elif bullet.mode == "guided_swarm": bullet.dir = Vector2(bullet.dir).slerp(w.player.aim, minf(1, delta * 3.5))
	elif bullet.mode == "orbit_blade" and bullet.age < .65:
		bullet.dir = Vector2(bullet.dir).rotated(delta * 4)
	elif bullet.mode == "orbit_blade" and not bullet.get("released", false):
		var target = w.nearest_enemy(bullet.pos, float(bullet.range))
		bullet.dir = bullet.pos.direction_to(target.pos) if not target.is_empty() else Vector2(w.player.aim).normalized()
		bullet.released = true

static func delayed(w, action: Dictionary) -> bool:
	if action.type == "expanded_burst":
		var attack = w.attack_uid
		w.attack_uid = int(action.attack)
		for angle in [-.08, .08] if action.last else [0]: projectile(w, w.db.row("weapons", str(action.weapon)), Vector2(action.dir).rotated(angle), action.damage, action.crit, action.pos)
		w.attack_uid = attack
		w.emit("shot", {"pos": action.pos, "dir": action.dir, "weapon": action.weapon, "mode": "burst"})
		return true
	if action.type == "expanded_area":
		for enemy in w.enemies.duplicate():
			if not enemy.dead and enemy.pos.distance_to(action.pos) < action.radius + enemy.radius and w.geometry.clear_segment(action.pos, enemy.pos): w.damage_enemy(enemy, action.damage, "secondary")
		Scenery.area_hit(w, action.pos, action.radius, action.damage)
		w.emit("burst", {"pos": action.pos, "radius": action.radius, "style": action.style, "heavy": true})
		return true
	return false
