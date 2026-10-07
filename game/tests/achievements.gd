extends SceneTree

const Meta = preload("res://scripts/core/meta_progress.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Slots = preload("res://scripts/core/save_slots.gd")
const World = preload("res://scripts/combat/world.gd")

var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func run_suite() -> void:
	var migrated = Migration.profile({})
	expect(migrated.ok and migrated.data.achievements.is_empty() and migrated.data.achievement_stats.runs == 0, "new and legacy profiles receive additive achievement fields")
	var profile_path = "user://achievement_test_profile_%d" % Time.get_ticks_usec()
	var meta = Meta.new(profile_path)
	var world = World.new()
	world.start("c_paper", 8801, 3)
	world.run.id = "achievement_fixture"
	world.run.talents = ["t_fire_1a", "t_thread_1a"]
	world.run.result = "victory"
	world.run.bosses_defeated = ["b01"]
	world.run.ending = "burn"
	world.stats.detonations = 6
	world.stats.hits = 40
	world.stats.kills = 12
	world.stats.max_chain = 4
	world.stats.ash_energy = 200
	world.stats.dodges = 8
	var messages = meta.observe(world)
	expect(meta.achievement_unlocked("ach_c_paper_burn") and meta.achievement_unlocked("ach_c_paper_victory"), "character achievements unlock from real run stats and victory")
	expect(meta.achievement_unlocked("ach_c_paper_routes") and meta.achievement_unlocked("ach_global_first_victory"), "route and global achievements share the same observed run ledger")
	expect(meta.achievement_unlocked("ach_global_endings") == false and messages.any(func(text): return str(text).contains("成就解锁")), "achievement unlock messaging is emitted while partial global goals remain locked")
	var before_runs = int(meta.data.achievement_stats.runs)
	var before_unlocked = meta.data.achievements.size()
	meta.observe(world)
	expect(int(meta.data.achievement_stats.runs) == before_runs and meta.data.achievements.size() == before_unlocked, "repeated checkpoint observation is idempotent for run and achievement counts")
	var reloaded = Meta.new(profile_path)
	expect(reloaded.achievement_unlocked("ach_c_paper_burn") and reloaded.data.achievement_stats.victories == 1, "achievement unlocks and aggregate counters survive a profile journal reload")
	var summary = reloaded.achievement_summary("c_paper")
	expect(summary.total == 4 and summary.unlocked >= 3, "character achievement summary is scoped to the selected character")
	var slots = Slots.new("user://achievement_slot_fixture")
	expect(slots.summaries().size() == 3 and slots.summaries().all(func(slot): return not slot.occupied), "three save slots expose stable empty summaries without touching the main slot")
	expect(slots.select(2) and slots.selected_slot() == 2 and Slots.new("user://achievement_slot_fixture").selected_slot() == 2, "selected save slot is persisted in its own checksum journal")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "per-character achievements, global achievement aggregation, idempotent checkpoint observation and three-slot selection"}
	var path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/achievement-tests.json")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Achievements: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
