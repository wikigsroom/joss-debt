extends Node

const MusicState = preload("res://scripts/ui/music_state.gd")

var players: Array = []
var streams: Dictionary = {}
var music: AudioStreamPlayer
var muted = false
var next_voice = 0
var last_shot = -10.0
var last_hit = -10.0
var last_chain = -10.0
var variant: Dictionary = {}
var music_tracks: Dictionary = {}
var active_context = ""
var master_level = .8
var music_level = .7
var effect_level = .8
var last_warning = -10.0
var fade_player: AudioStreamPlayer
var fade_left = 0.0
var score_manifest: Dictionary = {}
var music_state = MusicState.new()
var layer_gains: Array = [1.0, 0.0, 0.0, 0.0, 0.0]
var paused = false
var suspended = false
var duck_left = 0.0
var score_transitions = 0

func _ready() -> void:
	for id in ["shot", "shot_melee", "shot_ray", "shot_heavy", "shot_controlled", "hit", "hit_melee", "hit_heavy", "hit_crit", "hit_armor", "hit_chain", "hurt", "hurt_heavy", "hurt_debt", "skill", "dash", "pickup", "bell", "clear", "mark", "chain", "death", "warning", "contract", "repay", "menu", "armor", "deflect", "burst"]:
		streams[id] = []
		for i in 3: streams[id].append(load("res://assets/audio/" + id + ("" if i == 0 else "_%d" % i) + ".wav"))
	for i in 8:
		var player = AudioStreamPlayer.new()
		player.volume_db = -9.0
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	add_child(music)
	fade_player = AudioStreamPlayer.new()
	add_child(fade_player)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_scores.json"))
	score_manifest = manifest.scores
	for context in score_manifest:
		var synchronized = AudioStreamSynchronized.new()
		var stems: Array = score_manifest[context].stems
		synchronized.stream_count = stems.size()
		for i in stems.size():
			var track = load("res://assets/audio/" + stems[i] + ".ogg")
			track.loop = true
			track.loop_offset = 0.0
			synchronized.set_sync_stream(i, track)
			synchronized.set_sync_stream_volume(i, 0.0 if i == 0 else -80.0)
		music_tracks[context] = synchronized
	set_context("hub")

func _exit_tree() -> void:
	# Stop and detach every native player before the director leaves a scene.
	# This matters on mobile where a suspended scene can otherwise retain
	# decoded OGG/WAV streams across a long sequence of room transitions.
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	players.clear()
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	if is_instance_valid(fade_player):
		fade_player.stop()
		fade_player.stream = null
	streams.clear()
	music_tracks.clear()
	score_manifest.clear()
	variant.clear()

func set_context(context: String) -> void:
	if context == active_context or not music_tracks.has(context): return
	active_context = context
	score_transitions += 1
	music_state.configure(score_manifest[context])
	layer_gains = [1.0, 0.0, 0.0, 0.0, 0.0]
	fade_player.stop()
	var previous = music
	music = fade_player
	fade_player = previous
	music.stream = music_tracks[context]
	for i in music.stream.stream_count: music.stream.set_sync_stream_volume(i, 0.0 if i == 0 else -80.0)
	music.volume_db = -80
	music.play()
	music.stream_paused = suspended
	fade_left = .35

