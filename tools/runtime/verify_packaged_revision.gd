extends SceneTree
## Matching native Godot runner opens the EXE's actual embedded PCK with --main-pack.
var output = ""
var expected: Dictionary = {}
var expected_version = ""
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
		if argument.begins_with("--expected="): expected = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--expected=")))
		if argument.begins_with("--version="): expected_version = argument.trim_prefix("--version=")
	call_deferred("run_suite")

func expect(value: bool, name: String) -> void:
	checks.append(name)
	if not value:
		failures.append(name)
		push_error(name)

func run_suite() -> void:
	expect(not expected_version.is_empty() and ProjectSettings.get_setting("application/config/version") == expected_version, "the executable loads the current " + expected_version + " project from its embedded pack")
	var pickups = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pickups/manifest.json"))
	for row in pickups.records:
		var image: Texture2D = load(row.file)
		expect(image != null and image.get_width() == row.size[0] and image.get_height() == row.size[1] and image.get_image().get_pixel(0, 0).a == 0,
			"the generated pickup bitmap loads with its dimensions and transparent background: " + str(row.id))
	for path in expected:
		expect(FileAccess.get_sha256(path) == expected[path], "packaged file matches current source: " + path)
	var animation = load("res://scripts/ui/paper_animation.gd").new()
	var motion = load("res://scripts/ui/weapon_motion.gd").new()
	expect(motion.manifest.animation_method == "independently_drawn_six_frame_poses" and motion.manifest.actors.size() == 6 and motion.manifest.weapons.size() == 32, "the compiled presentation uses the six independent rigs and all 32 weapons")
	var valid = true
	var count = 0
	for actor in motion.manifest.actors:
		for state in animation.COUNTS.character:
			for direction in ["down","left","right","up"]:
				for index in 6:
					var frame = animation.texture(actor,"weapon_body",state,(index+.01)/animation.CHARACTER_FPS[state],direction)
					valid = valid and frame != null and frame.atlas.get_width() == 576 and frame.atlas.get_height() == 384
					count += 1
	expect(valid and count == 864, "all 864 drawn hero poses actually load from the executable")
	var creature_manifest: Dictionary = {}
	var creature_text := FileAccess.get_file_as_string("res://assets/creature-actions.json")
	var parsed_creatures: Variant = JSON.parse_string(creature_text)
	if parsed_creatures is Dictionary: creature_manifest = parsed_creatures
	expect(creature_manifest.get("complete", false) and animation.creature_actions.size() == 402, "the executable contains the complete 402-identity creature action catalog")
	var creature_frames := 0
	var creature_valid := true
	var directions := ["down", "left", "right", "up"]
	for identity in animation.creature_actions:
		var entry: Dictionary = animation.creature_actions[identity]
		var states: Dictionary = entry.get("states", {})
		var required_states := ["attack_a", "attack_b", "attack_c", "hurt"] if str(identity).begins_with("b") else ["attack", "hurt"]
		creature_valid = creature_valid and states.size() == required_states.size()
		for state in required_states:
			if not states.has(state):
				creature_valid = false
				continue
			var strip: Dictionary = states[state]
			creature_valid = creature_valid and strip.get("frames", 0) == 6 and strip.get("directions", []) == directions
			var size := int(entry.get("frame_size", 0))
			for row in 4:
				for index in 6:
					var pose: Texture2D = animation.texture(str(identity), "boss" if str(identity).begins_with("b") else "enemy", state, 0.0, directions[row], index)
					creature_valid = creature_valid and pose is AtlasTexture
					if pose is AtlasTexture:
						creature_valid = creature_valid and pose.region == Rect2(index * size, row * size, size, size) and pose.atlas.get_width() == size * 6 and pose.atlas.get_height() == size * 4
					creature_frames += 1
		# Keep native texture memory bounded while checking the whole exported roster.
		animation.clear()
	expect(creature_valid and creature_frames == 24048, "all 24048 creature attack/hurt poses load from the executable at the exact direction and frame")
	var fx = load("res://scripts/ui/drawn_action_fx.gd").new()
	var fx_valid = true
	for name in ["muzzle","melee","impact","hurt"]:
		for index in 6: fx_valid = fx_valid and fx.frame(name,index) != null
	expect(fx_valid, "the compiled effects load all 24 independently drawn FX frames")
	var adapter = load("res://scripts/ui/input_adapter.gd").new()
	expect(adapter.control_sizes.size() == 5 and adapter.valid_layout() and adapter.set_control_size("aim",1.2), "the exported input adapter includes individual sizes and the new layout")
	var finger = InputEventScreenTouch.new()
	finger.index = 1
	finger.position = adapter.control_center("move")
	finger.pressed = true
	adapter.event(finger)
	var movement = InputEventScreenDrag.new()
	movement.index = 1
	movement.position = finger.position + Vector2.RIGHT * adapter.control_travel("move")
	adapter.event(movement)
	var emulated = InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	adapter.event(emulated)
	var frame = adapter.sample(Vector2.ZERO,Vector2.ZERO)
	expect(frame.device == "touch" and not frame.fire and frame.dash_direction.x > .99, "actual exported input preserves touch identity across emulated mouse events")
	expect(adapter.profile.from_event(emulated,"keyboard").is_empty(), "actual exported bindings ignore touch-emulated mouse clicks")
	var playlist = load("res://scripts/ui/music_playlist.gd").new()
	expect(playlist.tracks.size() == 4, "the executable contains all four Yourset songs")
	for track in playlist.tracks:
		var stream = load(str(track.path))
		expect(stream is AudioStreamOggVorbis and not stream.loop and absf(stream.get_length()-float(track.duration)) < .01, "the exported Yourset decoder loads: " + str(track.id))
	animation.clear()
	fx.frames.clear()
	fx.strips.clear()
	var report = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"hero_frames":count,"creature_identities":animation.creature_actions.size(),"creature_frames":creature_frames,"scope":"matching native Godot test runner opens the actual Windows EXE embedded PCK; real exported resources and compiled scripts; separate packaged keyboard QA verifies executable runtime; no Android hardware claim"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Packaged revision: %d checks; %d failures" % [checks.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
