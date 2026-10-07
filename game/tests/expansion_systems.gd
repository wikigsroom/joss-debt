extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
const Scenery = preload("res://scripts/combat/interactive_scenery.gd")
const Patterns = preload("res://scripts/combat/expanded_patterns.gd")
const Weapons = preload("res://scripts/combat/expanded_weapons.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
var checks: Array = []
var failures: Array = []
var graph_samples = 0
var geometry_samples = 0

func _initialize() -> void: call_deferred("suite")
func check(value: bool, id: String, detail = "") -> void:
	checks.append({"id": id, "passed": value, "detail": detail})
	if not value: failures.append(id); print("EXPANSION FAIL: ", id, " ", detail)

func fixture(seed_value: int = 123456789012):
	var w = World.new()
	w.start("c_paper", seed_value, 11, {"seed_text": Seed.text(seed_value), "relic_pool": World.Content.new().rows("relics").map(func(r): return r.id)})
	w.player.hp = 12
	w.player.max_hp = 12
	w.player.invulnerable = 0
	return w

func encoded(w) -> String: return JSON.stringify(Store.encode(w.snapshot()))

func graph_valid(graph: Dictionary) -> bool:
	var seen: Dictionary = {}
	for point in graph.coords:
		if seen.has(str(point)): return false
		seen[str(point)] = true
	var reached: Array = [0]
	var head = 0
	while head < reached.size():
		var current = reached[head]
		head += 1
		var directions: Array = []
		for edge in graph.edges:
			if not edge.has(current): continue
			var other = edge[1] if edge[0] == current else edge[0]
			var delta = Vector2(graph.coords[other]) - Vector2(graph.coords[current])
			if absf(delta.x) + absf(delta.y) != 1 or directions.has(delta): return false
			directions.append(delta)
			if not reached.has(other): reached.append(other)
	return reached.size() == graph.types.size()

func suite() -> void:
	var w = fixture()
	check(w.db.rows("bosses").size() == 99 and w.db.rows("enemies").size() == 296 and w.db.rows("weapons").size() == 32, "complete_expanded_and_theme_bound_content_counts")
	check(Seed.valid("000000000000") and Seed.valid("999999999999") and not Seed.valid("123456") and not Seed.valid("12345678901x"), "twelve_digit_seed_validation")
	check(Seed.fresh().length() == 12 and Seed.text(1) == "000000000001", "automatic_seed_preserves_leading_zeroes")
	var a = fixture(900000000001)
	var b = fixture(900000000001)
	check(encoded(a) == encoded(b), "same_seed_initial_world_and_spawns")
	var other = fixture(900000000002)
	check(encoded(a) != encoded(other), "upper_12_digit_values_do_not_collapse")
	for i in 200: a.roll("enemy_timing_999").unit()
	check(a.relic_offer(3) == b.relic_offer(3), "enemy_timing_stream_cannot_change_loot")
	var graph_good = true
	var story_good = true
	var final_good = true
	var double_good = true
	var reached_maps: Dictionary = {}
	var theme_samples: Dictionary = {}
	for number in range(1, 101):
		for floor_id in range(1, 12):
			var graph = Campaign.build(w.db, Seed.text(892000000000 + number), floor_id)
			graph_samples += 1
			graph_good = graph_good and graph_valid(graph)
			reached_maps[graph.biome] = true
			if not theme_samples.has(graph.biome): theme_samples[graph.biome]=[Seed.text(892000000000 + number),floor_id]
			var exit = graph.types.find("boss")
			var ids = Campaign.boss_ids(graph, exit)
			var biome_row = Campaign.biome(w.db, Seed.text(892000000000 + number), floor_id)
			var guest_row = Campaign.guest_biome(w.db, Seed.text(892000000000 + number), floor_id)
			for assigned in graph.boss_assignments.values():
				graph_good = graph_good and assigned.all(func(id): return biome_row.boss_ids.has(id) or guest_row.random_boss_ids.has(id))
			if floor_id == 6: story_good = story_good and ids == ["b36"]
			if floor_id == 11:
				var gauntlet: Array = []
				for key in graph.room_roles:
					if str(graph.room_roles[key]).begins_with("gauntlet_"): gauntlet.append(int(key))
				gauntlet.sort()
				final_good = final_good and graph.types.size() >= 30 and ids == ["b37"] and gauntlet.size() == 6
				for i in range(1, gauntlet.size()): final_good = final_good and gauntlet[i] == gauntlet[i-1] + 1 and graph.edges.has([gauntlet[i-1],gauntlet[i]])
			elif floor_id in [7,8,9,10]: double_good = double_good and ids.size() == 2 and ids[0] != ids[1]
			if floor_id <= 5:
				var boss_rooms = graph.boss_assignments.values()
				double_good = double_good and boss_rooms.size()==2 and boss_rooms.all(func(pack): return pack.size()==1) and graph.room_roles.values().has("side_boss")
			else: double_good = double_good and graph.room_roles.values().has("double_boss")
	check(graph_good, "all_1100_floor_graphs_connected_and_physical", str(graph_samples))
	check(story_good, "fixed_sixth_floor_story_boss")
	check(final_good, "final_30plus_rooms_six_consecutive_bosses_and_fixed_final")
	check(double_good, "early_two_separate_single_boss_rooms_and_later_intensity_doubles")
	check(reached_maps.size() == 20, "all_twenty_biomes_are_reachable", str(reached_maps.size()))
	var reachable = true
	var joined = true
	var varied: Dictionary = {}
	for i in 100:
		var geometry = Geometry.new()
		geometry.build_procedural(Seed.derive(Seed.text(800000000000+i), "obstacles"), "m01", "combat")
		geometry_samples += 1
		reachable = reachable and geometry.all_reachable()
		for direction in ["north","south","east","west"]: reachable = reachable and geometry.valid_circle(World.door_position(direction), 12)
		joined = joined and geometry.objects.any(func(object): return object.group >= 0 and geometry.connections(object) > 0)
		varied[JSON.stringify(Store.encode(geometry.objects))] = true
	check(reachable, "hundred_obstacle_layouts_keep_all_walkable_cells_and_doors_connected")
	check(joined and varied.size() >= 90, "connected_obstacle_clusters_and_seed_variation", str(varied.size()))
	w = fixture()
	var saved = Store.decode(JSON.parse_string(encoded(w)))
	var resumed = World.new()
	check(resumed.restore(saved), "new_campaign_snapshot_restores", Migration.world(saved).get("message", ""))
	if not resumed.run.is_empty():
		for tick_id in 240:
			var frame = {"move": Vector2.RIGHT if tick_id < 90 else Vector2.ZERO, "aim": Vector2.UP, "fire": true}
			w.tick(frame); resumed.tick(frame)
		check(encoded(w) == encoded(resumed), "derived_streams_resume_same_combat_and_dynamic_obstacles")
	w = fixture()
	w.enemies.clear(); w.geometry.restore_objects([])
	w.secondary_bullet(Vector2(500, 350), Vector2.RIGHT, 8)
	var ash_save = Store.decode(JSON.parse_string(encoded(w)))
	var ash_resumed = World.new()
	check(ash_resumed.restore(ash_save), "secondary_ash_projectile_resumes_from_checkpoint")
	ash_save.bullets[0].erase("target_index")
	check(ash_resumed.restore(ash_save) and ash_resumed.bullets[0].target_index == 0, "early_v2_secondary_ash_save_recovers_default_without_losing_run")
	w = fixture()
	w.enemies.clear(); w.geometry.restore_objects([])
	var urn = {"key":"7,4","cell":Vector2(7,4),"pos":Vector2(544,360),"kind":"powder_urn","group":-1,"hp":12.0,"alive":true,"solid":true,"phase":0.0,"hit_until":0.0,"fuse_until":0.0}
	var adjacent = urn.duplicate(true)
	adjacent.key="6,4"; adjacent.cell=Vector2(6,4); adjacent.pos=Vector2(480,360)
	w.geometry.restore_objects([urn, adjacent])
	var enemy = w.spawn_enemy("e25",Vector2(590,360)); enemy.hp=90; enemy.max_hp=90
	w.player.pos=Vector2(600,360); w.player.aim=Vector2.LEFT; w.player.weapon="w01"
	w.shoot_input(true,1.0/60.0)
	for i in 12: w.update_bullets(1.0/60.0); w.time+=1.0/60.0
	check(w.geometry.objects[0].fuse_until > 0, "actual_projectile_ignites_urn")
	w.time+=.4; Scenery.tick(w)
	check(not w.geometry.objects[0].alive and enemy.hp < 90 and w.player.hp < 12 and w.geometry.objects[1].fuse_until > 0, "urn_explosion_damages_both_sides_and_chains")
	w.time+=.4; Scenery.tick(w)
	check(not w.geometry.objects[1].alive and w.geometry.blocks.is_empty(), "chain_explosion_removes_collision")
	var hazard=urn.duplicate(true); hazard.kind="thorn_seal"; hazard.solid=false; hazard.hp=9999; hazard.fuse_until=0; hazard.alive=true
	w.geometry.restore_objects([hazard]); w.player.pos=hazard.pos; w.player.invulnerable=0; w.time=2; var hp=w.player.hp
	Scenery.tick(w)
	check(w.player.hp == hp-1 and w.run.damage_history[-1].source.table == "obstacles", "contact_hazard_health_and_saved_provenance")
	w.mode="clear"; w.player.invulnerable=0; hp=w.player.hp; Scenery.tick(w)
	check(w.player.hp==hp-1, "cleared_room_hazards_still_damage_player")
	check(Migration.world(Store.decode(JSON.parse_string(encoded(w)))).ok, "hazards_and_explosions_survive_save_validation")
	w = fixture(); w.enemies.clear(); w.geometry.restore_objects([urn]); w.player.pos=Vector2(410,360); w.player.aim=Vector2.RIGHT; w.player.weapon="w14"
	var behind=w.spawn_enemy("e25",Vector2(670,360)); var before=behind.hp
	w.shoot_input(true,.02)
	var rays=w.events.filter(func(e): return e.kind=="ray")
	check(behind.hp == before and not rays.is_empty() and rays[0].end.x < 560, "ray_visual_endpoint_and_damage_stop_at_same_obstacle")
	check(w.geometry.clipped_ray(Vector2(410,320),Vector2(670,320),14).x < 544, "beam_width_grazing_obstacle_clips_actual_ray")
	w=fixture(); var graph_directions=true
	for edge in w.run.graph.edges:
		var from_id=int(edge[0]); var to_id=int(edge[1]); var offset=Vector2(w.run.graph.coords[to_id])-Vector2(w.run.graph.coords[from_id])
		graph_directions=graph_directions and w.direction_vector(w.room_connection_direction(to_id,from_id))==offset
	check(graph_directions, "campaign_map_directions_match_physical_doors")
	var boss_signatures: Dictionary = {}
	for spec in w.db.rows("bosses").slice(5):
		var sandbox=fixture(); sandbox.enemies.clear(); sandbox.geometry.restore_objects([])
		var boss=sandbox.spawn_boss(str(spec.id)); var attacks=0; var moved=false
		for phase in 3:
			boss.phase=phase; boss.target=sandbox.player.pos; boss.aim=Vector2.DOWN
			for repeat in 4: Patterns.attack(sandbox,boss); attacks+=1
			var position=Vector2(boss.pos)
			for i in 60: sandbox.time+=1.0/60; Patterns.move(sandbox,boss,1.0/60)
			moved=moved or boss.pos.distance_to(position)>1
		boss_signatures[spec.movement+"/"+spec.attack_family+"/"+spec.secondary_family]=true
		check(attacks==12 and moved and sandbox.events.any(func(e): return e.kind=="boss_attack") and sandbox.bullets.size()<=240 and sandbox.zones.size()<=48, "boss_"+spec.id+"_three_phases_and_motion")
	check(boss_signatures.size() >= 32, "at_least_thirty_two_distinct_boss_behavior_combinations", str(boss_signatures.size()))
	var theme_ids: Dictionary = {}
	for biome in w.db.expansion.biomes:
		var owned = true
		for id in biome.enemy_ids + biome.random_boss_ids:
			var row = w.db.row("enemies" if str(id).begins_with("e") else "bosses", id)
			owned = owned and row.get("theme", "") == biome.id and not theme_ids.has(id)
			theme_ids[id] = true
		check(biome.enemy_ids.size() == 12 and biome.boss_ids.size() in [3, 7] and owned, "theme_"+biome.id+"_twelve_mobs_and_exclusive_bosses")
		var local_behaviors: Dictionary = {}
		for id in biome.random_boss_ids:
			var row = w.db.row("bosses", id)
			local_behaviors[row.movement+"/"+row.attack_family+"/"+row.secondary_family] = true
		check(local_behaviors.size() == biome.random_boss_ids.size(), "theme_"+biome.id+"_distinct_boss_moves")
		var sample = theme_samples[biome.id]
		var themed = fixture(str(sample[0]).to_int())
		themed.run.floor = int(sample[1]); themed.run.graph = Campaign.build(themed.db, sample[0], sample[1])
		themed.run.room_plan = themed.run.graph.types.duplicate(); themed.run.room=9; themed.enter_room()
		var guest = themed.guest_spec()
		check(themed.enemies.size()==4 and themed.enemies.filter(func(e): return guest.enemy_ids.has(e.id)).size()==themed.encounter_foreign_count(4) and themed.enemies.all(func(e): return (biome.enemy_ids.has(e.id) or guest.enemy_ids.has(e.id)) and e.sprite_id==e.id), "theme_"+biome.id+"_actual_elite_and_adds_mixed_quota")
		themed.enemies.clear(); themed.geometry.restore_objects([])
		var caller = themed.spawn_boss(str(biome.boss_ids[0]))
		Patterns.execute(themed, caller, "summon")
		var summons = themed.enemies.filter(func(e): return not e.boss)
		check(summons.size()==2 and summons.filter(func(e): return guest.enemy_ids.has(e.id)).size()==1 and summons.all(func(e): return biome.enemy_ids.has(e.id) or guest.enemy_ids.has(e.id)), "theme_"+biome.id+"_actual_summons_mixed_quota")
	for spec in w.db.rows("enemies").slice(24):
		var sandbox=fixture(); sandbox.enemies.clear(); sandbox.geometry.restore_objects([])
		var new_enemy=sandbox.spawn_enemy(str(spec.id),Vector2(640,230)); new_enemy.aim=Vector2.DOWN; new_enemy.target=sandbox.player.pos
		for i in 2: Patterns.attack(sandbox,new_enemy)
		check(sandbox.bullets.size()>0 or sandbox.zones.size()>0 or new_enemy.lunge>0 or new_enemy.attack_step>0, "enemy_"+spec.id+"_actual_attack")
	for spec in w.db.rows("weapons").slice(16):
		var sandbox=fixture(); sandbox.enemies.clear(); sandbox.geometry.restore_objects([])
		sandbox.player.weapon=spec.id; sandbox.player.pos=Vector2(640,500); sandbox.player.aim=Vector2.UP
		var target=sandbox.spawn_enemy("e01",Vector2(640,390)); target.hp=500; target.max_hp=500; target.speed=0; target.attack_cd=10
		for i in 120:
			sandbox.time+=1.0/60; sandbox.player.shot_cd=maxf(0,sandbox.player.shot_cd-1.0/60)
			sandbox.shoot_input(true,1.0/60); sandbox.update_bullets(1.0/60); sandbox.update_delayed(1.0/60); sandbox.update_zones(1.0/60)
		check(target.hp < 500, "weapon_"+spec.id+"_real_damage", str(500-target.hp))
		check(Migration.world(Store.decode(JSON.parse_string(encoded(sandbox)))).ok, "weapon_"+spec.id+"_saveable_active_effects", Migration.world(sandbox.snapshot()).get("message", ""))
	w=fixture(); w.mode="checkpoint"; w.advance_room()
	check(w.mode=="transition" and w.run.floor==1, "floor_change_requires_transition")
	check(Migration.world(Store.decode(JSON.parse_string(encoded(w)))).ok, "transition_can_save_and_restore")
	w.continue_transition()
	check(w.run.floor==2 and w.mode=="choice" and w.choices.all(func(c): return c.kind=="skill"), "transition_then_mandatory_skill_evolution")
	w.take_choice(0)
	check(w.run.floor==2 and w.mode=="combat", "evolution_enters_new_campaign_room")
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"graph_samples":graph_samples,"geometry_samples":geometry_samples,"scope":"real simulation attacks, collisions, state validation and seed-derived graph coverage; native visual and full-run evidence recorded separately"}
	var path=ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expansion-systems.json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Expansion systems: ",checks.size()," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
