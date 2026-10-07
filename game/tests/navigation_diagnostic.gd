extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Bot = preload("res://tests/playthrough_bot.gd")

func _initialize() -> void:
	call_deferred("run_diagnostic")

func run_diagnostic() -> void:
	var w = World.new()
	w.start("c_bell", 6327, 3)
	w.geometry.build("room_side_doors_3", 2)
	w.enemies.clear()
	w.spawn_enemy("e15", Vector2(1056, 232))
	w.player.pos = Vector2(1107.233, 389.845)
	for tick in 1800:
		if w.mode == "clear": break
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
			w.advance_room()
		else:
			var frame = Bot.frame(w)
			w.tick(frame)
		w.take_events()
	var passed = w.mode == "clear" and w.stats.kills == 1 and w.stats.damage_taken < w.player.max_hp
	var report = {"passed": passed, "mode": w.mode, "kills": w.stats.kills, "seconds": snappedf(w.time, .1), "regression": "one stationary coin enemy behind a side-door obstacle; no fighting stat overrides"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/bot-navigation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(report)
	quit(0 if passed else 1)
