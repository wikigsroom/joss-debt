extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const Bot = preload("res://tests/playthrough_bot.gd")
const ContentDB = preload("res://scripts/core/content_db.gd")

var reports: Array = []
var failures: Array = []


func _initialize() -> void:
	call_deferred("run_suite")


func run_suite() -> void:
	var db = ContentDB.new()
	for character in db.rows("characters"):
		for route in character.routes:
			for evolution in 2:
				var w = World.new()
				w.start(character.id, 9100 + reports.size() * 37 + evolution, 3)
				var highest_floor = 1
				for tick in 72000:
					highest_floor = maxi(highest_floor, int(w.run.floor))
					if w.mode == "result": break
					if w.mode == "choice": w.take_choice(Bot.choose(w, evolution, route))
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
				var report = {"character": character.id, "character_name": character.name,
					"focus_route": route, "evolution": evolution, "skill": w.player.skill,
					"result": w.run.result, "highest_floor": highest_floor, "cleared": w.run.cleared,
					"bosses": w.run.bosses_defeated, "combat_seconds": snappedf(w.time, .1),
					"health": w.player.hp, "talents": w.run.talents, "relics": w.run.relics.keys(),
					"stats": w.stats}
				reports.append(report)
				print("Route run %s/%s/%d: %s; floor %d, %d clears, %.1fs" %
					[character.id, route, evolution, w.run.result, highest_floor, w.run.cleared, w.time])
				if w.run.result != "victory":
					failures.append("route did not complete: %s/%s/%d (%s)" %
						[character.id, route, evolution, w.run.result])
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/route-matrix-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "runs": reports,
		"method": "shared fixed-tick simulation, character-route-focused reward selection, normal stats and 72000-tick maximum",
		"limitations": ["Automated route coverage is not human feel or final balance acceptance", "Optional side bosses are excluded"]}, "\t"))
	file.close()
	print("Route matrix runs: %d; failures: %d" % [reports.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
