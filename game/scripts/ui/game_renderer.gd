extends Node2D
const ContentDB = preload("res://scripts/core/content_db.gd")
const PaperMotion = preload("res://scripts/ui/paper_animation.gd")
const WeaponMotion = preload("res://scripts/ui/weapon_motion.gd")
const UI = preload("res://scripts/ui/game_theme.gd")
const ExpandedVisuals = preload("res://scripts/ui/expanded_visuals.gd")
const PolishedFX = preload("res://scripts/ui/polished_fx.gd")
const EquipmentUI = preload("res://scripts/ui/equipment_ui.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")
var animation = PaperMotion.new()
var weapon_motion = WeaponMotion.new()
var actor_freeze: Dictionary = {}
var player_death_clock = 0.0
## Presentation consumes events; it cannot change the authoritative world or RNG.

var world
var adapter
var textures: Dictionary = {}
var visual_effects: Array = []
var font: Font
var clock = 0.0
var shake = 0.0
var reduce_motion = false
var damage_numbers = true
var shake_scale = 1.0
var hitstop = true
var flash_scale = 1.0
var particle_scale = 1.0
var fx_budget = 900
var fx_safe_draw = false
var last_draw_us = 0
var projectile_meshes: Dictionary = {}
var effect_limit = 120
var shape_cues = false
var combat_text_scale = 1.0
var stage = Geometry.STAGE
const INK = Color("242725")
const PAPER = Color("e7d8b6")
const GOLD = Color("c39a51")
const FIRE = Color("e9a34b")
const HOSTILE = Color("75c5b2")
var hub = false
var combat_interface_visible = true

func _ready() -> void:
	font = UI.body_font(true)
	for character in ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]:
		for direction in ["down", "left", "right", "up"]:
			textures[character + "_" + direction] = load("res://assets/heroes/" + character + "_" + direction + ".png")
	var definitions = world.db if world != null else ContentDB.new()
	for table in ["enemies", "bosses"]:
		for row in definitions.rows(table):
			var path = "res://assets/" + table + "/" + row.id + ".png"
			if ResourceLoader.exists(path): textures[row.id] = load(path)
	for i in range(1, 7):
		var path = "res://assets/elites/x%02d.png" % i
		if ResourceLoader.exists(path): textures["x%02d" % i] = load(path)
	textures.floor = load("res://assets/environment/floor-paper.png")
	textures.wall = load("res://assets/environment/wall-paper.png")
	for prop in ["incense", "paper_stack", "chest", "bell"]:
		var path = "res://assets/props/" + prop + ".png"
		if ResourceLoader.exists(path):
			textures["prop_" + prop] = load(path)
	for special in ["special_sacrifice", "special_judge", "special_angel"]:
		var special_path = "res://assets/props/" + special + ".png"
		if ResourceLoader.exists(special_path):
			textures["prop_" + special] = load(special_path)
	for state in ["clue", "open", "used"]:
		textures["secret_" + state] = load("res://assets/props/secret_" + state + ".png")
	if ResourceLoader.exists("res://assets/environment/paper-temple-arena.png"):
		textures.arena = load("res://assets/environment/paper-temple-arena.png")
	for region in ["coin-vault-arena", "ownerless-temple-arena", "hub-arena"]:
		if ResourceLoader.exists("res://assets/environment/" + region + ".png"):
			textures[region] = load("res://assets/environment/" + region + ".png")
	textures.sigil = load("res://assets/relics/r06.png")

func accept(events: Array) -> void:
	weapon_motion.accept(events, world)
	for event in events:
		if event.kind in ["room_enter", "room_return"]:
			visual_effects.clear()
			actor_freeze.clear()
			animation.clear()
			shake = 0.0
		if event.kind == "player_hurt" and event.get("hp", 1) <= 0: player_death_clock = clock
		if hitstop and event.kind == "hit" and (event.get("heavy", false) or event.get("crit", false)):
			actor_freeze[event.uid] = {"until": clock + (.035 if event.get("heavy", false) else .020), "time": world.time, "pos": event.pos}
		if event.kind in ["shot", "ray", "hit", "impact", "burst", "death", "dash", "slash", "pickup", "deflect", "skill", "scenery_explosion", "scenery_break", "active_item", "equipment_taken", "loot_spawn"]:
			var effect = event.duplicate()
			effect["left"] = 0.88 if event.kind == "death" else (0.62 if event.kind == "ray" else (0.58 if event.kind == "skill" else (0.34 if event.kind == "impact" else (0.24 if event.kind == "shot" else (0.42 if event.kind != "hit" else 0.6)))))
			effect["total"] = effect.left
			if event.kind in ["burst","scenery_explosion","scenery_break"]:
				effect.left = .72
				effect.total = .72
			if event.kind in ["active_item", "equipment_taken", "loot_spawn"]:
				effect.left = .65
				effect.total = .65
			visual_effects.append(effect)
		if event.kind == "skill":
			shake = 4.0
		elif event.kind == "player_hurt":
			shake = 6.0
			if event.get("damage", 0) > 0:
				visual_effects.append({"kind": "hurt_source", "pos": Vector2(event.pos), "dir": Vector2(event.get("direction", Vector2.ZERO)),
					"ground": event.get("source", {}).get("kind", "") == "zone", "left": .8, "total": .8})
	if visual_effects.size() > effect_limit:
		visual_effects = visual_effects.slice(visual_effects.size() - effect_limit)

func _process(delta: float) -> void:
	clock += delta
	shake = maxf(0, shake - delta * 24)
	if not reduce_motion:
		position = Vector2(sin(clock * 72), cos(clock * 93)) * shake * shake_scale
	else:
		position = Vector2.ZERO
	for effect in visual_effects.duplicate():
		effect.left -= delta
		if effect.left <= 0:
			visual_effects.erase(effect)
	queue_redraw()

