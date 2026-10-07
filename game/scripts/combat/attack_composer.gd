extends RefCounted
## One immutable recipe per root attack. Carriers and impact effects compose;
## child fragments never re-enter primary procs or recursively split/explode.
const Geometry = preload("res://scripts/combat/room_geometry.gd")
const Scenery = preload("res://scripts/combat/interactive_scenery.gd")
const Impact = preload("res://scripts/combat/impact_control.gd")
const FAMILIES = ["ember", "ink", "thread", "prism", "lotus", "smoke", "frost", "storm", "void", "brass"]

static func recipe(w, weapon: Dictionary) -> Dictionary:
	var base_count = 3 if weapon.mode == "prism" else int(weapon.pellets)
	var count = base_count
	for pair in [["r55", 3], ["r56", 4], ["r57", 5]]:
		if w.stack(pair[0]) > 0: count = maxi(count, pair[1])
	count = clampi(count, 1, 8)
	var beam = weapon.mode in ["ray", "prism", "tether"] or w.stack("r59") > 0
	var carrier = "beam" if beam else ("arc" if weapon.mode in ["arc", "charged_arc", "cone", "sweep"] else ("area" if weapon.mode == "nova" else ("chain" if weapon.mode == "lightning" else "projectile")))
	var explosive = weapon.mode in ["flame_orb", "explosive", "cloud", "rain", "mine", "homing_cluster"] or w.stack("r58") > 0
	var radius = 42.0 if weapon.mode == "flame_orb" else (92.0 if weapon.mode == "explosive" else (72.0 if weapon.mode in ["cloud", "rain", "mine"] else (48.0 if weapon.mode == "homing_cluster" else 76.0)))
	var charged = w.stack("r66") > 0
	var family = {"bell": "brass", "piercing": "ink", "charged_line": "ink", "ray": "ink", "tether": "thread",
		"prism": "prism", "lightning": "storm", "cloud": "smoke", "controlled": "lotus", "rain": "lotus",
		"returning": "lotus", "boomerang_arc": "void", "wave": "ink", "mine": "brass", "orbit_blade": "lotus"}.get(weapon.mode, "ember")
	return {"version": 1, "weapon": weapon.id, "mode": weapon.mode, "carrier": carrier,
		"pellets": count, "base_pellets": base_count, "spread": maxf(.16 if count > 1 else 0, float(weapon.get("spread", .16))),
		"pierce": int(weapon.pierce) + w.stack("r41") + w.talent("t_ink_1a") + int(w.run.character == "c_ink") + 2 * w.stack("r60"),
		"explosive": explosive, "blast_radius": radius * w.stat_multiplier("blast_radius") * (1.25 if charged else 1.0),
		"blast_factor": 1.4 if weapon.mode == "mine" else (.42 if w.stack("r58") > 0 else .5),
		"homing": w.stack("r61") > 0 or weapon.mode in ["seeker", "homing_cluster"],
		"controlled": w.stack("r62") > 0 or weapon.mode in ["controlled", "guided_swarm"],
		"bounces": mini(3, (2 if weapon.mode == "ricochet" else 0) + w.stack("r63")),
		"split": w.stack("r64") > 0 or weapon.mode == "split", "linger": w.stack("r65") > 0,
		"return": weapon.mode in ["returning", "boomerang_arc"] or w.stack("r35") > 0,
		"damage_factor": (1.8 if charged else 1.0) * (.86 if count > base_count else 1.0),
		"interval": float(weapon.interval_s) * (1 + .06 * maxi(0, count - base_count)) / w.stat_multiplier("fire_rate"),
		"speed": float(weapon.projectile_speed) * w.stat_multiplier("shot_speed"),
		"range": maxf(240 if beam else 0, float(weapon.range)) * w.stat_multiplier("range") * (1.15 if beam and w.stack("r60") > 0 else 1),
		"width": (14 + 4 * w.stack("r41")) * w.stat_multiplier("beam_width") * (1.3 if charged else 1),
		"push": minf(float(w.db.rules.combat.control.push_distance_cap), Impact.distance(w, "primary", false, weapon.id) * w.stat_multiplier("knockback")),
		"fx_family": family, "attack": w.attack_uid, "pulse": w.active_pulse, "primary": true, "depth": 0, "wave": 0}

static func directions(recipe_data: Dictionary, aim: Vector2) -> Array:
	var result: Array = []
	for i in int(recipe_data.pellets):
		var angle = (i - (int(recipe_data.pellets) - 1) * .5) * float(recipe_data.spread)
		if recipe_data.mode == "radial": angle = i * TAU / int(recipe_data.pellets)
		result.append(aim.rotated(angle).normalized())
	return result

