extends RefCounted
## The same circles and grid collision are used for every platform and automated tests.

const AREA = Rect2(64, 72, 1152, 576)
const STAGE = Transform2D(Vector2(1, 0), Vector2(0, .84722), Vector2(0, 59))
const TILE = 64
const WIDTH = 18
const HEIGHT = 9
var blocks: Array = []
var cells: Dictionary = {}
var flow: Dictionary = {}
var baked_cells: Dictionary = {}
var template_id = "room_open_1"
var region = 1
var objects: Array = []
var bounds = AREA
var floor_polygon = PackedVector2Array()
var floor_planes = PackedVector3Array()
var boundary_key = "legacy"
var fine_navigation: Dictionary = {}
static var boundary_specs: Dictionary = {}

func configure_biome(biome_id: String, variant: int) -> void:
	fine_navigation.clear()
	if boundary_specs.is_empty():
		boundary_specs = JSON.parse_string(FileAccess.get_file_as_string("res://data/arena_boundaries.json")).rooms
	boundary_key = biome_id + ("_a" if variant == 0 else "_b")
	floor_polygon.clear()
	for point in boundary_specs[boundary_key].polygon:
		floor_polygon.append(STAGE.affine_inverse() * Vector2(point[0], point[1]))
	bounds = Rect2(floor_polygon[0], Vector2.ZERO)
	for point in floor_polygon: bounds = bounds.expand(point)
	cache_floor_planes()

func cache_floor_planes() -> void:
	floor_planes.clear()
	var middle = bounds.get_center()
	for i in floor_polygon.size():
		var a = floor_polygon[i]
		var inward = (floor_polygon[(i + 1) % floor_polygon.size()] - a).orthogonal().normalized()
		if (middle - a).dot(inward) < 0: inward = -inward
		floor_planes.append(Vector3(inward.x, inward.y, a.dot(inward)))

func contains_floor(point: Vector2, radius: float = 0) -> bool:
	if minf(bounds.size.x,bounds.size.y)<=radius*2: return false
	if not bounds.grow(-radius).has_point(point): return false
	if floor_polygon.is_empty(): return true
	# The authored inner walls are convex. Cached inward planes describe the
	# same radius-eroded floor without thousands of per-frame segment queries.
	if floor_planes.size() != floor_polygon.size(): cache_floor_planes()
	var margin = sqrt(maxf(0, radius * radius - .01))
	for plane in floor_planes:
		if point.x * plane.x + point.y * plane.y - plane.z < margin: return false
	return true

func constrain_floor(point: Vector2, radius: float = 0) -> Vector2:
	var result = point.clamp(bounds.position + Vector2.ONE * (radius + .02), bounds.end - Vector2.ONE * (radius + .02))
	if floor_polygon.is_empty(): return result
	# Authored contours are convex. Project inward onto each radius-offset wall.
	var middle = bounds.get_center()
	for pass_index in 4:
		for i in floor_polygon.size():
			var a = floor_polygon[i]
			var b = floor_polygon[(i + 1) % floor_polygon.size()]
			var inward = (b - a).orthogonal().normalized()
			if (middle - a).dot(inward) < 0: inward = -inward
			var depth = (result - a).dot(inward)
			if depth < radius + .02: result += inward * (radius + .02 - depth)
	return result

func nearest_free(point: Vector2, radius: float) -> Vector2:
	var candidate = constrain_floor(point, radius)
	if valid_circle(candidate, radius): return candidate
	var best = bounds.get_center()
	var distance = INF
	for y in HEIGHT:
		for x in WIDTH:
			var value = center(Vector2i(x, y))
			if valid_circle(value, radius) and value.distance_squared_to(point) < distance:
				best = value
				distance = value.distance_squared_to(point)
	return best

