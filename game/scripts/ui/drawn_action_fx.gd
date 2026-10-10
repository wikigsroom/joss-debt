extends RefCounted
## Event time advances real drawn poses; this class never touches simulation or RNG.
var strips: Dictionary = {}
var frames: Dictionary = {}

func frame(name: String, index: int) -> Texture2D:
	if not strips.has(name): strips[name] = load("res://assets/fx/drawn-actions/%s.png" % name)
	var key = "%s:%d" % [name, index]
	if not frames.has(key):
		var atlas = AtlasTexture.new()
		atlas.atlas = strips[name]
		atlas.region = Rect2(index * 256, 0, 256, 256)
		frames[key] = atlas
	return frames[key]

func draw(renderer, event: Dictionary) -> bool:
	var age = float(event.total) - float(event.left)
	if age >= 6.0 / 18.0: return false
	var index = clampi(int(age * 18), 0, 5)
	var name = ""
	var center = Vector2(event.get("pos", Vector2.ZERO)) - Vector2(0, 18)
	var size = 64.0
	var angle = 0.0
	var direction = Vector2(event.get("dir", Vector2.RIGHT)).normalized()
	match str(event.kind):
		"shot":
			if str(event.get("mode", "")) in ["arc", "cone", "charged_arc", "sweep", "orbit_blade", "boomerang_arc"]: return true
			name = "muzzle"
			center += direction * 24
			angle = direction.angle()
			size = 100.0 if event.get("heavy", false) else 76.0
		"slash":
			name = "melee"
			var reach = float(event.get("range", 100))
			center += direction * minf(reach * .42, 58)
			angle = direction.angle()
			size = clampf(reach * 1.05, 96, 186)
		"hit":
			name = "impact"
			size = 76.0 if event.get("heavy", false) or event.get("crit", false) else 54.0
		"player_hurt":
			name = "hurt"
			size = 82.0
		_: return false
	renderer.draw_set_transform_matrix(renderer.stage * Transform2D(angle, center))
	renderer.draw_texture_rect(frame(name, index), Rect2(Vector2.ONE * -size * .5, Vector2.ONE * size), false, Color(1,1,1,.92))
	renderer.draw_set_transform_matrix(renderer.stage)
	return true
