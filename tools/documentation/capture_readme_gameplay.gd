extends SceneTree
## Record normal combat from the delivered executable's embedded scripts/assets.
## Creates its own world; it never opens or writes a user's save slot.
var output=""
var bot
var frames: Array=[]

func _initialize():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--bot-script="): bot=load(argument.trim_prefix("--bot-script="))
	if output.is_empty() or bot==null: quit(1); return
	call_deferred("record")

func record():
	var world=load("res://scripts/combat/world.gd").new()
	world.start("c_paper",6327,11,{"seed_text":"000000006327"})
	var initial_player=world.player.duplicate(true)
	var adapter=load("res://scripts/ui/input_adapter.gd").new()
	var renderer=load("res://scripts/ui/game_renderer.gd").new()
	renderer.world=world; renderer.adapter=adapter
	root.add_child(renderer); renderer.set_process(false)
	var hud=load("res://scripts/ui/game_hud.gd").new()
	hud.world=world; hud.adapter=adapter
	root.add_child(hud); hud.set_process(false)
	await process_frame
	await process_frame
	renderer.accept(world.take_events())
	var held_input: Dictionary={}
	for tick_id in 1440:
		if world.mode=="result": break
		if world.mode=="choice": world.take_choice(bot.choose(world,0))
		elif world.mode=="clear":
			var destination=int(world.run.room)+1
			for door in world.room_doors():
				if door.destination!=destination: continue
				world.geometry.rebuild_flow(door.pos)
				var movement=world.geometry.toward(world.player.pos,door.pos)
				if world.player.pos.distance_to(door.pos)<14: movement=world.direction_vector(door.direction)
				world.tick({"move":movement}); break
		elif world.mode=="combat":
			if tick_id%2==0: held_input=bot.frame(world)
			world.tick(held_input)
		renderer.accept(world.take_events())
		renderer._process(1.0/60)
		hud._process(1.0/60)
		if tick_id%12==0:
			await process_frame
			await RenderingServer.frame_post_draw
			var path=output+"/frame-%03d.png" % frames.size()
			var error=root.get_texture().get_image().save_png(path)
			frames.append({"file":path,"saved":error==OK,"tick":tick_id,"time":world.time,"room":world.run.room,"enemies":world.enemies.size(),"health":world.player.hp,"effects":renderer.visual_effects.size(),"shots":world.stats.shots,"hits":world.stats.hits})
	var report={"character":"c_paper","seed":"000000006327","physics_hz":60,"held_input_hz":30,"capture_hz":5,"initial_player":initial_player,"frames":frames,"stats":world.stats,"method":"Normal initial character stats, real weapon and skill actions from the action bot, actual enemy simulation and physical door movement; native viewport rendered from the delivered embedded scripts/assets; no save-slot access"}
	var Store=load("res://scripts/core/save_store.gd")
	FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(Store.encode(report),"\t"))
	print("README gameplay: ",frames.size()," native frames; ",world.stats.shots," real shots; hp ",world.player.hp)
	quit(0 if frames.size()>60 and frames.all(func(frame): return frame.saved) else 1)
