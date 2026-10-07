extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Bot = preload("res://tests/playthrough_bot.gd")
var reports: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func run_suite() -> void:
	for character in ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]:
		for evolution in 2:
			var w = World.new()
			w.start(character, 6327 + evolution * 710, 3)
			var highest_floor = 1
			# Multiwave rooms need a full campaign budget: twenty simulated minutes,
			# matching the optional campaign suite without altering combat statistics.
			for tick in 72000:
				highest_floor = maxi(highest_floor, int(w.run.floor))
				if w.mode == "result": break
				if w.mode == "choice": w.take_choice(Bot.choose(w, evolution))
				elif w.mode in ["shop", "debt"]:
					if w.mode == "shop" and w.player.hp < w.player.max_hp: w.take_choice(2)
					w.skip_choice()
				elif w.mode == "replace": w.replace_relic(w.run.relics.keys()[0])
				elif w.mode == "checkpoint":
					while not w.run.contracts.is_empty() and w.repay(0): pass
					w.advance_room()
				elif w.mode == "clear":
					for pickup in w.pickups:
						if pickup.kind == "heal": w.collect(pickup)
					w.advance_room()
				else: w.tick(Bot.frame(w))
				w.take_events()
			var report = {"character": character, "evolution": evolution, "skill": w.player.skill, "result": w.run.result,
				"highest_floor": highest_floor, "cleared": w.run.cleared, "bosses": w.run.bosses_defeated,
				"combat_seconds": snappedf(w.time, .1), "health": w.player.hp, "stats": w.stats}
			if w.run.result.is_empty(): report.stalled = {"mode": w.mode, "room": w.run.room, "template": w.geometry.template_id, "player": str(w.player.pos), "enemy_count": w.enemies.size(), "choice_reasons": w.choices.map(func(c): return w.choice_reason(c))}
			reports.append(report)
			print("Full run %s/%d: %s; floor %d, %d clears, %.1fs" % [character, evolution, w.run.result, highest_floor, w.run.cleared, w.time])
			if w.run.result not in ["victory", "defeat"]: failures.append("run did not terminate: %s/%d" % [character, evolution])
	if not reports.any(func(r): return r.result == "victory" and r.bosses.has("b03")): failures.append("no unmodified bot reached a complete three-region victory")
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/full-run-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "runs": reports,
		"method": "shared fixed-tick simulation, navigation-aware action bot, initial 18 relic pool, 72000-tick maximum; no health, energy, damage or invulnerability overrides",
		"limitations": ["Human feel, device input and real-time performance require separate checks", "Optional side bosses are tested separately"]}, "\t"))
	file.close()
	print("Three-region runs: %d; failures: %d" % [reports.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
