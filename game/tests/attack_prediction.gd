extends SceneTree
const Prediction = preload("res://scripts/network/attack_prediction.gd")
const World = preload("res://scripts/combat/world.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Inputs = preload("res://scripts/network/input_frames.gd")
var checks: Array = []

func check(label: String, passed: bool) -> void:
	checks.append({"id": label, "passed": passed})
	print("ATTACK_PREDICTION_", "PASS " if passed else "FAIL ", label)

func _initialize() -> void:
	var actor = World.new(); actor.start("c_paper", 91, 11)
	actor.player.pos = actor.geometry.bounds.get_center(); actor.enemies.clear()
	var before = actor.snapshot().duplicate(true)
	var before_events = actor.events.duplicate(true)
	var prediction = Prediction.new(); prediction.observe(actor, actor.player, [])
	var frame = Protocol.empty_input(); frame.seq = 1; frame.fire = true; frame.aim = Vector2.UP
	var events = prediction.tick(actor, frame, 1.0 / 60)
	check("first_tick_has_muzzle_and_projectile", events.any(func(event): return event.kind == "shot") and prediction.cosmetic.size() > 0)
	check("authority_untouched", before == actor.snapshot() and actor.events == before_events)
	check("input_carries_visual_identity", frame.shot > 0)
	var packet = Inputs.encode({"link": "1122334455667788", "match": "aabbccddeeff00112233445566778899", "frame": frame})
	check("compact_identity_roundtrip", Inputs.decode(packet).frame.shot == frame.shot and packet.size() <= 330)
	var repeated = events[0].duplicate(true); repeated.predicted = false
	check("authority_does_not_replay_predicted_sound", not prediction.accept_event(repeated))
	repeated.kind = "hit"
	check("actual_hit_feedback_is_preserved", prediction.accept_event(repeated))
	var predicted_bullet: Dictionary = prediction.cosmetic[0].duplicate(true)
	predicted_bullet.uid = 501
	predicted_bullet.owner = 0
	predicted_bullet.pos -= Vector2.UP * 40
	prediction.reconcile_bullets([predicted_bullet], 0)
	check("confirmation_removes_duplicate_projectile", prediction.cosmetic.is_empty())
	check("confirmation_preserves_continuous_position", prediction.merge([predicted_bullet], actor)[0].pos.distance_to(predicted_bullet.pos + Vector2.UP * 40) < .1)
	var previous_clock = actor.presentation_clock
	actor.time = -1; prediction.observe(actor, actor.player, [])
	check("delayed_authority_cannot_restart_pose", actor.presentation_clock >= previous_clock)
	prediction.clear()
	check("new_scene_clears_ghosts", prediction.cosmetic.is_empty() and prediction.corrections.is_empty() and not prediction.ready)
	print("ATTACK_PREDICTION_RESULT ", checks.all(func(row): return row.passed))
	quit(0 if checks.all(func(row): return row.passed) else 1)
