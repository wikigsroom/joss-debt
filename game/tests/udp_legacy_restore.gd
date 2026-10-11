extends "res://tests/cooperative_recovery.gd"
## Upgrade acceptance: canonical saved simulation is checked separately by Python.
## Only the old transport's presentation is normalized to the new wire format.
const Stream = preload("res://scripts/network/state_stream.gd")

func read_expected() -> void:
	super.read_expected()
	var sender = Stream.new("0123456789abcdef")
	var receiver = Stream.new("0123456789abcdef")
	var state = {"id": expected.match, "actors": expected.actors, "scene": expected.scene,
		"state_seq": 1, "lease": 0, "input_scene": int(expected.scene.serial)}
	for item in sender.encode(state): receiver.decode(item.bytes)
	check(receiver.scene_ready, "legacy_presentation_normalized_without_simulation_changes")
	expected.actors = receiver.view.actors
	expected.scene = receiver.view.scene
