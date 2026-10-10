extends SceneTree
const MusicState = preload("res://scripts/ui/music_state.gd")
const Audio = preload("res://scripts/ui/audio_director.gd")
const World = preload("res://scripts/combat/world.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, description: String) -> void:
	checks.append(description)
	if not condition:
		failures.append(description)
		push_error(description)

func run_suite() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	var w = World.new()
	w.start("c_paper", 4191)
	var state = MusicState.new()
	state.configure(manifest.scores.region_1)
	var seconds = 60.0 / state.bpm
	expect(MusicState.context_for(w, "menu") == "hub", "the title and safe hub select their own thematic score")
	expect(MusicState.context_for(w, "game") == "region_1", "the actual first chapter selects its region theme")
	state.observe(w)
	state.advance(seconds * 3.9)
	expect(state.current_tier == 0 and state.gains()[1] == 0, "entering combat waits for the next four-beat boundary")
	state.advance(seconds * 4.01)
	expect(state.current_tier == 1 and state.gains()[1] > 0, "the next bar introduces the real combat rhythm stem")
	w.player.hp = 2
	state.observe(w)
	state.advance(seconds * 7.9)
	expect(state.current_tier == 1, "low health cannot abruptly add a tension layer mid-phrase")
	state.advance(seconds * 8.01)
	expect(state.current_tier == 2 and state.gains()[2] > 0, "low health raises musical tension on the next bar")
	var transition_count = state.transitions.size()
	for i in 20:
		state.observe(w)
		state.advance(seconds * (8.02 + i * .01))
	expect(state.transitions.size() == transition_count, "stable observations do not repeatedly restart or pump a layer")
	w.player.hp = w.player.max_hp
	w.chains = [[1, 2, 3]]
	state.observe(w)
	expect(state.requested_tier == 2, "a real three-actor chain requests the heightened arrangement")
	w.chains.clear()
	state.accept([{"kind": "skill", "targets": 3}])
	state.observe(w)
	expect(state.requested_tier == 2, "a multi-target detonation keeps a short musical response after its chain vanishes")
	state.accept([{"kind": "chain_formed", "size": 5, "links": 4}])
	expect(state.burst_until > state.beat + 3.0, "a large newly formed chain extends the real musical response according to its link count")
	state.accept([{"kind": "burst"}])
	expect(state.burst_until > state.beat, "a real detonation burst keeps a short musical tail even without a new chain")
	state.advance(seconds * 19.1)
	state.observe(w)
	expect(state.requested_tier == 1, "the detonation response expires instead of remaining at maximum intensity")
	state.accept([{"kind": "boss_phase"}])
	state.advance(seconds * 19.9)
	expect(not state.gap_active(), "a phase break waits for its actual next beat")
	state.advance(seconds * 20.1)
	expect(state.gap_active() and state.gains()[1] == 0 and state.gains()[2] == 0, "one phase-transition beat leaves rhythmic space for the danger cue")
	state.advance(seconds * 21.1)
	expect(not state.gap_active(), "the phase break restores rhythm after exactly one beat")
	state.accept([{"kind": "wave_incoming"}])
	state.advance(seconds * 22.1)
	expect(state.gap_active(), "an incoming wave receives the same bounded musical breath")
	state.accept([{"kind": "room_return"}])
	expect(not state.gap_active(), "returning to a different room clears a stale warning gap")
	w.mode = "clear"
	state.observe(w)
	state.advance(seconds * 24.01)
	expect(state.current_tier == 0 and state.gains()[1] == 0, "a cleared room returns to the sparse base arrangement")
	state.advance(state.duration - .01)
	var before_wrap = state.beat
	state.advance(.05)
	expect(state.beat > before_wrap and state.position > state.duration, "an actual sample-loop wrap preserves the absolute musical transport")
	w.run.room = 10
	w.enter_room()
	expect(MusicState.context_for(w, "game") == "boss", "the real live boss selects a dedicated synchronized score")
	w.enemies[0].phase = 1
	state.observe(w)
	expect(state.requested_tier == 2, "a later actual boss phase requests the tension stem")
	for ending in ["burn", "repay", "rewrite"]:
		w.mode = "result"
		w.run.ending = ending
		expect(MusicState.context_for(w, "game") == "ending_" + ending, "the %s ending keeps its distinct thematic tail" % ending)
	w.run.room = w.run.graph.types.find("sacrifice")
	w.enter_room()
	state.observe(w)
	expect(state.requested_tier == 1 and MusicState.context_for(w, "game") == "region_1", "a sacrifice room keeps its region score while adding a quieter identity layer")
	w.run.room = w.run.graph.types.find("challenge")
	w.enter_room()
	state.observe(w)
	expect(state.requested_tier == 1 and w.room_type() == "challenge" and w.room_flags.wave_count == 3, "a challenge room keeps the region score while entering its three-wave tension arrangement")
	var world_before = JSON.stringify(w.snapshot())
	for i in 10:
		state.observe(w)
		state.advance(.06 + i * .01)
		MusicState.context_for(w, "game")
	expect(JSON.stringify(w.snapshot()) == world_before, "musical observation leaves the complete combat snapshot and every random stream unchanged")
	var audio = Audio.new()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -80.0)
	root.add_child(audio)
	audio.set_music_mode("score")
	audio.set_muted(true)
	var loaded_sfx = 0
	for id in audio.streams:
		var variants = audio.streams[id]
		if variants.size() == 3 and variants.all(func(stream): return stream is AudioStreamWAV): loaded_sfx += 1
	expect(loaded_sfx == 29, "all 29 attack/impact/hurt/UI sound families load three PCM variants")
	expect(audio.attack_sound({"kind": "ray"}) == "shot_ray" and audio.attack_sound({"kind": "slash", "charged": true}) == "shot_heavy" and audio.hit_sound({"source": "secondary"}) == "hit_chain" and audio.hurt_sound({"damage": 2}) == "hurt_heavy", "combat event metadata selects distinct attack, impact and hurt layers")
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	var expected_attack = {
		"orb": "shot", "bell": "shot", "flame_orb": "shot", "cone": "shot_melee",
		"returning": "shot_controlled", "piercing": "shot", "fan": "shot",
		"explosive": "shot_heavy", "ricochet": "shot_controlled", "seeker": "shot_controlled",
		"charged_line": "shot_heavy", "arc": "shot_melee", "triple": "shot",
		"ray": "shot_ray", "controlled": "shot_controlled", "charged_arc": "shot_heavy",
		"burst": "shot", "cloud": "shot_controlled", "orbit_blade": "shot_melee", "rain": "shot_heavy",
		"lightning": "shot_ray", "radial": "shot_heavy", "wave": "shot_controlled", "tether": "shot_ray",
		"split": "shot_controlled", "boomerang_arc": "shot_melee", "mine": "shot_heavy", "homing_cluster": "shot_controlled",
		"sweep": "shot_melee", "prism": "shot_ray", "guided_swarm": "shot_controlled", "nova": "shot_heavy",
	}
	var covered_modes = {}
	for weapon in catalog.weapons:
		var mode = str(weapon.get("mode", ""))
		var kind = "ray" if mode == "ray" else ("slash" if mode in ["arc", "cone", "charged_arc"] else "shot")
		var voice = audio.attack_voice({"kind": kind, "mode": mode, "charged": mode in ["charged_line", "charged_arc"]})
		covered_modes[mode] = true
		expect(expected_attack.get(mode, "") == str(voice.id) and not str(voice.layer).is_empty() if mode in ["fan", "triple", "bell", "charged_line", "charged_arc"] else expected_attack.get(mode, "") == str(voice.id), "weapon mode %s resolves to an authored attack voice" % mode)
		var impact = audio.hit_voice({"weapon_mode": mode, "heavy": mode in ["explosive", "charged_line"]})
		expect(not str(impact.id).is_empty() and (mode not in ["triple", "bell", "explosive", "charged_line", "ray"] or not str(impact.layer).is_empty()), "weapon mode %s resolves to an authored impact voice" % mode)
	expect(covered_modes.size() == expected_attack.size() and covered_modes.size() == 32, "all 32 catalog weapon modes have explicit attack and impact coverage")
	var light_hurt = audio.hurt_voice({"damage": 1})
	var heavy_hurt = audio.hurt_voice({"damage": 2})
	var debt_hurt_voice = audio.hurt_voice({"damage": 1, "source": {"kind": "debt"}})
	expect(light_hurt.id == "hurt" and heavy_hurt.id == "hurt_heavy" and debt_hurt_voice.id == "hurt_debt", "light, heavy and debt damage select distinct authored hurt voices")
	expect(heavy_hurt.layer == "warning" and debt_hurt_voice.layer == "contract", "heavy and debt damage add distinct warning and contract accents")
	var fan_voice = audio.attack_voice({"kind": "shot", "mode": "fan"})
	var charge_voice = audio.attack_voice({"kind": "shot", "mode": "charged_line"})
	var triple_hit = audio.hit_voice({"weapon_mode": "triple"})
	var debt_hurt = audio.hurt_voice({"damage": 2, "source": {"kind": "debt"}})
	audio.accept([{"kind": "chain_formed", "at": 1.0, "links": 3}])
	expect(fan_voice.layer == "shot_controlled" and fan_voice.pitch < 1.0 and charge_voice.layer == "shot_ray", "spread and charged weapons receive distinct layered attack voices")
	expect(triple_hit.layer == "mark" and debt_hurt.layer == "contract", "impact and debt hurt voices add authored material accents")
	expect(audio.last_chain == 1.0, "a real multi-link chain emits a throttled chain impact cue")
	expect(audio.music_tracks.size() == 9 and audio.score_manifest == manifest.scores, "the shipping configuration matches production and loads all nine complete themes")
	var checked_stems = 0
	for context in manifest.scores:
		var track = audio.music_tracks[context]
		for i in track.stream_count:
			var stream = track.get_sync_stream(i)
			checked_stems += 1
			expect(stream is AudioStreamOggVorbis and stream.packet_sequence.sampling_rate == 48000 and stream.loop and absf(stream.get_length() - float(manifest.scores[context].duration)) < .01, "%s/%d preserves its complete encoded length, native loop and sample rate" % [context, i])
	var expected_stems = 0
	for context in manifest.scores:
		expected_stems += manifest.scores[context].stems.size()
	expect(checked_stems == expected_stems and expected_stems == 25, "all produced score stems are actually native-loaded (%d including accent voices)" % expected_stems)
	audio.set_context("region_2")
	var stream_before = audio.music.stream
	var swaps_before = audio.score_transitions
	audio.set_context("region_2")
	expect(audio.music.stream == stream_before and audio.score_transitions == swaps_before, "repeated scene observation does not restart the theme")
	audio.set_paused(true)
	expect(audio.paused and not audio.music.stream_paused, "menu pause keeps a softly ducked musical transport")
	audio.set_suspended(true)
	var suspended_position = audio.music_state.position
	audio._process(.5)
	expect(audio.music.stream_paused and audio.music_state.position == suspended_position, "application suspension freezes the actual player and musical clock")
	audio.set_context("region_3")
	expect(audio.music.stream_paused and audio.fade_player.stream_paused, "a theme transition cannot unpause background audio")
	audio.set_suspended(false)
	expect(not audio.music.stream_paused and audio.paused, "foreground restoration preserves menu pause while restoring audio transport")
	audio.set_muted(false)
	audio.play("warning")
	expect(audio.duck_left > 0, "a dangerous warning actively reduces music underneath its real effect voice")
	audio.set_muted(true)
	expect(audio.music.volume_db == -80 and audio.fade_player.volume_db == -80 and not audio.players.any(func(player): return player.playing), "mute covers both sides of a crossfade and all current effects")
	audio.music.stop()
	audio.fade_player.stop()
	audio.music.stream = null
	audio.fade_player.stream = null
	for player in audio.players:
		player.stop()
		player.stream = null
	audio.music_tracks.clear()
	stream_before = null
	audio.free()
	audio = null
	state = null
	w = null
	await process_frame
	# Let the native mixer retire stopped playback references before exiting the fixture.
	await create_timer(.15).timeout
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "musical decisions, actual imported native streams, sample-loop lengths, lifecycle and RNG isolation; no human listening or physical handset claim"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/adaptive-music-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Adaptive music: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
