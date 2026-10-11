extends RefCounted
## Every main route includes four ordinary fights and the early reward.
const TYPES = ["combat", "combat", "reward", "combat", "debt", "combat", "elite", "shop", "combat", "combat", "boss"]
const NAMES = {"combat": "恶愿", "reward": "供物", "debt": "借愿", "elite": "催账", "shop": "灯摊", "boss": "主账", "event": "断愿", "secret": "断绳", "optional_boss": "撕页", "sacrifice": "献灯", "judge": "判官", "angel": "观音", "challenge": "破阵"}

static func build(random, floor_id: int, optional_bosses: Array) -> Dictionary:
	var coords = [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(0, 3), Vector2(-1, 3), Vector2(0, 4), Vector2(0, 5), Vector2(1, 5), Vector2(-1, 4), Vector2(1, 4), Vector2(0, 6)]
	var edges: Array = [[0, 1], [1, 2], [2, 3], [3, 5], [5, 6], [6, 10], [3, 4], [4, 8], [8, 5], [5, 9], [9, 7], [7, 6]]
	var types = TYPES.duplicate()
	var entries: Array = []
	var mirror = -1 if random.unit() < .5 else 1
	for i in coords.size(): coords[i].x *= mirror
	var extra = random.between(0, 2)
	if extra > 0:
		types.append("event")
		coords.append(Vector2(-mirror, 2))
		edges.append([2, 11])
	if extra > 1:
		types.append("secret")
		coords.append(Vector2(mirror, 2))
		edges.append([2, 12])
		entries.append({"parent": 2, "room": 12, "side": mirror, "pos": Vector2(1088 if mirror > 0 else 192, 296)})
	# Three optional side rooms make route choice meaningful without touching the
	# authored main path. Their physical entrances are ordinary doors in the arena.
	var sacrifice = types.size()
	types.append("sacrifice")
	coords.append(Vector2(-2 * mirror, 3))
	edges.append([3, sacrifice])
	var judge = types.size()
	types.append("judge")
	coords.append(Vector2(2 * mirror, 4))
	edges.append([5, judge])
	var angel = types.size()
	types.append("angel")
	coords.append(Vector2(2 * mirror, 5))
	edges.append([6, angel])
	var challenge = types.size()
	types.append("challenge")
	coords.append(Vector2(-2 * mirror, 5))
	edges.append([6, challenge])
	var boss = "b04" if floor_id == 2 else ("b05" if floor_id == 3 else "")
	var boss_room = -1
	if optional_bosses.has(boss):
		boss_room = types.size()
		types.append("optional_boss")
		coords.append(Vector2(-mirror, 6))
		edges.append([6, boss_room])
	return {"types": types, "coords": coords, "edges": edges, "optional_boss": boss, "optional_boss_room": boss_room, "secret_entries": entries, "revealed": []}

static func visible(graph: Dictionary, room: int) -> bool:
	if room < 0 or room >= graph.types.size(): return false
	return graph.types[room] != "secret" or not graph.has("revealed") or graph.revealed.has(room)

static func normalize(graph: Dictionary) -> void:
	graph.edges = graph.edges.map(func(edge): return [int(edge[0]), int(edge[1])])
	if graph.has("revealed"): graph.revealed = graph.revealed.map(func(room): return int(room))
	graph.optional_boss_room = int(graph.get("optional_boss_room", -1))
	for entry in graph.get("secret_entries", []):
		for key in ["parent", "room", "side"]: entry[key] = int(entry[key])

static func can_return(graph: Dictionary, visited: Array, current: int, destination: int) -> bool:
	if destination == current or not visited.has(destination) or not visible(graph, destination): return false
	var pending = [current]
	var seen = [current]
	while not pending.is_empty():
		var node = pending.pop_front()
		for edge in graph.edges:
			if not node in edge: continue
			var next = edge[1] if edge[0] == node else edge[0]
			if not visited.has(next) or not visible(graph, next) or seen.has(next): continue
			if next == destination: return true
			seen.append(next)
			pending.append(next)
	return false

static func frontier(graph: Dictionary, visited: Array, current: int) -> Array:
	var cleared = visited.duplicate()
	if not cleared.has(current): cleared.append(current)
	var result: Array = []
	for edge in graph.edges:
		if cleared.has(edge[0]) and not cleared.has(edge[1]) and not result.has(edge[1]): result.append(edge[1])
		if cleared.has(edge[1]) and not cleared.has(edge[0]) and not result.has(edge[0]): result.append(edge[0])
	result.sort()
	return result.filter(func(room): return visible(graph, room))
