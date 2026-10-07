extends RefCounted
## 80 source-bound animated presets with readable cores and bounded particles.
## This layer never changes simulation state or consumes a gameplay RNG stream.
const Clip = preload("res://scripts/ui/combat_fx.gd")
const Styles = preload("res://scripts/combat/projectile_styles.gd")
const FAMILIES = ["ember", "ink", "thread", "prism", "lotus", "smoke", "frost", "storm", "void", "brass"]
const COLORS = ["ffac65", "84bbed", "ff8495", "a6f0db", "f6b3de", "d6d9ee", "b3e8ff", "d4a6ff", "b998f6", "ffe29b"]

static func color(family: String) -> Color:
	var index = FAMILIES.find(family)
	return Color(COLORS[maxi(0, index)])

static func frame(r, id: String, stage: int) -> Texture2D:
	stage = clampi(stage, 0, 5)
	var key = "polish/%s/%d" % [id, stage]
	if r.textures.has(key): return r.textures[key]
	var path = "res://assets/fx/equipment-polish/" + id + ".png"
	if not r.textures.has(path):
		if not ResourceLoader.exists(path): return null
		r.textures[path] = load(path)
	var image = AtlasTexture.new()
	image.atlas = r.textures[path]
	image.region = Rect2(stage * 256, 0, 256, 256)
	r.textures[key] = image
	return image

static func spend(r, amount: int = 1) -> bool:
	if r.fx_budget < amount: return false
	r.fx_budget -= amount
	return true

static func chosen(r, event: Dictionary, shape: String) -> String:
	var explicit = str(event.get("fx_preset", ""))
	if not explicit.is_empty(): return explicit
	if event.has("source"):
		var profile = Styles.enemy(event.source)
		return Styles.preset(profile, shape.begins_with("beam"))
	var style = str(event.get("style", ""))
	var family = str(event.get("fx_family", {"beam_ink": "ink", "beam_thread": "thread", "beam_prism": "prism", "blast_ink": "ink", "blast_lotus": "lotus", "shockwave": "brass"}.get(style, "ember")))
	if family not in FAMILIES: family = "ember"
	return family + "_" + shape

static func beam(r, event: Dictionary, progress: float) -> bool:
	var id = chosen(r, event, "beam_lance")
	var image = frame(r, id, mini(5, int(progress * 6)))
	if image == null: return false
	var from = Vector2(event.pos)
	var to = Vector2(event.get("end", from + event.get("dir", Vector2.UP) * float(event.get("range", 500))))
	var direction = from.direction_to(to)
	var width = float(event.get("width", 14))
	var elapsed = float(event.total) * progress
	var front = from.lerp(to, minf(1, elapsed / .055))
	var fade = clampf((1 - progress) / .35, 0, 1)
	var tint = color(id.get_slice("_", 0))
	Clip.line(r, from, front, Color("0b1924", .78 * fade), width * 2 + 5)
	Clip.line(r, from, front, Color(tint, .15 * fade), width * 2 + 1)
	Clip.sprite(r, image, (from + front) * .5, Vector2(from.distance_to(front) + 16, width * 3 + 10), direction.angle(), Color(1, 1, 1, .84 * fade))
	var path = PackedVector2Array()
	for i in 15:
		var amount = i / 14.0
		var offset = 0.0
		if not r.reduce_motion:
			if id.ends_with("beam_fork"): offset = sin(i * 13.7 + floor(elapsed * 18)) * width * .45
			elif id.ends_with("beam_wave"): offset = sin(amount * TAU * 2 + elapsed * 9) * width * .42
			elif id.ends_with("beam_tether"): offset = sin(amount * TAU * 4 - elapsed * 10) * width * .35
		path.append(from.lerp(front, amount) + direction.orthogonal() * offset)
	for i in range(1, path.size()): Clip.line(r, path[i - 1], path[i], Color("fff7df", fade * .8), 2.2)
	if id.ends_with("beam_tether"):
		for i in range(1, path.size()):
			var a = from.lerp(front, (i - 1) / 14.0) * 2 - path[i - 1]
			var b = from.lerp(front, i / 14.0) * 2 - path[i]
			Clip.line(r, a, b, Color(tint, fade * .84), 2)
	Clip.sprite(r, frame(r, id, 0), from, Vector2.ONE * (32 + width), r.clock * .2 if not r.reduce_motion else 0, Color(1, 1, 1, fade))
	var terminal = str(id.get_slice("_", 0)) + "_blast"
	Clip.sprite(r, frame(r, terminal, 2 if progress < .45 else 5), to, Vector2.ONE * (width * 4 + 28), direction.angle(), Color(1, 1, 1, fade * .8))
	var count = mini(7, roundi(7 * r.particle_scale))
	for i in count:
		if not spend(r): break
		var amount = fposmod(i / float(maxi(1, count)) + elapsed * (1.7 if not r.reduce_motion else 0), 1)
		var point = from.lerp(front, amount)
		Clip.sprite(r, frame(r, id, 4), point, Vector2(18 + width * .3, 11 + width * .2), direction.angle(), Color(1, 1, 1, fade * .62))
		if not r.reduce_motion:
			var side = direction.orthogonal() * sin(i * 2.1 + elapsed * 8) * width
			Clip.line(r, point, point + side, Color(tint, fade * .4), 1.2)
	return true

