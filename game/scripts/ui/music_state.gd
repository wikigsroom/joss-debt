extends RefCounted
## Musical transport and layer decisions. No combat mutation or gameplay RNG.

var bpm = 88.0
var duration = 1.0
var position = 0.0
var previous_position = 0.0
var cycle_offset = 0.0
var beat = 0.0
var last_bar = 0
var requested_tier = 0
var current_tier = 0
var burst_until = 0.0
var gap_start = -10.0
var room = ""
var transitions: Array = []

func configure(meta: Dictionary) -> void:
	bpm = float(meta.bpm)
	duration = float(meta.duration)
	position = 0.0
	previous_position = 0.0
	cycle_offset = 0.0
	beat = 0.0
	last_bar = 0
	requested_tier = 0
	current_tier = 0
	burst_until = 0.0
	gap_start = -10.0
	room = ""
	transitions.clear()

static func context_for(world, screen: String) -> String:
	if screen in ["menu", "hub", "story"] or world.run.is_empty(): return "hub"
	if world.mode in ["result", "epilogue"]:
		var ending = str(world.run.get("ending", ""))
		return "ending" + ("_" + ending if not ending.is_empty() else "")
	if world.enemies.any(func(enemy): return enemy.boss and not enemy.dead): return "boss"
	if world.run.get("campaign", false): return "region_%d" % (1 + posmod(str(world.region_spec().id).trim_prefix("m").to_int() - 1, 3))
	return "region_%d" % maxi(1, int(world.run.get("floor", 1)))

func observe(world) -> void:
	if world.run.is_empty():
		requested_tier = 0
		return
	var room_key = "%s/%d/%d" % [world.run.id, world.run.floor, world.run.room]
	if room_key != room:
		room = room_key
		burst_until = 0.0
		gap_start = -10.0
	if world.mode != "combat":
		# Special rooms keep the map's own theme but add its quieter identity stem:
		# vermilion sacrifice, gold judgment and jade blessing all breathe at tier 1.
		var room_spec = world.db.row("special_rooms", world.room_type())
		requested_tier = 1 if world.room_type() == "shop" or room_spec.get("music_layer", "") == "region_tension" else 0
		return
	requested_tier = 1
	var boss_phase = 0
	for enemy in world.enemies:
		if enemy.boss and not enemy.dead: boss_phase = maxi(boss_phase, int(enemy.phase))
	var linked = world.chains.any(func(chain): return chain.size() >= 3)
	var low_health = float(world.player.hp) / maxf(1, world.player.max_hp) <= .34
	if boss_phase >= 1 or world.room_type() == "elite" or low_health or linked or beat < burst_until:
		requested_tier = 2

func accept(events: Array) -> void:
	for event in events:
		if event.kind == "skill" and int(event.get("targets", 0)) >= 3: burst_until = beat + 8.0
		elif event.kind == "chain_formed":
			# A newly linked group should lift the arrangement before the player
			# spends the marks. Larger chains earn a slightly longer response.
			var chain_size = clampi(int(event.get("size", 2)), 2, 6)
			burst_until = maxf(burst_until, beat + 1.5 + float(chain_size - 2) * .75)
		elif event.kind == "burst":
			# Detonation and other real burst events leave a short musical tail;
			# a skill with many targets already owns the longer eight-beat lift.
			burst_until = maxf(burst_until, beat + .75)
		elif event.kind in ["boss_phase", "wave_incoming"]:
			# A single silent rhythm beat leaves room for the actual danger cue.
			gap_start = ceilf(beat + .001)
		elif event.kind in ["room_clear", "room_enter", "room_return", "run_end"]:
			burst_until = 0.0
			gap_start = -10.0

func advance(playback_position: float) -> void:
	var next = maxf(0, playback_position)
	if next < previous_position - .1: cycle_offset += duration
	previous_position = next
	position = cycle_offset + next
	beat = position * bpm / 60.0
	var bar = int(floor(beat / 4.0))
	if bar != last_bar:
		last_bar = bar
		if current_tier != requested_tier:
			current_tier = requested_tier
			transitions.append({"bar": bar, "tier": current_tier, "seconds": position})
			if transitions.size() > 32: transitions.pop_front()

func gap_active() -> bool:
	return beat >= gap_start and beat < gap_start + 1.0

func gains() -> Array:
	# Combat themes have five synchronized voices: base, rhythm, tension,
	# accent and the quiet CC0 room-air bed. The accent is a separately
	# authored melodic answer, so danger can feel richer without simply
	# making the whole theme louder. Contexts such as the hub and endings
	# still expose a one-stem array and the director truncates safely.
	if gap_active(): return [.35, 0.0, 0.0, 0.0, .10]
	return [1.0, .58 if current_tier >= 1 else 0.0, .45 if current_tier >= 2 else 0.0, .30 if current_tier >= 1 else 0.0, .22]
