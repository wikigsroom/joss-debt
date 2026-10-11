extends RefCounted
## Local-only, opt-in-by-presence run observations for balance review.
## The file never leaves the device and is deliberately separate from the save journal.

const MAX_STATS := ["shots", "hits", "secondary_hits", "kills", "damage_taken", "detonations", "max_chain", "ash_energy", "dodges", "parries", "summoned"]
var path: String
var recorded: Dictionary = {}

func _init(target_path: String = "user://run_telemetry.jsonl") -> void:
	path = target_path
	_load_recorded()

func _load_recorded() -> void:
	if not FileAccess.file_exists(path): return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty(): continue
		var row = JSON.parse_string(line)
		if row is Dictionary and not str(row.get("record_key", "")).is_empty(): recorded[str(row.record_key)] = true
	file.close()

func _routes(world) -> Array:
	var routes: Array = []
	for talent_id in world.run.get("talents", []):
		var talent = world.db.row("talents", str(talent_id))
		var route = str(talent.get("route", ""))
		if not route.is_empty() and not routes.has(route): routes.append(route)
	routes.sort()
	return routes

func _stats(world) -> Dictionary:
	var result: Dictionary = {}
	for key in MAX_STATS:
		result[key] = world.stats.get(key, 0)
	return result

func record(world, event: Dictionary = {}) -> bool:
	if world == null or world.run.is_empty(): return false
	if bool(world.run.get("training", false)) or bool(world.run.get("daily", false)): return false
	var result = str(world.run.get("result", ""))
	if result.is_empty(): return false
	var run_id = str(world.run.get("id", ""))
	if run_id.is_empty(): return false
	var record_key = "%s/%s" % [run_id, result]
	if recorded.has(record_key): return false
	var row = {
		"schema": 1,
		"record_key": record_key,
		"recorded_at": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string,
		"content_version": str(world.db.catalog.get("version", "")),
		"run_id": run_id,
		"seed": int(world.run.get("seed", 0)),
		"result": result,
		"win": bool(event.get("win", result == "victory")),
		"character": str(world.run.get("character", "")),
		"routes": _routes(world),
		"weapon": str(world.player.get("weapon", "")),
		"skill": str(world.player.get("skill", "")),
		"floor": int(world.run.get("floor", 1)),
		"cleared": int(world.run.get("cleared", 0)),
		"duration_s": snappedf(float(world.time), .1),
		"rooms_visited": world.run.get("visited", []).size(),
		"bosses": world.run.get("bosses_defeated", []).duplicate(),
		"contracts": world.run.get("contracts", []).map(func(entry): return str(entry.get("id", ""))),
		"relics": world.run.get("relics", {}).keys(),
		"talents": world.run.get("talents", []).duplicate(),
		"growth_choices": world.run.get("growth_log", []).size(),
		"special_rooms": world.run.get("special_rooms", {}).size(),
		"coins": int(world.run.get("coins", 0)),
		"metrics": _stats(world),
		"damage_events": world.run.get("damage_history", []).size()
	}
	var file = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null and not FileAccess.file_exists(path): file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.seek_end()
	file.store_line(JSON.stringify(row))
	file.flush()
	file.close()
	recorded[record_key] = true
	return true