static func fire(w, weapon: Dictionary, resolved: Dictionary, damage: float, crit: bool, point: Vector2, aim: Vector2, burst_part: bool = false) -> void:
	var shot = resolved.duplicate(true)
	var amount = damage * float(shot.damage_factor)
	var lanes = directions(shot, aim)
	match shot.carrier:
		"beam":
			for direction in lanes:
				var guided = direction
				if shot.homing:
					var candidates = w.enemies.filter(func(enemy): return not enemy.dead and point.distance_to(enemy.pos) <= shot.range and direction.dot(point.direction_to(enemy.pos)) > .8 and w.geometry.clear_segment(point, enemy.pos))
					candidates.sort_custom(func(a,b): return point.distance_squared_to(a.pos) < point.distance_squared_to(b.pos))
					if not candidates.is_empty(): guided = direction.slerp(point.direction_to(candidates[0].pos), .45).normalized()
				beam(w, point, guided, shot.range, amount, crit, shot)
		"chain":
			for direction in lanes: chain(w, point, direction, amount, crit, shot)
		"area":
			for i in 3:
				var wave = shot.duplicate(true)
				wave.wave = i
				var radius = minf(360, (90 + i * 75) * w.stat_multiplier("blast_radius"))
				for direction in lanes:
					var center = point if lanes.size() == 1 else w.geometry.constrain_floor(point + direction * 82, 8)
					# All overlapping lobes of this wave share one target damage ledger.
					schedule_area(w, center, radius, amount / 3, i * .16, str(shot.fx_family) + "_ring", "%d/nova/%d" % [shot.attack, i], wave)
		"arc":
			var hit_ids: Array = []
			var width = 1.05 if weapon.mode in ["charged_arc", "sweep"] else .8
			for direction in lanes:
				for enemy in w.enemies.duplicate():
					if enemy.dead or hit_ids.has(enemy.uid) or enemy.pos.distance_to(point) > shot.range or direction.dot(point.direction_to(enemy.pos)) < cos(width) or not w.geometry.clear_segment(point, enemy.pos): continue
					hit_ids.append(enemy.uid)
					hit(w, enemy, amount * (1.18 if lanes.size() > 1 else 1), crit, direction, shot)
				for object in w.geometry.objects:
					if object.alive and object.pos.distance_to(point) < shot.range and direction.dot(point.direction_to(object.pos)) >= cos(width): Scenery.hit(w, object, amount)
				w.emit("slash", {"pos": point, "dir": direction, "range": shot.range, "weapon": weapon.id, "mode": weapon.mode, "charged": weapon.mode in ["charged_arc", "sweep"], "fx_family": shot.fx_family})
		"projectile":
			for i in lanes.size(): projectile(w, point, lanes[i], amount, crit, shot, (i - (lanes.size() - 1) * .5) * shot.spread)
			if weapon.mode == "burst" and not burst_part:
				for i in [1, 2]:
					var repeat = shot.duplicate(true)
					repeat.wave = i
					schedule_fire(w, weapon, repeat, damage, crit, point, aim, i * .09, true)
	w.emit("shot", {"pos": point, "dir": aim, "weapon": weapon.id, "mode": weapon.mode,
		"pellets": shot.pellets, "heavy": shot.explosive or shot.carrier != "projectile", "fx_family": shot.fx_family})

static func projectile(w, origin: Vector2, direction: Vector2, damage: float, crit: bool, shot: Dictionary, lane: float = 0) -> Dictionary:
	if w.bullets.size() >= 240: return {}
	var radius = 11.0 if shot.mode in ["wave", "cloud"] else (5.0 if shot.mode in ["piercing", "charged_line"] else 7.0)
	var bullet = {"uid": w.next_uid(), "pos": w.geometry.constrain_floor(origin + direction * 22, radius),
		"dir": direction, "base_dir": direction, "speed": shot.speed, "range": shot.range, "travel": 0.0,
		"damage": damage, "radius": radius, "friendly": true, "primary": shot.primary,
		"attack": shot.attack, "crit": crit, "mode": shot.mode, "weapon": shot.weapon,
		"pierce": shot.pierce, "hits": [], "returning": false, "bounces": 0, "age": 0.0,
		"can_return": shot["return"], "pulse": shot.pulse, "target_index": 0, "push_distance": shot.push,
		"recipe": shot.duplicate(true), "lane": lane, "controllable": shot.controlled,
		"motion": "wave" if shot.mode == "wave" else "", "impact_done": false, "fx_family": shot.fx_family}
	w.bullets.append(bullet)
	return bullet

