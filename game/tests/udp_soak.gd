extends SceneTree
## Real native sessions, repeated campaigns and transactions; no fake snapshots.
const Session = preload("res://scripts/network/online_session.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const Graph = preload("res://scripts/core/room_graph.gd")
var clients: Array = []
var url = "ws://127.0.0.1:18977"
var seconds = 3600.0
var room_count = 2
var output = ""
var errors: Array = []
var counters = {"states": 0, "sampled_playing_frames": 0, "fresh_playing_frames": 0, "choices": 0, "rematches": 0}
var gaps: Array = []
var latencies: Array = []
var started = 0
var armed = false
var mode = "coop"
var weapons: Array = ["w07", "w14"]
var phase_wait: Dictionary = {}
var issued: Dictionary = {}
var bootstrap_issues: Array = []
var bootstrap_started = 0
var visited_scenes: Dictionary = {}
var fault_context: Array = []
var navigation_cache: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2: continue
		match parts[0]:
			"url": url = parts[1]
			"seconds": seconds = float(parts[1])
			"rooms": room_count = int(parts[1])
			"output": output = parts[1]
			"game-mode": mode = parts[1]
			"weapons": weapons = Array(parts[1].split(",", false))
	call_deferred("run")

func until(predicate: Callable, timeout: float = 20) -> bool:
	var begin = Time.get_ticks_msec()
	while Time.get_ticks_msec() - begin < timeout * 1000:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func run() -> void:
	if output.is_empty(): quit(1); return
	var directory = output.get_basename() + "-private"
	bootstrap_started = Time.get_ticks_msec()
	for index in room_count * 2:
		var client = Session.new(directory.path_join("client%d" % index))
		client.loadout = {"character": "c_mask", "weapon": weapons[index % weapons.size()], "skill": "s10"}
		client.problem.connect(func(code): errors.append(code); print("SOAK_PROBLEM ", code, " state=", client.state, " phase=", client.room.get("phase"), " age=", client.now() - client.last_state_received, " baseline=", client.stream_codec.revision, " rejected=", client.stream_codec.rejected_baselines))
		client.state_received.connect(func(_state): counters.states += 1)
		root.add_child(client); clients.append(client)
		client.connect_service(url, "原生负载%d" % index)
	if not await until(func(): return clients.all(func(client): return client.state == "online"), 30):
		errors.append("authentication_deadline"); finish(); return
	var base = 300000 + randi() % 200000
	for index in clients.size():
		clients[index].request("code", {"code": "%06d" % (base + int(index / 2)), "loadout": clients[index].loadout, "game_mode": mode})
	if not await until(func(): return clients.all(func(client): return client.room.get("players", []).size() == 2)):
		errors.append("pairing_deadline"); finish(); return
	for client in clients: client.request("ready")
	if not await until(func(): return clients.all(func(client): return client.can_play())):
		errors.append("combat_deadline"); finish(); return
	bootstrap_issues = errors.duplicate(); errors.clear()
	started = Time.get_ticks_msec(); armed = true
	while Time.get_ticks_msec() - started < seconds * 1000 and errors.is_empty():
		for client in clients:
			if client.room.get("phase") == "playing":
				gaps.append((client.now() - client.last_state_received) * 1000)
				latencies.append(client.latency_ms)
			while gaps.size() > 20000: gaps.pop_front()
		while latencies.size() > 20000: latencies.pop_front()
		await create_timer(.25).timeout
	armed = false
	for client in clients:
		if not client.room.is_empty(): client.request("leave")
	await until(func(): return clients.all(func(client): return client.pending.is_empty()), 10)
	finish()

func _process(_delta: float) -> bool:
	if not armed: return false
	var now = Time.get_ticks_msec() / 1000.0
	for index in clients.size():
		var client = clients[index]
		if client.room.get("phase") == "playing": phase_wait[index] = now
		elif now - float(phase_wait.get(index, now)) > 25:
			errors.append("bot_phase_stalled/" + str(client.room.get("phase", "")))
		match client.room.get("phase"):
			"draft":
				var mate = clients[index - 1 if index % 2 == 1 else index + 1]
				# Shop prices use the shared wallet. Serialize the bot's purchases
				# and wait for both absolute wallet views, like a player reading the
				# updated offer. A raced, unaffordable purchase is correctly rejected.
				if not mate.pending.is_empty(): continue
				if index % 2 == 1 and mate.room.get("choice_mode") in ["choice", "shop", "debt", "replace"]: continue
				if client.room.get("actors", []).size() != 2 or mate.room.get("actors", []).size() != 2: continue
				if int(client.room.actors[0].run.coins) != int(mate.room.actors[0].run.coins): continue
				if client.pending.is_empty():
					if mode == "coop" and client.room.get("choice_mode") in ["choice", "shop", "debt"] and not client.room.get("offers", []).is_empty():
						var token = "%d/" % index + str(client.room.choice_token)
						if not issued.has(token):
							var offers: Array = client.room.offers
							var usable = offers.find_custom(func(offer): return str(offer.get("reason", "")).is_empty())
							issued[token] = true
							if usable >= 0: client.request("choose", {"index": usable, "choice_token": client.room.choice_token})
							else: client.request("cooperative_action", {"action": "skip", "choice_token": client.room.choice_token})
							counters.choices += 1
					elif mode == "duel" and int(client.room.picked[int(client.room.seat)]) < 0:
						client.request("choose", {"index": index % 4}); counters.choices += 1
					elif mode == "coop" and client.room.get("choice_mode") in ["choice", "shop", "debt", "replace"]:
						var token = "%d/" % index + str(client.room.choice_token)
						if not issued.has(token):
							issued[token] = true
							var operation = "replace" if client.room.get("choice_mode") == "replace" else "skip"
							var relics: Dictionary = client.room.actors[int(client.room.seat)].run.relics
							var value = str(relics.keys()[0]) if operation == "replace" and not relics.is_empty() else ""
							client.request("cooperative_action", {"action": operation, "value": value, "choice_token": client.room.choice_token})
			"finished":
				if client.pending.is_empty() and not client.room.get("rematch_ready", [false, false])[int(client.room.seat)]:
					var token = "%d/rematch/" % index + str(client.room.id)
					if not issued.has(token):
						issued[token] = true
						client.request("rematch"); counters.rematches += 1
			"suspended":
				if errors.is_empty():
					fault_context = clients.map(func(peer): return {"phase": peer.room.get("phase"), "scene_ready": peer.stream_codec.scene_ready, "age_ms": (peer.now() - peer.last_state_received) * 1000, "core": peer.stream_codec.core_sequence, "scene_revision": peer.stream_codec.scene_revision, "pending_core": not peer.stream_codec.pending_core.is_empty(), "input_serial": peer.input_serial, "input_ack": peer.room.get("input_ack"), "enet": enet_statistics(peer)})
					errors.append("unexpected_suspension/" + str(client.room.get("suspend_reason", "")))
			"playing":
				counters.sampled_playing_frames += 1
				if not client.can_play(): continue
				counters.fresh_playing_frames += 1
				var own = client.presentation[int(client.room.seat)]
				var other = client.presentation[1 - int(client.room.seat)]
				visited_scenes[str(client.room.id) + "/" + str(own.run.floor) + "/" + str(own.run.room)] = true
				var frame = Protocol.empty_input()
				var target = own.nearest_enemy(own.player.pos) if mode == "coop" else {"pos": other.player.pos}
				frame.move = Vector2(sin(now * .8 + index), cos(now * .7 + index))
				frame.aim = own.player.pos.direction_to(target.pos) if not target.is_empty() else Vector2.RIGHT
				frame.fire = fmod(now, 1.5) < 1.25
				frame.dash = own.player.dash_cd <= 0
				frame.skill = own.player.skill_cd <= 0
				if mode == "coop" and not target.is_empty():
					var reach = float(own.db.row("weapons", own.player.weapon).range)
					var distance = own.player.pos.distance_to(target.pos)
					if distance > reach * .72 or not own.geometry.clear_segment(own.player.pos, target.pos): frame.move = toward(index, own, target.pos, now)
					elif distance < minf(150, reach * .4): frame.move = -frame.aim
					else: frame.move = frame.aim.orthogonal() * (.7 if index % 2 == 0 else -.7)
				if mode == "coop" and own.mode == "clear":
					var doors = own.room_doors()
					if not doors.is_empty():
						var door = route_door(own, doors)
						frame.move = toward(index, own, door.pos, now)
				elif mode == "coop" and own.mode == "checkpoint":
					frame.move = toward(index, own, own.room_door_position("north"), now)
				if mode == "coop" and other.player.get("downed", false):
					frame.move = own.player.pos.direction_to(other.player.pos)
					frame.interact = own.player.pos.distance_to(other.player.pos) < 65
				client.submit_input(frame)
	return false

func toward(index: int, actor, target: Vector2, now: float) -> Vector2:
	var cached: Dictionary = navigation_cache.get(index, {})
	if cached.get("actor") != actor.get_instance_id() or cached.get("scene") != actor.online_scene or now >= float(cached.get("until", 0)):
		actor.geometry.rebuild_flow(target)
		navigation_cache[index] = {"actor": actor.get_instance_id(), "scene": actor.online_scene, "until": now + .35}
	return actor.geometry.toward(actor.player.pos, target)

func route_door(own, doors: Array) -> Dictionary:
	# Follow the authored graph through cleared rooms to the nearest unexplored
	# visible room. A first-exit bot otherwise bounces between visited branches.
	var current = int(own.run.room)
	var queue: Array = [{"room": current, "first": -1}]
	var seen: Dictionary = {current: true}
	while not queue.is_empty():
		var node: Dictionary = queue.pop_front()
		if node.room != current and not own.run.visited.has(node.room):
			var index = doors.find_custom(func(door): return int(door.destination) == int(node.first))
			if index >= 0: return doors[index]
		for edge in own.run.graph.edges:
			if not edge.has(node.room): continue
			var destination = int(edge[1] if int(edge[0]) == int(node.room) else edge[0])
			if seen.has(destination) or not Graph.visible(own.run.graph, destination): continue
			var first = destination if int(node.first) < 0 else int(node.first)
			if node.room == current and not doors.any(func(door): return int(door.destination) == destination): continue
			seen[destination] = true
			queue.append({"room": destination, "first": first})
	return doors[0]

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0
	var sorted = values.duplicate(); sorted.sort()
	return float(sorted[mini(sorted.size() - 1, ceili(sorted.size() * fraction) - 1)])

func enet_statistics(client) -> Dictionary:
	if not client.battle.connected(): return {}
	var peer = client.battle.remote
	return {"round_trip_ms": peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), "rtt_variance": peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE), "throttle": peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), "throttle_limit": peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT), "packet_loss_raw": peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)}