func _draw() -> void:
	var draw_started = Time.get_ticks_usec()
	fx_budget = roundi(900 * particle_scale)
	draw_floor()
	if hub: return
	draw_set_transform_matrix(stage)
	if world == null or world.run.is_empty():
		return
	draw_secret_entry()
	draw_room_doors()
	draw_room_ambient()
	ExpandedVisuals.ambient(self)
	ExpandedVisuals.scenery(self)
	for zone in world.zones:
		if PolishedFX.zone(self, zone): continue
		if not textures.has("res://assets/fx/expansion/animation/beam_prism.png"): ExpandedVisuals.texture(self, "res://assets/fx/expansion/animation/beam_prism.png")
		if textures.has("res://assets/fx/expansion/animation/beam_prism.png"):
			ExpandedVisuals.zone(self, zone)
			continue
		var warning = world.time < zone.active
		var color = Color(FIRE, 0.14) if zone.friendly else Color(HOSTILE, 0.14 if warning else 0.32)
		if zone.get("shape", "") == "line":
			draw_line(zone.from, zone.to, Color(INK, .35), zone.width * 2 + 4, true)
			draw_line(zone.from, zone.to, color, zone.width * 2, true)
			draw_line(zone.from, zone.to, Color(HOSTILE, .55), 2 if warning else 5, true)
			continue
		draw_circle(zone.pos, zone.radius, color)
		draw_arc(zone.pos, zone.radius, 0, TAU, 48, FIRE if zone.friendly else HOSTILE, 2 if warning else 4, true)
		if warning:
			var progress = clampf(1.0 - (zone.active - world.time) / 0.9, 0.0, 1.0)
			draw_arc(zone.pos, zone.radius - 5, -PI / 2, -PI / 2 + TAU * progress, 36, PAPER, 3, true)
	# Hostile debt pairs use striped jade lines so their shot cannot be confused with our warm chain.
	var debt_pair = world.room_flags.get("debt_pair", [])
	if debt_pair.size() == 2:
		var a = world.enemy_by_uid(debt_pair[0])
		var b = world.enemy_by_uid(debt_pair[1])
		if not a.is_empty() and not b.is_empty() and not a.dead and not b.dead:
			var from = a.pos - Vector2(0, 16)
			var to = b.pos - Vector2(0, 16)
			for i in 12:
				draw_line(from.lerp(to, i / 12.0), from.lerp(to, (i + .55) / 12.0), Color(HOSTILE, .65), 3, true)
	for pending in world.delayed:
		if pending.type == "debt_bullet" and pending.time > world.time:
			var progress = clampf(1.0 - (pending.time - world.time) / .8, 0, 1)
			draw_line(pending.pos, pending.pos + pending.aim * 190, Color(HOSTILE, .26), 12, true)
			draw_line(pending.pos, pending.pos + pending.aim * 190, HOSTILE, 2, true)
			draw_arc(pending.pos, 17, -PI / 2, -PI / 2 + TAU * progress, 24, PAPER, 3, true)
	for chain in world.chains:
		for i in range(1, chain.size()):
			var current = world.enemy_by_uid(chain[i])
			if current.is_empty() or current.dead:
				continue
			var previous = world.enemy_by_uid(chain[0])
			for j in i:
				var other = world.enemy_by_uid(chain[j])
				if not other.is_empty() and current.pos.distance_squared_to(other.pos) < current.pos.distance_squared_to(previous.pos):
					previous = other
			var a = previous.pos - Vector2(0, 20)
			var b = current.pos - Vector2(0, 20)
			var normal = a.direction_to(b).orthogonal()
			var ribbon = PackedVector2Array()
			for step in 24:
				var fraction = float(step) / 23
				ribbon.append(a.lerp(b, fraction) + normal * sin(fraction * TAU * 1.3 + clock * 5) * 8 * sin(fraction * PI))
			var warmed = current.mark >= 3 and previous.mark >= 3
			draw_polyline(ribbon, Color("6c311e"), 8, true)
			draw_polyline(ribbon, FIRE if warmed else Color("d85939"), 4, true)
			for ember in 3:
				var fraction = fmod(clock * .5 + ember / 3.0, 1.0)
				var point = a.lerp(b, fraction) + normal * sin(fraction * TAU * 1.3 + clock * 5) * 8 * sin(fraction * PI)
				draw_circle(point, 3, Color("ffe0a0"))
	for pickup in world.pickups:
		var p = pickup.pos + Vector2(0, sin(clock * 5 + pickup.uid) * 3 - 6)
		if pickup.kind in world.Equipment.MANUAL_KINDS:
			draw_equipment_pickup(pickup, p)
			continue
		match pickup.kind:
			"ash":
				draw_circle(p, 9, Color(INK, 0.9))
				draw_circle(p, 5, Color("d7bd89"))
				draw_line(p + Vector2(-3, 0), p + Vector2(3, 0), FIRE, 2)
			"coin":
				draw_circle(p, 10, INK)
				draw_circle(p, 7, GOLD)
				draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), INK)
			"heal":
				draw_circle(p, 14, Color(INK, 0.8))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(8, 0), p + Vector2(0, 10), p + Vector2(-8, 0)]), Color("dd7048"))
	# Ground energy stays readable without covering character silhouettes.
	for effect in visual_effects:
		if effect.kind in ["ray","burst","scenery_explosion"]: draw_effect(effect)
	var actors = world.enemies.duplicate()
	actors.append({"is_player": true, "pos": world.player.pos})
	actors.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for actor in actors:
		if actor.get("is_player", false):
			draw_player()
		else:
			draw_enemy(actor)
	for effect in visual_effects:
		if effect.kind not in ["ray","burst","scenery_explosion"]: draw_effect(effect)
	for bullet in world.bullets:
		if PolishedFX.projectile(self, bullet): continue
		if ExpandedVisuals.projectile(self, bullet): continue
		var p = bullet.pos - Vector2(0, 14)
		if bullet.friendly:
			var trail_length = 18.0 + minf(24.0, float(bullet.speed) * .045)
			var bullet_color = Color("7fd0b0") if bullet.mode == "controlled" else FIRE
			draw_line(p - bullet.dir * trail_length, p, Color(bullet_color, 0.16), 9, true)
			draw_line(p - bullet.dir * trail_length * .72, p, Color(bullet_color, 0.52), 4, true)
			if bullet.primary and bullet.mode in ["returning", "ricochet"]:
				var id = "w05" if bullet.mode == "returning" else "w09"
				var path = "res://assets/weapons/" + id + ".png"
				if not textures.has("flight_" + id): textures["flight_" + id] = load(path)
				var flight = Transform2D(bullet.age * (5 if reduce_motion else 14), p)
				flight.y *= 1.0 / .84722
				draw_set_transform_matrix(stage * flight)
				draw_texture_rect(textures["flight_" + id], Rect2(-Vector2.ONE * 16, Vector2.ONE * 32), false)
				draw_set_transform_matrix(stage)
				draw_circle(p, bullet.radius + 3, Color(FIRE, .45), false, 1, true)
				continue
			draw_circle(p, bullet.radius + 2, INK)
			draw_circle(p, bullet.radius, bullet_color if bullet.primary else PAPER)
			draw_circle(p - bullet.dir * 1.5, 2, Color("fff0c0"))
			if bullet.mode == "controlled":
				var orbit = p + bullet.dir.orthogonal() * sin(bullet.age * 15.0) * 9.0
				draw_arc(p, bullet.radius + 7, bullet.age * 3.0, bullet.age * 3.0 + PI * 1.3, 18, Color("a9e6c8", .85), 2, true)
				draw_line(p, orbit, Color("a9e6c8", .58), 1.5, true)
			if not reduce_motion:
				var orbit = p + bullet.dir.orthogonal() * sin(bullet.age * 18.0) * (bullet.radius + 3.0)
				draw_circle(orbit, 1.6, Color(PAPER, .72))
		else:
			# Pointed jade silhouette stays distinct from round amber player shots.
			var direction = Vector2(bullet.dir).normalized()
			var trail_length = 22.0 + minf(30.0, float(bullet.speed) * .05)
			draw_line(p - direction * trail_length, p - direction * 4, Color(HOSTILE, .14), 11, true)
			draw_line(p - direction * trail_length * .78, p - direction * 5, Color(HOSTILE, .48), 3, true)
			draw_arc(p, bullet.radius + 6, 0, TAU, 20, Color(HOSTILE, .34), 2, true)
			var side = direction.orthogonal() * (bullet.radius + 3)
			var points = PackedVector2Array([p + direction * 12, p + side, p - direction * 8, p - side])
			draw_colored_polygon(points, INK)
			for i in points.size():
				points[i] = p + (points[i] - p) * 0.7
			draw_colored_polygon(points, HOSTILE)
			if not reduce_motion:
				for i in 3:
					var spark = p - direction * (10 + i * 7) + direction.orthogonal() * sin(bullet.age * 16 + i * 2.1) * 4
					draw_circle(spark, 1.5, Color(PAPER, .64))
			if shape_cues:
				var outline = points.duplicate()
				outline.append(points[0])
				draw_polyline(outline, PAPER, 1.5, true)
				draw_line(p - direction * 24, p - direction * 10, PAPER, 2, true)
	if adapter != null and adapter.touch_mode and combat_interface_visible:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_touch_controls()
	last_draw_us = Time.get_ticks_usec() - draw_started

