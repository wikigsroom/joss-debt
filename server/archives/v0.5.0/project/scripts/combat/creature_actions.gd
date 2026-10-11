extends RefCounted
## Presentation timestamps share the simulation clock, so pause and saves preserve poses.
const DIRECTIONS = ["down", "left", "right", "up"]
const HURT_FPS = 18.0
const HURT_DURATION = 6.0 / HURT_FPS
const RELEASE_FRAME_TIME = .065
const RELEASE_DURATION = .32

static func facing(vector: Vector2) -> String:
	if vector.is_zero_approx(): return "down"
	if absf(vector.x) > absf(vector.y): return "right" if vector.x > 0 else "left"
	return "down" if vector.y >= 0 else "up"

static func next_attack_state(enemy: Dictionary) -> String:
	var sprite_id = str(enemy.get("sprite_id", enemy.id))
	if not enemy.boss: return "attack_a" if sprite_id.begins_with("b") else "attack"
	var phase = clampi(int(enemy.phase), 0, 2)
	var step = int(enemy.get("attack_step", 0)) + 1
	if int(str(enemy.id).substr(1)) >= 6:
		if phase == 2 and step % 3 == 0: return "attack_c"
		return "attack_a" if phase == 0 or step % 2 == 0 else "attack_b"
	# The ledger boss cycles its three patterns during its final phase.
	if enemy.id == "b03" and phase == 2:
		return ["attack_a", "attack_b", "attack_c"][step % 3]
	return ["attack_a", "attack_b", "attack_c"][phase]

static func last_attack_state(enemy: Dictionary) -> String:
	# Older v2 saves have a strike time and completed attack_step but no bank.
	var previous = enemy.duplicate()
	previous.attack_step = int(enemy.get("attack_step", 1)) - 1
	return next_attack_state(previous)

static func prepare(enemy: Dictionary, now: float, duration: float = -1.0) -> void:
	enemy.visual_prepare_at = now
	enemy.visual_prepare_duration = maxf(.001, float(enemy.tell) if duration < 0 else duration)
	enemy.visual_prepare_state = next_attack_state(enemy)
	enemy.visual_prepare_facing = facing(enemy.aim)

static func strike(enemy: Dictionary, now: float, aim: Vector2 = Vector2.ZERO) -> void:
	enemy.visual_attack_at = now
	enemy.visual_attack_state = next_attack_state(enemy)
	enemy.visual_attack_facing = facing(enemy.aim if aim.is_zero_approx() else aim)
	enemy.visual_lunge_attack = false
	enemy.visual_attack_recovery_at = now

static func finish_attack_setup(enemy: Dictionary, now: float) -> void:
	enemy.visual_lunge_attack = float(enemy.lunge) > 0
	if not enemy.visual_lunge_attack: enemy.visual_attack_recovery_at = now

static func hurt(enemy: Dictionary, now: float, look: Vector2) -> void:
	var direction = facing(look)
	if float(enemy.windup) > 0:
		direction = str(enemy.get("visual_prepare_facing", facing(enemy.aim)))
	elif now - float(enemy.get("visual_attack_at", -999.0)) < RELEASE_DURATION:
		direction = str(enemy.get("visual_attack_facing", facing(enemy.aim)))
	enemy.visual_hurt_at = now
	enemy.visual_hurt_facing = direction

static func sample(enemy: Dictionary, now: float, player_position: Vector2) -> Dictionary:
	var direction = facing(Vector2(enemy.pos).direction_to(player_position))
	var pose = {"state": "idle", "elapsed": now + float(enemy.uid) * .13,
		"direction": direction, "frame": -1}
	var hurt_age = now - float(enemy.get("visual_hurt_at", -999.0))
	var attack_age = now - float(enemy.get("visual_attack_at", -999.0))
	var lunge_attack = bool(enemy.get("visual_lunge_attack", float(enemy.lunge) > 0))
	var attack_active = attack_age >= 0 and attack_age < RELEASE_DURATION
	var attack_frame = mini(5, 2 + int(maxf(0, attack_age + .00001) / RELEASE_FRAME_TIME))
	if lunge_attack and attack_age >= 0:
		var recovery_age = now - float(enemy.get("visual_attack_recovery_at", -999.0))
		attack_active = float(enemy.lunge) > 0 or (recovery_age >= 0 and recovery_age < RELEASE_DURATION - RELEASE_FRAME_TIME)
		attack_frame = 2 if float(enemy.lunge) > 0 else mini(5, 3 + int(maxf(0, recovery_age + .00001) / RELEASE_FRAME_TIME))
	var stunned = now < float(enemy.get("stun_until", 0))
	# An active release must stay readable even under repeated ranged damage.
	# Actual stun still interrupts it, as in the authoritative combat logic.
	if attack_active and attack_frame == 2 and float(enemy.windup) <= 0 and not stunned:
		pose.state = str(enemy.visual_attack_state) if enemy.has("visual_attack_state") else last_attack_state(enemy)
		pose.elapsed = maxf(0, attack_age)
		pose.frame = 2
		pose.direction = str(enemy.get("visual_attack_facing", facing(enemy.aim)))
	elif hurt_age >= 0 and (hurt_age < HURT_DURATION or stunned):
		pose.state = "hurt"
		pose.elapsed = hurt_age
		pose.frame = mini(5, int((hurt_age + .00001) * HURT_FPS))
		pose.direction = str(enemy.get("visual_hurt_facing", direction))
	elif float(enemy.windup) > 0:
		var duration = maxf(.001, float(enemy.get("visual_prepare_duration", enemy.tell)))
		var progress = clampf(1.0 - float(enemy.windup) / duration, 0.0, 1.0)
		pose.state = str(enemy.get("visual_prepare_state", next_attack_state(enemy)))
		pose.frame = 0 if progress < .45 else 1
		pose.elapsed = progress * duration
		pose.direction = str(enemy.get("visual_prepare_facing", facing(enemy.aim)))
	else:
		if attack_active:
			pose.state = str(enemy.visual_attack_state) if enemy.has("visual_attack_state") else last_attack_state(enemy)
			pose.elapsed = attack_age
			pose.frame = attack_frame
			pose.direction = str(enemy.get("visual_attack_facing", facing(enemy.aim)))
		elif enemy.boss and now - float(enemy.get("visual_phase_at", -999.0)) < .375:
			pose.state = "phase"
			pose.elapsed = maxf(0, now - float(enemy.get("visual_phase_at", now)))
		elif float(enemy.get("visual_motion", 0)) > 8 or (not enemy.boss and enemy.speed > 0 and Vector2(enemy.pos).distance_to(player_position) > 240):
			pose.state = "move"
	return pose

static func valid_saved_state(enemy: Dictionary) -> bool:
	for field in ["visual_prepare_at", "visual_prepare_duration", "visual_attack_at", "visual_attack_recovery_at", "visual_hurt_at"]:
		if not enemy.has(field): continue
		if not (enemy[field] is float or enemy[field] is int) or not is_finite(float(enemy[field])): return false
		if field == "visual_prepare_duration" and float(enemy[field]) <= 0: return false
	for field in ["visual_prepare_facing", "visual_attack_facing", "visual_hurt_facing"]:
		if enemy.has(field) and not enemy[field] in DIRECTIONS: return false
	for field in ["visual_prepare_state", "visual_attack_state"]:
		if enemy.has(field) and not enemy[field] in ["attack", "attack_a", "attack_b", "attack_c"]: return false
	if enemy.has("visual_lunge_attack") and not enemy.visual_lunge_attack is bool: return false
	return true
