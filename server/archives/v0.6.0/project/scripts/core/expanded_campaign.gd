extends RefCounted
## All rooms and their authored roles are fixed by seed before the floor is entered.
const Seed = preload("res://scripts/core/derived_seed.gd")
const Graph = preload("res://scripts/core/room_graph.gd")
const STEPS = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const FLOOR_COLORS = ["#a34627","#244759","#cca24d","#7b9c35","#45515f","#64364f","#e6d9b6","#53428e","#4d3427","#9ec9b7","#c2cdd0","#a57f38","#344c2c","#172c43","#54285f","#3b3830","#b8a47c","#486464","#722d25","#35334f"]

static func biome(db, seed_text: String, floor_id: int) -> Dictionary:
	var rows: Array = db.expansion.biomes
	if floor_id == 6: return rows[18]
	if floor_id == 11: return rows[19]
	var order = Seed.derive(seed_text, "campaign/biome_order").shuffle(rows.slice(0, 18))
	return order[floor_id - 1 if floor_id <= 5 else floor_id + 1]

static func guest_biome(db, seed_text: String, floor_id: int) -> Dictionary:
	var local = biome(db, seed_text, floor_id)
	var own = Color(FLOOR_COLORS[int(str(local.id).substr(1)) - 1])
	var choices: Array = []
	for row in db.expansion.biomes:
		if row.id == local.id: continue
		var color = Color(FLOOR_COLORS[int(str(row.id).substr(1)) - 1])
		var hue = minf(absf(own.h - color.h), 1 - absf(own.h - color.h))
		var contrast = absf(own.get_luminance() - color.get_luminance()) * 1.8 + hue * minf(own.s, color.s) + absf(own.s - color.s) * .2
		choices.append({"row": row, "contrast": contrast})
	choices.sort_custom(func(a,b): return a.contrast > b.contrast)
	# A reproducible guest among the six most contrasting themes, rather than
	# another near-identical palette. Exactly one guest theme is used per floor.
	return Seed.derive(seed_text, "floor/%d/guest_theme_v2" % floor_id).choose(choices.slice(0, 6)).row

static func mob_prefix(graph: Dictionary, floor_id: int, room_id: int) -> int:
	var prefix = 0
	for room in room_id:
		match graph.types[room]:
			"elite": prefix += 4
			"challenge":
				for wave in 3: prefix += mini(7,4+floor_id+wave)
			"combat":
				var total = 3+mini(3,room/3)+mini(4,floor_id-1)
				prefix += maxi(6,total) if room>=8 or (floor_id>=2 and room==5) else mini(6,total)
	return prefix

static func boss_prefix(floor_id: int) -> int:
	return (floor_id-1)*2 if floor_id<=6 else 12+(floor_id-7)*4

static func mix_bosses(assignments: Dictionary, map: Dictionary, guest: Dictionary, random, seed_text: String, floor_id: int) -> Dictionary:
	var slots: Array = []
	for room in assignments:
		if assignments[room] in [["b36"], ["b37"]]: continue
		for i in assignments[room].size(): slots.append(room)
	# The campaign has 36 random boss slots. A single shuffled quota deck keeps
	# 14 guests (nearest possible to 40%) without rounding every pair to 50%.
	var origins: Array = []
	for i in 36: origins.append(i < roundi(36*.4))
	origins = Seed.derive(seed_text,"campaign/boss_origins_v2").shuffle(origins)
	# The six consecutive final rooms must also have six distinct boss identities;
	# a guest owns three bosses. Exchange excess guest slots outside the gauntlet
	# while keeping the campaign's total quota unchanged.
	var guests = 0
	for i in range(28,34):
		if not origins[i]: continue
		guests += 1
		if guests <= 3: continue
		var candidates = [34,35]
		candidates.append_array(range(28))
		for other in candidates:
			if not origins[other]:
				origins[other] = true
				origins[i] = false
				break
	origins = origins.slice(boss_prefix(floor_id),boss_prefix(floor_id)+slots.size())
	var used: Array = []
	var result = assignments.duplicate(true)
	for room in result:
		if result[room] not in [["b36"], ["b37"]]: result[room] = []
	for i in slots.size():
		var room = slots[i]
		var pool: Array = guest.random_boss_ids if origins[i] else map.random_boss_ids
		var available = pool.filter(func(id): return not used.has(id) and not result[room].has(id))
		if available.is_empty(): available = pool.filter(func(id): return not result[room].has(id))
		var id = random.choose(available)
		result[room].append(id)
		used.append(id)
	return result

