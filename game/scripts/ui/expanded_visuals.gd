extends RefCounted
## Generated texture layers; decorative clocks never advance a gameplay random stream.
const Scenery = preload("res://scripts/combat/interactive_scenery.gd")
const Weapons = preload("res://scripts/combat/expanded_weapons.gd")
const CombatFX = preload("res://scripts/ui/combat_fx.gd")

static func texture(r, path: String) -> Texture2D:
	if not r.textures.has(path):
		if not ResourceLoader.exists(path): return null
		r.textures[path] = load(path)
	return r.textures[path]

static func frame(r, id: String, elapsed: float, loop: bool = true) -> Texture2D:
	var image = texture(r, "res://assets/fx/expansion/animation/" + id + ".png")
	if image == null: return null
	var beam = id.begins_with("beam_")
	var size = Vector2(256, 96) if beam else Vector2(192, 192)
	var index = posmod(int(elapsed * 24), 12) if loop else clampi(int(elapsed * 24), 0, 11)
	var cache_key = "fx_frame_%s_%d" % [id, index]
	if r.textures.has(cache_key): return r.textures[cache_key]
	var item = AtlasTexture.new()
	item.atlas = image
	item.region = Rect2(Vector2(index * size.x, 0), size)
	r.textures[cache_key] = item
	return item

static func sprite(r, image: Texture2D, position: Vector2, size: Vector2, angle: float = 0, tint: Color = Color.WHITE) -> void:
	if image == null: return
	var local = Transform2D(angle, position)
	r.draw_set_transform_matrix(r.stage * local)
	r.draw_texture_rect(image, Rect2(-size * .5, size), false, tint)
	r.draw_set_transform_matrix(r.stage)

static func ambient(r) -> void:
	if not r.world.run.get("campaign", false): return
	var map = r.world.region_spec()
	var time = r.clock * (.35 if r.reduce_motion else 1.0)
	var light = Color(str(map.get("light_color", "#f9b95f")))
	var motes = Color(str(map.get("ambient_color", "#f9b95f")))
	var kind = str(map.ambient)
	var warm_light = kind in ["ember", "wax", "ash", "cinder", "judgment"]
	for anchor in [Vector2(414, 103), Vector2(858, 103), Vector2(413, 606), Vector2(858, 606)]:
		var phase = anchor.x * .021 + time * 5.5
		var intensity = .75 + sin(phase) * .13 + sin(phase * 2.3) * .07
		for radius in [22, 36, 55]: r.draw_circle(anchor, radius, Color(light, .044 * intensity))
		if warm_light:
			sprite(r, frame(r, "ember_cluster", time + anchor.x), anchor - Vector2(0, 15 + sin(phase) * 2), Vector2(22, 37), sin(phase * .6) * .07, Color(light, .8))
		elif kind in ["star", "storm", "seal", "mirror"]:
			r.draw_arc(anchor, 12 + sin(phase) * 2, time * .2, time * .2 + PI * 1.5, 26, Color(light, .35 * intensity), 1.6, true)
		else:
			sprite(r, frame(r, "lotus_petal", time + anchor.x), anchor - Vector2(0, 9 + sin(phase) * 4), Vector2(19, 23), sin(phase * .3) * .15, Color(light, .42))
	var count = roundi(34 * r.particle_scale)
	for i in count:
		var seed = float(i * 101 + int(r.world.run.room) * 31)
		var speed = 12 + i % 6 * 5
		var x = 90 + fmod(seed * 17 + sin(time * .4 + seed) * 19, 1090)
		var y = 110 + fmod(seed * 13 + time * speed, 492)
		var position = Vector2(x, y)
		var opacity = .2 + sin(time + seed) * .1
		match kind:
			"rain", "storm":
				r.draw_line(position, position + Vector2(-7, 20 if kind == "rain" else 29), Color(motes, opacity), 1.3, true)
			"leaf", "bamboo", "ash", "cinder", "silk", "snow_silk":
				var size = Vector2(8, 19) if kind in ["bamboo", "silk", "snow_silk"] else Vector2(10, 11)
				var drift = Vector2(sin(time * .9 + seed) * 25, sin(time * .5 + seed) * 7)
				sprite(r, frame(r, "paper_blade", time + seed), position + drift, size, sin(time + seed) * .8, Color(motes, opacity * 1.5))
			"water", "lotus", "mirror":
				# Ripples stay near the water rim and leave the combat centre legible.
				if i % 3 == 0:
					position.x = 108 + i % 2 * 1060
					r.draw_arc(position, 8 + fmod(time * 8 + seed, 18), 0, TAU, 22, Color(motes, opacity), 1, true)
				if kind == "lotus" and i % 4 == 0: sprite(r, frame(r, "lotus_petal", time + seed), Vector2(x, y), Vector2(13, 11), time * .2 + seed, Color(motes, .22))
			"star", "seal", "judgment":
				var color = Color(motes, opacity * 1.6)
				r.draw_line(position - Vector2(4, 0), position + Vector2(4, 0), color, 1.5, true)
				r.draw_line(position - Vector2(0, 4), position + Vector2(0, 4), color, 1.5, true)
			"coin":
				r.draw_arc(position, 3.2, 0, TAU, 12, Color(motes, opacity), 1.2, true)
				r.draw_rect(Rect2(position - Vector2.ONE, Vector2.ONE * 2), Color(motes, opacity))
			"wind": r.draw_arc(position, 23, -.4, .8, 12, Color(motes, opacity * .65), 1.1, true)
			_: r.draw_circle(position, 1.4 + i % 3 * .4, Color(motes, opacity * 1.3))
	if kind == "storm":
		# A brief, peripheral branch of lightning; no full-screen combat flash.
		var flicker = maxf(0, sin(time * 1.7) - .96) * 13
		for side in [126, 1154]:
			var bolt = PackedVector2Array([Vector2(side, 125), Vector2(side + 18, 168), Vector2(side - 9, 204), Vector2(side + 14, 240)])
			r.draw_polyline(bolt, Color(light, flicker * .5), 2, true)
	# Different diffuse layers hug the rim rather than covering the targeting area.
	var foggy = kind in ["water", "rain", "snow_silk", "mirror", "mist", "wind", "ash", "cinder"]
	for i in (7 if foggy else 3):
		var t = fmod(time * .18 + i * .21, 1.0)
		var origin = Vector2(140 + i * 165, (579 if i % 2 else 163) - t * 50)
		sprite(r, frame(r, "smoke_cloud", time + i), origin, Vector2(175 if foggy else 95, 45 + t * 60), sin(time * .4 + i) * .12, Color(light, (.08 if foggy else .025) * sin(t * PI)))