func doorway(direction: String, inset: float = 22) -> Vector2:
	var axis = {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}[direction]
	var middle = Vector2(640, 360)
	# Clip against the authored wall rather than the old viewport rectangle.
	var low = 0.0
	var high = 1500.0
	for i in 20:
		var amount = (low + high) * .5
		if contains_floor(middle + axis * amount, inset): low = amount
		else: high = amount
	return middle + axis * low

func build(id: String, region_id: int = 1) -> void:
	bounds = AREA
	floor_polygon.clear()
	floor_planes.clear()
	boundary_key = "legacy"
	objects.clear()
	template_id = id
	region = region_id
	blocks.clear()
	cells.clear()
	baked_cells.clear()
	var tokens = id.trim_prefix("room_").split("_")
	var variant = int(tokens[-1])
	var family = id.trim_prefix("room_").trim_suffix("_" + str(variant))
	var pattern: Array = []
	# These obstacles correspond to the reference-locked arena's perimeter props.
	var perimeter = [Vector2i(0, 7), Vector2i(0, 8), Vector2i(17, 7), Vector2i(17, 8)]
	if region_id == 1: perimeter.append_array([Vector2i(1, 5), Vector2i(1, 6), Vector2i(16, 5), Vector2i(16, 6)])
	# Later-region props remain outside the central floor, as in their source boards.
	for c in perimeter:
		cells[key(c)] = true
		baked_cells[key(c)] = true
		blocks.append(Rect2(AREA.position + Vector2(c) * TILE, Vector2(TILE, TILE)))
	match family:
		"open":
			if variant == 2: pattern = [Vector2i(2, 3), Vector2i(15, 5)]
			elif variant == 3: pattern = [Vector2i(4, 2), Vector2i(13, 6), Vector2i(2, 5)]
		"pillars":
			pattern = [[Vector2i(4, 3), Vector2i(13, 3), Vector2i(4, 5), Vector2i(13, 5)], [Vector2i(5, 2), Vector2i(12, 4), Vector2i(5, 6)], [Vector2i(3, 4), Vector2i(9, 2), Vector2i(14, 5), Vector2i(9, 6)]][variant - 1]
		"zigzag":
			pattern = [[Vector2i(6, 2), Vector2i(6, 3), Vector2i(11, 5), Vector2i(11, 6)], [Vector2i(4, 2), Vector2i(5, 2), Vector2i(11, 4), Vector2i(12, 4), Vector2i(5, 6)], [Vector2i(5, 3), Vector2i(5, 4), Vector2i(11, 3), Vector2i(11, 4), Vector2i(12, 6)]][variant - 1]
		"bridge":
			for x in ([4, 13] if variant == 1 else ([5, 11] if variant == 2 else [3, 14])):
				for y in ([2, 3, 5, 6] if variant != 2 else [1, 2, 4, 5]):
					pattern.append(Vector2i(x, y))
		"loop":
			pattern = [[Vector2i(6, 3), Vector2i(11, 3), Vector2i(6, 5), Vector2i(11, 5)], [Vector2i(5, 3), Vector2i(12, 3), Vector2i(5, 5), Vector2i(12, 5), Vector2i(8, 3)], [Vector2i(7, 2), Vector2i(11, 2), Vector2i(7, 6), Vector2i(11, 6), Vector2i(11, 4)]][variant - 1]
		"side_doors":
			pattern = [[Vector2i(3, 2), Vector2i(14, 2), Vector2i(3, 6), Vector2i(14, 6)], [Vector2i(3, 3), Vector2i(14, 5), Vector2i(7, 2)], [Vector2i(2, 4), Vector2i(15, 4), Vector2i(6, 6), Vector2i(11, 2)]][variant - 1]
	for cell in pattern:
		var c = Vector2i(cell)
		cells[key(c)] = true
		blocks.append(Rect2(AREA.position + Vector2(c) * TILE, Vector2(TILE, TILE)))

func corridor(cell: Vector2i) -> bool:
	return cell.x in [8, 9] or cell.y == 4 or cell.x < 2 or cell.x > 15 or cell.y < 1 or cell.y > 7