func draw_equipment_pickup(drop: Dictionary, point: Vector2) -> void:
	var tint = UI.JADE if drop.kind == "trinket" else (UI.ACCENT if drop.kind == "active" else UI.GOLD)
	PolishedFX.Clip.disk(self, drop.pos, 22, Color("101b25", .82))
	PolishedFX.Clip.arc(self, drop.pos, 23, 0, TAU, 32, Color(tint, .78), 2)
	if drop.kind == "battery":
		PolishedFX.Clip.sprite(self, UI.icon("zap"), point, Vector2(28, 34), 0, tint)
	else:
		var path = EquipmentUI.art(drop.kind, str(drop.id))
		if not textures.has(path): textures[path] = load(path)
		PolishedFX.Clip.sprite(self, textures[path], point - Vector2(0, 15), Vector2(50, 59))
	if not reduce_motion and PolishedFX.spend(self):
		var orbit = drop.pos + Vector2.RIGHT.rotated(clock * .6 + drop.uid) * 24
		PolishedFX.Clip.disk(self, orbit, 2.1, tint)

func draw_secret_entry() -> void:
	var entry = world.secret_entry()
	if entry.is_empty(): return
	var revealed = world.Graph.visible(world.run.graph, int(entry.room))
	var state = "used" if world.run.visited.has(int(entry.room)) else ("open" if revealed else "clue")
	var ground = entry.pos + Vector2(int(entry.side) * 70, 0)
	draw_sprite(textures["secret_" + state], ground, 216, 0, 0, Color.WHITE if revealed else Color(.78, .77, .74))
	var progress = minf(1, float(world.room_flags.get("secret_inspect", 0)) / .45)
	if not revealed and progress > 0:
		draw_arc(entry.pos, 24, -PI / 2, -PI / 2 + TAU * progress, 24, GOLD, 2, true)
	elif revealed and world.nearby_secret_room() >= 0:
		draw_arc(entry.pos, 24, 0, TAU, 32, Color(GOLD, .8), 2, true)
		draw_string(font, entry.pos + Vector2(-39, 44), "断绳入页", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PAPER)

func draw_room_doors() -> void:
	if world.mode != "clear": return
	for door in world.room_doors():
		var direction = str(door.direction)
		var outward = world.direction_vector(direction)
		var center = Vector2(door.pos) + (outward * 22 if world.run.get("campaign", false) else Vector2.ZERO)
		var visited = bool(door.get("visited", false))
		var tint = Color(GOLD if visited else UI.JADE, .88)
		var pulse = .5 + .5 * sin(clock * 3.2 + float(door.destination))
		var horizontal = direction in ["north", "south"]
		var opening = Rect2(center - (Vector2(46, 14) if horizontal else Vector2(14, 46)), Vector2(92, 28) if horizontal else Vector2(28, 92))
		# The threshold is drawn over the baked arena art, so its direction stays
		# readable on every room template without replacing the approved scene art.
		draw_rect(opening, Color(INK, .86), true)
		draw_rect(opening.grow(3), Color(INK, .72), false, 3, true)
		draw_arc(center, 26 + pulse * 3, 0, TAU, 32, Color(tint, .18 + pulse * .12), 6, true)
		draw_arc(center, 26 + pulse * 3, 0, TAU, 32, tint, 2, true)
		var side = outward.orthogonal() * 11
		var tip = center + outward * 14
		var chevron = PackedVector2Array([tip, center - outward * 8 + side, center - outward * 8 - side])
		draw_colored_polygon(chevron, tint)
		draw_line(center - outward * 23, center + outward * 23, Color(tint, .45), 2, true)

