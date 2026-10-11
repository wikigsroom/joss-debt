extends RefCounted
## Cosmetics only: never calls fire(), step(), hit(), RNG or reward functions.
const Composer = preload("res://scripts/combat/attack_composer.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")
var clock = 0.0
var cooldown = 0.0
var charge = 0.0
var equipped = ""
var ready = false
var hint = 0
var cosmetic: Array = []
var predicted: Dictionary = {}
var corrections: Dictionary = {}
var serial = 0

func clear() -> void:
	ready = false; cooldown = 0.0; charge = 0.0; hint = 0
	cosmetic.clear(); predicted.clear(); corrections.clear()

func observe(actor, authoritative: Dictionary, history: Array) -> void:
	if not ready or equipped != str(authoritative.weapon):
		clear(); ready = true; equipped = str(authoritative.weapon)
		clock = float(actor.time); cooldown = float(authoritative.shot_cd)
		charge = float(authoritative.charge)
	var pending_seconds = 0.0
	for input in history: pending_seconds += float(input.seconds)
	cooldown = maxf(cooldown, float(authoritative.shot_cd) - pending_seconds)
	# A monotonic presentation clock prevents delayed authority from restarting poses.
	clock = maxf(clock, float(actor.time))
	actor.presentation_clock = clock

func tick(actor, frame: Dictionary, delta: float) -> Array:
	if not ready: frame.shot = 0; return []
	clock += delta; cooldown = maxf(0, cooldown - delta)
	actor.presentation_clock = clock
	for id in predicted.keys():
		if clock - float(predicted[id].at) > 2: predicted.erase(id)
	for uid in corrections.keys():
		corrections[uid] *= exp(-22 * delta)
		if Vector2(corrections[uid]).length() < .5: corrections.erase(uid)
	advance_projectiles(actor, frame, delta)
	frame.shot = hint
	if not frame.get("fire", false) or actor.player.get("downed", false) or actor.player.hp <= 0:
		charge = 0.0; actor.player.charge = 0.0; return []
	if cooldown > 0 or actor.player.dash_left > 0: return []
	var weapon = actor.db.row("weapons", equipped)
	var charge_time = .65 if weapon.mode == "nova" else (.35 if actor.stack("r66") > 0 else (.25 if weapon.mode in ["charged_line", "charged_arc"] else 0.0))
	charge += delta
	actor.player.charge = charge if charge_time > 0 else 0.0
	if charge < charge_time: return []
	charge = 0.0; actor.player.charge = 0.0
	serial += 1; hint = serial; frame.shot = hint
	var recipe = Composer.recipe(actor, weapon)
	cooldown = float(recipe.interval)
	predicted[hint] = {"at": clock, "carrier": recipe.carrier}
	var point = Vector2(actor.player.pos)
	var aim = Vector2(frame.get("aim", actor.player.aim)).normalized()
	var events: Array = [{"kind": "shot", "at": clock, "pos": point, "dir": aim, "weapon": equipped,
		"mode": weapon.mode, "pellets": recipe.pellets, "heavy": recipe.explosive or recipe.carrier != "projectile",
		"fx_family": recipe.fx_family, "prediction": hint, "predicted": true}]
	for direction in Composer.directions(recipe, aim):
		if recipe.carrier == "projectile":
			var radius = 11.0 if recipe.mode in ["wave", "cloud"] else (5.0 if recipe.mode in ["piercing", "charged_line"] else 7.0)
			cosmetic.append({"uid": -serial * 16 - cosmetic.size() % 16, "pos": actor.geometry.constrain_floor(point + direction * 22, radius),
				"dir": direction, "base_dir": direction, "speed": recipe.speed, "range": recipe.range, "travel": 0.0,
				"radius": radius, "friendly": true, "primary": true, "mode": recipe.mode, "weapon": equipped,
				"prediction": hint, "age": 0.0, "returning": false, "can_return": recipe["return"], "controllable": recipe.controlled,
				"fx_family": recipe.fx_family, "motion": "wave" if recipe.mode == "wave" else "", "predicted": true})
		elif recipe.carrier == "beam":
			var origin = actor.geometry.constrain_floor(point, recipe.width)
			var end = actor.geometry.clipped_ray(origin, origin + direction * recipe.range, recipe.width)
			events.append({"kind": "ray", "at": clock, "pos": origin, "end": end, "dir": direction,
				"range": origin.distance_to(end), "width": recipe.width, "weapon": equipped, "style": "beam_ink",
				"fx_preset": str(recipe.fx_family) + "_beam_lance", "prediction": hint, "predicted": true})
		elif recipe.carrier == "arc":
			events.append({"kind": "slash", "at": clock, "pos": point, "dir": direction, "range": recipe.range,
				"weapon": equipped, "mode": recipe.mode, "charged": recipe.mode in ["charged_arc", "sweep"],
				"fx_family": recipe.fx_family, "prediction": hint, "predicted": true})
		# Chain targets, area impacts, damage, knockback and drops await authority.
	while cosmetic.size() > 96: cosmetic.pop_front()
	return events

func advance_projectiles(actor, frame: Dictionary, delta: float) -> void:
	for bullet in cosmetic.duplicate():
		bullet.age += delta
		if bullet.controllable:
			bullet.dir = Vector2(bullet.dir).slerp(Vector2(frame.get("aim", bullet.dir)).normalized(), minf(1, delta * 8)).normalized()
		var previous = Vector2(bullet.pos)
		var next = previous + Vector2(bullet.dir) * float(bullet.speed) * delta
		bullet.travel += previous.distance_to(next)
		var hits_surface = not actor.geometry.clear_swept_segment(previous, next, bullet.radius)
		var hits_enemy = actor.enemies.any(func(enemy): return not enemy.dead and Geometry.segment_circle(previous, next, enemy.pos, float(enemy.radius) + float(bullet.radius)))
		if hits_surface or hits_enemy or bullet.travel > bullet.range or bullet.age > 1.5:
			cosmetic.erase(bullet)
		else: bullet.pos = next

func accept_event(event: Dictionary) -> bool:
	var id = int(event.get("prediction", 0))
	return not predicted.has(id) or event.get("burst_part", false) or event.get("kind", "") not in ["shot", "ray", "slash"]

func reconcile_bullets(authoritative: Array, seat: int) -> void:
	for bullet in authoritative:
		if int(bullet.get("owner", seat)) != seat or not bullet.get("friendly", false): continue
		var id = int(bullet.get("prediction", 0))
		if id <= 0: continue
		var candidates = cosmetic.filter(func(value): return int(value.prediction) == id)
		candidates.sort_custom(func(a, b): return Vector2(a.dir).dot(bullet.dir) > Vector2(b.dir).dot(bullet.dir))
		if candidates.is_empty(): continue
		var matched: Dictionary = candidates[0]
		corrections[int(bullet.uid)] = Vector2(matched.pos) - Vector2(bullet.pos)
		cosmetic.erase(matched)

func merge(authoritative: Array, actor) -> Array:
	var result: Array = []
	for source in authoritative:
		var bullet: Dictionary = source.duplicate(false)
		if corrections.has(int(bullet.uid)):
			bullet.pos = actor.geometry.constrain_floor(Vector2(bullet.pos) + Vector2(corrections[int(bullet.uid)]), float(bullet.radius))
		result.append(bullet)
	for bullet in cosmetic: result.append(bullet.duplicate(false))
	return result