static func burst(r, event: Dictionary, progress: float) -> bool:
	var id = chosen(r, event, "blast")
	var image = frame(r, id, int(progress * 6))
	if image == null: return false
	var point = Vector2(event.pos)
	var radius = float(event.get("radius", 80))
	var tint = color(id.get_slice("_", 0))
	var fade = clampf((1 - progress) * 2.0, 0, 1)
	var expanding = radius * minf(1, .18 + progress * 2.6)
	Clip.disk(r, point, expanding, Color(tint, fade * .065 * r.flash_scale))
	Clip.sprite(r, image, point, Vector2.ONE * radius * 2.2, progress * .1 if id.ends_with("vortex") and not r.reduce_motion else 0, Color(1, 1, 1, fade))
	Clip.arc(r, point, radius, 0, TAU, 56, Color("0b1924", fade * .6), 4)
	Clip.arc(r, point, radius, 0, TAU, 56, Color(tint, fade * .6), 1.6)
	if progress < .5: Clip.arc(r, point, expanding, 0, TAU, 48, Color("fff7df", fade * .44), 2.6)
	var count = mini(22, roundi(19 * r.particle_scale))
	for i in count:
		if not spend(r): break
		var angle = i * TAU / maxi(1, count) + float(event.get("at", 0)) * .7
		var direction = Vector2.RIGHT.rotated(angle)
		var length = radius * minf(1.08, .15 + progress * (1.2 + i % 3 * .21))
		var position = point + direction * length
		if i % 3 == 0:
			Clip.sprite(r, frame(r, id, 5), position, Vector2(9 + i % 4 * 3, 6 + i % 5 * 2), angle + progress * 3, Color(1, 1, 1, fade * .8))
		else:
			Clip.line(r, position - direction * (4 + (1 - progress) * 13), position, Color(tint if i % 2 else Color("fff7df"), fade * .7), 1.3 + i % 2)
		if id.ends_with("vortex") and not r.reduce_motion:
			Clip.arc(r, point, length * .8, angle, angle + .4, 8, Color(tint, fade * .32), 1.2)
	return true

