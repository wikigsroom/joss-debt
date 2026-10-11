extends SceneTree
## Read-only source profile with isolated synthetic worlds, never live sessions.
const Match = preload("res://scripts/network/cooperative_match.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
var output = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.substr(9)
	call_deferred("run")

func percentile(values: Array, fraction: float) -> float:
	var sorted = values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * fraction)) - 1)])

func profile(encounter, name: String) -> Dictionary:
	var views: Array = []
	var encodes: Array = []
	var decodes: Array = []
	var total: Array = []
	var wire = PackedByteArray()
	var view: Dictionary = {}
	var decoded: Dictionary = {}
	for index in 70:
		var start = Time.get_ticks_usec()
		view = encounter.view(0)
		var viewed = Time.get_ticks_usec()
		wire = Protocol.packet(view, true)
		var encoded = Time.get_ticks_usec()
		decoded = Protocol.unpack(wire)
		var done = Time.get_ticks_usec()
		if index < 10: continue
		views.append((viewed - start) / 1000.0)
		encodes.append((encoded - viewed) / 1000.0)
		decodes.append((done - encoded) / 1000.0)
		total.append((done - start) / 1000.0)
	var fields: Dictionary = {}
	for key in ["actors", "scene", "builds", "arena", "players", "events"]:
		fields[key] = var_to_bytes(view.get(key)).size()
	return {"fixture": name, "samples": 60, "decode_valid": not decoded.is_empty(), "enemies": encounter.world.enemies.size(), "bullets": encounter.world.bullets.size(),
		"compressed_bytes": wire.size(), "expanded_bytes": var_to_bytes(view).size(), "per_client_kib_s_at_20hz": wire.size() * 20.0 / 1024.0,
		"view_p95_ms": percentile(views, .95), "encode_p95_ms": percentile(encodes, .95), "decode_p95_ms": percentile(decodes, .95), "roundtrip_cpu_p95_ms": percentile(total, .95), "expanded_field_bytes": fields}

func run() -> void:
	if output.is_empty(): push_error("Specify --output"); quit(1); return
	var encounter = Match.new()
	encounter.begin("isolated-payload-profile", [{"character": "c_paper", "weapon": "w03", "skill": "s01"}, {"character": "c_ink", "weapon": "w06", "skill": "s16"}], 1741)
	for index in 181: encounter.advance([Protocol.empty_input(), Protocol.empty_input()])
	var results = [profile(encounter, "opening-room")]
	encounter.world.bullets.clear()
	for index in 240:
		encounter.world.bullets.append({"uid": index, "pos": Vector2(200 + index * 3, 200 + index % 19 * 20), "dir": Vector2.UP.rotated(index * .123), "speed": 200 + index % 180, "radius": 8.0, "age": .1 + index * .007, "mode": "controlled", "owner": index % 2, "friendly": true, "primary": true, "recipe": {"hits": range(200)}, "hits": range(200)})
	results.append(profile(encounter, "synthetic-240-diverse-projectiles"))
	for context in encounter.world.contexts:
		var entry: Dictionary = context.run.growth_log[0].duplicate(true) if not context.run.growth_log.is_empty() else {"kind": "skill", "id": "s01", "floor": 1}
		context.run.growth_log.clear()
		for index in 256:
			var history = entry.duplicate(true)
			history.floor = index % 11 + 1
			history.room = index
			context.run.growth_log.append(history)
	results.append(profile(encounter, "synthetic-240-projectiles-256-build-entries-per-player"))
	var report = {"passed": results.all(func(result): return result.decode_valid), "native_engine": Engine.get_version_info().string,
		"scope": "Current v0.5.0 view/Variant-DEFLATE/unpack on native Windows CPU. 60 warmed samples per static fixture; dense cases are synthetic, not a WAN or Android test. Does not attribute observed production main-loop stalls to a specific function.", "production_modified": false, "virtualization": "none", "fixtures": results}
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Cannot write isolated profile"); quit(1); return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print(JSON.stringify(report))
	quit(0 if report.passed else 1)
