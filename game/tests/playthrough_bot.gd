extends RefCounted
const Geometry = preload("res://scripts/combat/room_geometry.gd")
static var navigation = Geometry.new()
static var navigation_key = ""
static var target_cell = Vector2i(-100, -100)
static var actor_key = ""
static var last_hit_count = 0
static var last_damage_at = 0.0
static var navigate_until = 0.0

static func choose(w, evolution: int, focus_route: String = "") -> int:
	if w.choices.is_empty(): return -1
	if w.choices[0].kind == "skill": return mini(evolution, w.choices.size() - 1)
	var priority = ["r01", "r09", "r26", "r02", "r43", "r41", "r18", "r27", "r11", "r33", "r35", "r17",
		"t_fire_1a", "t_thread_1a", "t_seal_1a", "t_ash_1a", "t_seal_1b", "t_fire_2b", "t_fire_3a", "t_thread_3a", "t_ink_1a"]
	var character = w.db.row("characters", w.run.character)
	var routes: Array = character.get("routes", [])
	var best = 0
	var score = -INF
	for i in w.choices.size():
		var item = w.choices[i]
		var value = 0.0
		var id = str(item.get("id", ""))
		var rank = priority.find(id)
		if rank >= 0: value += 50.0 - rank
		if item.kind == "relic":
			var relic = w.db.row("relics", id)
			for route in relic.get("routes", []):
				if routes.has(route): value += 90.0
				else: value -= 8.0
				if not focus_route.is_empty() and route == focus_route: value += 130.0
			# Keep a small defensive floor so fragile characters get a real
			# survival option when the offer contains one.
			if id in ["r26", "r29", "r32"]: value += 34.0
			elif id in ["r33", "r34", "r36", "r38"]: value += 18.0
			elif id in ["r17", "r19", "r21", "r22", "r24"]: value += 12.0
			elif id in ["r46", "r49", "r52", "r53", "r54"]: value += 10.0
		elif item.kind == "talent":
			var talent = w.db.row("talents", id)
			if routes.has(talent.get("route", "")): value += 86.0
			if not focus_route.is_empty() and talent.get("route", "") == focus_route: value += 130.0
			if id in ["t_seal_1a", "t_seal_1b", "t_ash_2b", "t_wind_1a", "t_wind_1b"]: value += 28.0
			value -= float(talent.get("tier", 1)) * 2.0
		if value > score:
			best = i
			score = value
	return best

static func danger(w, position: Vector2) -> float:
	var score = 0.0
	for bullet in w.bullets:
		if bullet.friendly: continue
		var soon = bullet.pos + bullet.dir * bullet.speed * .25
		var near = Geometry2D.get_closest_point_to_segment(position, bullet.pos, soon)
		var gap = position.distance_to(near)
		score += maxf(0, 62 - gap) / 62 * 210
	for zone in w.zones:
		if zone.friendly or zone.until < w.time + .12: continue
		var gap = position.distance_to(Geometry2D.get_closest_point_to_segment(position, zone.from, zone.to)) if zone.get("shape", "") == "line" else position.distance_to(zone.pos)
		var radius = zone.get("width", zone.radius)
		score += maxf(0, radius + 42 - gap) / (radius + 42) * (300 if zone.active - w.time < .35 else 160)
	for enemy in w.enemies:
		if enemy.dead: continue
		score += maxf(0, enemy.radius + 65 - position.distance_to(enemy.pos)) * 3.0
		if enemy.windup > 0 and (enemy.id in ["e02", "e13", "e17", "e21", "e23"] or enemy.get("pattern", "") in ["charge", "dash", "hop", "melee", "grab"]):
			var gap = position.distance_to(Geometry2D.get_closest_point_to_segment(position, enemy.pos, enemy.pos + enemy.aim * 260))
			score += maxf(0, 52 - gap) * 3
	for object in w.geometry.objects:
		if not object.alive: continue
		if object.kind == "thorn_seal" and fmod(w.time + float(object.phase), 3.8) > .9:
			score += maxf(0, 60 - position.distance_to(object.pos)) * 5
		elif float(object.fuse_until) > 0:
			score += maxf(0, 146 - position.distance_to(object.pos)) * 4
	return score

static func firing_lane(w, point: Vector2, target: Dictionary, weapon: Dictionary) -> bool:
	if weapon.mode not in ["ray","prism","tether"]: return w.geometry.clear_swept_segment(point,target.pos,7)
	var width = 14.0+4*w.stack("r41") if weapon.mode=="ray" else 12.0 if weapon.mode=="prism" else 9.0
	var from = w.geometry.constrain_floor(point,width)
	var direction = point.direction_to(target.pos)
	var end = w.geometry.clipped_ray(from,from+direction*float(weapon.range),width)
	return w.geometry.clear_segment(from,target.pos) and Geometry.segment_circle(from,end,target.pos,target.radius+width)