static func zone(r, zone_data: Dictionary) -> bool:
	var line = zone_data.get("shape", "") == "line"
	var id = chosen(r, zone_data, "beam_lance" if line else "field")
	if frame(r, id, 0) == null: return false
	var warning = r.world.time < zone_data.active
	var tint = color(id.get_slice("_", 0)) if zone_data.friendly else r.HOSTILE
	var born = float(zone_data.get("born", zone_data.active - 1))
	var fraction = clampf((r.world.time - born) / maxf(.01, zone_data.active - born), 0, 1)
	if line:
		var from = Vector2(zone_data.from)
		var to = Vector2(zone_data.to)
		if warning:
			Clip.line(r, from, to, Color("0b1924", .88), zone_data.width * 2 + 4)
			Clip.line(r, from, to, Color(tint, .13 + fraction * .15), zone_data.width * 2)
			for i in 16: Clip.line(r, from.lerp(to, i / 16.0), from.lerp(to, (i + .5) / 16.0), Color(tint, .8), 2.6)
		else:
			var effect = zone_data.duplicate()
			effect.pos = from
			effect.end = to
			effect.total = 1.0
			effect.fx_preset = id
			beam(r, effect, .25 + fposmod(r.world.time - zone_data.active, .2))
		return true
	var point = Vector2(zone_data.pos)
	var radius = float(zone_data.radius)
	if warning:
		Clip.disk(r, point, radius, Color(tint, .045 + fraction * .055))
		Clip.arc(r, point, radius, 0, TAU, 52, Color("0b1924", .94), 5)
		Clip.arc(r, point, radius, 0, TAU, 52, Color(tint, .88), 2.3)
		Clip.arc(r, point, radius - 5, -PI * .5, -PI * .5 + TAU * fraction, 48, Color("fff4dc", .76), 2)
		Clip.sprite(r, frame(r, id, 0), point, Vector2.ONE * (24 + fraction * 35), 0, Color(1, 1, 1, .75))
	else:
		var elapsed = r.world.time - zone_data.active
		Clip.sprite(r, frame(r, id, 2 + posmod(int(elapsed * 9), 3)), point, Vector2.ONE * radius * 2, elapsed * .15 if not r.reduce_motion else 0, Color(1, 1, 1, .38))
		Clip.arc(r, point, radius, 0, TAU, 52, Color("0b1924", .85), 5)
		Clip.arc(r, point, radius, 0, TAU, 52, Color(tint, .7), 2.3)
		for i in mini(10, roundi(9 * r.particle_scale)):
			if not spend(r): break
			var direction = Vector2.RIGHT.rotated(i * TAU / 9 + (elapsed * .28 if not r.reduce_motion else 0))
			Clip.sprite(r, frame(r, id, 4), point + direction * radius * .7, Vector2.ONE * 20, direction.angle(), Color(1, 1, 1, .55))
	return true

static func projectile(r, bullet: Dictionary) -> bool:
	var profile = bullet.get("visual_profile", {})
	var friendly = bool(bullet.friendly)
	var family = str(bullet.get("fx_family", profile.get("family", "smoke" if bullet.mode == "ash" else "ember")))
	var tint = color(family)
	var point = Vector2(bullet.pos) - Vector2(0, 14)
	var direction = Vector2(bullet.dir)
	var radius = float(bullet.radius)
	var age = float(bullet.get("age", 0))
	var angle = direction.angle()
	var shape = str(profile.get("shape", {"orb": "ring", "bell": "coin", "flame_orb": "drop", "piercing": "needle", "charged_line": "dart", "wave": "fan", "cloud": "spiral", "mine": "knot", "controlled": "petal", "explosive": "star", "rain": "petal", "homing_cluster": "seed", "guided_swarm": "diamond", "split": "shuriken"}.get(bullet.mode, "diamond")))
	var tail = 15 + minf(30, float(bullet.speed) * .055)
	# One conservative envelope covers the complete trail, glyph and aura.
	# Interior bullets can submit their primitives without repeating wall tests.
	r.fx_safe_draw = r.world.geometry.contains_floor(point, tail + radius * 1.5 + 8)
	Clip.line(r, point - direction * tail, point, Color(tint, .15), radius * 1.6)
	Clip.line(r, point - direction * tail * .65, point, Color(tint, .58), maxf(1.5, radius * .37))
	if spend(r):
		var preset = family + "_" + (["blast", "ring", "vortex", "field"][int(profile.get("orbit", 0)) % 4])
		Clip.sprite(r, frame(r, preset, 3 + posmod(int(age * 12), 2)), point, Vector2.ONE * radius * 4.3, age * .9 if not r.reduce_motion else 0, Color(1, 1, 1, .36 if friendly else .29))
	if friendly and bullet.mode in ["returning", "ricochet", "boomerang_arc"]:
		var weapon = str(bullet.get("weapon", "w05"))
		var path = "res://assets/weapons/" + weapon + ".png"
		if not r.textures.has(path) and ResourceLoader.exists(path): r.textures[path] = load(path)
		if r.textures.has(path): Clip.sprite(r, r.textures[path], point, Vector2.ONE * 33, age * 10 if not r.reduce_motion else angle)
		Clip.arc(r, point, radius + 2, 0, TAU, 20, Color(tint, .88), 1.5)
	else: glyph(r, point, direction, radius, shape, tint, profile, age)
	# Hostile collision perimeter remains stable across every skin and camera mode.
	if not friendly:
		Clip.arc(r, point, radius + .6, 0, TAU, 18, Color("101b25", .92), 2.8)
		Clip.arc(r, point, radius + .6, 0, TAU, 18, Color("a2f0dc", .9), 1.1)
	if spend(r) and not r.reduce_motion:
		var count = 2 if friendly else int(profile.get("trail_layers", 2))
		for i in mini(4, count):
			var offset = direction.orthogonal() * sin(age * 11 + i * 2 + float(bullet.uid)) * (radius + 3)
			var at = point - direction * (10 + i * 7) + offset
			Clip.line(r, at - direction * 3, at + direction * 2, Color(tint, .52 - i * .08), 1.3)
	r.fx_safe_draw = false
	return true

