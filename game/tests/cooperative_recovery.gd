extends "res://tests/online_recovery.gd"
## Two independent client processes reuse durable identities after a server crash.

func identical(a, b) -> bool:
	# Integral floats normalize to integers in the durable schema. Fractional
	# doubles retain their exact IEEE-754 bits; compare that canonical encoding.
	return JSON.stringify(Protocol.Store.encode(a), "", true, true) == JSON.stringify(Protocol.Store.encode(b), "", true, true)

func read_expected() -> void:
	expected = Protocol.Store.decode(JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json"))))

func replica_complete(client, sequence: int) -> bool:
	# Core and entity datagrams are intentionally independent. Seeing the pause
	# core is not proof that that core's NPC/pickup inventories arrived already.
	var stream = client.stream_codec
	if not stream.scene_ready: return false
	for group in stream.schemas:
		var inventory: Dictionary = stream.inventories.get(group, {})
		if int(inventory.get("seq", 0)) < sequence: return false
		for uid in inventory.get("alive", []):
			if int(stream.entity_sequences.get(group, {}).get(uid, 0)) < sequence: return false
	return true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 2:
		var client = Session.new(folder.path_join("client-%d" % i))
		root.add_child(client)
		clients.append(client)
		client.connect_service(url, "Cooperative Recovery %d" % i)
	var connected = await until(func(): return clients.all(func(client): return client.state in ["online", "room"]), 9)
	check(connected, "cooperative_process_credentials_connect")
	if not connected: finish(); return
	var a = clients[0]
	var b = clients[1]
	if stage == "prepare":
		await command(a, "code", {"code": "006125", "loadout": {"character": "c_mask", "weapon": "w14", "skill": "s10"}, "game_mode": "coop"})
		await command(b, "code", {"code": "006125", "loadout": {"character": "c_ink", "weapon": "w07", "skill": "s16"}, "game_mode": "coop"})
		await command(a, "ready"); await command(b, "ready")
		check(await until(func(): return a.can_play() and b.can_play(), 7), "cooperative_live_campaign_started")
		if a.presentation.size() != 2: finish(); return
		var started = Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 1800 and a.can_play():
			for index in 2:
				var actor = clients[index].presentation[index]
				var frame = Protocol.empty_input()
				var enemy = actor.nearest_enemy(actor.player.pos)
				if not enemy.is_empty(): frame.aim = actor.player.pos.direction_to(enemy.pos); frame.fire = true
				frame.move = Vector2.RIGHT if index == 0 and actor.player.pos.x < 750 else Vector2.ZERO
				clients[index].submit_input(frame)
			await process_frame
		var receipt = await command(a, "pause")
		check(await until(func(): return a.room.get("phase") == "suspended" and b.room.get("phase") == "suspended"), "cooperative_durable_pause")
		var paused_sequence = a.state_sequence
		check(await until(func(): return replica_complete(a, paused_sequence)), "cooperative_paused_scene_datagrams_received")
		expected = {"match": a.room.id, "room": a.room.room, "actors": a.room.actors.duplicate(true), "scene": a.room.scene.duplicate(true),
			"builds": a.room.builds.duplicate(true), "phase": a.room.get("resume_phase"), "receipt": receipt, "input_floor": a.input_serial}
		var file = FileAccess.open(folder.path_join("expected.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(Protocol.Store.encode(expected), "\t", true, true)); file.close()
		a.pending[str(receipt)] = {"op": "pause", "request": receipt}
		check(a.save_preferences(), "cooperative_lost_receipt_saved_locally")
	elif stage == "restore":
		read_expected()
		check(await until(func(): return a.room.get("phase") == "suspended" and b.room.get("phase") == "suspended"), "cooperative_restart_suspended")
		var restored_sequence = a.state_sequence
		check(await until(func(): return replica_complete(a, restored_sequence)), "cooperative_restored_scene_datagrams_received")
		if a.presentation.size() != 2: finish(); return
		check(a.room.id == expected.match and a.room.room == expected.room and a.room.game_mode == "coop", "cooperative_same_room_and_mode")
		var diagnostic = FileAccess.open(folder.path_join("restore-observed.json"), FileAccess.WRITE)
		diagnostic.store_string(JSON.stringify(Protocol.Store.encode({"actors": a.room.actors, "scene": a.room.scene}), "\t", true, true)); diagnostic.close()
		check(identical(a.room.actors, expected.actors), "cooperative_both_full_player_states_restored")
		check(identical(a.room.scene, expected.scene), "cooperative_npcs_drops_obstacles_restored")
		check(identical(a.room.builds, expected.builds), "cooperative_both_growth_histories_restored")
		check(await until(func(): return not a.pending.has(str(int(expected.receipt)))), "cooperative_lost_receipt_idempotent")
		check(a.input_serial >= int(expected.input_floor), "cooperative_input_floor_restored")
		if mode == "expiry":
			var replacement = Session.new(folder.path_join("client-0"))
			root.add_child(replacement)
			replacement.connect_service(url, "Cooperative Recovery 0")
			var transferred = await until(func(): return replacement.state == "room" and a.state == "expired")
			check(transferred, "cooperative_single_live_identity")
			if not transferred: print("TAKEOVER_DIAGNOSTIC old_state=%s new_state=%s old_error=%s new_error=%s old_retries=%d new_retries=%d" % [a.state, replacement.state, a.last_error, replacement.last_error, a.retry_count, replacement.retry_count])
			check(not a.wants_connection, "cooperative_old_client_stops_takeover")
			a.disconnect_service(); clients[0] = replacement; a = replacement
			await command(a, "resume"); await command(b, "resume")
			check(await until(func(): return a.can_play() and b.can_play(), 7), "cooperative_mutual_restart_resume")
			var position = Vector2(a.presentation[0].player.pos)
			await create_timer(.35).timeout
			check(a.presentation[0].player.pos.distance_to(position) < 1, "cooperative_old_held_input_cleared")
			b.disconnect_service()
			check(await until(func(): return a.room.get("phase") == "suspended"), "cooperative_partner_loss_freezes")
			check(await until(func(): return a.room.get("phase") == "finished", 15), "cooperative_grace_expiry_ends_team")
			check(int(a.room.winner) == -1 and a.room.reason == "reconnect_timeout" and int(a.stats.coop_losses) == 1 and int(a.stats.wins) == 0, "cooperative_expiry_is_team_loss_once")
			b.connect_service(url, "Cooperative Recovery 1")
			check(await until(func(): return b.room.get("phase") == "finished"), "cooperative_late_reconnect_sees_result")
			check(not b.can_play() and int(b.stats.coop_losses) == 1, "cooperative_late_client_cannot_reopen_run")
			await command(a, "leave"); await command(b, "leave")
	finish()