func draw_floor() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_rect(Rect2(0, 0, 1280, 720), INK)
	if not textures.has("floor"):
		return
	if textures.has("arena"):
		var region = 1 if world == null or world.run.is_empty() else int(world.run.floor)
		var backdrop = textures.get("coin-vault-arena" if region == 2 else "ownerless-temple-arena", textures.arena) if region > 1 else textures.arena
		if hub: backdrop = textures.get("hub-arena", textures.arena)
		elif world != null and world.run.get("campaign", false):
			var variants = world.region_spec().backgrounds
			var id = int(world.run.graph.get("backgrounds", {}).get(str(int(world.run.room)), 0))
			var generated = ExpandedVisuals.texture(self, str(variants[id]))
			if generated != null: backdrop = generated
		draw_texture_rect(backdrop, Rect2(0, 0, 1280, 720), false)
	else:
		for y in range(72, 648, 192):
			for x in range(64, 1216, 192):
				draw_texture_rect(textures.floor, Rect2(x, y, 192, 192), false, Color("8f9b8f"))
		for x in range(64, 1216, 185):
			draw_texture_rect(textures.wall, Rect2(x, 50, 185, 50), false)
			draw_texture_rect(textures.wall, Rect2(x, 623, 185, 50), false)
	if world != null and not hub and not world.run.get("campaign", false):
		draw_set_transform_matrix(stage)
		for block in world.geometry.blocks:
			if world.geometry.baked_cells.has(world.geometry.key(world.geometry.cell_of(block.position + Vector2(1, 1)))):
				continue
			var prop = "prop_paper_stack" if int(block.position.x / 64) % 2 == 0 else "prop_chest"
			if textures.has(prop):
				draw_sprite(textures[prop], block.position + Vector2(32, 61), 96)

func draw_room_ambient() -> void:
	if world == null or world.run.is_empty(): return
	var kind = str(world.room_type())
	var region = int(world.run.floor)
	var base = Color("d7bd89")
	if region == 2: base = Color("e6c56a")
	elif region == 3: base = Color("9dd6bf")
	if kind == "sacrifice": base = Color("df704f")
	elif kind == "judge": base = Color("e5be73")
	elif kind == "angel": base = Color("a9e6c8")
	elif kind == "challenge": base = Color("df704f")
	elif kind == "shop": base = Color("e6c56a")
	if kind in ["sacrifice", "judge", "angel"] and textures.has("prop_special_" + kind):
		# The authored room centerpiece sits behind the procedural rings and
		# particles, keeping the same readable interaction silhouette on every
		# room template while replacing the placeholder geometry with the locked
		# paper-cut prop art.
		draw_sprite(textures["prop_special_" + kind], Vector2(640, 470), 220, 0, 0, Color(1, 1, 1, .96))
	var count = roundi(22 * particle_scale)
	for i in count:
		var seed = float(i * 37 + int(world.run.room) * 11 + region * 19)
		var x = 104.0 + fmod(seed * 73.0, 1070.0)
		var y = 92.0 + fmod(seed * 41.0, 520.0)
		var drift = sin(clock * (1.2 + fmod(seed, 3.0) * .2) + seed) * (5.0 if kind != "judge" else 12.0)
		var point = Vector2(x + drift, y)
		var radius = 1.4 + fmod(seed, 3.0) * .45
		draw_circle(point, radius + 2.5, Color(base, .06))
		draw_circle(point, radius, Color(base, .36 if kind == "combat" else .54))
		if kind in ["sacrifice", "judge", "angel"] and i % 4 == 0:
			var spoke = Vector2.RIGHT.rotated(clock * .5 + seed) * (7.0 + fmod(seed, 8.0))
			draw_line(point - spoke, point + spoke, Color(base, .22), 1.0, true)
	if kind == "sacrifice":
		var altar = Vector2(640, 354)
		draw_arc(altar, 92 + sin(clock * 2.0) * 3.0, 0, TAU, 48, Color("df704f", .22), 3, true)
		draw_arc(altar, 68, -clock, TAU - clock, 32, Color("f4d29c", .38), 2, true)
	elif kind == "judge":
		var scale_center = Vector2(640, 328)
		draw_line(scale_center + Vector2(-70, 0), scale_center + Vector2(70, 0), Color("f1d598", .28), 3, true)
		draw_circle(scale_center + Vector2(-44, 22 + sin(clock) * 4), 14, Color("e6c56a", .16))
		draw_circle(scale_center + Vector2(44, 22 - sin(clock) * 4), 14, Color("e6c56a", .16))
	elif kind == "angel":
		for side in [-1, 1]:
			draw_arc(Vector2(640 + side * 36, 350), 46, PI * (0.15 if side > 0 else 0.85), PI * (0.85 if side > 0 else 1.85), 24, Color("a9e6c8", .28), 3, true)
	elif kind == "challenge":
		var center = Vector2(640, 350)
		for ring in [72.0, 108.0, 144.0]:
			draw_arc(center, ring + sin(clock * 2.4 + ring) * 3.0, clock * .5, clock * .5 + PI * 1.55, 32, Color("df704f", .28), 3, true)
		for spoke in 8:
			var direction = Vector2.RIGHT.rotated(TAU * spoke / 8.0 + clock * .25)
			draw_line(center + direction * 54, center + direction * 128, Color("f4d29c", .18), 2, true)

func facing(direction: Vector2) -> String:
	if absf(direction.y) >= absf(direction.x):
		return "down" if direction.y >= 0 else "up"
	return "left" if direction.x < 0 else "right"

func draw_actor_shadow(ground: Vector2, size: float) -> void:
	var shadow_width = size * 0.3
	var shadow = Transform2D(0, ground + Vector2(0, 3))
	shadow.y *= .32
	draw_set_transform_matrix(stage * shadow)
	draw_circle(Vector2.ZERO, shadow_width, Color(0.06, 0.07, 0.06, 0.28))
	draw_set_transform_matrix(stage)

