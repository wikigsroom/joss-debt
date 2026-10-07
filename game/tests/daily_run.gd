extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const DailySeed = preload("res://scripts/core/daily_seed.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Store = preload("res://scripts/core/save_store.gd")

var checks: Array = []
var failures: Array = []

class MemoryJournal extends RefCounted:
	var data: Dictionary = {}
	func read() -> Dictionary: return data.duplicate(true)
	func write(value: Dictionary) -> bool:
		data = value.duplicate(true)
		return true

func _initialize() -> void: call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func digest(value) -> String:
	return JSON.stringify(Store.encode(value), "", true, true)

func run_suite() -> void:
	var date = {"year": 2026, "month": 10, "day": 6}
	var key = DailySeed.key(date)
	var seed = DailySeed.seed_for(date)
	expect(key == "2026-10-06" and DailySeed.title(date).contains(key), "daily identity uses a readable local calendar key")
	expect(seed == DailySeed.seed_for(date) and seed > 0 and seed < 2147483647, "the same date and rules version always produce the same bounded seed")
	expect(seed != DailySeed.seed_for({"year": 2026, "month": 10, "day": 7}), "adjacent dates receive different challenge seeds")

	var options = {"daily": true, "daily_key": key, "daily_pool_version": DailySeed.pool_version(), "relic_pool": ["r01", "r02", "r03", "r09", "r10", "r11"]}
	var first = World.new()
	first.start("c_paper", seed, 3, options)
	var second = World.new()
	second.start("c_paper", seed, 3, options)
	expect(first.run.daily and first.run.daily_key == key and first.run.daily_pool_version == DailySeed.pool_version(), "daily runs carry their challenge identity into the authoritative snapshot")
	expect(first.run.relic_pool == second.run.relic_pool and first.run.relic_pool == options.relic_pool, "daily runs use the explicitly frozen relic pool")
	expect(first.run.graph.types == second.run.graph.types and first.snapshot().streams == second.snapshot().streams, "daily runs reproduce graph topology and independent random streams")
	expect(first.run.optional_bosses.is_empty() and first.run.coin_pickup_bonus == 0, "daily runs remove account-dependent optional bosses and coin bonuses")

	var account = Progress.new("", MemoryJournal.new())
	var before = digest(account.data)
	first.run.merit = 99
	first.run.bosses_defeated = ["b01"]
	expect(account.observe(first).is_empty() and digest(account.data) == before, "daily results never credit meta merit, unlocks or route history")

	var snapshot = first.snapshot()
	var restored = World.new()
	expect(Migration.world(snapshot).ok and restored.restore(snapshot), "daily snapshots pass the normal save migration and restore path")
	expect(restored.run.daily and restored.run.daily_key == key and restored.run.daily_pool_version == DailySeed.pool_version(), "daily identity survives a disk-shaped restore")
	var invalid = snapshot.duplicate(true)
	invalid.run.daily = true
	invalid.run.daily_pool_version = ""
	expect(not Migration.world(invalid).ok, "a daily snapshot without a pool version is rejected instead of silently changing rules")

	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "date-keyed deterministic daily run, fixed relic pool, account isolation and schema restore; no network clock or leaderboard claim"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/daily-run-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Daily run: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
