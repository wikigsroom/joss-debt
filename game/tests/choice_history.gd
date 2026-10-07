extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Shortcuts = preload("res://scripts/core/choice_shortcuts.gd")

var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func logical_key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func run_suite() -> void:
	var w = World.new()
	w.start("c_paper", 6621, 3)
	expect(w.run.growth_log.size() == 2 and w.run.growth_log[0].type == "weapon" and w.run.growth_log[1].type == "skill" and w.run.growth_log.all(func(entry): return entry.source == "initial"), "a fresh run records its starting weapon and base skill in chronological growth history")
	w.mode = "choice"
	w.choices = [{"kind": "relic", "id": "r01", "price": 0, "slot": "history_relic"}]
	expect(w.take_choice(0) and w.run.growth_log[-1].type == "relic" and w.run.growth_log[-1].id == "r01" and w.run.growth_log[-1].source == "choice", "a normal offering appends its real bonus to the same history ledger")
	w.mode = "choice"
	w.choices = [{"kind": "weapon", "id": "w13", "price": 0, "slot": "history_weapon"}]
	expect(w.take_choice(0) and w.run.growth_log[-1].type == "weapon" and w.run.growth_log[-1].id == "w13" and w.player.weapon == "w13", "a weapon replacement records both the selected item and the live equipped state")
	w.mode = "choice"
	w.choices = [{"kind": "skill", "id": "s02", "price": 0, "slot": "history_skill"}]
	expect(w.take_choice(0) and w.run.growth_log[-1].type == "skill" and w.run.growth_log[-1].id == "s02" and w.player.skill == "s02", "a skill evolution records the chosen skill instead of only exposing the current skill")
	var saved = w.snapshot()
	var resumed = World.new()
	expect(resumed.restore(saved) and resumed.run.growth_log == w.run.growth_log, "the complete choice history survives an actual checksum snapshot and restore")
	var bad = saved.duplicate(true)
	bad.run.growth_log = [{"type": "future", "id": "unknown", "room": "x", "at": 0.0}]
	var migrated = Migration.world(bad)
	expect(migrated.ok, "legacy-compatible history records remain readable while new UI fields are additive")
	expect(Shortcuts.index_for(key(KEY_1)) == 0 and Shortcuts.index_for(key(KEY_4)) == 3 and Shortcuts.index_for(key(KEY_KP_2)) == 1 and Shortcuts.index_for(key(KEY_KP_4)) == 3 and Shortcuts.index_for(logical_key(KEY_3)) == 2 and Shortcuts.index_for(key(KEY_2, false)) == -1 and Shortcuts.index_for(key(KEY_3, true, true)) == -1, "number-row and keypad shortcuts map one-to-four and ignore releases or key repeat")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "PC number-row choice selection, chronological growth history, current loadout and checksum restore"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/choice-history-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Choice history: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