func draw_sprite(texture: Texture2D, ground: Vector2, size: float, bob: float = 0, tilt: float = 0, tint: Color = Color.WHITE, squash: float = 1, with_shadow: bool = true) -> void:
	if with_shadow: draw_actor_shadow(ground, size)
	var pose = Transform2D(tilt, ground - Vector2(0, bob))
	pose.x *= 1.0 / squash
	pose.y *= squash / .84722
	draw_set_transform_matrix(stage * pose)
	draw_texture_rect(texture, Rect2(Vector2(-size * .5, -size * .84), Vector2(size, size)), false, tint)
	draw_set_transform_matrix(stage)

func draw_player() -> void:
	var player = world.player
	var motion = weapon_motion.sample(world, reduce_motion)
	var aim_direction = Vector2(motion.get("aim", player.get("facing_direction", player.aim)))
	var direction = facing(aim_direction)
	var texture = textures.get(world.run.character + "_" + direction)
	if texture == null:
		return
	var state = str(motion.state)
	var elapsed = float(motion.elapsed)
	if player.hp <= 0:
		elapsed = clock - player_death_clock
	var modular = weapon_motion.manifest.get("actors", {}).has(world.run.character)
	var animated = animation.texture(world.run.character, "weapon_body" if modular else "character", state, elapsed, direction)
	if animated != null: texture = animated
	var tint = Color.WHITE.lerp(Color(1, .85, .75), flash_scale) if player.invulnerable > 0 and int(clock * 18) % 2 == 0 else Color.WHITE
	draw_circle(player.pos, 16, Color("d9af65"), false, 2, true)
	if modular:
		motion.elapsed = elapsed
		draw_equipped_actor(world.run.character, player.pos, direction, motion, texture, tint)
	else: draw_sprite(texture, player.pos, 96, 0, 0, tint)
	if player.armor > 0:
		draw_arc(player.pos - Vector2(0, 27), 38, -PI, PI, 32, Color(GOLD, 0.7), 2, true)
	var pointer = player.pos + aim_direction * 37 - Vector2(0, 14)
	draw_line(pointer - aim_direction * 5, pointer + aim_direction * 6, PAPER, 2, true)
	if player.charge > 0:
		draw_arc(player.pos, 25, -PI / 2, -PI / 2 + TAU * player.charge / .25, 24, FIRE, 3, true)

func draw_equipped_actor(actor: String, ground: Vector2, direction: String, motion: Dictionary, body: Texture2D, tint: Color = Color.WHITE) -> void:
	var placements = weapon_motion.placements(actor, direction, motion)
	draw_actor_shadow(ground, 96)
	for placement in placements:
		if placement.behind: draw_held_weapon(ground, placement, tint)
	draw_sprite(body, ground, 96, 0, 0, tint, 1, false)
	for placement in placements:
		if not placement.behind: draw_held_weapon(ground, placement, tint)
	if motion.held_visible:
		var hands = animation.texture(actor, "weapon_hand", motion.state, motion.elapsed, direction)
		if hands != null: draw_sprite(hands, ground, 96, 0, 0, tint, 1, false)

func draw_held_weapon(ground: Vector2, placement: Dictionary, tint: Color) -> void:
	var id = str(placement.weapon)
	var key = "held_" + id
	if not textures.has(key): textures[key] = load(weapon_motion.manifest.weapons[id].texture)
	var root = Transform2D(0, ground)
	root.y *= 1.0 / .84722
	var item = Transform2D(placement.angle, placement.point)
	if placement.flip: item.x *= -1
	draw_set_transform_matrix(stage * root * item)
	draw_texture_rect(textures[key], Rect2(-placement.grip * placement.size, Vector2.ONE * placement.size), false, tint)
	draw_set_transform_matrix(stage)

