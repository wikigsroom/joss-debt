extends SceneTree
const Playlist = preload("res://scripts/ui/music_playlist.gd")
const Audio = preload("res://scripts/ui/audio_director.gd")
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("run_suite")

func expect(value: bool, message: String) -> void:
	checks.append(message)
	if not value:
		failures.append(message)
		push_error(message)

func run_suite() -> void:
	var playlist = Playlist.new()
	expect(playlist.tracks.size() == 4, "four user-selected Yourset tracks are actually imported")
	var previous = ""
	var cycles_valid = true
	var adjacent_valid = true
	for cycle in 50:
		var seen = {}
		for index in 4:
			var track = playlist.next_track()
			seen[track.id] = true
			adjacent_valid = adjacent_valid and track.id != previous
			previous = track.id
		cycles_valid = cycles_valid and seen.size() == 4
	expect(cycles_valid, "50 shuffle cycles play every song once before refill")
	expect(adjacent_valid, "200 selected songs include no adjacent repeat across cycle boundaries")
	for track in playlist.tracks:
		var stream = load(str(track.path))
		expect(stream is AudioStreamOggVorbis and not stream.loop and stream.packet_sequence.sampling_rate == 48000 and absf(stream.get_length() - float(track.duration)) < .01, "%s loads the full 48 kHz native stream with looping disabled" % track.id)
	var world = World.new()
	world.start("c_paper", 20261009)
	var before = JSON.stringify(Store.encode(world.snapshot()), "", true, true)
	var audio = Audio.new()
	root.add_child(audio)
	audio.set_process(false)
	audio.set_muted(true)
	expect(audio.music_mode == "random" and audio.track_changes == 1 and audio.music.stream is AudioStreamOggVorbis, "native director starts a real playlist stream by default")
	var current = audio.music
	var song = audio.playlist.current_id
	for context in ["region_1", "region_2", "shop", "boss", "hub"]: audio.set_context(context)
	expect(audio.music == current and audio.playlist.current_id == song and audio.track_changes == 1, "room and menu changes preserve the currently playing song")
	audio.next_song()
	expect(audio.music != current and audio.fade_player == current and audio.fade_duration == 1.2 and audio.track_changes == 2, "song transitions preserve outgoing playback for a 1.2 second crossfade")
	var changes = audio.track_changes
	audio.on_track_finished(audio.fade_player)
	expect(audio.track_changes == changes, "an outgoing player's completion cannot replace the new song")
	audio.on_track_finished(audio.music)
	expect(audio.track_changes == changes + 1, "completion of the active song advances the playlist")
	audio.set_paused(true)
	expect(not audio.music.stream_paused, "menu pause keeps background music playing softly")
	audio.set_suspended(true)
	changes = audio.track_changes
	audio.on_track_finished(audio.music)
	audio._process(.5)
	expect(audio.track_changes == changes and audio.music.stream_paused and audio.fade_player.stream_paused, "application suspension freezes both music players and track changes")
	audio.set_suspended(false)
	audio.set_muted(false)
	audio._process(2.0)
	expect(audio.fade_left == 0 and not audio.fade_player.playing and audio.music.volume_db > -80, "crossfade finishes and retires the outgoing decoder")
	audio.set_muted(true)
	expect(audio.music.volume_db == -80 and audio.fade_player.volume_db == -80, "mute silences both sides of a playlist transition")
	audio.set_music_mode("score")
	expect(audio.music.stream is AudioStreamSynchronized, "original chapter themes remain an explicit settings option")
	audio.set_music_mode("random")
	expect(audio.music.stream is AudioStreamOggVorbis and audio.playlist.current_id != "", "returning to random mode resumes a packaged Yourset song")
	expect(JSON.stringify(Store.encode(world.snapshot()), "", true, true) == before, "music selection and transitions never consume gameplay RNG or modify a save")
	current = null
	audio.queue_free()
	await process_frame
	await process_frame
	await create_timer(.25).timeout
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "200 shuffle selections, actual native OGG playback, crossfade/lifecycle and world snapshot isolation"}
	var file = FileAccess.open("res://../docs/incense-debt/reports/action-mobile-2026-10-09/playlist-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Random playlist: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