static func glyph(r, point: Vector2, direction: Vector2, radius: float, shape: String, tint: Color, profile: Dictionary, age: float) -> void:
	var angle = direction.angle() + (age * float(profile.get("spin", .6)) if not r.reduce_motion else 0)
	var extent = radius * maxf(1, float(profile.get("aspect", 1))) + 1
	if r.fx_safe_draw or r.world.geometry.contains_floor(point, extent):
		var key = "%s/%s/%s/%s/%s" % [shape, radius, profile.get("aspect", 1), profile.get("ribs", 5), tint.to_html()]
		if not r.projectile_meshes.has(key):
			if r.projectile_meshes.size() >= 1024: r.projectile_meshes.erase(r.projectile_meshes.keys()[0])
			r.projectile_meshes[key] = glyph_mesh(radius, shape, tint, profile)
		r.draw_set_transform_matrix(r.stage * Transform2D(angle, point))
		r.draw_mesh(r.projectile_meshes[key], null)
		r.draw_set_transform_matrix(r.stage)
		Clip.disk(r, point - direction * radius * .13, maxf(1.2, radius * .22), Color("fff8df"))
		return
	var forward = Vector2.RIGHT.rotated(angle)
	var side = forward.orthogonal()
	var aspect = clampf(float(profile.get("aspect", 1)), .7, 1.7)
	var points = PackedVector2Array()
	match shape:
		"needle", "dart", "capsule":
			points = PackedVector2Array([point + forward * radius * aspect, point - forward * radius * .5 + side * radius * .5, point - forward * radius, point - forward * radius * .5 - side * radius * .5])
		"drop", "seed", "petal":
			for i in 12:
				var phase = i * TAU / 12
				var length = radius * (.63 + .34 * cos(phase))
				points.append(point + forward * cos(phase) * length * aspect + side * sin(phase) * radius * .7)
		"star", "shuriken", "fan", "knot":
			var ribs = int(profile.get("ribs", 5))
			for i in ribs * 2:
				var axis = Vector2.RIGHT.rotated(angle + i * PI / ribs)
				points.append(point + axis * radius * (1 if i % 2 == 0 else .43))
		"scroll":
			points = PackedVector2Array([point + forward * radius + side * radius * .5, point - forward * radius + side * radius * .7, point - forward * radius - side * radius * .5, point + forward * radius - side * radius * .7])
		"diamond": points = PackedVector2Array([point + forward * radius * aspect, point + side * radius, point - forward * radius, point - side * radius])
		_:
			Clip.disk(r, point, radius * .87, Color("0b1924"))
			Clip.arc(r, point, radius * .8, 0, TAU if shape != "moon" else PI * 1.45, 18, tint, 2.5)
			if shape in ["coin", "ring"]:
				Clip.line(r, point - side * radius * .45, point + side * radius * .45, Color("fff8df"), 1.3)
			elif shape == "spiral":
				Clip.arc(r, point, radius * .43, angle, angle + PI * 1.6, 12, Color("fff8df"), 1.7)
	if not points.is_empty():
		if r.fx_safe_draw or r.world.geometry.contains_floor(point, radius * maxf(1, aspect)):
			r.draw_colored_polygon(points, tint)
		else:
			for piece in Geometry2D.intersect_polygons(points, r.world.geometry.floor_polygon):
				# Preserve concave stars and shuriken rather than filling their hull.
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty(): r.draw_colored_polygon(piece, tint)
		if r.fx_safe_draw or r.world.geometry.contains_floor(point, radius * maxf(1, aspect) + .7):
			var outline = points.duplicate()
			outline.append(points[0])
			r.draw_polyline(outline, Color("0b1924"), 1.3, true)
		else:
			for i in points.size(): Clip.line(r, points[i], points[(i + 1) % points.size()], Color("0b1924"), 1.3)
	Clip.disk(r, point - direction * radius * .13, maxf(1.2, radius * .22), Color("fff8df"))