func draw_enemy(enemy: Dictionary) -> void:
	var texture = textures.get(enemy.get("sprite_id", enemy.id), textures.get("e01"))
	var size = float(enemy.get("render_size", 256.0 if enemy.boss else (146.0 if enemy.elite else 110.0)))
	var bob = sin(clock * 4 + enemy.uid) * 2
	var kind = "boss" if enemy.boss else "enemy"
	var state = "idle"
	var elapsed = world.time + float(enemy.uid) * .13
	if world.time - float(enemy.get("visual_hurt_at", -999)) < .125:
		state = "hurt"
		elapsed = world.time - enemy.visual_hurt_at
	elif enemy.boss and world.time - float(enemy.get("visual_phase_at", -999)) < .375:
		state = "phase"
		elapsed = world.time - enemy.visual_phase_at
	elif enemy.windup > 0:
		state = ["attack_a", "attack_b", "attack_c"][int(enemy.phase)] if enemy.boss else "tell"
		elapsed = enemy.tell - enemy.windup
	elif world.time - float(enemy.get("visual_attack_at", -999)) < .25:
		state = ["attack_a", "attack_b", "attack_c"][int(enemy.phase)] if enemy.boss else "attack"
		elapsed = world.time - enemy.visual_attack_at
	elif float(enemy.get("visual_motion", 0)) > 8 or (not enemy.boss and enemy.speed > 0 and enemy.pos.distance_to(world.player.pos) > 240): state = "move"
	var frozen = actor_freeze.get(enemy.uid, {})
	var drawn_position = enemy.pos
	if hitstop and not reduce_motion and not frozen.is_empty() and clock < frozen.until:
		drawn_position = frozen.pos
		elapsed = maxf(0, frozen.time - float(enemy.get("visual_hurt_at", frozen.time)))
		state = "hurt"
	var sprite_id = enemy.get("sprite_id", enemy.id)
	var animated = animation.texture(sprite_id, kind, state, elapsed) if not enemy.get("sigil", false) else null
	if animated != null:
		texture = animated
		bob = 0
	var tint = Color.WHITE.lerp(Color(2.4, 2.0, 1.5), flash_scale) if enemy.hit_flash > 0 else Color.WHITE
	draw_sprite(texture, drawn_position, size, bob, sin(clock * 3 + enemy.uid) * .02, tint)
	if world.time < float(enemy.get("arrival", 0)):
		draw_arc(enemy.pos, enemy.radius + 15, 0, TAU, 32, HOSTILE, 3, true)
	if int(enemy.get("shield_layers", 0)) > 0:
		var direction = enemy.aim.angle()
		draw_arc(enemy.pos - Vector2(0, 19), 32, direction - .85, direction + .85, 20, GOLD, 4, true)
	if enemy.windup > 0:
		var amount = 1 - enemy.windup / enemy.tell
		draw_arc(enemy.pos, enemy.radius + 10, -PI / 2, -PI / 2 + TAU * amount, 40, HOSTILE, 3, true)
		if enemy.id == "e02":
			var end = enemy.pos + enemy.aim * 240
			draw_line(enemy.pos, end, Color(HOSTILE, .5), 12, true)
			draw_line(enemy.pos, end, PAPER, 1, true)
	if enemy.elite:
		draw_arc(enemy.pos - Vector2(0, 45), 60, PI * 1.05, PI * 1.95, 24, GOLD, 3, true)
	if int(enemy.mark) > 0:
		var y = enemy.pos.y - size * .78 - 8
		for i in int(enemy.mark):
			var center = Vector2(enemy.pos.x + (i - (int(enemy.mark) - 1) / 2.0) * 14, y)
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(5, 2), center + Vector2(0, 7), center + Vector2(-5, 2)]), FIRE)
	if int(enemy.burn) > 0:
		draw_arc(enemy.pos - Vector2(0, 8), enemy.radius, PI, TAU, 20, FIRE, 3, true)
	if world.time < float(enemy.get("stun_until", 0)) and not enemy.boss:
		var anchor = enemy.pos + Vector2(0, 5)
		var radius = enemy.radius + 8
		draw_arc(anchor, radius, 0, TAU, 32, Color("6c311e"), 6, true)
		draw_arc(anchor, radius, 0, TAU, 32, FIRE, 3, true)
		for sign_value in [-1, 1]:
			var knot = anchor + Vector2(sign_value * radius, 0)
			draw_circle(knot, 4, GOLD, false, 2, true)
	if enemy.hp < enemy.max_hp and not enemy.boss:
		var rect = Rect2(enemy.pos + Vector2(-25, -size * .75), Vector2(50, 4))
		draw_style_box(UI.style(INK, Color.TRANSPARENT, 2), rect)
		rect.size.x *= enemy.hp / enemy.max_hp
		draw_style_box(UI.style(UI.ACCENT, Color.TRANSPARENT, 2), rect)
	if enemy.boss and combat_interface_visible:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var boss_list = world.enemies.filter(func(e): return e.boss and not e.dead)
		var boss_index = boss_list.find(enemy)
		var rect = Rect2(416, 100 + maxi(0, boss_index) * 36, 448, 8)
		draw_style_box(UI.style(UI.INSET, Color.TRANSPARENT, 6), rect.grow(3))
		rect.size.x *= maxf(0, enemy.hp / enemy.max_hp)
		draw_style_box(UI.style(UI.ACCENT, Color.TRANSPARENT, 4), rect)
		var name = world.db.name_of("bosses", enemy.id)
		var point_size = roundi(18 * combat_text_scale)
		var width = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x
		draw_string(font, Vector2(640 - width * .5, 132 + maxi(0, boss_index) * 36), name, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, UI.TEXT)
		for fraction in [.3333, .6667]:
			draw_line(Vector2(416 + 448 * fraction, 100 + maxi(0, boss_index) * 36), Vector2(416 + 448 * fraction, 108 + maxi(0, boss_index) * 36), UI.INSET, 2)
		draw_set_transform_matrix(stage)

func to_world(canvas_position: Vector2) -> Vector2:
	return stage.affine_inverse() * (canvas_position - position)