func all_reachable() -> bool:
	rebuild_flow(center(Vector2i(8, 4)))
	for y in HEIGHT:
		for x in WIDTH:
			var cell = Vector2i(x, y)
			if is_walkable(cell) and not flow.has(key(cell)): return false
	return true

func rebuild_blocks() -> void:
	fine_navigation.clear()
	blocks.clear()
	for name in cells:
		var pair = str(name).split(",")
		blocks.append(Rect2(AREA.position + Vector2(int(pair[0]), int(pair[1])) * TILE, Vector2.ONE * TILE))

func build_procedural(random, biome_id: String, room_kind: String) -> void:
	template_id = "procedural_" + biome_id
	region = 0
	cells.clear()
	baked_cells.clear()
	objects.clear()
	if room_kind not in ["combat", "elite", "challenge"]:
		rebuild_blocks()
		return
	var family = random.choose(["bamboo_wall", "stone_wall", "rope_wall"])
	var cluster_count = random.between(3, 5)
	for group in cluster_count:
		var anchor = Vector2i(random.between(3, 14), random.between(1, 7))
		var cluster: Array = []
		var target_count = random.between(2, 5)
		for attempt in 24:
			var candidate = anchor if cluster.is_empty() else Vector2i(random.choose(cluster)) + Vector2i(random.choose([Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]))
			if corridor(candidate) or cells.has(key(candidate)) or not contains_floor(center(candidate), 48): continue
			cells[key(candidate)] = true
			if not all_reachable():
				cells.erase(key(candidate))
				continue
			cluster.append(candidate)
			if cluster.size() >= target_count: break
		for cell in cluster:
			objects.append({"key": key(cell), "cell": Vector2(cell), "pos": center(cell), "kind": family, "group": group,
				"hp": 80.0 if family == "stone_wall" else 34.0, "alive": true, "solid": true,
				"phase": random.unit() * TAU, "hit_until": 0.0, "fuse_until": 0.0})
	# Explosive urns and retracting seals occupy free cells beside connected scenery.
	var available: Array = []
	for y in range(1, 8):
		for x in range(2, 16):
			var cell = Vector2i(x, y)
			if not corridor(cell) and not cells.has(key(cell)) and contains_floor(center(cell), 48): available.append(cell)
	for i in mini(random.between(4, 7), available.size()):
		var cell = Vector2i(random.choose(available))
		available.erase(cell)
		var kind = random.choose(["powder_urn", "oil_lamp"]) if i < 3 else "thorn_seal"
		var solid = kind != "thorn_seal"
		if solid:
			cells[key(cell)] = true
			if not all_reachable():
				cells.erase(key(cell))
				continue
		objects.append({"key": key(cell), "cell": Vector2(cell), "pos": center(cell), "kind": kind, "group": -1,
			"hp": 12.0 if solid else 9999.0, "alive": true, "solid": solid, "phase": random.unit() * TAU,
			"hit_until": 0.0, "fuse_until": 0.0})
	rebuild_blocks()

func connections(object: Dictionary) -> int:
	var mask = 0
	var offsets = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in offsets.size():
		var location = Vector2i(object.cell) + offsets[i]
		if objects.any(func(other): return other.alive and other.kind == object.kind and Vector2i(other.cell) == location): mask |= 1 << i
	return mask

func remove_object(object: Dictionary) -> void:
	object.alive = false
	if object.solid:
		cells.erase(str(object.key))
		rebuild_blocks()
		flow.clear()

func restore_objects(values: Array) -> void:
	cells.clear()
	baked_cells.clear()
	objects = values.filter(func(object): return contains_floor(object.pos, 34)).duplicate(true)
	for object in objects:
		# Vector2i is encoded by the save store as Vector2; normalize at the boundary.
		object.cell = Vector2(object.cell)
		if object.alive and object.solid: cells[str(object.key)] = true
	rebuild_blocks()

