extends SceneTree
const Server = preload("res://scripts/network/server_runtime.gd")
const Session = preload("res://scripts/network/online_session.gd")
const Store = preload("res://scripts/core/save_store.gd")
var server
var clients: Array = []
var checks: Array = []
var errors: Array = [[], [], []]
var folder = ""
var loadout = {"character": "c_paper", "weapon": "w06", "skill": "s01"}

func _initialize() -> void:
	folder = "user://cooperative-transport-%d" % Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	call_deferred("run")

func check(name: String, value: bool) -> void:
	checks.append({"id": name, "passed": value})
	print("COOP_TRANSPORT_", "PASS " if value else "FAIL ", name)

func until(predicate: Callable, timeout: float = 6) -> bool:
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func command(client, op: String, data: Dictionary = {}) -> bool:
	var request = client.request(op, data)
	return request > 0 and await until(func(): return not client.pending.has(str(request)))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	server = Server.new()
	root.add_child(server)
	check("native_loopback_server", server.start({"port": 18779, "bind": "127.0.0.1", "data_directory": folder.path_join("server")}) == OK)
	for i in 3:
		var client = Session.new(folder.path_join("client%d" % i))
		client.problem.connect(func(error): errors[i].append(error))
		root.add_child(client)
		clients.append(client)
		client.connect_service("ws://127.0.0.1:18779", "合作验证%d" % i)
	check("three_real_socket_clients", await until(func(): return clients.all(func(client): return client.state == "online")))
	if not checks[-1].passed: finish(); return
	var a = clients[0]
	var b = clients[1]
	var c = clients[2]
	await command(a, "queue", {"loadout": loadout, "game_mode": "coop"})
	await command(b, "queue", {"loadout": loadout, "game_mode": "duel"})
	check("cooperation_and_duel_queues_separate", a.state == "queued" and b.state == "queued" and server.rooms.is_empty())
	await command(c, "queue", {"loadout": loadout, "game_mode": "coop"})
	check("matching_selects_same_mode_partner", await until(func(): return a.room.get("phase") == "lobby" and c.room.get("phase") == "lobby" and b.state == "queued"))
	await command(b, "cancel_queue")
	await command(a, "ready")
	await command(c, "ready")
	check("both_ready_start_real_campaign", await until(func(): return a.can_play() and c.can_play(), 7))
	if not checks[-1].passed: finish(); return
	# UDP replicas can represent different authoritative ticks. Verify the shared
	# identities and scene, rather than requiring simultaneous position samples.
	var shared_npcs = server.rooms[a.room.room].match.world.enemies.map(func(enemy): return int(enemy.uid))
	var own_npcs = a.presentation[0].enemies.map(func(enemy): return int(enemy.uid))
	var teammate_npcs = c.presentation[1].enemies.map(func(enemy): return int(enemy.uid))
	shared_npcs.sort(); own_npcs.sort(); teammate_npcs.sort()
	check("clients_share_npcs_not_opponent_proxy", not own_npcs.is_empty() and own_npcs == shared_npcs and teammate_npcs == shared_npcs and a.presentation[0].enemies.all(func(enemy): return not enemy.get("online_actor", false)))
	check("encrypted_enet_battle_connections", server.battle_connections.size() == 3 and clients.all(func(client): return client.battle_bound and client.battle.connected()))
	check("both_client_geometry_matches_server", a.presentation[0].geometry.objects == c.presentation[1].geometry.objects)
	var room = server.rooms[a.room.room]
	var world = room.match.world
	for context in world.contexts: context.player.invulnerable = 100.0
	var position = Vector2(world.contexts[0].player.pos)
	var start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 600:
		var frame = Session.Protocol.empty_input()
		frame.move = Vector2.RIGHT
		frame.fire = true
		frame.aim = Vector2.UP
		a.submit_input(frame)
		await process_frame
	a.clear_input()
	check("real_inputs_move_and_fire", world.contexts[0].player.pos.x > position.x + 30 and world.contexts[0].stats.shots > 0)
	check("authority_never_uploads_offline_progress", not server.sessions[a.identity.session].has("save_session"))
	await command(a, "pause")
	check("pause_suspends_both_clients", await until(func(): return a.room.phase == "suspended" and c.room.phase == "suspended"))
	var frozen = world.time
	await create_timer(.4).timeout
	check("paused_dungeon_stops_simulation", world.time == frozen)
	room.suspend_until = server.wall_time() - 1
	server.maintenance()
	check("connected_coop_menu_has_no_reconnect_timeout", room.suspended and room.match.phase != "finished")
	check("paused_control_checkpoints_commit", server.persist_registry() and server.persist_registry())
	var saved_revisions = []
	for slot in 2:
		var envelope = Store.parse_envelope(FileAccess.get_file_as_string(server.meta_store.folder.path_join("checkpoint_%d.json" % slot)))
		saved_revisions.append(int(envelope.snapshot.room_revisions[room.id]))
	check("paused_registry_generations_have_independent_room_files", saved_revisions[0] != saved_revisions[1] and saved_revisions.all(func(revision): return not server.room_generation(room.id, revision).is_empty()))
	await command(a, "resume")
	check("one_ready_cannot_resume_team", room.suspended)
	await command(c, "resume")
	check("mutual_resume_preserves_campaign", await until(func(): return a.can_play() and c.can_play(), 7))
	# Isolated authority fixtures exercise reward controls without trusting client loot.
	world.enemies.clear()
	world.delayed.clear()
	world.room_flags.wave_count = 1
	world.room_flags.wave_index = 1
	world.contexts[0].run.xp = 100
	world.contexts[1].run.xp = 100
	world.clear_room()
	room.match.sync_phase()
	server.broadcast(room)
	check("growth_modal_snapshot", await until(func(): return a.room.phase == "draft" and c.room.phase == "draft"))
	await create_timer(1.6).timeout
	check("growth_menu_can_outlive_input_protection_window", room.match.phase == "draft" and not room.suspended)
	var token = str(a.room.choice_token)
	await command(a, "choose", {"index": 0, "choice_token": "old-token"})
	check("stale_choice_rejected", errors[0].has("stale_choice"))
	await command(a, "choose", {"index": 0, "choice_token": token})
	check("number_choice_records_personal_talent", world.contexts[0].run.talents.size() == 1 and world.contexts[1].run.talents.is_empty())
	var event_count = a.last_event
	a.simulate_link_loss()
	check("disconnect_freezes_other_client", await until(func(): return c.room.phase == "suspended"))
	check("automatic_resume_identity", await until(func(): return a.state == "room" and a.room.phase == "suspended", 9))
	check("reconnect_preserves_pending_growth", a.room.game_mode == "coop" and a.room.actors[0].run.talents.size() == 1 and a.room.actors[1].run.talents.is_empty())
	check("reconnect_does_not_replay_events", a.last_event >= event_count)
	await command(a, "resume")
	await command(c, "resume")
	check("unfinished_growth_stays_modal_after_resume", await until(func(): return a.room.phase == "draft" and c.room.phase == "draft"))
	for attempt in 16:
		if room.match.phase != "draft": break
		for client in [a, c]:
			if client.room.get("choice_mode") == "choice" and not client.room.get("offers", []).is_empty():
				await command(client, "choose", {"index": 0, "choice_token": client.room.choice_token})
		await create_timer(.1).timeout
	check("growth_return_clears_old_input_deadline", await until(func(): return a.can_play() and c.can_play()) and not room.suspended)
	await command(a, "leave")
	check("partner_leave_is_team_end", await until(func(): return c.room.phase == "finished" and c.room.reason == "partner_left" and c.room.winner == -1))
	check("team_loss_counted_for_both_once", server.sessions[a.identity.session].coop_losses == 1 and server.sessions[c.identity.session].coop_losses == 1 and server.sessions[a.identity.session].wins == 0)
	server.settle_match(room)
	check("duplicate_settlement_cannot_duplicate_loss", server.sessions[a.identity.session].coop_losses == 1)
	room.created = server.wall_time() - 7200
	server.maintenance()
	check("long_campaign_keeps_its_fresh_result_screen", server.rooms.has(room.id))
	await command(c, "leave")
	await command(b, "code", {"code": "004281", "loadout": loadout, "game_mode": "coop"})
	check("leading_zero_cooperative_room_code", await until(func(): return b.room.get("code") == "004281"))
	await command(c, "code", {"code": "004281", "loadout": loadout, "game_mode": "duel"})
	check("same_code_wrong_mode_rejected", errors[2].has("room_mode_mismatch"))
	await command(a, "code", {"code": "004281", "loadout": loadout, "game_mode": "coop"})
	check("same_code_cooperative_partner_joins", await until(func(): return not a.room.is_empty() and a.room.get("room") == b.room.get("room") and b.room.get("players", []).size() == 2))
	await command(a, "advance_room", {"destination": 5})
	check("no_client_teleport_command", errors[0].has("unknown_command"))
	await command(a, "leave")
	await command(b, "leave")
	finish()

func finish() -> void:
	for client in clients: client.disconnect_service()
	if server != null: server.shutdown()
	var passed = checks.all(func(check): return check.passed)
	var file = FileAccess.open(folder.path_join("cooperative-transport.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "native_sockets": true, "isolated_authority_fixtures": true}, "\t"))
	print("COOPERATIVE_TRANSPORT_RESULT checks=%d passed=%s" % [checks.size(), passed])
	quit(0 if passed else 1)
