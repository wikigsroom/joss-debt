extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Bot = preload("res://tests/playthrough_bot.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Migrations = preload("res://scripts/core/save_migrations.gd")
var reports: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("suite")

func travel(w) -> Dictionary:
	var equipment = w.pickups.filter(func(drop):
		if drop.kind == "battery": return w.run.active_item.charge < w.Equipment.active_row(w).charge_rooms
		if drop.kind == "trinket": return not w.run.equipment_seen.trinkets.has(drop.id)
		if drop.kind == "active": return not w.run.equipment_seen.active_items.has(drop.id)
		if drop.kind == "relic": return w.stack(drop.id) == 0 and not w.run.growth_log.any(func(entry): return entry.type == "relic" and entry.id == drop.id)
		return false)
	if not equipment.is_empty():
		var drop = equipment[0]
		w.geometry.rebuild_flow(drop.pos)
		return {"move": w.geometry.toward(w.player.pos, drop.pos) if w.player.pos.distance_to(drop.pos) > 48 else Vector2.ZERO, "interact": w.player.pos.distance_to(drop.pos) <= 64}
	if w.player.hp < w.player.max_hp:
		for pickup in w.pickups:
			if pickup.kind == "heal":
				w.geometry.rebuild_flow(pickup.pos)
				return {"move": w.geometry.toward(w.player.pos, pickup.pos)}
	var doors = w.room_doors()
	var main_end = w.run.room_plan.find("boss")
	var destination = -1
	if int(w.run.room) < main_end:
		destination = int(w.run.room) + 1
	else:
		for door in doors:
			if door.visited: destination = door.destination
	for door in doors:
		if door.destination == destination:
			if w.player.pos.distance_to(door.pos) < 14: return {"move": w.direction_vector(door.direction)}
			w.geometry.rebuild_flow(door.pos)
			return {"move": w.geometry.toward(w.player.pos, door.pos)}
	return {}

func suite() -> void:
	var characters = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]
	var report_suffix = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="): characters = [argument.trim_prefix("--character=")]
		if argument.begins_with("--report-suffix="): report_suffix="-"+argument.trim_prefix("--report-suffix=")
	for character in characters:
		var w = World.new()
		w.start(character, 6327, 11, {"seed_text": Seed.text(6327)})
		var highest_floor = 1
		var transitions: Array = []
		var doors_crossed = 0
		var doubles_cleared: Array = []
		var save_checks: Array = []
		var seen_rooms: Dictionary = {}
		var held_input: Dictionary = {}
		var input_mode = ""
		var activity_key = ""
		var last_activity_tick = 0
		for tick_id in 480000:
			var activity = "%d/%d/%s/%d/%d/%d/%d" % [w.run.floor,w.run.room,w.mode,w.stats.hits,w.player.hp,w.enemies.size(),w.pickups.size()]
			if activity != activity_key:
				activity_key = activity
				last_activity_tick = tick_id
			elif tick_id-last_activity_tick > 3600:
				print("No gameplay progress for 60 seconds; saving an actual-state diagnostic for ",character)
				break
			if tick_id>0 and tick_id%30000==0: print("Campaign progress %s: floor %d room %d mode %s at %.1fs; hp %d; enemies %d" % [character,w.run.floor,w.run.room,w.mode,w.time,w.player.hp,w.enemies.size()])
			highest_floor = maxi(highest_floor, int(w.run.floor))
			if w.mode == "result": break
			var before_room = int(w.run.room)
			var before_floor = int(w.run.floor)
			if w.mode == "choice":
				if not w.take_choice(Bot.choose(w, 0)):
					var available = -1
					for i in w.choices.size():
						if w.choice_reason(w.choices[i]).is_empty(): available=i; break
					if available >= 0: w.take_choice(available)
					else: w.skip_choice()
			elif w.mode in ["shop", "debt"]:
				if w.mode == "shop" and w.player.hp < w.player.max_hp: w.take_choice(2)
				w.skip_choice()
			elif w.mode == "replace": w.replace_relic(w.run.relics.keys()[0])
			elif w.mode == "checkpoint":
				while not w.run.contracts.is_empty() and w.repay(0): pass
				w.advance_room()
			elif w.mode == "transition":
				var resumed = World.new()
				var decoded = Store.decode(JSON.parse_string(JSON.stringify(Store.encode(w.snapshot()))))
				var validation = Migrations.world(decoded)
				var restored = resumed.restore(decoded)
				save_checks.append({"to_floor": int(w.run.transition.to_floor), "restored": restored, "validation": validation.get("message", "ok")})
				if not restored:
					failures.append("transition restore %s floor %d: %s" % [character, w.run.floor, validation.get("message", "runtime")])
					FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expanded-restore-failed-%s-%d.json" % [character, w.run.floor]), FileAccess.WRITE).store_string(JSON.stringify(Store.encode(w.snapshot()), "\t"))
					print("Restore failed: ", validation.get("message", "runtime"))
				else: w = resumed
				w.continue_transition(); transitions.append(int(w.run.floor))
				print("Campaign %s entered floor %d at %.1fs; hp %d" % [character, w.run.floor, w.time, w.player.hp])
			elif w.mode == "epilogue":
				w.finish_epilogue()
			else:
				# Refresh held input while following adaptive fine navigation.
				# Hold actions for 33 ms; game physics and normal player stats stay intact.
				if w.mode=="clear" or tick_id % 2 == 0 or input_mode != w.mode:
					held_input = travel(w) if w.mode == "clear" else Bot.frame(w)
					input_mode = w.mode
				if w.mode == "combat" and w.Equipment.use_reason(w).is_empty() and (w.enemies.size() >= 3 or w.enemies.any(func(e): return e.boss)):
					held_input.active_item = true
				else: held_input.active_item = false
				w.tick(held_input)
			if int(w.run.room) != before_room and int(w.run.floor) == before_floor: doors_crossed += 1
			for event in w.take_events():
				if event.kind == "room_clear":
					var key = "%d/%d" % [w.run.floor, w.run.room]
					seen_rooms[key] = true
					if w.run.graph.room_roles.get(str(w.run.room), "") == "double_boss": doubles_cleared.append(int(w.run.floor))
		var report = {"character": character, "seed": w.run.seed_text, "result": w.run.result, "highest_floor": highest_floor,
			"cleared": w.run.cleared, "bosses": w.run.bosses_defeated, "transitions": transitions, "physical_doors": doors_crossed,
			"double_boss_floors": doubles_cleared, "save_checks": save_checks, "combat_seconds": snappedf(w.time, .1),
			"health": w.player.hp, "stats": w.stats, "last_room": w.run.room, "last_mode": w.mode,
			"last_enemy_ids": w.enemies.map(func(enemy): return enemy.id), "epilogue_seen": w.run.get("epilogue_seen", false)}
		reports.append(report)
		if w.run.result.is_empty():
			var checkpoint_path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expanded-stalled-" + character + ".json")
			FileAccess.open(checkpoint_path, FileAccess.WRITE).store_string(JSON.stringify(Store.encode(w.snapshot()), "\t"))
		print("Eleven-floor run %s: %s; floor %d, %d clears, %d doors, %.1fs" % [character, w.run.result, highest_floor, w.run.cleared, doors_crossed, w.time])
		if w.run.result not in ["victory", "defeat"]: failures.append("stalled " + character)
	if not reports.any(func(row): return row.result == "victory" and row.bosses.has("b36") and row.bosses.has("b37") and row.transitions.size() == 10 and row.epilogue_seen): failures.append("no complete unmodified eleven-floor victory")
	FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expanded-full-run"+report_suffix+".json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": failures.is_empty(), "runs": reports, "failures": failures,
		"method": "initial unlock pool, unchanged player health/damage/energy, 60 Hz combat and 30 Hz held action decisions for adaptive fine navigation, physical door walking and once-per-discovery equipment pickup on the main route, charged active-item use in combat, mandatory double-boss floors 7–10, ten checkpoint save/restores; maximum 480000 ticks per attempt with a 60-second no-progress diagnostic cutoff",
		"limitations": ["Action bot does not establish human feel or real-time device performance", "Native cinematic/keyboard checks are recorded separately"]}, "\t"))
	quit(0 if failures.is_empty() else 1)