func clipped_ray(from: Vector2, to: Vector2, radius: float = 0.0) -> Vector2:
	var length = from.distance_to(to)
	if length < .001: return from
	var low = 0.0
	var high = 1.0
	if not contains_floor(from, radius): return from
	if clear_swept_segment(from, to, radius): return to
	for iteration in 18:
		var middle = (low + high) * .5
		var point = from.lerp(to, middle)
		if clear_swept_segment(from, point, radius): low = middle
		else: high = middle
	return from.lerp(to, low)

func clear_swept_segment(from: Vector2, to: Vector2, radius: float) -> bool:
	if not contains_floor(from, radius) or not contains_floor(to, radius): return false
	for rect in blocks:
		if not segment_rect(from,to,rect.grow(radius)): continue
		if segment_rect(from,to,rect): return false
		# Rounded corners must match valid_circle/slide, rather than using a
		# larger square that rejects legal actor positions near obstacle corners.
		if from.distance_squared_to(from.clamp(rect.position,rect.end))<radius*radius or to.distance_squared_to(to.clamp(rect.position,rect.end))<radius*radius: return false
		for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
			if Geometry2D.get_closest_point_to_segment(corner,from,to).distance_squared_to(corner)<radius*radius: return false
	return true

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func cell_of(position: Vector2) -> Vector2i:
	return Vector2i(floor((position.x - AREA.position.x) / TILE), floor((position.y - AREA.position.y) / TILE))

func center(cell: Vector2i) -> Vector2:
	return AREA.position + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE

