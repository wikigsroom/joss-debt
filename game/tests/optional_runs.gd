extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Bot = preload("res://tests/playthrough_bot.gd")
var reports: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func run_suite() -> void:
	for character in ["c_paper", "c_mask"]:
		var w = World.new()
		w.start(character, 6327, 3, {"optional_bosses": ["b04", "b05"]})
		for tick in 72000:
			if w.mode == "result": break
			if w.mode == "choice": w.take_choice(Bot.choose(w, 0))
			elif w.mode in ["shop", "debt"]:
				if w.mode == "shop" and w.player.hp < w.player.max_hp: w.take_choice(2)
				w.skip_choice()
			elif w.mode == "replace": w.replace_relic(w.run.relics.keys()[0])
			elif w.mode == "checkpoint": w.advance_room()
			elif w.mode == "clear":
				for pickup in w.pickups:
					if pickup.kind == "heal": w.collect(pickup)
				var side = int(w.run.graph.optional_boss_room)
				w.advance_room(side if w.next_rooms().has(side) else -1)
			else: w.tick(Bot.frame(w))
			w.take_events()
		var report = {"character": character, "result": w.run.result, "bosses": w.run.bosses_defeated, "floor": w.run.floor, "health": w.player.hp, "combat_seconds": snappedf(w.time, .1), "clears": w.run.cleared}
		if w.run.result.is_empty(): report.stalled = {"mode": w.mode, "room": w.run.room, "enemy_count": w.enemies.size(), "choice_reasons": w.choices.map(func(c): return w.choice_reason(c))}
		reports.append(report)
		print("Optional run %s: %s; bosses %s" % [character, w.run.result, str(w.run.bosses_defeated)])
		if w.run.result not in ["victory", "defeat"]: failures.append("Run failed to terminate: " + character)
	if not reports.any(func(r): return r.result == "victory" and r.bosses.has("b04") and r.bosses.has("b05")): failures.append("No legitimate five-boss campaign victory")
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/optional-runs-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"runs": reports, "failures": failures, "passed": failures.is_empty(), "method": "navigation-aware action bot; optional branches pre-unlocked, initial relic pool; no fighting stat, HP, energy or invulnerability overrides"}, "\t"))
	file.close()
	quit(0 if failures.is_empty() else 1)