static func mesh_triangle(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector2, b: Vector2, c: Vector2, tint: Color) -> void:
	for p in [a, b, c]:
		vertices.append(Vector3(p.x, p.y, 0))
		colors.append(tint)

static func mesh_stroke(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector2, b: Vector2, width: float, tint: Color) -> void:
	var side = a.direction_to(b).orthogonal() * width * .5
	mesh_triangle(vertices, colors, a + side, b + side, b - side, tint)
	mesh_triangle(vertices, colors, a + side, b - side, a - side, tint)

static func mesh_arc(vertices: PackedVector3Array, colors: PackedColorArray, radius: float, start: float, end: float, width: float, tint: Color) -> void:
	for i in 24:
		var a = Vector2.RIGHT.rotated(lerpf(start, end, i / 24.0))
		var b = Vector2.RIGHT.rotated(lerpf(start, end, (i + 1) / 24.0))
		mesh_triangle(vertices, colors, a * (radius - width * .5), a * (radius + width * .5), b * (radius + width * .5), tint)
		mesh_triangle(vertices, colors, a * (radius - width * .5), b * (radius + width * .5), b * (radius - width * .5), tint)

static func glyph_mesh(radius: float, shape: String, tint: Color, profile: Dictionary) -> ArrayMesh:
	# Stable geometry is built once. Spin and aim only transform the cached mesh.
	# Boundary-crossing glyphs still use the authoritative polygon clipping path.
	var points = PackedVector2Array()
	var aspect = clampf(float(profile.get("aspect", 1)), .7, 1.7)
	match shape:
		"needle", "dart", "capsule":
			points = PackedVector2Array([Vector2(radius * aspect, 0), Vector2(-radius * .5, radius * .5), Vector2(-radius, 0), Vector2(-radius * .5, -radius * .5)])
		"drop", "seed", "petal":
			for i in 12:
				var phase = i * TAU / 12
				points.append(Vector2(cos(phase) * radius * (.63 + .34 * cos(phase)) * aspect, sin(phase) * radius * .7))
		"star", "shuriken", "fan", "knot":
			var ribs = int(profile.get("ribs", 5))
			for i in ribs * 2: points.append(Vector2.RIGHT.rotated(i * PI / ribs) * radius * (1 if i % 2 == 0 else .43))
		"scroll": points = PackedVector2Array([Vector2(radius, radius * .5), Vector2(-radius, radius * .7), Vector2(-radius, -radius * .5), Vector2(radius, -radius * .7)])
		"diamond": points = PackedVector2Array([Vector2(radius * aspect, 0), Vector2(0, radius), Vector2(-radius, 0), Vector2(0, -radius)])
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	if not points.is_empty():
		for i in points.size():
			mesh_triangle(vertices, colors, Vector2.ZERO, points[i], points[(i + 1) % points.size()], tint)
		for i in points.size(): mesh_stroke(vertices, colors, points[i], points[(i + 1) % points.size()], 1.3, Color("0b1924"))
	else:
		for i in 24: mesh_triangle(vertices, colors, Vector2.ZERO, Vector2.RIGHT.rotated(i * TAU / 24) * radius * .87, Vector2.RIGHT.rotated((i + 1) * TAU / 24) * radius * .87, Color("0b1924"))
		mesh_arc(vertices, colors, radius * .8, 0, TAU if shape != "moon" else PI * 1.45, 2.5, tint)
		if shape in ["coin", "ring"]: mesh_stroke(vertices, colors, Vector2(0, -radius * .45), Vector2(0, radius * .45), 1.3, Color("fff8df"))
		elif shape == "spiral": mesh_arc(vertices, colors, radius * .43, 0, PI * 1.6, 1.7, Color("fff8df"))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var result = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func equipment_event(r, event: Dictionary, progress: float) -> void:
	var family = {"a02": "lotus", "a03": "brass", "a04": "ink", "a05": "thread", "a06": "lotus", "a08": "lotus", "a10": "frost", "a11": "frost", "a12": "storm"}.get(str(event.get("id", "")), "ember")
	var preset = str(family) + "_ring"
	var effect = event.duplicate()
	effect.fx_preset = preset
	effect.radius = 52 if event.kind == "active_item" else 28
	burst(r, effect, progress)
