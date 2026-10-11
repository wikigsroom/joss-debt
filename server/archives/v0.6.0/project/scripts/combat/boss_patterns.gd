extends RefCounted
const Pattern = preload("res://scripts/combat/enemy_patterns.gd")

static func sigils(w, boss: Dictionary, count: int, template: String = "e01", clone: bool = false) -> void:
	for i in count:
		var direction = Vector2.RIGHT.rotated(-PI * .1 + i * TAU / count)
		var location = w.geometry.slide(boss.pos, direction * 135, 18)
		var sign = w.spawn_enemy(template, location, false, true)
		if sign.is_empty(): break
		sign.guarding_boss = boss.uid
		sign.clone = clone
		sign.sigil = not clone and template == "e01"
		sign.hp = 54.0 if not clone else 220.0
		sign.max_hp = sign.hp
		sign.speed = 0.0 if not clone else 60.0
		sign.attack_cd = 7.0 if sign.sigil else 1.6
		sign.arrival = w.time + .8
		sign.render_size = 170.0 if clone else (98.0 if sign.sigil else 110.0)
		sign.sprite_id = boss.id if clone else ("sigil" if sign.sigil else template)
		w.emit("summon_warning", {"pos": location, "duration": .8})

static func phase_enter(w, boss: Dictionary, phase: int) -> void:
	if boss.id == "b01" and phase == 2: sigils(w, boss, 3)
	elif boss.id == "b02" and phase == 2:
		sigils(w, boss, 2, "e09")
		boss.shield_layers = 1
	elif boss.id == "b03" and phase == 0: sigils(w, boss, 2, "e20")
	elif boss.id == "b04" and phase == 0: sigils(w, boss, 2, "e17", true)
	elif boss.id == "b05" and phase in [0, 2]: sigils(w, boss, 3)
	if boss.id == "b03" and phase > 0 and w.contract("d09") and int(w.room_flags.get("total_ledger_extra", 0)) < 2:
		w.room_flags.total_ledger_extra = int(w.room_flags.get("total_ledger_extra", 0)) + 1
		sigils(w, boss, 1)

static func attack(w, boss: Dictionary) -> void:
	boss.attack_step = int(boss.get("attack_step", 0)) + 1
	var phase = int(boss.phase)
	var step = int(boss.attack_step)
	boss.attack_cd = 1.8 if phase < 2 else 1.5
	match boss.id:
		"b01":
			if phase == 0:
				for i in 11:
					var angle = -1.55 + i * .31
					if absf(angle) > .2: w.enemy_bullet(boss.pos, boss.aim.rotated(angle), 175, 1, 8, w.source_of(boss, "projectile"))
			elif phase == 1:
				w.add_zone(boss.target, 80, 1.3, 2, false, .9, w.source_of(boss, "zone"))
				w.add_zone(boss.target + Vector2(160 if step % 2 == 0 else -160, 0), 68, 1.3, 2, false, .9, w.source_of(boss, "zone"))
				boss.guard_open = w.time + 1.2
			else:
				Pattern.fan(w, boss, 7, .18, 210, 8)
				if step % 3 == 0 and not w.enemies.any(func(e): return not e.dead and e.get("guarding_boss", -1) == boss.uid): sigils(w, boss, 2)
		"b02":
			if phase == 0:
				Pattern.bead_grid(w, boss)
				boss.guard_open = w.time + 1.0
			elif phase == 1:
				w.add_zone(boss.target, 90, .7, 2, false, 1.0, w.source_of(boss, "zone"))
				Pattern.fan(w, boss, 1, 0, 105, 19)
				boss.guard_open = w.time + 1.0
			else:
				Pattern.fan(w, boss, 5, .28, 190)
				if step % 2 == 0: Pattern.bead_grid(w, boss)
		"b03":
			if phase == 0 or (phase == 2 and step % 3 == 0):
				for x in [320, 940]: Pattern.lane(w, Vector2(x, 140), Vector2(x, 590), 48, 1.0, .8, 2, w.source_of(boss, "zone"))
			elif phase == 1 or (phase == 2 and step % 3 == 1):
				w.add_zone(boss.target, 88, .65, 2, false, 1.1, w.source_of(boss, "zone"))
				w.add_zone(boss.target + Vector2(155 if step % 2 else -155, 0), 66, .65, 1, false, 1.1, w.source_of(boss, "zone"))
			else: Pattern.ring(w, boss, 16, 180)
			boss.guard_open = w.time + 1.2
		"b04":
			if phase == 0: Pattern.fan(w, boss, 5, .24, 170)
			elif phase == 1:
				for enemy in w.enemies:
					if not enemy.dead and enemy.mark > 0: w.add_zone(enemy.pos, 56, .4, 1, false, 1.0, w.source_of(boss, "zone"))
				w.add_zone(boss.target, 72, .4, 1, false, 1.0, w.source_of(boss, "zone"))
			else:
				Pattern.ring(w, boss, 12, 185)
				if step % 3 == 0 and not w.enemies.any(func(e): return not e.dead and e.get("clone", false)): sigils(w, boss, 2, "e17", true)
		"b05":
			if phase == 0:
				Pattern.fan(w, boss, 3, .3, 130, 15)
				w.add_zone(boss.target, 86, .7, 2, false, 1.0, w.source_of(boss, "zone"))
			elif phase == 1:
				for angle in [0.55, -0.55]:
					var direction = Vector2.RIGHT.rotated(angle if step % 2 else angle + PI * .5)
					Pattern.lane(w, boss.pos - direction * 370, boss.pos + direction * 370, 40, 1.0, .7, 2, w.source_of(boss, "zone"))
			else:
				Pattern.ring(w, boss, 14, 160)
				if step % 4 == 0 and not w.enemies.any(func(e): return not e.dead and e.get("guarding_boss", -1) == boss.uid): sigils(w, boss, 3)
	w.emit("boss_attack", {"pos": boss.pos, "phase": phase, "boss": boss.id})

static func hit(w, enemy: Dictionary, source: String) -> void:
	if source != "detonate": return
	if enemy.id == "e20" or (enemy.boss and enemy.id == "b03" and enemy.phase == 1):
		if enemy.windup > 0:
			enemy.windup = 0.0
			enemy.attack_cd = 1.5
			enemy.guard_open = w.time + 1.5
			w.emit("interrupted", {"pos": enemy.pos})
	if enemy.get("clone", false):
		var boss = w.enemy_by_uid(enemy.get("guarding_boss", -1))
		if boss.is_empty(): return
		var key = "clone_hits_" + w.active_pulse
		var hits = w.room_flags.get(key, [])
		if not hits.has(enemy.uid): hits.append(enemy.uid)
		w.room_flags[key] = hits
		if hits.size() >= 2: boss.guard_open = w.time + 1.4

static func guard_destroyed(w, enemy: Dictionary) -> void:
	if not enemy.has("guarding_boss"): return
	var boss = w.enemy_by_uid(enemy.guarding_boss)
	if boss.is_empty() or boss.dead: return
	if boss.id == "b05" and w.enemies.any(func(e): return not e.dead and e.get("guarding_boss", -1) == boss.uid): return
	boss.guard_open = w.time + (1.6 if boss.id == "b05" else (1.4 if boss.id == "b04" else (1.0 if boss.id == "b02" else 1.2)))
	w.add_mark(boss, 1, false)
	w.emit("boss_open", {"pos": boss.pos, "until": boss.guard_open})
