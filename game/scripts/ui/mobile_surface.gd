extends RefCounted
## Scenery fills the physical surface; gameplay and interaction have separate safe bounds.
const DESIGN = Vector2(1280, 720)

static func contained(rect: Rect2) -> Transform2D:
	var factor = minf(rect.size.x / DESIGN.x, rect.size.y / DESIGN.y)
	return Transform2D(Vector2(factor, 0), Vector2(0, factor), rect.position + (rect.size - DESIGN * factor) * .5)

static func covered(surface: Rect2, source_size: Vector2) -> Rect2:
	var factor = maxf(surface.size.x / source_size.x, surface.size.y / source_size.y)
	var size = source_size * factor
	return Rect2(surface.position + (surface.size - size) * .5, size)

static func safe_area(surface: Rect2, screen_transform: Transform2D, raw_safe: Rect2, cutouts: Array) -> Rect2:
	var inverse = screen_transform.affine_inverse()
	var safe = (inverse * raw_safe).intersection(surface) if raw_safe.has_area() else surface
	if not safe.has_area(): safe = surface
	var start = safe.position
	var end = safe.end
	for raw_cutout in cutouts:
		var cutout = (inverse * Rect2(raw_cutout)).intersection(surface)
		if not cutout.has_area(): continue
		# Punch-hole cameras can be inset from an edge. Reserve their nearest edge,
		# rather than relying on the cutout rectangle touching pixel zero.
		var distances = [cutout.end.x - surface.position.x, surface.end.x - cutout.position.x,
			cutout.end.y - surface.position.y, surface.end.y - cutout.position.y]
		match distances.find(distances.min()):
			0: start.x = maxf(start.x, cutout.end.x)
			1: end.x = minf(end.x, cutout.position.x)
			2: start.y = maxf(start.y, cutout.end.y)
			3: end.y = minf(end.y, cutout.position.y)
	var result = Rect2(start, end - start)
	return result if result.has_area() else safe
