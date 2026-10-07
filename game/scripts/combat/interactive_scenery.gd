extends RefCounted
const Geometry = preload("res://scripts/combat/room_geometry.gd")

static func dangerous(object: Dictionary, time: float) -> bool:
	return object.alive and object.kind == "thorn_seal" and fmod(time + float(object.phase), 3.8) > 1.2

static func hit(w, object: Dictionary, damage: float) -> void:
	if not object.alive or object.kind == "thorn_seal": return
	object.hp -= damage
	object.hit_until = w.time + .12
	if object.hp > 0: return
	if object.kind in ["powder_urn", "oil_lamp"]:
		if object.fuse_until <= 0:
			object.fuse_until = w.time + .36
			w.emit("scenery_warning", {"pos": object.pos, "radius": 116, "duration": .36})
	else:
		w.geometry.remove_object(object)
		w.emit("scenery_break", {"pos": object.pos, "radius": 48, "style": "blast_ink"})

static func segment_hit(w, from: Vector2, to: Vector2, damage: float) -> bool:
	var nearest: Dictionary = {}
	var distance = INF
	for object in w.geometry.objects:
		if not object.alive or not object.solid: continue
		if Geometry.segment_circle(from, to, object.pos, 34):
			var value = from.distance_squared_to(object.pos)
			if value < distance:
				nearest = object
				distance = value
	if nearest.is_empty(): return false
	hit(w, nearest, damage)
	return true

static func area_hit(w, center: Vector2, radius: float, damage: float) -> void:
	for object in w.geometry.objects.duplicate():
		if object.alive and object.pos.distance_to(center) <= radius + 30: hit(w, object, damage)

static func tick(w) -> void:
	for object in w.geometry.objects.duplicate():
		if not object.alive: continue
		if object.kind == "thorn_seal" and dangerous(object, w.time) and w.player.pos.distance_to(object.pos) < 37:
			w.damage_player(1, {"id": "thorn_seal", "table": "obstacles", "kind": "hazard", "origin": object.pos})
		if float(object.fuse_until) <= 0 or w.time < float(object.fuse_until): continue
		w.geometry.remove_object(object)
		w.emit("scenery_explosion", {"pos": object.pos, "radius": 116, "style": "blast_flame", "heavy": true})
		w.begin_pulse("scenery_" + str(object.key))
		for enemy in w.enemies.duplicate():
			if not enemy.dead and enemy.pos.distance_to(object.pos) < 116 + enemy.radius:
				w.damage_enemy(enemy, 72, "secondary", false, object.pos.direction_to(enemy.pos), 60)
		if w.player.pos.distance_to(object.pos) < 128:
			w.damage_player(2, {"id": str(object.kind), "table": "obstacles", "kind": "explosion", "origin": object.pos})
		area_hit(w, object.pos, 116, 25)
		if object.kind == "oil_lamp": w.add_zone(object.pos, 64, 3.0, 12, true, 0.0)