static func hit(w, enemy: Dictionary, damage: float, crit: bool, direction: Vector2, shot: Dictionary) -> void:
	if enemy.dead or w.time < float(enemy.get("arrival", 0)): return
	if shot.primary: w.primary_hit(enemy, damage, int(shot.attack), crit, direction, shot.push, shot)
	else:
		w.damage_enemy(enemy, damage, "secondary", crit, direction, shot.push)
		hit_effects(w, enemy.pos, damage, shot)

static func effect_key(shot: Dictionary, suffix: String) -> String:
	return "composition/%d/%d/%s" % [int(shot.attack), int(shot.get("wave", 0)), suffix]

static func claim(w, shot: Dictionary, key: String) -> bool:
	var name = effect_key(shot, key)
	if w.room_flags.get("composition_ledger", {}).has(name): return false
	if not w.room_flags.has("composition_ledger"): w.room_flags.composition_ledger = {}
	w.room_flags.composition_ledger[name] = w.time + 12.0
	return true

static func hit_effects(w, point: Vector2, damage: float, shot: Dictionary, terminal: bool = false) -> void:
	if shot.is_empty() or int(shot.get("depth", 0)) > 0: return
	var tile = "%d/%d" % [roundi(point.x / 48), roundi(point.y / 48)]
	if shot.explosive:
		if shot.mode == "mine":
			if (terminal or shot.carrier != "projectile") and claim(w, shot, "mine_origin/" + tile):
				schedule_area(w, point, shot.blast_radius, damage * 1.4, .65, str(shot.fx_family) + "_blast", effect_key(shot, "mine"))
		else: explosion(w, point, shot.blast_radius, damage * shot.blast_factor, shot)
	if (terminal or shot.carrier != "projectile") and claim(w, shot, "terrain_origin/" + tile):
		if shot.mode == "rain":
			for i in [1, 2]: schedule_area(w, point, shot.blast_radius, damage * .5, i * .28, str(shot.fx_family) + "_vortex", effect_key(shot, "rain/" + str(i)))
		elif shot.mode == "cloud":
			var previous = w.zones.size()
			w.add_zone(point, shot.blast_radius, 2.5, damage * .45, true)
			if w.zones.size() > previous: w.zones[-1].fx_preset = str(shot.fx_family) + "_field"
	if shot.linger and claim(w, shot, "field_at_" + tile):
		var previous = w.zones.size()
		w.add_zone(point, 52, 1.7, damage * .18, true)
		if w.zones.size() > previous: w.zones[-1].fx_preset = str(shot.fx_family) + "_field"

static func explosion(w, point: Vector2, radius: float, damage: float, shot: Dictionary, suffix: String = "blast") -> void:
	var origin_key = suffix + "/origin/%d/%d" % [roundi(point.x / 8), roundi(point.y / 8)]
	if not claim(w, shot, origin_key) or not w.claim_secondary(): return
	for enemy in w.enemies.duplicate():
		if enemy.dead or enemy.pos.distance_to(point) > radius + enemy.radius or not w.geometry.clear_segment(point, enemy.pos): continue
		if claim(w, shot, suffix + "/target/" + str(int(enemy.uid))): w.damage_enemy(enemy, damage, "secondary", false, point.direction_to(enemy.pos))
	Scenery.area_hit(w, point, radius, damage)
	w.emit("burst", {"pos": point, "radius": radius, "style": "blast_flame", "fx_preset": str(shot.fx_family) + "_blast", "heavy": true, "attack": shot.attack})

