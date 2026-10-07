extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Bot = preload("res://tests/playthrough_bot.gd")

func _initialize(): call_deferred("inspect")

func inspect():
	var path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/expanded-stalled-c_umbrella.json")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="): path=argument.trim_prefix("--snapshot=")
	var w=World.new()
	var ok=w.restore(Store.decode(JSON.parse_string(FileAccess.get_file_as_string(path))))
	if not ok: print("restore_failed"); quit(1); return
	if w.enemies.is_empty():
		print("Mode ",w.mode," player ",w.player.pos," doors ",w.room_doors())
		print("Bounds ",w.geometry.bounds," floor ",w.geometry.floor_polygon," objects ",w.geometry.objects.filter(func(o): return o.alive and o.pos.distance_to(w.player.pos)<180))
		for i in 8:
			var axis=Vector2.RIGHT.rotated(i*TAU/8)
			print("Step ",axis," at ",w.geometry.slide(w.player.pos,axis*8,12))
		for spacing in [16.0,8.0,4.0]:
			var test_grid=AStarGrid2D.new()
			test_grid.region=Rect2i(Vector2i.ZERO,Vector2i(ceili(w.geometry.bounds.size.x/spacing),ceili(w.geometry.bounds.size.y/spacing)))
			test_grid.cell_size=Vector2.ONE*spacing
			test_grid.offset=w.geometry.bounds.position+Vector2.ONE*spacing*.5
			test_grid.update()
			var visible=0
			var near=INF
			for y in test_grid.region.size.y:
				for x in test_grid.region.size.x:
					var p=test_grid.get_point_position(Vector2i(x,y))
					if w.geometry.valid_circle(p,12) and w.geometry.clear_swept_segment(w.player.pos,p,12):
						visible+=1; near=minf(near,w.player.pos.distance_to(p))
			print("Spacing ",spacing," visible ",visible," nearest ",near)
		for door in w.room_doors():
			w.geometry.rebuild_flow(door.pos)
			var direction=w.geometry.toward(w.player.pos,door.pos)
			print("Door ",door.destination," position ",door.pos," toward ",direction," movement ",w.geometry.slide(w.player.pos,direction*30,12)," fine ",w.geometry.navigation_waypoint(w.player.pos,door.pos,12))
		quit(); return
	var original=w.snapshot()
	w.geometry.navigation_waypoint(w.player.pos,w.enemies[0].pos,12)
	var cache=w.geometry.fine_navigation.values()[0]
	var grid=cache.grid
	var start=Vector2i(-1,-1)
	var goal=Vector2i(-1,-1)
	var ds=INF
	var dg=INF
	for id in cache.free:
		var point=grid.get_point_position(id)
		if point.distance_squared_to(w.player.pos)<ds and w.geometry.clear_swept_segment(w.player.pos,point,12): start=id; ds=point.distance_squared_to(w.player.pos)
		if point.distance_squared_to(w.enemies[0].pos)<dg: goal=id; dg=point.distance_squared_to(w.enemies[0].pos)
	print("Fine start ",start," goal ",goal," path ",grid.get_point_path(start,goal,true))
	var samples: Array=[]
	for tick_id in 240:
		var input=Bot.frame(w)
		if tick_id%30==0:
			var target=w.nearest_enemy(w.player.pos)
			samples.append({"time":w.time,"player":w.player.duplicate(true),"target":target.duplicate(true),"input":input,"hits":w.stats.hits,
				"waypoint":w.geometry.navigation_waypoint(w.player.pos,target.pos,12) if not target.is_empty() else w.player.pos,
				"valid_position":w.geometry.valid_circle(w.player.pos,12)})
		w.tick(input)
		w.take_events()
	var report={"snapshot":path,"floor":w.run.floor,"room":w.run.room,"samples":samples,"objects":w.geometry.objects,"pickups":w.pickups,"relics":w.run.relics,"initial_state":original}
	var output=ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/combat-revision/navigation-diagnostic.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(Store.encode(report),"\t"))
	print("Actual-state navigation diagnostic: ",output)
	print("Player ",w.player.pos," weapon ",w.player.weapon," hp ",w.player.hp," targets ",w.enemies.map(func(enemy): return [enemy.id,enemy.hp,enemy.pos])," input ",Bot.frame(w))
	quit()