func draw_effect(effect: Dictionary) -> void:
	var progress = 1.0 - effect.left / effect.total
	var color = Color(FIRE, 1.0 - progress)
	if effect.kind == "ray" and PolishedFX.beam(self, effect, progress): return
	if effect.kind in ["burst", "scenery_explosion", "scenery_break"] and PolishedFX.burst(self, effect, progress): return
	if effect.kind in ["active_item", "equipment_taken", "loot_spawn"]:
		PolishedFX.equipment_event(self, effect, progress)
		return
	match effect.kind:
		"shot":
			var direction = Vector2(effect.get("dir", Vector2.UP)).normalized()
			var origin = effect.pos - Vector2(0, 14)
			var muzzle = origin + direction * 25
			var fade = 1.0 - progress
			draw_line(origin + direction * 12, origin + direction * 46, Color(INK, .7 * fade), 12, true)
			draw_line(origin + direction * 18, origin + direction * 52, Color(FIRE, .82 * fade), 5, true)
			draw_arc(muzzle, 12 + (6 if effect.get("heavy", false) else 0) * progress, direction.angle() - .95, direction.angle() + .95, 18, Color(PAPER, .9 * fade), 3, true)
			for i in 7:
				var angle = direction.angle() + (i - 3) * .24
				var length = 18.0 + fmod(float(i * 13), 17.0)
				draw_line(muzzle + Vector2.RIGHT.rotated(angle) * 5, muzzle + Vector2.RIGHT.rotated(angle) * length, Color(FIRE if i % 2 else PAPER, .65 * fade), 2, true)
			if str(effect.get("mode", "")) in ["triple", "fan"]:
				for spread in [-.22, 0.0, .22]:
					var fan_dir = direction.rotated(spread)
					draw_line(muzzle + fan_dir * 8, muzzle + fan_dir * (36 + 18 * fade), Color(GOLD, .62 * fade), 2, true)
					draw_circle(muzzle + fan_dir * (38 + 14 * fade), 3, Color(PAPER, .72 * fade))
			if str(effect.get("mode", "")) == "controlled":
				draw_arc(muzzle, 20 + 10 * fade, -PI, PI, 24, Color("a9e6c8", .72 * fade), 2, true)
		"ray":
			var ray_dir = Vector2(effect.get("dir", Vector2.RIGHT)).normalized()
			var ray_origin = effect.pos - Vector2(0, 14) + ray_dir * 16
			var ray_range = float(effect.get("range", 520)) * (.72 + .28 * progress)
			var ray_end = ray_origin + ray_dir * ray_range
			var fade = 1.0 - progress
			draw_line(ray_origin, ray_end, Color(INK, .72 * fade), float(effect.get("width", 16)) + 12, true)
			draw_line(ray_origin, ray_end, Color("a9e6c8", .22 * fade), float(effect.get("width", 16)) + 5, true)
			draw_line(ray_origin, ray_end, Color(PAPER, .86 * fade), 3, true)
			for i in 12:
				var point = ray_origin + ray_dir * (ray_range * (i + .35) / 12.0)
				var spark_dir = ray_dir.orthogonal() * sin(clock * 16 + i * 2.4) * (4 + 7 * fade)
				draw_circle(point + spark_dir, 2.2, Color(GOLD if i % 2 else PAPER, .76 * fade))
		"hurt_source":
			var tint = Color(HOSTILE, 1 - progress)
			var center = effect.pos - Vector2(0, 15)
			if effect.ground or effect.dir.length_squared() < .01:
				var size = 37.0
				var shape = PackedVector2Array([center + Vector2(0, -size), center + Vector2(size, 0), center + Vector2(0, size), center - Vector2(size, 0), center + Vector2(0, -size)])
				draw_polyline(shape, Color(INK, tint.a), 7, true)
				draw_polyline(shape, tint, 3, true)
			else:
				var direction = Vector2(effect.dir).normalized()
				var point = center + direction * 44
				var shape = PackedVector2Array([point + direction * 13, point - direction * 5 + direction.orthogonal() * 10, point - direction * 5 - direction.orthogonal() * 10])
				draw_colored_polygon(shape, tint)
				shape.append(shape[0])
				draw_polyline(shape, Color(INK, tint.a), 2, true)
		"burst":
			var radius = float(effect.get("radius", 48)) * (0.35 + progress)
			var center = effect.pos - Vector2(0, 14)
			draw_circle(center, radius * .7, Color(FIRE, (1 - progress) * .12))
			draw_circle(center, radius * .34, Color(PAPER, (1 - progress) * .12))
			draw_arc(effect.pos - Vector2(0, 14), radius, 0, TAU, 32, color, 5 * (1 - progress) + 1, true)
			draw_arc(center, radius * .58, -progress * TAU, TAU - progress * TAU, 32, Color(PAPER, (1 - progress) * .68), 2, true)
			for i in 8:
				var direction = Vector2.RIGHT.rotated(i * TAU / 8)
				draw_line(effect.pos + direction * radius * .6 - Vector2(0, 14), effect.pos + direction * radius - Vector2(0, 14), color, 3, true)
			for i in 16:
				var angle = i * 2.399
				var direction = Vector2.RIGHT.rotated(angle)
				var point = effect.pos + direction * radius * (0.4 + i % 4 * .16) - Vector2(0, 14)
				var shard = PackedVector2Array([point - direction * 3, point + direction * 8, point + direction.orthogonal() * 5])
				if i < roundi(16 * particle_scale): draw_colored_polygon(shard, Color(PAPER if i % 3 == 0 else FIRE, 1 - progress))
		"impact":
			var direction = Vector2(effect.get("dir", Vector2.RIGHT)).normalized()
			var center = effect.pos - Vector2(0, 14)
			var fade = 1.0 - progress
			draw_arc(center, 14 + progress * 30, 0, TAU, 28, Color(PAPER, .72 * fade), 3, true)
			var side = direction.orthogonal() * (10 + progress * 12)
			var tip = center + direction * (24 + progress * 18)
			draw_colored_polygon(PackedVector2Array([tip, center - direction * 6 + side, center - direction * 6 - side]), Color(FIRE, .72 * fade))
			for i in 5:
				var angle = direction.angle() + (i - 2) * .32
				var start = center + Vector2.RIGHT.rotated(angle) * (9 + progress * 8)
				var end = center + Vector2.RIGHT.rotated(angle) * (25 + progress * 26)
				draw_line(start, end, Color(GOLD if i == 2 else PAPER, .6 * fade), 2, true)
		"hit":
			var tint = GOLD if effect.get("crit", false) else (FIRE if effect.get("heavy", false) else PAPER)
			var fade = 1 - progress
			draw_circle(effect.pos - Vector2(0, 14), 8 + progress * 18, Color(tint, .18 * fade))
			for i in 6:
				var angle = i * TAU / 6.0 + float(effect.get("uid", 0)) * .17
				var start = effect.pos - Vector2(0, 14) + Vector2.RIGHT.rotated(angle) * 8
				var end = effect.pos - Vector2(0, 14) + Vector2.RIGHT.rotated(angle) * (15 + progress * 13)
				draw_line(start, end, Color(tint, .7 * fade), 2, true)
			if damage_numbers:
				var position = effect.pos - Vector2(12, 60 + progress * 28)
				tint.a = fade
				var size = roundi((21 if effect.get("heavy", false) else 16) * combat_text_scale)
				draw_string(font, position + Vector2(1, 1), str(roundi(effect.damage)), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, tint.a))
				draw_string(font, position, str(roundi(effect.damage)), HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)
		"death":
			var id = effect.get("sprite_id", effect.get("id", ""))
			var corpse = animation.texture(id, "boss" if effect.get("boss", false) else "enemy", "death", progress * effect.total) if id != "sigil" else null
			if corpse != null: draw_sprite(corpse, effect.pos, 256 if effect.get("boss", false) else (146 if effect.get("elite", false) else 110))
			var fade = 1 - progress
			draw_circle(effect.pos - Vector2(0, 18), 18 + progress * 48, Color(FIRE, .1 * fade))
			draw_arc(effect.pos - Vector2(0, 18), 20 + progress * 48, 0, TAU, 28, Color(PAPER, .7 * fade), 3, true)
			for i in roundi(18 * particle_scale):
				var angle = i * 2.399 + float(effect.get("uid", 0)) * .07
				var point = effect.pos + Vector2.RIGHT.rotated(angle) * progress * (34 + (i % 4) * 12) - Vector2(0, 20)
				var shard = PackedVector2Array([point, point + Vector2.RIGHT.rotated(angle) * 10, point + Vector2.RIGHT.rotated(angle + .8) * 5])
				draw_colored_polygon(shard, Color(PAPER if i % 3 else FIRE, fade))
		"dash":
			draw_line(effect.pos, effect.pos + effect.dir * progress * 140, Color(PAPER, .35 * (1 - progress)), 8, true)
		"slash":
			var direction = effect.dir.angle()
			var center = effect.pos - Vector2(0, 14)
			var width = .85 if effect.get("charged", false) else .75
			draw_arc(center, effect.range * (.68 + .08 * progress), direction - width, direction + width, 28, Color(INK, .72 * (1 - progress)), 11 * (1 - progress) + 3, true)
			draw_arc(center, effect.range * (.72 + .08 * progress), direction - width, direction + width, 28, Color(GOLD if effect.get("charged", false) else FIRE, 1 - progress), 6 * (1 - progress) + 1, true)
			for i in 8:
				var slash_dir = Vector2.RIGHT.rotated(direction + (i - 3.5) * .12)
				draw_line(center + slash_dir * (effect.range * .35), center + slash_dir * (effect.range * (.48 + .18 * (i % 2))), Color(PAPER, .42 * (1 - progress)), 2, true)
		"deflect":
			draw_arc(effect.pos - Vector2(0, 22), 35 + progress * 22, -PI, PI, 32, Color(GOLD, 1 - progress), 4, true)
		"skill": draw_skill_trace(effect, progress)

