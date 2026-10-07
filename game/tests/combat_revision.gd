extends SceneTree
const Bot = preload("res://tests/playthrough_bot.gd")
const World = preload("res://scripts/combat/world.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Patterns = preload("res://scripts/combat/expanded_patterns.gd")
var checks: Array = []
var samples: Dictionary = {}
var failures: Array = []
func _initialize() -> void: call_deferred("suite")
func expect(id: String, passed: bool, detail: String = "") -> void:
	checks.append({"id":id,"passed":passed,"detail":detail})
	if not passed: failures.append(id); print("COMBAT REVISION FAIL: ",id," ",detail)
func fixture(sample: Array, variant: int = 0):
	var w = World.new()
	w.start("c_paper",str(sample[0]).to_int(),11,{"seed_text":sample[0]})
	w.run.floor=sample[1]; w.run.graph=Campaign.build(w.db,sample[0],sample[1])
	w.run.room_plan=w.run.graph.types.duplicate(); w.run.graph.backgrounds["0"]=variant
	w.enter_room()
	return w
func distinct_frames(row: Dictionary) -> bool:
	var unique: Dictionary = {}
	for hash_value in row.frame_hashes: unique[hash_value] = true
	return unique.size() == 6
func suite() -> void:
	var db = World.new().db
	var graphs_ok = true
	var quota_ok = true
	var final_unique = true
	for number in 100:
		var seed_text = Seed.text(890000000001+number)
		var guest_bosses = 0
		var random_bosses = 0
		for floor_id in range(1,12):
			var graph = Campaign.build(db,seed_text,floor_id)
			if not samples.has(graph.biome): samples[graph.biome]=[seed_text,floor_id]
			var guest = Campaign.guest_biome(db,seed_text,floor_id)
			graphs_ok = graphs_ok and graph.guest_biome==guest.id and guest.id!=graph.biome
			var room_ids = graph.boss_assignments.keys()
			if floor_id<=5:
				graphs_ok = graphs_ok and room_ids.size()==2 and graph.boss_assignments.values().all(func(pack): return pack.size()==1)
				graphs_ok = graphs_ok and graph.room_roles.values().has("side_boss") and not graph.room_roles.values().has("double_boss")
			var gauntlet: Array = []
			for room in room_ids:
				for id in graph.boss_assignments[room]:
					if id in ["b36","b37"]: continue
					random_bosses+=1
					if guest.random_boss_ids.has(id): guest_bosses+=1
					if graph.room_roles.get(room,"").begins_with("gauntlet_"): gauntlet.append(id)
			if floor_id==11:
				var unique: Dictionary = {}
				for id in gauntlet: unique[id]=true
				final_unique = final_unique and unique.size()==6
		quota_ok = quota_ok and random_bosses==36 and guest_bosses==roundi(random_bosses*.4)
	expect("1100_graphs_early_two_independent_single_boss_rooms_and_one_guest_theme",graphs_ok)
	expect("campaign_boss_quota_14_guests_of_36_random_slots_in_every_seed",quota_ok)
	expect("final_six_consecutive_bosses_remain_distinct_after_mixing",final_unique)
	expect("all_twenty_themes_sampled",samples.size()==20)
	for biome in db.expansion.biomes:
		for variant in 2:
			var key = biome.id+"_"+str(variant)
			var w = fixture(samples[biome.id],variant)
			var guest = w.guest_spec()
			var enemies = w.room_flags.waves.reduce(func(all_ids,wave): all_ids.append_array(wave); return all_ids,[])
			expect(key+"_natural_room_exact_accumulated_quota",enemies.filter(func(id): return guest.enemy_ids.has(id)).size()==w.encounter_foreign_count(enemies.size()))
			expect(key+"_spawn_and_player_are_inside_reviewed_inner_wall",w.geometry.valid_circle(w.player.pos,12) and w.enemies.all(func(e): return w.geometry.valid_circle(e.pos,e.radius)))
			var pathways = w.geometry.all_reachable()
			for side in ["north","south","east","west"]:
				var door = w.room_door_position(side)
				pathways = pathways and w.geometry.valid_circle(door,12) and w.geometry.clear_segment(Vector2(640,360),door)
			expect(key+"_four_doors_and_connected_scenery_follow_same_contour",pathways)
			var transition_ok = true
			w.enemies.clear(); w.mode="clear"
			var gate = w.room_doors()[0]
			w.player.pos=gate.pos-w.direction_vector(gate.direction)*70
			for tick in 40:
				if int(w.run.room)==0: w.tick({"move":w.direction_vector(gate.direction)})
			transition_ok=transition_ok and int(w.run.room)==int(gate.destination) and w.geometry.valid_circle(w.player.pos,12)
			w.enemies.clear(); w.mode="clear"
			var back = w.room_doors().filter(func(door): return int(door.destination)==0)[0]
			w.player.pos=back.pos-w.direction_vector(back.direction)*70
			for tick in 40:
				if int(w.run.room)!=0: w.tick({"move":w.direction_vector(back.direction)})
			expect(key+"_actual_physical_gate_crossing_and_return_keep_legal_entry",transition_ok and int(w.run.room)==0 and w.geometry.valid_circle(w.player.pos,12))
			w.enemies.clear(); w.geometry.restore_objects([]); w.mode="clear"
			w.run.graph.edges=[]; w.run.graph.secret_entries=[]
			var movement_ok = true
			for direction_index in 8:
				w.player.pos=Vector2(640,360)
				var direction = Vector2.RIGHT.rotated(direction_index*TAU/8)
				for tick in 180:
					w.tick({"move":direction,"aim":direction,"dash":tick%60==0})
					movement_ok = movement_ok and w.geometry.valid_circle(w.player.pos,12)
				for radius in [9,17,32,48,86]:
					var position = w.geometry.slide(Vector2(640,360),direction*5000,radius)
					movement_ok = movement_ok and w.geometry.valid_circle(position,radius)
			expect(key+"_actual_movement_dashes_and_fast_large_actors_cannot_cross_wall",movement_ok)
			var beam_ok = true
			for direction_index in 16:
				var direction = Vector2.RIGHT.rotated(direction_index*TAU/16)
				var end = w.geometry.clipped_ray(Vector2(640,360),Vector2(640,360)+direction*4000,18)
				beam_ok = beam_ok and w.geometry.contains_floor(end,18) and w.geometry.clear_swept_segment(Vector2(640,360),end,18)
			expect(key+"_sixteen_ray_directions_stop_at_radius_offset_inner_wall",beam_ok)
			w.enemies.clear(); w.mode="combat"; w.player.weapon="w14"; w.player.shot_cd=0
			w.player.pos=w.geometry.doorway("west",12.1)
			var dummy=w.spawn_enemy(biome.enemy_ids[0],Vector2(640,360))
			dummy.hp=1000; dummy.max_hp=1000
			w.take_events(); w.tick({"aim":Vector2.RIGHT,"fire":true})
			var rays=w.take_events().filter(func(event): return event.kind=="ray")
			expect(key+"_player_touching_inner_wall_still_fires_full_width_ray",rays.size()==1 and rays[0].range>200 and w.geometry.contains_floor(rays[0].pos,rays[0].width) and dummy.hp<1000)
			w.enemies.clear()
			var mob = w.spawn_enemy(biome.enemy_ids[-1],Vector2(10,680))
			var boss = w.spawn_boss(biome.boss_ids[0],Vector2(1250,10))
			for i in 120:
				w.time+=1.0/60; Patterns.move(w,mob,1.0/60); Patterns.move(w,boss,1.0/60)
			expect(key+"_spawn_repair_and_real_enemy_boss_motion_stay_inside",w.geometry.valid_circle(mob.pos,mob.radius) and w.geometry.valid_circle(boss.pos,boss.radius))
			var saved = w.snapshot()
			saved.player.pos=Vector2(20,20); saved.enemies[0].pos=Vector2(1250,680)
			var resumed = World.new()
			var restored = resumed.restore(Store.decode(JSON.parse_string(JSON.stringify(Store.encode(saved)))))
			expect(key+"_old_wall_positions_restore_inside_without_losing_build",restored and resumed.geometry.valid_circle(resumed.player.pos,12) and resumed.enemies.all(func(e): return resumed.geometry.valid_circle(e.pos,e.radius)) and resumed.run.coins==w.run.coins and resumed.player.hp==w.player.hp)
	var w = fixture(samples.m01)
	var saved = w.snapshot(); saved.run.graph.guest_biome="m99"
	expect("unknown_guest_theme_save_is_rejected",not Migration.world(saved).ok)
	var legacy = fixture(["123456789012",3])
	var side = legacy.run.graph.room_roles.keys().filter(func(room): return legacy.run.graph.room_roles[room]=="side_boss")[0]
	var own = legacy.region_spec().random_boss_ids
	legacy.run.graph.boss_assignments[side]=own.slice(0,2)
	legacy.run.graph.room_roles[side]="double_boss"; legacy.run.graph.campaign=1
	legacy.run.room=int(side); legacy.enter_room()
	legacy.enemies[1].hp*=.43
	var carried_hp = legacy.enemies[1].hp
	var resume = World.new()
	expect("old_live_early_pair_migrates_to_separate_rooms_without_resetting_health",resume.restore(legacy.snapshot()) and resume.enemies.filter(func(e): return e.boss).size()==1 and resume.run.graph.room_roles[side]=="side_boss" and resume.run.coins==legacy.run.coins and resume.player.hp==legacy.player.hp)
	resume.run.room=resume.run.graph.types.find("boss"); resume.enter_room()
	expect("old_displaced_boss_remaining_health_carries_into_exit_chamber",resume.enemies.filter(func(e): return e.boss).size()==1 and is_equal_approx(resume.enemies[0].hp,carried_hp) and resume.run.legacy_boss_health.is_empty())
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/combat-revision/manifest.json"))
	expect("eight_source_bound_fx_sequences_with_48_distinct_generated_keyframes",manifest.records.size()==8 and manifest.frames==48 and manifest.records.all(distinct_frames))
	var corner = World.new()
	var corner_file = "res://../docs/incense-debt/reports/runtime/combat-revision/corner-stall-before.json"
	var corner_ok = corner.restore(Store.decode(JSON.parse_string(FileAccess.get_file_as_string(corner_file))))
	var initial_health = corner.player.hp
	var escaped = false
	for tick in 1200:
		corner.tick(Bot.frame(corner)); corner.take_events()
		corner_ok=corner_ok and corner.geometry.valid_circle(corner.player.pos,12)
		if corner.mode!="combat": escaped=corner.mode=="clear" or corner.mode=="choice"; break
	expect("real_stalled_corner_save_escapes_and_clears_without_boosting_player",corner_ok and escaped and corner.player.hp<=initial_health)
	var fringe=World.new()
	var fringe_file="res://../docs/incense-debt/reports/runtime/combat-revision/narrow-fringe-before.json"
	var fringe_ok=fringe.restore(Store.decode(JSON.parse_string(FileAccess.get_file_as_string(fringe_file))))
	var fringe_origin=fringe.player.pos
	var anchor=fringe.geometry.navigation_waypoint(fringe_origin,fringe.enemies[0].pos,12)
	expect("real_narrow_fringe_joins_visible_grid_node_beyond_96_unit_lookahead",fringe_ok and fringe_origin.distance_to(anchor)>80 and fringe.geometry.clear_swept_segment(fringe_origin,anchor,12) and fringe.geometry.valid_circle(anchor,12))
	var fringe_input: Dictionary={}
	var fringe_cleared=false
	var fringe_max_hp=fringe.player.max_hp
	for tick in 2400:
		if tick%2==0: fringe_input=Bot.frame(fringe)
		fringe.tick(fringe_input); fringe.take_events()
		fringe_ok=fringe_ok and fringe.geometry.valid_circle(fringe.player.pos,12)
		if fringe.mode!="combat": fringe_cleared=fringe.mode in ["clear","choice"]; break
	expect("real_narrow_fringe_save_clears_with_normal_build_and_30_hz_actions",fringe_ok and fringe_cleared and fringe.player.max_hp==fringe_max_hp)
	var thin=World.new()
	var thin_file="res://../docs/incense-debt/reports/runtime/combat-revision/thin-corridor-before.json"
	var thin_ok=thin.restore(Store.decode(JSON.parse_string(FileAccess.get_file_as_string(thin_file))))
	var exit_door=thin.room_doors().filter(func(door): return door.destination==int(thin.run.room)+1)[0]
	var thin_start=thin.player.pos
	var thin_anchor=thin.geometry.navigation_waypoint(thin_start,exit_door.pos,12)
	expect("real_seven_unit_legal_corridor_connects_through_adaptive_grid",thin_ok and thin_start.distance_to(thin_anchor)>8 and thin.geometry.clear_swept_segment(thin_start,thin_anchor,12))
	var thin_room=int(thin.run.room)
	for tick in 1800:
		thin.geometry.rebuild_flow(exit_door.pos)
		var movement=thin.geometry.toward(thin.player.pos,exit_door.pos)
		if thin.player.pos.distance_to(exit_door.pos)<14: movement=thin.direction_vector(exit_door.direction)
		thin.tick({"move":movement}); thin.take_events()
		thin_ok=thin_ok and thin.geometry.valid_circle(thin.player.pos,12)
		if int(thin.run.room)!=thin_room: break
	expect("real_thin_corridor_reaches_and_walks_through_physical_exit",thin_ok and int(thin.run.room)==thin_room+1)
	var report = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"graph_samples":1100,"boundary_variants":40,"movement_ticks":57600,
		"scope":"actual fixed-tick player movement and dashes; all-size swept collision, real enemy movement, radius-aware rays, legacy-position restoration, mixed quotas and independent early boss chambers"}
	FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/combat-revision/systems.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Combat revision: ",checks.size()," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
