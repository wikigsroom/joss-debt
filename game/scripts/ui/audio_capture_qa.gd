extends Node
## Internal native-mixer fixture; never records the microphone or affects OS volume.
const World = preload("res://scripts/combat/world.gd")
var director
var directory = ""
var recorder: AudioEffectRecord
var checks: Array = []
var failures: Array = []
var recordings: Array = []
var trace: Array = []

func _ready() -> void:
	call_deferred("run_fixture")

func expect(condition: bool, text: String) -> void:
	checks.append(text)
	if not condition: failures.append(text)

func record_clip(name: String, seconds: float) -> void:
	recorder.set_recording_active(true)
	await get_tree().create_timer(seconds).timeout
	recorder.set_recording_active(false)
	var recording = recorder.get_recording()
	var path = directory.path_join(name + ".wav")
	var error = recording.save_to_wav(path)
	recordings.append({"name": name, "file": path, "seconds": recording.get_length(), "sample_rate": recording.mix_rate, "saved": error == OK})
	trace.append({"name": name, "audio": director.diagnostics()})
	expect(error == OK and recording.get_length() > seconds * .8, name + " produces real native PCM samples")

func compare_interval(world, name: String, tier: int, paused: bool = false) -> void:
	world.mode = "clear" if tier == 0 else "combat"
	world.player.hp = 2 if tier == 2 else world.player.max_hp
	director.observe(world, "game")
	director.set_paused(paused)
	# Let the native mix thread commit a newly selected stream before seeking.
	await get_tree().create_timer(.4).timeout
	director.music.seek(30.0)
	# Use the same source interval so RMS differences reflect real layer mixing.
	await get_tree().create_timer(.65).timeout
	expect(director.music_state.current_tier == tier, name + " reaches its requested musical arrangement")
	await record_clip(name, 2.0)

func run_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var master = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, -80.0)
	AudioServer.add_bus()
	var bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "QA internal capture")
	AudioServer.set_bus_send(bus, "Master")
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, recorder)
	director.music.bus = "QA internal capture"
	director.fade_player.bus = "QA internal capture"
	for player in director.players: player.bus = "QA internal capture"
	director.set_levels(.8, .7, .8)
	director.set_muted(false)
	var world = World.new()
	world.start("c_paper", 9414)
	await compare_interval(world, "exploration", 0)
	await compare_interval(world, "combat", 1)
	await compare_interval(world, "tension", 2)
	await compare_interval(world, "menu-pause", 0, true)
	var playing_before = director.music.get_playback_position()
	await get_tree().create_timer(.25).timeout
	expect(director.music.get_playback_position() > playing_before + .1, "menu pause retains a live softly mixed transport")
	director.set_suspended(true)
	var suspended_position = director.music.get_playback_position()
	await get_tree().create_timer(.3).timeout
	expect(absf(director.music.get_playback_position() - suspended_position) < .03, "native application suspension stops sample transport")
	director.set_context("boss")
	await get_tree().create_timer(.2).timeout
	expect(director.music.get_playback_position() < .05 and director.music.stream_paused, "changing scene during suspension cannot start native samples")
	director.set_suspended(false)
	director.set_paused(false)
	director.set_context("region_1")
	world.mode = "clear"
	director.observe(world, "game")
	var length = director.score_manifest.region_1.duration
	director.music.seek(length - .4)
	await get_tree().create_timer(.15).timeout
	await record_clip("loop-seam", 1.2)
	expect(director.music.playing and director.music_state.position > length, "native synchronized stems continue across the full-length loop seam")
	director.set_muted(true)
	await get_tree().create_timer(.2).timeout
	await record_clip("muted", 1.0)
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"recordings": recordings, "trace": trace, "mix_rate": AudioServer.get_mix_rate(),
		"scope": "native Windows audio mixer with authored stems plus filtered CC0 room-air texture; comparison clips seek the same source interval; no microphone, physical phone or human listening claim"}
	var file = FileAccess.open(directory.path_join("native-audio.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Native audio: %d checks; %d failures; %d recordings" % [checks.size(), failures.size(), recordings.size()])
	if not failures.is_empty(): print(failures)
	director.set_suspended(true)
	get_tree().quit(0 if failures.is_empty() else 1)