func draw_skill_trace(effect: Dictionary, progress: float) -> void:
	var origin = effect.pos - Vector2(0, 14)
	var skill = str(effect.skill)
	var color = Color(FIRE, (1 - progress) * .7)
	var direction = Vector2(effect.get("dir", Vector2.UP))
	if skill in ["s03", "s08", "s16", "s17", "s18"]:
		var angles = [0.0, PI * .5, PI, -PI * .5] if skill == "s03" else ([-.18, 0.0, .18] if skill == "s17" else [0.0])
		for angle in angles:
			var end = origin + direction.rotated(angle) * (310 if skill == "s03" else 480) * minf(1, .45 + progress)
			draw_line(origin, end, Color(INK, (1 - progress) * .7), 18, true)
			draw_line(origin, end, Color(PAPER if skill in ["s16", "s17", "s18"] else FIRE, (1 - progress) * .8), 4, true)
	elif skill in ["s10", "s11", "s12"]:
		var half = 40 + 45 * progress
		var shape = PackedVector2Array([origin + Vector2(-half, -half), origin + Vector2(half, -half), origin + Vector2(half, half), origin + Vector2(-half, half), origin + Vector2(-half, -half)])
		draw_polyline(shape, Color(GOLD, 1 - progress), 7, true)
		draw_arc(origin, half * .7, direction.angle() - 1.1, direction.angle() + 1.1, 32, color, 8, true)
	elif skill in ["s04", "s05", "s06"]:
		var points = effect.get("points", [])
		for point in points:
			draw_line(origin, point - Vector2(0, 20), Color(Color("bc3c2f"), (1 - progress) * .65), 3, true)
			draw_arc(point - Vector2(0, 20), 28 + progress * 35, 0, TAU, 28, color, 3, true)
	elif skill == "s02":
		for i in mini(2, effect.get("points", []).size()):
			var end = effect.points[i] - Vector2(0, 20)
			var point = origin.lerp(end, minf(1, progress * 2)) + direction.orthogonal() * sin(progress * PI) * (35 if i == 0 else -35)
			var forward = origin.direction_to(end)
			draw_colored_polygon(PackedVector2Array([point + forward * 11, point - forward * 8 + forward.orthogonal() * 13, point - forward * 3, point - forward * 8 - forward.orthogonal() * 13]), Color(PAPER, 1 - progress))
	else:
		var radius = 45 + progress * (85 if skill in ["s13", "s14", "s15"] else 65)
		draw_arc(origin, radius, -PI + progress * PI, PI + progress * PI, 42, Color(PAPER if skill in ["s13", "s14", "s15"] else FIRE, (1 - progress) * .7), 4, true)

func draw_touch_controls() -> void:
	var left = adapter.left_origin if adapter.move_id >= 0 else adapter.control_center("move")
	var right = adapter.right_origin if adapter.aim_id >= 0 else adapter.control_center("aim")
	var opacity = adapter.control_opacity
	var radius = adapter.control_radius("move")
	var clearing = world.mode == "clear"
	for center in ([left] if clearing else [left, right]):
		draw_circle(center, radius, Color(INK, .35 * opacity))
		draw_arc(center, radius, 0, TAU, 40, Color(PAPER, .5 * opacity), 2, true)
	draw_circle(left + adapter.move_touch * 50 * adapter.control_scale, 25 * adapter.control_scale, Color(PAPER, .45 * opacity))
	if not clearing: draw_circle(right + adapter.aim_touch * 50 * adapter.control_scale, 25 * adapter.control_scale, Color(FIRE, .45 * opacity))
	var entries = [[adapter.control_center("active_item"), "active_item", world.player.item_cd]]
	if not clearing: entries.append_array([[adapter.dash_center(), "dash", world.player.dash_cd], [adapter.skill_center(), "skill", world.player.skill_cd]])
	for entry in entries:
		var center = Vector2(entry[0])
		var action_radius = adapter.control_radius(str(entry[1]))
		draw_circle(center, action_radius, Color(UI.INSET, .92 * opacity))
		var ready = entry[2] <= 0
		var active = world.Equipment.active_row(world)
		if entry[1] == "active_item": ready = ready and not active.is_empty() and world.run.active_item.charge >= active.charge_rooms
		draw_arc(center, action_radius - 3, 0, TAU, 40, Color(UI.JADE, opacity if ready else .3 * opacity), 3, true)
		if entry[1] == "dash":
			draw_texture_rect(UI.icon("wind"), Rect2(center - Vector2.ONE * 17, Vector2.ONE * 34), false, Color(UI.TEXT, opacity))
		else:
			var id = str(world.player.skill) if entry[1] == "skill" else str(world.run.active_item.id)
			var path = "res://assets/skills/" + id + ".png" if entry[1] == "skill" else "res://assets/active_items/" + id + ".png"
			if not id.is_empty():
				if not textures.has(path): textures[path] = load(path)
				draw_texture_rect(textures[path], Rect2(center - Vector2.ONE * 25, Vector2.ONE * 50), false, Color(1, 1, 1, opacity))
			if entry[1] == "active_item" and not active.is_empty():
				var fraction = clampf(float(world.run.active_item.charge) / float(active.charge_rooms), 0, 1)
				draw_arc(center, action_radius - 7, -PI * .5, -PI * .5 + TAU * fraction, 40, Color(UI.ACCENT, opacity), 3, true)
		if entry[2] > 0:
			draw_string(font, center + Vector2(-13, 30), "%.1f" % entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