static func beam(w, point: Vector2, direction: Vector2, distance: float, damage: float, crit: bool, shot: Dictionary, bounce: int = 0) -> void:
	var width = clampf(float(shot.width), 7, 34)
	var from = w.geometry.constrain_floor(point, width)
	var to = w.geometry.clipped_ray(from, from + direction * distance, width)
	var hit_any = false
	for enemy in w.enemies.duplicate():
		if not enemy.dead and w.geometry.clear_segment(from, enemy.pos) and Geometry.segment_circle(from, to, enemy.pos, enemy.radius + width):
			hit_any = true
			hit(w, enemy, damage, crit, direction, shot)
	Scenery.segment_hit(w, from, to + direction * (width + 4), damage)
	var shape = "beam_tether" if shot.mode == "tether" else ("beam_fork" if shot.mode == "lightning" else ("beam_wave" if shot.mode == "wave" else "beam_lance"))
	w.emit("ray", {"pos": from, "end": to, "dir": direction, "range": from.distance_to(to), "width": width,
		"weapon": shot.weapon, "style": "beam_ink", "fx_preset": str(shot.fx_family) + "_" + shape, "heavy": true})
	if shot.mode == "tether":
		for enemy in w.enemies:
			if Geometry.segment_circle(from, to, enemy.pos, enemy.radius + width): enemy.slow_until = maxf(enemy.slow_until, w.time + .4)
	if not hit_any: hit_effects(w, to, damage, shot)
	if shot.split and claim(w, shot, "beam_split"):
		fragments(w, to, direction, damage, shot)
	var traveled = from.distance_to(to)
	if bounce < int(shot.bounces) and traveled + 28 < distance:
		var probe_x = to + Vector2(direction.x * 6, 0)
		var probe_y = to + Vector2(0, direction.y * 6)
		var reflected = direction
		if not w.geometry.clear_swept_segment(to, probe_x, width): reflected.x *= -1
		elif not w.geometry.clear_swept_segment(to, probe_y, width): reflected.y *= -1
		else: reflected = -direction
		beam(w, to - direction * 4, reflected.normalized(), distance - traveled, damage * .82, crit, shot, bounce + 1)

static func chain(w, point: Vector2, direction: Vector2, damage: float, crit: bool, shot: Dictionary) -> void:
	var from = point
	var selected: Array = []
	for jump in 3:
		var candidates = w.enemies.filter(func(enemy): return not enemy.dead and not selected.has(enemy.uid) and from.distance_to(enemy.pos) <= (shot.range if jump == 0 else 230) and (jump > 0 or direction.dot(from.direction_to(enemy.pos)) >= -.1) and w.geometry.clear_segment(from, enemy.pos))
		candidates.sort_custom(func(a,b): return from.distance_squared_to(a.pos) < from.distance_squared_to(b.pos))
		if candidates.is_empty(): break
		var enemy = candidates[0]
		hit(w, enemy, damage * pow(.8, jump), crit, from.direction_to(enemy.pos), shot)
		w.emit("ray", {"pos": from, "end": enemy.pos, "dir": from.direction_to(enemy.pos), "range": from.distance_to(enemy.pos), "width": 8,
			"weapon": shot.weapon, "style": "beam_prism", "fx_preset": str(shot.fx_family) + "_beam_fork"})
		selected.append(enemy.uid)
		from = enemy.pos

static func fragments(w, point: Vector2, direction: Vector2, damage: float, shot: Dictionary) -> void:
	var child = shot.duplicate(true)
	child.primary = false
	child.depth = 1
	child.explosive = false
	child.split = false
	child.linger = false
	child.carrier = "projectile"
	child.mode = "piercing"
	child.bounces = 0
	child["return"] = false
	child.range = minf(300, float(child.range))
	for angle in [-.62, .62]: projectile(w, point, direction.rotated(angle), damage * .42, false, child)

static func impact(w, bullet: Dictionary, point: Vector2) -> bool:
	if not bullet.has("recipe"): return false
	if not bullet.friendly or bullet.get("impact_done", false): return true
	bullet.impact_done = true
	var shot = bullet.recipe
	if int(shot.depth) > 0: return true
	hit_effects(w, point, bullet.damage, shot, true)
	if shot.split: fragments(w, point, bullet.dir, bullet.damage, shot)
	w.emit("impact", {"pos": point, "dir": bullet.dir, "friendly": true, "fx_family": shot.fx_family})
	return true

static func tick(w, bullet: Dictionary, delta: float) -> bool:
	if not bullet.has("recipe") or bullet.returning: return false
	var shot = bullet.recipe
	if shot.controlled:
		var desired = Vector2(w.player.aim).rotated(float(bullet.get("lane", 0)))
		if shot.homing:
			var enemy = w.nearest_enemy(bullet.pos, 320)
			if not enemy.is_empty() and desired.dot(bullet.pos.direction_to(enemy.pos)) > .8: desired = desired.slerp(bullet.pos.direction_to(enemy.pos), .2)
		bullet.dir = Vector2(bullet.dir).slerp(desired.normalized(), minf(1, delta * 6)).normalized()
	elif shot.homing and bullet.age > .12:
		var enemy = w.nearest_enemy(bullet.pos, 420)
		if not enemy.is_empty() and w.geometry.clear_segment(bullet.pos, enemy.pos): bullet.dir = Vector2(bullet.dir).slerp(bullet.pos.direction_to(enemy.pos), minf(1, delta * 4)).normalized()
	return shot.controlled or shot.homing

