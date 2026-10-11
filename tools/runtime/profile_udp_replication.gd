extends SceneTree
const Match = preload("res://scripts/network/cooperative_match.gd")
const Stream = preload("res://scripts/network/state_stream.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var output = ""

func percentile(values: Array) -> float:
	var sorted = values.duplicate(); sorted.sort()
	return float(sorted[mini(sorted.size() - 1, ceili(sorted.size() * .95) - 1)])

func profile(encounter, name: String) -> Dictionary:
	var sender = Stream.new("1122334455667788")
	var receiver = Stream.new(sender.link)
	var encode_times: Array = []; var decode_times: Array = []; var view_times: Array = []
	var sizes: Array = []; var baseline_size = 0; var maximum = 0; var packet_count = 0
	var legacy_bytes = 0
	for index in 70:
		var start = Time.get_ticks_usec()
		var state = encounter.view(0, 0, true)
		state.state_seq = index + 1; state.lease = 1000 + index; state.input_scene = 1
		var viewed = Time.get_ticks_usec()
		var packets = sender.encode(state)
		var encoded = Time.get_ticks_usec()
		var size = 0
		for item in packets:
			size += item.bytes.size(); maximum = maxi(maximum, item.bytes.size())
			if item.reliable: baseline_size += item.bytes.size()
			receiver.decode(item.bytes)
		var decoded = Time.get_ticks_usec()
		if index < 10: continue
		view_times.append((viewed - start) / 1000.0)
		encode_times.append((encoded - viewed) / 1000.0)
		decode_times.append((decoded - encoded) / 1000.0)
		sizes.append(size); packet_count = packets.size()
		legacy_bytes = Protocol.packet(state, true).size()
	return {"fixture": name, "samples": 60, "enemies": encounter.world.enemies.size(), "bullets": encounter.world.bullets.size(),
		"passed": receiver.scene_ready and receiver.view.scene.enemies == encounter.view(0).scene.enemies and maximum <= Stream.MAX_PACKET,
		"dynamic_bytes_per_update_p95": percentile(sizes), "per_client_payload_kib_s_at_20hz": percentile(sizes) * 20.0 / 1024,
		"one_time_baseline_bytes": baseline_size, "max_message_bytes": maximum, "messages_per_update": packet_count,
		"view_p95_ms": percentile(view_times), "encode_p95_ms": percentile(encode_times), "decode_p95_ms": percentile(decode_times),
		"same_state_legacy_format_bytes": legacy_bytes, "same_state_legacy_format_kib_s_at_20hz": legacy_bytes * 20.0 / 1024}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty(): quit(1); return
	var encounter = Match.new()
	encounter.begin("isolated-replication-profile", [{"character": "c_paper", "weapon": "w03", "skill": "s01"}, {"character": "c_ink", "weapon": "w06", "skill": "s16"}], 1741)
	for index in 181: encounter.advance([Protocol.empty_input(), Protocol.empty_input()])
	var results = [profile(encounter, "opening-room")]
	encounter.world.bullets.clear()
	for index in 240:
		encounter.world.bullets.append({"uid": index, "pos": Vector2(200 + index * 3, 200 + index % 19 * 20), "dir": Vector2.UP.rotated(index * .123), "speed": 200 + index % 180, "radius": 8.0, "age": .1 + index * .007, "mode": "controlled", "owner": index % 2, "friendly": true, "primary": true, "recipe": {"hits": range(200)}, "hits": range(200)})
	results.append(profile(encounter, "synthetic-240-diverse-projectiles"))
	for context in encounter.world.contexts:
		var entry = context.run.growth_log[0].duplicate(true)
		for index in 256:
			var history = entry.duplicate(true); history.floor = index % 11 + 1; history.room = index
			context.run.growth_log.append(history)
	results.append(profile(encounter, "synthetic-240-projectiles-256-build-entries-per-player"))
	var passed = results.all(func(result): return result.passed)
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify({"passed": passed, "native_engine": Engine.get_version_info().string,
		"scope": "60 warmed static native Windows samples per fixture. Payload bytes exclude DTLS/IP/ENet overhead; legacy is same-state representation, not a claim of running the old production binary. Dense cases are synthetic; no WAN, rendering or Android acceptance.", "fixtures": results}, "\t") + "\n")
	for row in results: print(JSON.stringify(row))
	quit(0 if passed else 1)