func finish() -> void:
	armed = false
	var elapsed = (Time.get_ticks_msec() - started) / 1000.0 if started > 0 else 0.0
	var fresh = float(counters.fresh_playing_frames) / maxi(1, counters.sampled_playing_frames)
	# A transient transport reconnect during bootstrap is still visible to the
	# player and must fail acceptance even when the later session recovered.
	var passed = errors.is_empty() and bootstrap_issues.is_empty() and elapsed >= seconds and fresh >= .995
	var report = {"passed": passed, "rooms": room_count, "clients": clients.size(), "game_mode": mode, "battle_seconds": elapsed,
		"fault_context": fault_context,
		"weapons": weapons, "counters": counters, "fresh_playable_frame_ratio": fresh, "errors": errors,
		"state_age_p95_ms": percentile(gaps, .95), "ping_p95_ms": percentile(latencies, .95),
		"bootstrap_issues": bootstrap_issues, "bootstrap_seconds": (started - bootstrap_started) / 1000.0 if started > 0 else (Time.get_ticks_msec() - bootstrap_started) / 1000.0,
		"distinct_campaign_scenes": visited_scenes.size(),
		"scope": "Native production Session and authoritative repeated real campaigns. No rendering/WAN/Android acceptance. Age samples are a bounded rolling window."}
	report.client_streams = clients.map(func(client): return {"state": client.state, "phase": client.room.get("phase"), "last_error": client.last_error,
		"core": client.stream_codec.core_sequence, "revision": client.stream_codec.revision, "pending_revision": client.stream_codec.pending_core.decode_u32(10) if client.stream_codec.pending_core.size() > 14 else 0,
		"partial_baseline_parts": client.stream_codec.parts.size(), "partial_baseline_revision": client.stream_codec.part_revision,
		"received_datagrams": client.state_datagrams_received, "ignored_messages": client.ignored_state_messages, "accepted_cores": client.snapshot_serial,
		"rejected_baselines": client.stream_codec.rejected_baselines,
		"scene_ready": client.stream_codec.scene_ready, "bound": client.battle_bound, "transport_rebinds": client.battle_rebinds,
		"native_connected": client.battle.connected(), "edge_rejected": client.battle.edge.rejected,
		"wire_received": client.battle.edge.bytes_received, "wire_sent": client.battle.edge.bytes_sent,
		"inventory_sizes": client.stream_codec.inventories.keys().map(func(key): return [key, client.stream_codec.inventories[key].alive.size(), client.stream_codec.entities.get(key, {}).size()])})
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	for client in clients: client.disconnect_service()
	print("UDP_SOAK_RESULT ", JSON.stringify(report))
	quit(0 if passed else 1)
