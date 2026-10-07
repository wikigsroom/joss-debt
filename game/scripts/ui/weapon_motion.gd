extends RefCounted
## Read-only presentation: the combat clock, equipped ID and real shot event drive poses.
const PaperMotion = preload("res://scripts/ui/paper_animation.gd")
var manifest: Dictionary = {}
var source_world = 0
var equipped = ""
var observed_time = -1.0
var last_shot: Dictionary = {}

func _init() -> void:
	if FileAccess.file_exists("res://assets/weapon-rig.json"):
		manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapon-rig.json"))

func clear() -> void:
	source_world = 0
	equipped = ""
	observed_time = -1.0
	last_shot.clear()

func synchronize(world) -> void:
	if world == null or world.player.is_empty():
		clear()
		return
	if source_world != world.get_instance_id() or equipped != str(world.player.weapon) or world.time < observed_time:
		last_shot.clear()
	source_world = world.get_instance_id()
	equipped = str(world.player.weapon)
	observed_time = world.time

func accept(events: Array, world) -> void:
	synchronize(world)
	if world == null or world.player.is_empty(): return
	for event in events:
		if event.kind in ["room_enter", "room_return", "dash"] or (event.kind == "player_hurt" and event.get("hp", 1) <= 0):
			last_shot.clear()
		elif event.kind == "choice_taken" and event.get("type", "") == "weapon":
			last_shot.clear()
		elif event.kind == "shot" and str(event.get("weapon", equipped)) == equipped:
			# Event time survives a delayed presentation flush; renderer time never enters here.
			last_shot = {"weapon": equipped, "at": float(event.get("at", world.time)),
				"dir": event.get("dir", world.player.aim)}

func sample(world, reduce_motion: bool = false) -> Dictionary:
	synchronize(world)
	if world == null or world.player.is_empty(): return {}
	var player = world.player
	var weapon = world.db.row("weapons", equipped)
	var duration = minf(.334, float(weapon.get("interval_s", .4)) * .85)
	var age = world.time - float(last_shot.get("at", -999))
	var attack = not last_shot.is_empty() and age >= 0 and age < duration
	var charging = weapon.get("mode", "") in ["charged_line", "charged_arc", "nova"] and player.charge > 0 and player.hp > 0
	var state = "run" if player.move.length() > .1 else "idle"
	var elapsed = world.time
	var active = attack or charging
	if player.hp <= 0:
		state = "death"
		active = false
	elif player.dash_left > 0:
		state = "dash"
		elapsed = .2 - player.dash_left
		active = false
	elif world.time - float(player.get("visual_hurt_at", -999)) < .125:
		state = "hurt"
		elapsed = world.time - player.visual_hurt_at
		active = false
	elif world.time - float(player.get("visual_cast_at", -999)) < .334:
		state = "cast"
		elapsed = world.time - player.visual_cast_at
		active = false
	elif active:
		state = "cast"
		elapsed = .084 if charging else age / duration * .333
	var phase = clampf(age / duration, 0, 1) if attack and active else 0.0
	var impulse = sin(phase * PI) if attack and active else 0.0
	var aim_direction = Vector2(last_shot.get("dir", player.get("facing_direction", player.aim))) if attack else Vector2(player.get("facing_direction", player.aim))
	if aim_direction.length_squared() < .0001: aim_direction = Vector2.UP
	aim_direction = aim_direction.normalized()
	var angle = 0.0
	var scale = 1.0
	if not reduce_motion:
		match equipped:
			"w01", "w02", "w03", "w10": angle = impulse * .24
			"w04": angle = lerpf(-.7, .45, phase) * impulse
			"w05": angle = impulse * -.28
			"w06", "w11": angle = impulse * -.12
			"w07": angle = impulse * .18
			"w08": angle = impulse * -.26
			"w09": angle = impulse * .4
			"w12": angle = lerpf(-.95, .75, phase) * impulse
			"w13": angle = impulse * .24
			"w14": angle = impulse * -.08
			"w15": angle = sin(phase * PI) * .3
			"w16": angle = lerpf(-1.1, .9, phase) * impulse
			_:
				match str(weapon.get("mode", "")):
					"sweep": angle = lerpf(-1.15, .95, phase) * impulse
					"orbit_blade", "radial", "boomerang_arc": angle = impulse * .46
					"lightning", "prism", "tether": angle = impulse * -.10
					"cloud", "rain", "mine", "nova": angle = impulse * -.28
					_: angle = impulse * .24
		if charging:
			angle = -.16 * clampf(player.charge / .25, 0, 1)
		scale = 1.0 - impulse * .045
	return {"weapon": equipped, "state": state, "elapsed": elapsed, "attack": attack and active,
		"charging": charging and active, "angle": angle, "scale": scale,
		"aim": aim_direction, "held_visible": player.hp > 0, "phase": phase}

func placements(actor: String, direction: String, motion: Dictionary) -> Array:
	if motion.is_empty() or not motion.held_visible or not manifest.get("actors", {}).has(actor): return []
	var weapon = str(motion.weapon)
	if not manifest.get("weapons", {}).has(weapon): return []
	var spec = manifest.weapons[weapon]
	var state = str(motion.state)
	var column = PaperMotion.frame_index("character", state, motion.elapsed)
	var grips = manifest.actors[actor][state][direction][column]
	var result: Array = []
	var hand_count = 2 if weapon == "w02" else 1
	for hand in hand_count:
		var point = Vector2(grips[hand][0], grips[hand][1])
		# A shield/scroll stays a permanent offhand prop; both bell loops share the free wrist.
		if hand == 1 and actor in ["c_mask", "c_ink"]:
			point = Vector2(grips[0][0] + 5, grips[0][1] + 1)
		var flip = spec.get("mirror_outward", false) and point.x > 48
		var aimed = spec.get("aimed", true)
		var aim = Vector2(motion.aim).normalized()
		var angle = aim.angle() if aimed else 0.0
		angle += float(motion.angle) * (-1 if hand == 1 else 1)
		result.append({"weapon": weapon, "hand": hand, "point": point - Vector2(48, 80.64),
			"grip": Vector2(spec.grip[0], spec.grip[1]), "angle": angle,
			"size": float(spec.size) * float(motion.scale), "flip": flip, "behind": direction == "up"})
	return result