static func scenery(r) -> void:
	for object in r.world.geometry.objects:
		if not object.alive: continue
		var key = str(object.kind)
		var path = "res://assets/obstacles/" + key + ".png"
		if key.ends_with("wall"):
			path = "res://assets/obstacles/connected/%s/%d.png" % [key, r.world.geometry.connections(object)]
		var dangerous = Scenery.dangerous(object, r.world.time)
		if key == "thorn_seal" and not dangerous: path = "res://assets/obstacles/cold_thorn.png"
		var center = Vector2(object.pos)
		var pulse = .5 + sin(r.clock * 5 + object.phase) * .5
		r.draw_circle(center + Vector2(0, 9), 27, Color(0, 0, 0, .2))
		var tint = Color(1.4, 1.25, 1.05) if r.world.time < object.hit_until else Color.WHITE
		sprite(r, texture(r, path), center - Vector2(0, 12), Vector2.ONE * (77 if key.ends_with("wall") else 89), 0, tint)
		if key in ["powder_urn", "oil_lamp"]:
			sprite(r, frame(r, "ember_cluster", r.clock + object.phase), center - Vector2(0, 38), Vector2(17, 24), .03 * sin(r.clock * 8), Color(1, .9, .7, .8))
			if object.fuse_until > 0:
				r.draw_circle(center, 116, Color("efaa6b", .08 + pulse * .07))
				r.draw_arc(center, 116, 0, TAU, 48, Color("efaa6b", .6 + pulse * .3), 3, true)
		elif key == "thorn_seal":
			r.draw_arc(center, 36, 0, TAU, 26, Color("efaa6b", .75 if dangerous else .25), 2, true)

static func projectile(r, bullet: Dictionary) -> bool:
	var id = str(bullet.get("style", Weapons.style(str(bullet.mode)) if bullet.friendly else "jade_needle"))
	var image = frame(r, id, bullet.age + float(bullet.uid) * .01)
	if image == null: return false
	var point = Vector2(bullet.pos) - Vector2(0, 14)
	var size = Vector2(29, 20) if bullet.friendly else Vector2(26, 18)
	if bullet.mode in ["cloud", "wave", "explosive", "homing_cluster"]: size *= 1.3
	r.draw_line(point - bullet.dir * 30, point, Color(r.FIRE if bullet.friendly else r.HOSTILE, .14), 10, true)
	sprite(r, image, point, size, Vector2(bullet.dir).angle())
	return true

static func beam(r, effect: Dictionary, progress: float) -> bool:
	return CombatFX.beam(r,effect,progress)

static func burst(r, effect: Dictionary, progress: float) -> bool:
	return CombatFX.burst(r,effect,progress)

static func zone(r, zone: Dictionary) -> void:
	CombatFX.zone(r,zone)