func is_walkable(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT and not cells.has(key(cell)) and contains_floor(center(cell), 12)

func rebuild_flow(target: Vector2) -> void:
	flow.clear()
	var start = cell_of(target)
	if not is_walkable(start):
		var distance = INF
		for y in HEIGHT:
			for x in WIDTH:
				var cell = Vector2i(x, y)
				if is_walkable(cell) and center(cell).distance_squared_to(target) < distance:
					start = cell
					distance = center(cell).distance_squared_to(target)
		if distance == INF: return
	var queue: Array = [start]
	flow[key(start)] = 0
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next = current + offset
			if is_walkable(next) and not flow.has(key(next)):
				flow[key(next)] = flow[key(current)] + 1
				queue.append(next)

func navigation_waypoint(position: Vector2, target: Vector2, radius: float = 12, spacing: float = 16) -> Vector2:
	var cache_key = "%s/%s" % [radius,spacing]
	if not fine_navigation.has(cache_key):
		var grid = AStarGrid2D.new()
		grid.region=Rect2i(Vector2i.ZERO,Vector2i(ceili(bounds.size.x/spacing),ceili(bounds.size.y/spacing)))
		grid.cell_size=Vector2.ONE*spacing
		grid.offset=bounds.position+Vector2.ONE*spacing*.5
		grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		var free: Array = []
		for y in grid.region.size.y:
			for x in grid.region.size.x:
				var id=Vector2i(x,y)
				if valid_circle(grid.get_point_position(id),radius): free.append(id)
				else: grid.set_point_solid(id)
		fine_navigation[cache_key]={"grid":grid,"free":free}
	var grid = fine_navigation[cache_key].grid
	var start = Vector2i(-1,-1)
	var goal = Vector2i(-1,-1)
	var start_distance = INF
	var goal_distance = INF
	for id in fine_navigation[cache_key].free:
		var point = grid.get_point_position(id)
		var distance = point.distance_squared_to(position)
		if distance<start_distance and clear_swept_segment(position,point,radius): start=id; start_distance=distance
		distance = point.distance_squared_to(target)
		if distance<goal_distance: goal=id; goal_distance=distance
	if start.x<0 or goal.x<0:
		return navigation_waypoint(position,target,radius,spacing*.5) if spacing>4 else position
	var path = grid.get_point_path(start,goal,true)
	# The inner wall can leave a legal strip narrower than the base grid.
	# Refine only an unavailable connection, and cache it for this room/radius.
	if (path.is_empty() or path[-1]!=grid.get_point_position(goal)) and spacing>4:
		return navigation_waypoint(position,target,radius,spacing*.5)
	var result = position
	for point in path:
		if position.distance_to(point)>96:
			# A legal narrow fringe may have no grid centre within the lookahead.
			# Join its first visible node through the already verified swept lane.
			if result==position and clear_swept_segment(position,point,radius):
				result=position.move_toward(point,96)
			break
		if clear_swept_segment(position,point,radius): result=point
	return result

func toward(position: Vector2, target: Vector2, radius: float = 12) -> Vector2:
	var cell = cell_of(position)
	if clear_swept_segment(position, target,radius):
		return position.direction_to(target)
	if not is_walkable(cell):
		# A circle can legally enter a clipped corner whose grid centre is outside.
		# Connect that fringe to the nearest visible flow cell instead of steering
		# back into an unreachable grid centre beyond the wall.
		var anchor = position
		var distance = INF
		for y in HEIGHT:
			for x in WIDTH:
				var candidate = Vector2i(x,y)
				var point = center(candidate)
				if flow.has(key(candidate)) and point.distance_squared_to(position)<distance and valid_circle(point,radius) and clear_swept_segment(position,point,radius):
					anchor=point; distance=point.distance_squared_to(position)
		if distance==INF: anchor=navigation_waypoint(position,target,radius)
		return position.direction_to(anchor)
	var best = cell
	var score = int(flow.get(key(cell), 9999))
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next = cell + offset
		var value = int(flow.get(key(next), 9999))
		if value < score and valid_circle(center(next),radius):
			best = next
			score = value
	if best==cell: return position.direction_to(navigation_waypoint(position,target,radius))
	return position.direction_to(center(best))

func slide(position: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var result = position if contains_floor(position, radius) else nearest_free(position, radius)
	# Substeps prevent dash and enemy lunges tunneling through one-tile obstacles.
	var steps = maxi(1, int(ceil(displacement.length() / 12.0)))
	var step = displacement / steps
	for unused in steps:
		var combined = result+step
		if valid_circle(combined,radius) and clear_swept_segment(result,combined,radius):
			result=combined
			continue
		var candidate = result + Vector2(step.x, 0)
		if valid_circle(candidate, radius) and clear_swept_segment(result,candidate,radius):
			result.x = candidate.x
		candidate = result + Vector2(0, step.y)
		if valid_circle(candidate, radius) and clear_swept_segment(result,candidate,radius):
			result.y = candidate.y
	return result

func valid_circle(position: Vector2, radius: float) -> bool:
	if not contains_floor(position, radius):
		return false
	for rect in blocks:
		var nearest = position.clamp(rect.position, rect.end)
		if position.distance_squared_to(nearest) < radius * radius:
			return false
	return true

func clear_segment(from: Vector2, to: Vector2) -> bool:
	if not contains_floor(from) or not contains_floor(to): return false
	var minimum = from.min(to)
	var maximum = from.max(to)
	for rect in blocks:
		if rect.position.x > maximum.x or rect.end.x < minimum.x or rect.position.y > maximum.y or rect.end.y < minimum.y: continue
		if segment_rect(from, to, rect):
			return false
	return true

static func segment_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var delta = to - from
	var near = 0.0
	var far = 1.0
	for axis in 2:
		if absf(delta[axis]) < 0.00001:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return false
		else:
			var a = (rect.position[axis] - from[axis]) / delta[axis]
			var b = (rect.end[axis] - from[axis]) / delta[axis]
			near = maxf(near, minf(a, b))
			far = minf(far, maxf(a, b))
			if near > far:
				return false
	return true

static func segment_circle(from: Vector2, to: Vector2, point: Vector2, radius: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(point, from, to).distance_squared_to(point) <= radius * radius
