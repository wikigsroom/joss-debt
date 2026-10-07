extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Telemetry = preload("res://scripts/core/run_telemetry.gd")

var checks: Array = []
var failures: Array = []
const PATH := "user://run-telemetry-test.jsonl"

func expect(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition: failures.append(name)

func _initialize() -> void:
	call_deferred("run_suite")

func _read_rows() -> Array:
	if not FileAccess.file_exists(PATH): return []
	var file = FileAccess.open(PATH, FileAccess.READ)
	if file == null: return []
	var rows: Array = []
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if not line.is_empty(): rows.append(JSON.parse_string(line))
	file.close()
	return rows

func _fixture(result: String = "defeat", flags: Dictionary = {}) -> World:
	var world = World.new()
	world.start("c_paper", 6123, 3)
	world.run.result = result
	world.run.floor = 2
	world.run.cleared = 7
	world.run.visited = [0, 1, 2, 3]
	world.run.talents = ["t_ash_1a", "t_fire_1a"]
	world.run.relics = {"r01": 1, "r09": 2}
	world.run.contracts = [{"id": "d01"}]
	world.run.bosses_defeated = ["b01"]
	world.run.growth_log = [{"type": "weapon"}, {"type": "relic"}]
	world.run.special_rooms = {"1/2": {"kind": "sacrifice"}}
	world.stats.shots = 18
	world.stats.hits = 14
	world.stats.secondary_hits = 3
	world.stats.kills = 9
	world.stats.damage_taken = 2
	world.stats.detonations = 4
	world.stats.max_chain = 3
	world.stats.ash_energy = 88
	world.stats.dodges = 2
	world.stats.parries = 1
	world.time = 42.37
	for key in flags: world.run[key] = flags[key]
	return world

func run_suite() -> void:
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var logger = Telemetry.new(PATH)
	var world = _fixture()
	expect(logger.record(world, {"win": false}), "a normal terminal run writes one local observation")
	var rows = _read_rows()
	expect(rows.size() == 1, "the observation is a single JSONL record")
	var row: Dictionary = rows[0] if rows.size() == 1 else {}
	expect(row.get("character", "") == "c_paper" and row.get("routes", []).has("ash") and row.get("routes", []).has("fire"), "character and selected routes are retained")
	expect(row.get("weapon", "") == world.player.weapon and row.get("skill", "") == world.player.skill and row.get("relics", []).size() == 2, "live loadout is retained without copying account data")
	expect(int(row.get("metrics", {}).get("hits", 0)) == 14 and int(row.get("metrics", {}).get("max_chain", 0)) == 3 and int(row.get("damage_events", 0)) == 0, "combat metrics are retained with explicit zero damage history")
	expect(not logger.record(world, {"win": false}) and _read_rows().size() == 1, "repeating the same run result is idempotent")
	var reloaded = Telemetry.new(PATH)
	expect(not reloaded.record(world, {"win": false}) and _read_rows().size() == 1, "idempotence survives a logger reload")
	var training = _fixture("victory", {"training": true})
	var daily = _fixture("victory", {"daily": true})
	expect(not reloaded.record(training, {"win": true}) and not reloaded.record(daily, {"win": true}) and _read_rows().size() == 1, "training and daily runs never enter balance observations")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "local-only terminal run observations, reload-safe idempotence and training/daily exclusion"}
	var report_path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/run-telemetry-tests.json")
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Run telemetry: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