func _process(delta: float) -> void:
	if suspended: return
	duck_left = maxf(0, duck_left - delta)
	fade_left = maxf(0, fade_left - delta)
	var amount = 1.0 - fade_left / .35
	var position = maxf(0, music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	music_state.advance(position)
	if layer_gains.size() != music.stream.stream_count:
		layer_gains.resize(music.stream.stream_count)
		for i in music.stream.stream_count:
			if i == 0: layer_gains[i] = 1.0
			else: layer_gains[i] = 0.0
	var target_gains: Array = music_state.gains()
	for i in music.stream.stream_count:
		var target = float(target_gains[i]) if i < target_gains.size() else 0.0
		layer_gains[i] = move_toward(float(layer_gains[i]), target, delta * 4.0)
		music.stream.set_sync_stream_volume(i, linear_to_db(maxf(.0001, float(layer_gains[i]))))
	var gain = master_level * music_level * .65 * (.32 if paused else 1.0) * (.45 if duck_left > 0 else 1.0)
	music.volume_db = linear_to_db(maxf(.0001, gain * amount)) if not muted else -80
	fade_player.volume_db = linear_to_db(maxf(.0001, gain * (1.0 - amount))) if not muted else -80
	if fade_left == 0 and fade_player.playing: fade_player.stop()

func observe(world, screen: String) -> void:
	set_context(MusicState.context_for(world, screen))
	music_state.observe(world)

func set_levels(master: float, background: float, effects: float) -> void:
	master_level = clampf(master, 0, 1)
	music_level = clampf(background, 0, 1)
	effect_level = clampf(effects, 0, 1)

func play(id: String, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> void:
	if muted or suspended or not streams.has(id):
		return
	var high_priority = id in ["hurt", "warning", "skill", "armor"]
	if high_priority: duck_left = maxf(duck_left, .22 if id in ["hurt", "warning"] else .12)
	if players.filter(func(p): return p.playing and p.get_meta("group", "") == id).size() >= 4: return
	var player = null
	for i in players.size():
		var candidate = players[(next_voice + i) % players.size()]
		if not candidate.playing or high_priority or candidate.get_meta("group", "") not in ["hurt", "warning", "skill", "armor"]:
			player = candidate
			break
	if player == null: return
	next_voice = (next_voice + 1) % players.size()
	var index = int(variant.get(id, 0))
	variant[id] = (index + 1) % 3
	player.stream = streams[id][index]
	player.set_meta("group", id)
	player.volume_db = linear_to_db(maxf(.0001, master_level * effect_level * .42 * clampf(volume_scale, .06, 1.35)))
	player.pitch_scale = clampf(pitch_scale, .72, 1.35)
	player.play()

func play_compound(primary: String, secondary: String, secondary_gain: float = .22, secondary_pitch: float = 1.0) -> void:
	# A tiny second layer makes attacks and impacts read as material gestures
	# instead of one-shot beeps. Both voices still use the bounded native pool.
	play(primary)
	if not secondary.is_empty(): play(secondary, secondary_gain, secondary_pitch)

func accept(events: Array) -> void:
	music_state.accept(events)
	for event in events:
		match event.kind:
			"shot", "ray", "slash":
				if event.at - last_shot > 0.14:
					last_shot = event.at
					var attack = attack_voice(event)
					play(str(attack.id), float(attack.gain), float(attack.pitch))
					if not str(attack.layer).is_empty(): play(str(attack.layer), float(attack.layer_gain), float(attack.layer_pitch))
			"skill": play("skill")
			"hit":
				if event.at - last_hit >= .05:
					last_hit = event.at
					var hit = hit_voice(event)
					play(str(hit.id), float(hit.gain), float(hit.pitch))
					if not str(hit.layer).is_empty(): play(str(hit.layer), float(hit.layer_gain), float(hit.layer_pitch))
			"dash": play("dash")
			"player_hurt":
				var hurt = hurt_voice(event)
				play(str(hurt.id), float(hurt.gain), float(hurt.pitch))
				if not str(hurt.layer).is_empty(): play(str(hurt.layer), float(hurt.layer_gain), float(hurt.layer_pitch))
			"death": play("death")
			"armor_break": play("armor")
			"debt_repaid": play("repay")
			"mark_added": play("mark")
			"chain_formed":
				if event.at - last_chain >= .08:
					last_chain = event.at
					var links = clampi(int(event.get("links", 1)), 1, 5)
					play("chain", 1.0 + .05 * float(links - 1), 1.0 - .025 * float(links - 1))
					if links >= 2: play("bell", .13 + .025 * float(links - 2), 1.08 + .03 * float(links - 2))
			"debt_warning", "summon_warning", "telegraph":
				if event.at - last_warning >= .3:
					last_warning = event.at
					play("warning")
			"deflect": play("deflect")
			"boss_phase", "secret_discovered": play("bell")
			"wave_incoming": play("warning")
			"room_clear", "run_end": play("clear")
			"burst", "scenery_explosion": play("burst")
			"scenery_warning": play("warning")
			"scenery_break": play("hit_heavy")
			"choice_taken": play("contract" if event.type == "contract" else "bell")
			"special_choice": play("contract" if event.type in ["sacrifice", "judgment"] else "bell")
			"pickup":
				if event.type != "ash": play("pickup")

func attack_sound(event: Dictionary) -> String:
	var mode = str(event.get("mode", ""))
	if event.kind == "ray" or mode == "ray": return "shot_ray"
	if event.kind == "slash": return "shot_heavy" if bool(event.get("charged", false)) or mode == "charged_arc" else "shot_melee"
	if mode in ["arc", "cone", "charged_arc"]: return "shot_melee" if not bool(event.get("heavy", false)) else "shot_heavy"
	if mode == "controlled": return "shot_controlled"
	if bool(event.get("heavy", false)) or mode in ["explosive", "charged_line"]: return "shot_heavy"
	return "shot"

func attack_voice(event: Dictionary) -> Dictionary:
	var mode = str(event.get("mode", ""))
	var voice = {"id": attack_sound(event), "gain": 1.0, "pitch": 1.0, "layer": "", "layer_gain": .18, "layer_pitch": 1.0}
	if mode == "fan":
		voice.pitch = .92
		voice.layer = "shot_controlled"
		voice.layer_gain = .16
		voice.layer_pitch = 1.08
	elif mode == "triple":
		voice.pitch = .98
		voice.layer = "shot"
		voice.layer_gain = .20
		voice.layer_pitch = 1.18
	elif mode == "bell":
		voice.pitch = 1.08
		voice.layer = "bell"
		voice.layer_gain = .16
		voice.layer_pitch = 1.24
	elif mode in ["returning", "ricochet", "seeker"]:
		voice.id = "shot_controlled"
		voice.pitch = .96
	elif mode in ["charged_line", "charged_arc"]:
		voice.id = "shot_heavy"
		voice.layer = "shot_ray"
		voice.layer_gain = .24
		voice.layer_pitch = .86
	return voice

func hit_sound(event: Dictionary) -> String:
	if bool(event.get("crit", false)): return "hit_crit"
	if str(event.get("source", "")) == "armor": return "hit_armor"
	if str(event.get("source", "")) == "secondary": return "hit_chain"
	if bool(event.get("heavy", false)) or str(event.get("source", "")) == "detonate": return "hit_heavy"
	if str(event.get("weapon_mode", "")) in ["arc", "cone", "charged_arc"]: return "hit_melee"
	return "hit"

func hit_voice(event: Dictionary) -> Dictionary:
	var voice = {"id": hit_sound(event), "gain": 1.0, "pitch": 1.0, "layer": "", "layer_gain": .16, "layer_pitch": 1.0}
	var mode = str(event.get("weapon_mode", ""))
	if mode == "fan":
		voice.pitch = 1.08
	elif mode == "triple":
		voice.pitch = 1.14
		voice.layer = "mark"
		voice.layer_gain = .12
		voice.layer_pitch = 1.22
	elif mode == "bell":
		voice.layer = "bell"
		voice.layer_gain = .12
		voice.layer_pitch = 1.16
	elif mode in ["explosive", "charged_line", "ray"]:
		voice.layer = "burst"
		voice.layer_gain = .16
		voice.layer_pitch = .88
	return voice

func hurt_sound(event: Dictionary) -> String:
	var source = event.get("source", {})
	if source is Dictionary and str(source.get("kind", "")) == "debt": return "hurt_debt"
	return "hurt_heavy" if int(event.get("damage", 0)) >= 2 else "hurt"

func hurt_voice(event: Dictionary) -> Dictionary:
	var voice = {"id": hurt_sound(event), "gain": 1.0, "pitch": 1.0, "layer": "", "layer_gain": .18, "layer_pitch": 1.0}
	var source = event.get("source", {})
	if source is Dictionary and str(source.get("kind", "")) == "debt":
		voice.layer = "contract"
		voice.layer_gain = .16
		voice.layer_pitch = .82
	elif int(event.get("damage", 0)) >= 2:
		voice.layer = "warning"
		voice.layer_gain = .14
		voice.layer_pitch = .74
	return voice

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		music.volume_db = -80
		fade_player.volume_db = -80
	for player in players:
		if muted:
			player.stop()

func set_paused(value: bool) -> void:
	paused = value

func set_suspended(value: bool) -> void:
	suspended = value
	music.stream_paused = value
	fade_player.stream_paused = value
	if value:
		for player in players: player.stop()

func diagnostics() -> Dictionary:
	return {"context": active_context, "tier": music_state.current_tier, "requested_tier": music_state.requested_tier,
		"beat": music_state.beat, "bar": music_state.last_bar, "layer_gains": layer_gains.duplicate(),
		"position": music.get_playback_position(), "gap": music_state.gap_active(), "paused": paused,
		"suspended": suspended, "volume_db": music.volume_db, "score_transitions": score_transitions}