static func frame(w) -> Dictionary:
	var target = w.nearest_enemy(w.player.pos)
	if target.is_empty(): return {}
	var weapon = w.db.row("weapons", w.player.weapon)
	var desired = minf(weapon.range * .68, 290)
	var aim = w.player.pos.direction_to(target.pos)
	var preferred = aim * clampf((w.player.pos.distance_to(target.pos) - desired) / 90, -1, 1) + aim.orthogonal() * .4
	var blocked = not firing_lane(w,w.player.pos,target,weapon)
	var actor = "%s/%s" % [w.get_instance_id(), w.run.id]
	if actor != actor_key:
		actor_key = actor
		last_hit_count = int(w.stats.hits)
		last_damage_at = w.time
		navigate_until = 0.0
	if int(w.stats.hits) != last_hit_count:
		last_hit_count = int(w.stats.hits)
		last_damage_at = w.time
	if blocked and w.time - last_damage_at > 3.0: navigate_until = w.time + 2.0
	var recovering_lane = w.time < navigate_until
	var waypoint = target.pos
	if blocked and recovering_lane:
		var key = "%s/%d/%d/%d/%d" % [w.geometry.template_id, w.geometry.region, w.run.floor, w.run.room, w.geometry.blocks.size()]
		if key != navigation_key:
			navigation = Geometry.new()
			if w.run.get("campaign", false):
				navigation.bounds = w.geometry.bounds
				navigation.floor_polygon = w.geometry.floor_polygon.duplicate()
				navigation.cells = w.geometry.cells.duplicate(true)
				navigation.blocks = w.geometry.blocks.duplicate(true)
				navigation.template_id = w.geometry.template_id
			else: navigation.build(w.geometry.template_id, w.geometry.region)
			navigation_key = key
			target_cell = Vector2i(-100, -100)
		var cell = navigation.cell_of(target.pos)
		if cell != target_cell:
			target_cell = cell
			navigation.rebuild_flow(target.pos)
		var current = navigation.cell_of(w.player.pos)
		var best_cell = current
		var distance = int(navigation.flow.get(navigation.key(current), 9999))
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var candidate = current + offset
			var value = int(navigation.flow.get(navigation.key(candidate), 9999))
			if value < distance:
				best_cell = candidate
				distance = value
		waypoint = w.geometry.navigation_waypoint(w.player.pos,target.pos,12)
		preferred = w.player.pos.direction_to(waypoint)
	var heal: Dictionary = {}
	if w.player.hp < w.player.max_hp:
		for pickup in w.pickups:
			if pickup.kind == "heal" and (heal.is_empty() or w.player.pos.distance_to(pickup.pos) < w.player.pos.distance_to(heal.pos)): heal = pickup
	if not heal.is_empty(): preferred = w.player.pos.direction_to(heal.pos)
	var move = Vector2.ZERO
	var best = INF
	for i in 17:
		var direction = Vector2.ZERO if i == 16 else Vector2.RIGHT.rotated(i * TAU / 16)
		var lookahead = minf(64,w.player.pos.distance_to(waypoint)) if blocked and recovering_lane else 64.0
		var next = w.geometry.slide(w.player.pos, direction * lookahead, 12)
		var travel = next.distance_to(w.player.pos)
		var cost = danger(w, next)
		if blocked and recovering_lane:
			cost += next.distance_to(waypoint) * .8
		else:
			cost += absf(next.distance_to(target.pos) - desired) * .16
			# Retreat along visible firing lanes instead of oscillating across a wall edge.
			if recovering_lane and not firing_lane(w,next,target,weapon): cost += 120
		cost += (1 - direction.dot(preferred.normalized())) * 25
		if not heal.is_empty(): cost += next.distance_to(heal.pos) * .35
		if i != 16 and travel < minf(48,lookahead): cost += 70 if travel<1 else (minf(48,lookahead)-travel)*.5
		if cost < best:
			best = cost
			move = direction
	var marked = w.enemies.filter(func(e): return not e.dead and e.mark >= 2 and e.pos.distance_to(w.player.pos) < 420).size()
	var skill = marked >= 2 or target.mark >= 3 or (w.player.hp <= 2 and target.mark > 0)
	var danger_now = danger(w, w.player.pos)
	return {"move": move, "aim": aim, "fire": not blocked,
		# The bot is intentionally conservative around telegraphs and contact
		# pressure. This exercises the real invulnerability window and keeps
		# route coverage from measuring only raw DPS.
		"dash": w.player.dash_cd <= 0.0 and (danger_now > 170.0 or (w.player.hp <= 2 and danger_now > 85.0)), "skill": skill}