static func path(random, count: int) -> Array:
	# Backtracking prevents the rare four-sided pocket from overlapping rooms.
	var result: Array = [Vector2.ZERO]
	var tried: Dictionary = {}
	while result.size() < count:
		var here = Vector2(result[-1])
		var key = str(here)
		if not tried.has(key): tried[key] = random.shuffle(STEPS)
		var options: Array = tried[key]
		var moved = false
		while not options.is_empty():
			var target = here + Vector2(options.pop_back())
			if result.has(target): continue
			result.append(target)
			moved = true
			break
		if not moved:
			tried.erase(key)
			result.pop_back()
	return result

static func build(db, seed_text: String, floor_id: int) -> Dictionary:
	var random = Seed.derive(seed_text, "floor/%d/graph" % floor_id)
	var count = 32 if floor_id == 11 else 12 + random.between(0, 3)
	var coords = path(random, count)
	var types: Array = []
	var edges: Array = []
	var assignments: Dictionary = {}
	var roles: Dictionary = {}
	var map = biome(db, seed_text, floor_id)
	var guest = guest_biome(db, seed_text, floor_id)
	var boss_random = Seed.derive(seed_text, "floor/%d/boss_composition" % floor_id)
	for i in count:
		types.append("combat")
		if i > 0: edges.append([i - 1, i])
	types[2] = "reward"
	types[4] = "debt"
	types[7] = "shop"
	types[9] = "elite"
	types[count - 1] = "boss"
	if floor_id == 6: assignments[str(count - 1)] = [db.expansion.mid_boss]
	elif floor_id == 11:
		assignments[str(count - 1)] = [db.expansion.final_boss]
		for j in 6:
			var index = count - 7 + j
			types[index] = "optional_boss"
			assignments[str(index)] = [""]
			roles[str(index)] = "gauntlet_%d" % (j + 1)
	else:
		assignments[str(count - 1)] = ["", ""] if floor_id >= 7 else [""]
	roles[str(count - 1)] = "final" if floor_id == 11 else ("story" if floor_id == 6 else "floor_exit")
	var entries: Array = []
	var branches = random.shuffle(["sacrifice", "judge", "angel", "challenge", "event", "reward", "secret"])
	branches.push_front("optional_boss")
	for kind in branches:
		var found = false
		# Final six boss chambers have no shortcut edges or branch exits.
		var parents = random.shuffle(range(1, count - (7 if floor_id == 11 else 2)))
		for parent in parents:
			for step in random.shuffle([Vector2.LEFT, Vector2.RIGHT] if kind == "secret" else STEPS):
				var candidate = Vector2(coords[parent]) + Vector2(step)
				if coords.has(candidate): continue
				var index = types.size()
				coords.append(candidate)
				types.append(kind)
				edges.append([parent, index])
				if kind == "secret": entries.append({"parent": parent, "room": index, "side": int(step.x), "pos": Vector2(1088 if step.x > 0 else 192, 296)})
				if kind == "optional_boss":
					assignments[str(index)] = [""] if floor_id <= 5 else ["", ""]
					roles[str(index)] = "side_boss" if floor_id <= 5 else "double_boss"
				found = true
				break
			if found: break
	var backgrounds: Dictionary = {}
	for i in types.size():
		backgrounds[str(i)] = int(Seed.derive(seed_text, "floor/%d/room/%d/background" % [floor_id, i]).between(0, 1))
	return {"types": types, "coords": coords, "edges": edges, "optional_boss": "", "optional_boss_room": -1,
		"secret_entries": entries, "revealed": [], "boss_assignments": mix_bosses(assignments, map, guest, boss_random, seed_text, floor_id), "room_roles": roles,
		"biome": map.id, "guest_biome": guest.id, "backgrounds": backgrounds, "campaign": 2, "encounter_mix": .4}

static func boss_ids(graph: Dictionary, room: int) -> Array:
	return graph.get("boss_assignments", {}).get(str(room), [])

static func story_for_floor(db, floor_id: int, seed_text: String = "") -> Dictionary:
	var id = "reveal" if floor_id == 6 else ("ordeal" if floor_id == 7 else ("final" if floor_id == 11 else ""))
	if id.is_empty():
		var map = biome(db, seed_text, floor_id) if not seed_text.is_empty() else {}
		var journeys = {2: "沿河而行的名字，不该永远被渡船收藏。", 3: "铜钱可以买来一夜光，却买不回被抹去的名字。", 4: "有些人只借了一缕火，便把一生都留在纸上。", 5: "秤影已经近了。有人在账页背面悄悄写下归路。", 8: "第二道封契裂开。守债者开始记起自己许过的愿。", 9: "第三道封契后，灯与影已分不清谁在追赶谁。", 10: "最后一道封契之后，再没有人能替你做出选择。"}
		return {"id": "floor_%d" % floor_id, "title": "第%d重 · %s" % [floor_id, str(map.get("name", "旧账"))],
			"lines": [str(journeys.get(floor_id, "带着取回的名字，走入下一重旧愿。"))]}
	for row in db.expansion.story:
		if row.id == id: return row
	return {}