static func schedule_fire(w, weapon: Dictionary, shot: Dictionary, damage: float, crit: bool, point: Vector2, aim: Vector2, delay: float, burst_part: bool = false) -> void:
	if w.delayed.size() >= 120: return
	w.delayed.append({"type": "composition_fire", "time": w.time + delay, "weapon": weapon.id, "recipe": shot.duplicate(true),
		"damage": damage, "crit": crit, "pos": point, "aim": aim, "pulse": shot.pulse, "burst_part": burst_part})

static func schedule_area(w, point: Vector2, radius: float, damage: float, delay: float, preset: String, key: String, resolved: Dictionary = {}) -> void:
	if w.delayed.size() >= 120: return
	point = w.geometry.constrain_floor(point, 8)
	var action = {"type": "composition_area", "time": w.time + delay, "pos": point, "radius": minf(380, radius),
		"damage": damage, "fx_preset": preset, "key": key, "pulse": w.active_pulse}
	if not resolved.is_empty(): action.recipe = resolved.duplicate(true)
	w.delayed.append(action)
	if delay > .1:
		var previous = w.zones.size()
		w.add_zone(point, radius, .01, 0, true, delay)
		if w.zones.size() > previous:
			w.zones[-1].fx_preset = preset
			w.zones[-1].anticipation_only = true

static func delayed(w, action: Dictionary) -> bool:
	if action.type == "composition_fire":
		fire(w, w.db.row("weapons", action.weapon), action.recipe, action.damage, action.crit, action.pos, action.aim, action.burst_part)
		return true
	if action.type == "composition_area":
		if not w.room_flags.has("composition_ledger"): w.room_flags.composition_ledger = {}
		for enemy in w.enemies.duplicate():
			var key = str(action.key) + "/" + str(int(enemy.uid))
			if not enemy.dead and enemy.pos.distance_to(action.pos) < action.radius + enemy.radius and w.geometry.clear_segment(action.pos, enemy.pos) and not w.room_flags.composition_ledger.has(key):
				w.room_flags.composition_ledger[key] = w.time + 12.0
				w.damage_enemy(enemy, action.damage, "secondary")
				if action.has("recipe"): hit_effects(w, enemy.pos, action.damage, action.recipe, true)
		Scenery.area_hit(w, action.pos, action.radius, action.damage)
		w.emit("burst", {"pos": action.pos, "radius": action.radius, "fx_preset": action.fx_preset, "style": "blast_flame", "heavy": true})
		return true
	return false

static func summary(w) -> Array:
	var weapon = w.db.row("weapons", w.player.weapon)
	var resolved = recipe(w, weapon)
	var rows: Array = []
	var carrier_name = {"beam": "射线", "projectile": "弹丸", "arc": "近战", "area": "震波", "chain": "连锁"}[resolved.carrier]
	rows.append({"icon": "crosshair", "name": carrier_name, "detail": str(weapon.name) + " · " + carrier_name})
	var suffix = {"beam": "束", "projectile": "发", "arc": "扇", "area": "瓣", "chain": "道"}[resolved.carrier]
	rows.append({"icon": "layers", "name": str(int(resolved.pellets)) + suffix, "detail": "三、四、五发取最高数量；相互不乘算。震波重叠区域按波次结算一次。"})
	for entry in [["explosive", "flame", "爆炸", "同次攻击的重叠爆炸对每个目标只结算一次。"],
		["homing", "target", "追踪", "弹丸平滑追踪，射线朝目标所在扇区校准。"],
		["controlled", "crosshair", "导引", "弹丸追随实时瞄准；即时攻击使用发射时的瞄准方向。"],
		["split", "sparkles", "分裂", "命中或到达终点生成两个碎片；碎片不会再次分裂或爆炸。"],
		["linger", "circle-dot", "留场", "命中留下持续场域。"],
		["return", "wind", "回旋", "弹丸飞至终点后回到身边。"]]:
		if resolved[entry[0]]: rows.append({"icon": entry[1], "name": entry[2], "detail": entry[3]})
	if resolved.bounces > 0: rows.append({"icon": "wind", "name": "反弹%d" % int(resolved.bounces), "detail": "弹丸和射线均反弹，最多三次。"})
	if resolved.pierce > 0: rows.append({"icon": "link", "name": "贯穿%d" % int(resolved.pierce), "detail": "弹丸贯穿；射线原生贯穿，贯穿供物增加射程。"})
	if w.stack("r66") > 0 or weapon.mode in ["charged_line", "charged_arc", "nova"]: rows.append({"icon": "zap", "name": "蓄力", "detail": "持续按住射击，完成蓄力后释放攻击。"})
	return rows
