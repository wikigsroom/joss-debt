extends RefCounted
## Explicit v1 -> v2 conversion. Stable content IDs survive; unknown IDs are never guessed.
const Content = preload("res://scripts/core/content_db.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Damage = preload("res://scripts/core/damage_record.gd")
const Impact = preload("res://scripts/combat/impact_control.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const PROFILE_VERSION = 2
const RUN_VERSION = 2

static func failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func content_version() -> String:
	return str(Content.new().catalog.version)

static func fields(value: Dictionary, numbers: Array = [], vectors: Array = [], arrays: Array = [], dictionaries: Array = [], texts: Array = [], flags: Array = []) -> bool:
	for key in numbers:
		if not Store.number(value.get(key)): return false
	for key in vectors:
		if not value.get(key) is Vector2: return false
	for key in arrays:
		if not value.get(key) is Array: return false
	for key in dictionaries:
		if not value.get(key) is Dictionary: return false
	for key in texts:
		if not value.get(key) is String: return false
	for key in flags:
		if not value.get(key) is bool: return false
	return true

static func ids(values: Array, kind: String, db, unique: bool = true) -> bool:
	var seen: Dictionary = {}
	for id in values:
		if not id is String or db.row(kind, id).is_empty() or (unique and seen.has(id)): return false
		seen[id] = true
	return true

static func profile(source: Dictionary) -> Dictionary:
	if not Store.valid_tree(source, 0, [200000]): return failure("愿簿内容损坏，原档案已保留。")
	var version = source.get("version", 1)
	if not Store.integer(version) or int(version) not in [1, PROFILE_VERSION]: return failure("这份愿簿来自其他存档版本，请使用相应版本的游戏。")
	var db = Content.new()
	if source.has("content_version") and source.content_version != db.catalog.version: return failure("这份愿簿的内容版本尚不兼容，请保留原文件。")
	var data = source.duplicate(true)
	var defaults = {"version": PROFILE_VERSION, "content_version": db.catalog.version, "merit": 0, "unlocks": [], "characters": ["c_paper"], "bosses": [],
		"route_pairs": [], "endings": [], "runs": {}, "repayments": 0, "defenses": 0,
		"personal": {}, "seen": {"enemies": [], "bosses": [], "relics": [], "weapons": []},
		"settings": {}, "loadouts": {}, "wish_name": "无名之愿", "read_story_ids": [], "repaid_ids": [], "name_pages": 0, "name_page_ids": [], "interest_page": false,
		"achievements": [], "achievement_stats": {"runs": 0, "victories": 0, "character_victories": {}, "endings": [], "routes": [], "bosses": [], "relics": 0, "character_stats": {}}}
	for key in defaults:
		if not data.has(key): data[key] = defaults[key]
	if not fields(data, ["merit", "repayments", "defenses", "name_pages"], [], ["unlocks", "characters", "bosses", "route_pairs", "endings", "read_story_ids", "repaid_ids", "name_page_ids", "achievements"], ["runs", "personal", "seen", "settings", "loadouts", "achievement_stats"], ["wish_name"], ["interest_page"]): return failure("愿簿字段不完整，原档案已保留。")
	var achievement_defaults = defaults.achievement_stats
	for key in achievement_defaults:
		if not data.achievement_stats.has(key): data.achievement_stats[key] = achievement_defaults[key].duplicate(true) if achievement_defaults[key] is Dictionary else achievement_defaults[key]
	if not data.achievements.all(func(id): return id is String and not db.achievement_row(id).is_empty()): return failure("愿簿包含无法识别的成就。")
	var achievement_seen: Dictionary = {}
	for achievement_id in data.achievements:
		if achievement_seen.has(achievement_id): return failure("愿簿成就记录重复。")
		achievement_seen[achievement_id] = true
	var achievement_numbers = ["runs", "victories", "relics"]
	if not achievement_numbers.all(func(key): return Store.number(data.achievement_stats.get(key)) and data.achievement_stats[key] >= 0): return failure("成就统计损坏。")
	for key in ["endings", "routes", "bosses"]:
		if not data.achievement_stats[key] is Array or not data.achievement_stats[key].all(func(id): return id is String): return failure("成就统计损坏。")
	for character in data.achievement_stats.character_victories:
		if db.row("characters", character).is_empty() or not Store.number(data.achievement_stats.character_victories[character]) or data.achievement_stats.character_victories[character] < 0: return failure("角色成就统计损坏。")
	for character in data.achievement_stats.character_stats:
		if db.row("characters", character).is_empty() or not data.achievement_stats.character_stats[character] is Dictionary: return failure("角色成就统计损坏。")
		var character_stats = data.achievement_stats.character_stats[character]
		for key in ["runs", "victories", "detonations", "max_chain", "kills", "defenses", "ash_energy", "hits", "routes", "personal_stage"]:
			if not Store.number(character_stats.get(key, 0)) or character_stats.get(key, 0) < 0: return failure("角色成就统计损坏。")
		if not character_stats.get("route_ids", []) is Array or not character_stats.route_ids.all(func(id): return id is String): return failure("角色路线成就统计损坏。")
	for key in ["merit", "repayments", "defenses", "name_pages"]:
		if data[key] < 0 or data[key] > 1e9: return failure("愿簿计数超出可恢复范围。")
	for pair in [["unlocks", "meta_unlocks"], ["characters", "characters"], ["bosses", "bosses"], ["repaid_ids", "debt_contracts"]]:
		if not ids(data[pair[0]], pair[1], db): return failure("愿簿包含本版本无法识别的内容，请保留原文件。")
	if not data.characters.has("c_paper"): return failure("愿簿缺少初始还愿人。")
	for id in data.endings:
		if id not in ["burn", "repay", "rewrite"]: return failure("愿簿结局记录无效。")
	for key in data.runs:
		if not data.runs[key] is Dictionary: return failure("还愿结算账本损坏。")
		for count in ["merit", "defenses", "repayments", "name_pages", "bonus_merit"]:
			if data.runs[key].has(count) and (not Store.number(data.runs[key][count]) or data.runs[key][count] < 0): return failure("还愿结算账本损坏。")
		if data.runs[key].has("bosses") and (not data.runs[key].bosses is Array or not ids(data.runs[key].bosses, "bosses", db)): return failure("首领结算账本损坏。")
		for pair in [["characters_unlocked", "characters"], ["new_bosses", "bosses"]]:
			if data.runs[key].has(pair[0]) and (not data.runs[key][pair[0]] is Array or not ids(data.runs[key][pair[0]], pair[1], db)): return failure("本局新页账本损坏。")
		if data.runs[key].has("personal_pages"):
			var pages = data.runs[key].personal_pages
			if not pages is Array or pages.size() > 3: return failure("本局个人页账本损坏。")
			var seen_pages: Dictionary = {}
			for page in pages:
				if not Store.integer(page) or int(page) not in [1, 2, 3] or seen_pages.has(int(page)): return failure("本局个人页账本损坏。")
				seen_pages[int(page)] = true
			data.runs[key].personal_pages = pages.map(func(page): return int(page))
	for id in data.personal:
		if db.row("characters", id).is_empty(): return failure("个人愿页属于无法识别的还愿人。")
	for character in db.rows("characters"):
		if not data.personal.has(character.id): data.personal[character.id] = {"stage": 0, "progress": 0, "cross": false, "final": false}
		var page = data.personal[character.id]
		if not page is Dictionary or not fields(page, ["stage", "progress"], [], [], [], [], ["cross", "final"]) or page.stage < 0 or page.stage > 3 or page.progress < 0: return failure("个人愿页进度损坏。")
	for kind in ["enemies", "bosses", "relics", "weapons"]:
		if not data.seen.has(kind): data.seen[kind] = []
		if not data.seen[kind] is Array or not ids(data.seen[kind], kind, db): return failure("图鉴包含无法识别的内容。")
	for character in data.loadouts:
		if db.row("characters", character).is_empty() or not data.loadouts[character] is String or db.row("weapons", data.loadouts[character]).is_empty(): return failure("初始器具记录无效。")
	if not valid_settings(data.settings): return failure("操作或声音设置损坏，原档案已保留。")
	data.version = PROFILE_VERSION
	data.content_version = db.catalog.version
	return {"ok": true, "data": data, "migrated": int(version) == 1 and not source.is_empty()}

static func world(source: Dictionary) -> Dictionary:
	if source.is_empty(): return {"ok": true, "data": {}, "migrated": false}
	if not Store.valid_tree(source, 0, [200000]): return failure("当前还愿内容损坏，原档案已保留。")
	if not Store.integer(source.get("version")) or int(source.version) not in [1, RUN_VERSION]: return failure("当前还愿来自其他存档版本，请使用相应游戏版本。")
	var db = Content.new()
	if source.has("content_version") and source.content_version != db.catalog.version: return failure("当前还愿的内容版本尚不兼容。")
	var data = source.duplicate(true)
	if not fields(data, ["rng", "time", "uid", "attack_uid"], [], [], ["run", "player"], ["mode", "template"]): return failure("当前还愿缺少完整快照。")
	var run: Dictionary = data.run
	var player: Dictionary = data.player
	if not fields(run, ["seed", "floor", "floor_limit", "room", "coins", "xp", "level", "merit", "heal_misses", "cleared", "rerolls"], [], ["talents", "contracts", "consumed", "repayments", "room_plan"], ["relics"], ["id", "character", "result"]): return failure("还愿路线或库存损坏。")
	if not run.has("growth_log"): run.growth_log = []
	if not run.has("special_rooms"): run.special_rooms = {}
	if not run.has("daily"): run.daily = false
	if not run.has("daily_key"): run.daily_key = ""
	if not run.has("daily_pool_version"): run.daily_pool_version = ""
	if not run.growth_log is Array or run.growth_log.size() > 256 or not run.special_rooms is Dictionary: return failure("特殊房间成长记录损坏。")
	if not run.daily is bool or not run.daily_key is String or not run.daily_pool_version is String: return failure("每日挑战标识损坏。")
	if run.daily and (run.daily_key.length() != 10 or run.daily_pool_version.is_empty()): return failure("每日挑战版本无法恢复。")
	if not run.has("damage_history"): run.damage_history = []
	if not run.has("death_cause"): run.death_cause = {}
	if not run.damage_history is Array or run.damage_history.size() > 12 or not run.damage_history.all(func(hit): return Damage.valid_record(hit, db)): return failure("受击记录损坏，原档案已保留。")
	if not run.death_cause is Dictionary or (not run.death_cause.is_empty() and (not Damage.valid_record(run.death_cause, db) or not run.death_cause.lethal)): return failure("最后一击记录损坏，原档案已保留。")
	if db.row("characters", run.character).is_empty() or run.floor < 1 or run.floor > 11 or run.floor_limit < run.floor or run.floor_limit > 11 or run.room < 0 or run.room >= run.room_plan.size(): return failure("还愿所在章节无法恢复。")
	if run.get("campaign", false) and (not Seed.valid(str(run.get("seed_text", ""))) or int(run.seed) != str(run.seed_text).to_int() or run.get("random_version", "") != Seed.VERSION): return failure("派生种子记录损坏或来自其他版本。")
	if data.mode not in ["combat", "clear", "choice", "shop", "debt", "checkpoint", "replace", "result", "transition", "epilogue"]: return failure("当前还愿状态无效。")
	if data.mode == "transition" and (not run.get("transition") is Dictionary or not fields(run.transition, ["to_floor", "cursor"]) or int(run.transition.to_floor) != int(run.floor) + 1 or run.transition.to_floor > 11): return failure("层间过场记录损坏。")
	if data.rng < 1 or data.rng >= 2147483647 or data.time < 0 or data.uid < 0 or data.attack_uid < 0: return failure("还愿随机流或时间记录无效。")
	if not fields(player, ["hp", "max_hp", "energy", "shot_cd", "skill_cd", "dash_cd", "dash_left", "invulnerable", "guard", "armor", "still", "passive_cd", "passive_hits", "charge", "attack_bonus", "attack_bonus_until"], ["pos", "aim", "move", "dash_dir"], [], [], ["weapon", "skill"]): return failure("还愿人状态损坏。")
	if db.row("weapons", player.weapon).is_empty() or db.row("skills", player.skill).is_empty() or player.max_hp < 1 or player.hp > player.max_hp or player.hp < 0 or player.energy < 0 or player.energy > 100: return failure("当前器具、焚债或心火无法恢复。")
	for id in run.relics:
		var row = db.row("relics", id)
		if row.is_empty() or not Store.number(run.relics[id]) or run.relics[id] < 1 or run.relics[id] > row.stack_limit: return failure("供物库存无法恢复。")
	for pair in [["talents", "talents"], ["consumed", "relics"], ["repayments", "debt_contracts"]]:
		if not ids(run[pair[0]], pair[1], db): return failure("成长或债约包含未知内容。")
	for debt in run.contracts:
		if not debt is Dictionary or not fields(debt, ["interest"], [], [], [], ["id"]) or db.row("debt_contracts", debt.id).is_empty(): return failure("债约记录损坏。")
	var arrays = ["enemies", "bullets", "pickups", "zones", "delayed", "chains", "choices", "choice_queue"]
	for key in arrays:
		if not data.has(key): data[key] = []
		if not data[key] is Array: return failure("还愿快照中的%s记录损坏。" % key)
	for key in ["streams", "enemy_ledger", "reward_ledger", "pair_cooldowns", "room_flags", "stats", "proc_ledger"]:
		if not data.has(key): data[key] = {}
		if not data[key] is Dictionary: return failure("还愿账本%s损坏。" % key)
	var flag_defaults = {"combat_kills": 0, "dash_armor": 0, "passive_detonate": false, "summoned": 0, "summon_rewards": 0, "chain_pairs": {}, "forced_links": {}}
	for key in flag_defaults:
		if not data.room_flags.has(key): data.room_flags[key] = flag_defaults[key]
	if not valid_flags(data.room_flags, db): return failure("房间或阵次状态损坏。")
	for pulse in data.proc_ledger.values():
		if not pulse is Dictionary or not fields(pulse, ["used", "expires"]): return failure("派生效果账本损坏。")
	for key in ["favors_used", "replacement", "room_history", "legacy_boss_health"]:
		if run.has(key) and not run[key] is Dictionary: return failure("还愿房间记录损坏。")
	for room in run.get("legacy_boss_health",{}):
		var carried = run.legacy_boss_health[room]
		if not str(room).is_valid_int() or int(room)<0 or int(room)>=run.room_plan.size() or not carried is Dictionary or not fields(carried,["hp","max_hp"],[],[],[],["id"]) or db.row("bosses",carried.id).is_empty() or carried.hp<=0 or carried.hp>carried.max_hp: return failure("迁移首领的生命记录损坏，原档案已保留。")
	if run.get("replacement", {}).size() > 0:
		var replacement = run.replacement
		if not fields(replacement, ["index"], [], [], ["choice"], ["return_mode"]) or not validate_choice(replacement.choice, db): return failure("待替换供物记录损坏。")
	for history in run.get("room_history", {}).values():
		if not history is Dictionary or not fields(history, [], [], ["pickups"], ["flags"], ["template"]) or not history.pickups.all(valid_pickup) or not valid_flags(history.flags, db): return failure("已行房间记录损坏。")
	for key in ["visited", "name_page_ids", "optional_bosses", "relic_pool"]:
		if run.has(key) and not run[key] is Array: return failure("还愿路线记录损坏。")
	if run.has("optional_bosses") and not ids(run.optional_bosses, "bosses", db): return failure("可选首领记录损坏。")
	if run.has("relic_pool") and not ids(run.relic_pool, "relics", db): return failure("掉落池记录损坏。")
	for state in data.streams.values():
		if not Store.number(state) or state < 1 or state >= 2147483647: return failure("独立随机流记录损坏。")
	for key in ["shots", "hits", "kills", "detonations", "max_chain", "dodges", "damage_taken", "ash_energy", "secondary_hits", "elapsed"]:
		if not data.stats.has(key): data.stats[key] = 0
		if not Store.number(data.stats[key]): return failure("还愿统计损坏。")
	for enemy in data.enemies:
		if not enemy is Dictionary or not fields(enemy, ["uid", "hp", "max_hp", "radius", "speed", "damage", "mark", "mark_until", "mark_energy_at", "burn", "burn_until", "burn_next", "hit_flash", "primary_hits", "attack_cd", "windup", "tell", "lunge", "slow_until", "first_fire_at", "phase", "guard_open", "shield_layers", "stun_until", "burn_ticks"], ["pos", "aim", "target"], [], ["attack_history"], ["id"], ["elite", "boss", "summoned", "natural_reward", "dead"]): return failure("恶愿或首领状态不完整。")
		if db.row("bosses" if enemy.boss else "enemies", enemy.id).is_empty() or enemy.phase < 0 or enemy.phase > 2: return failure("恶愿或首领身份无法识别。")
		if not Impact.valid_state(enemy, db.rules.combat.control): return failure("恶愿击退状态损坏。")
	for bullet in data.bullets:
		if not bullet is Dictionary or not fields(bullet, ["uid", "speed", "range", "travel", "damage", "radius"], ["pos", "dir"], [], [], [], ["friendly"]): return failure("弹道记录损坏。")
		# Early v2 ash fragments never target a chain member; recover that omitted default.
		if bullet.friendly and bullet.get("mode", "") == "ash" and bullet.get("primary", true) == false and not bullet.has("target_index"):
			bullet.target_index = 0
		if bullet.has("source") and not Damage.valid_source(bullet.source, db): return failure("弹道来源无法识别。")
		if bullet.has("push_distance") and (not Store.number(bullet.push_distance) or bullet.push_distance < 0 or bullet.push_distance > db.rules.combat.control.push_distance_cap): return failure("弹道击退记录损坏。")
		if bullet.friendly and not fields(bullet, ["attack", "pierce", "bounces", "age", "target_index"], [], ["hits"], [], ["mode"], ["primary", "crit", "returning", "can_return"]): return failure("主攻弹道记录损坏。")
	for pickup in data.pickups:
		if not valid_pickup(pickup): return failure("掉落物记录损坏。")
	for zone in data.zones:
		if zone is Dictionary and zone.has("source") and not Damage.valid_source(zone.source, db): return failure("印区来源无法识别。")
		if not zone is Dictionary or not fields(zone, ["uid", "radius", "until", "active", "next", "damage"], ["pos"], [], [], [], ["friendly"]): return failure("持续场域记录损坏。")
		if zone.get("shape", "") == "line" and not fields(zone, ["width"], ["from", "to"]): return failure("债线范围记录损坏。")
	for group in data.chains:
		if not group is Array or not group.all(Store.number): return failure("连债目标记录损坏。")
	for action in data.delayed:
		if not action is Dictionary or not fields(action, ["time"], [], [], [], ["type"]): return failure("延迟效果记录损坏。")
		if action.time < 0 or (action.has("pulse") and not action.pulse is String): return failure("延迟效果时钟损坏。")
		if action.type == "expanded_area":
			if not fields(action, ["radius", "damage"], ["pos"], [], [], ["style"]) or action.radius < 0 or action.radius > 420 or action.damage < 0: return failure("场域爆发记录损坏。")
		elif action.type == "expanded_burst":
			if not fields(action, ["damage", "attack"], ["pos", "dir"], [], [], ["weapon"], ["crit", "last"]) or db.row("weapons", action.weapon).is_empty(): return failure("器具连发记录损坏。")
		elif action.type == "fixed_damage":
			if not fields(action, ["radius", "damage"], ["pos"]): return failure("延迟爆发范围损坏。")
		elif action.type == "fixed_target":
			if not fields(action, ["target", "damage"]): return failure("延迟目标记录损坏。")
		elif action.type in ["skill_first", "skill_replay", "guard_counter"]:
			if not fields(action, [], [], ["items"]): return failure("焚债快照记录损坏。")
			if action.has("factor") and (not Store.number(action.factor) or action.factor < 0): return failure("焚债重演系数损坏。")
			for item in action.items:
				if not item is Dictionary or not fields(item, ["uid", "damage", "marks", "burn", "chain_index", "group_uid"], ["pos"]): return failure("焚债目标快照损坏。")
		elif action.type == "repeat_attack":
			if not fields(action, ["damage"], ["pos", "aim"], [], [], ["weapon"]) or db.row("weapons", action.weapon).is_empty() or action.damage <= 0: return failure("器具重演记录损坏。")
		elif action.type == "enemy_fan":
			if not fields(action, ["uid", "count", "spread", "speed"]) or not Store.integer(action.uid) or action.uid < 1 or not Store.integer(action.count) or action.count < 1 or action.count > 32 or action.spread < 0 or action.spread > PI or action.speed <= 0 or action.speed > 2000: return failure("恶愿延期弹记录损坏。")
			for key in ["pos", "aim"]:
				if action.has(key) and not action[key] is Vector2: return failure("恶愿延期弹位置损坏。")
		elif action.type == "enemy_lunge":
			if not fields(action, ["uid"]) or not Store.integer(action.uid) or action.uid < 1: return failure("恶愿延期冲撞记录损坏。")
		elif action.type == "debt_bullet":
			if not fields(action, [], ["pos", "aim"], ["pair"]) or action.pair.size() != 2 or not action.pair.all(Store.integer) or action.pair[0] < 1 or action.pair[1] < 1 or action.pair[0] == action.pair[1]: return failure("债约延期弹记录损坏。")
		else: return failure("延迟效果无法识别。")
	for choice in data.choices:
		var result = validate_choice(choice, db)
		if not result: return failure("奖励候选包含损坏或未知内容。")
	for object in data.get("scenery", []):
		if not valid_scenery(object, db): return failure("动态障碍记录损坏。")
	for history in run.get("room_history", {}).values():
		if not history.get("objects", []) is Array or not history.get("objects", []).all(func(object): return valid_scenery(object, db)): return failure("已行障碍记录损坏。")
	for queued in data.choice_queue:
		if not queued is Dictionary or not fields(queued, [], [], ["items"], [], ["kind"]) or queued.kind not in ["talent", "relic", "floor_end"] or not queued.items.all(func(c): return validate_choice(c, db)): return failure("待领取奖励记录损坏。")
	if run.has("graph"):
		var graph = run.graph
		if not graph is Dictionary or not fields(graph, [], [], ["types", "coords", "edges"]) or graph.types.size() != graph.coords.size() or run.room >= graph.types.size(): return failure("行路图损坏。")
		if graph.has("guest_biome"):
			if not graph.guest_biome is String or graph.guest_biome==graph.get("biome","") or not db.expansion.biomes.any(func(row): return row.id==graph.guest_biome): return failure("外来主题记录损坏。")
		if graph.has("encounter_mix") and (not Store.number(graph.encounter_mix) or not is_equal_approx(float(graph.encounter_mix),.4)): return failure("怪物混编比例记录损坏。")
		for point in graph.coords:
			if not point is Vector2: return failure("行路图坐标损坏。")
		for edge in graph.edges:
			if not edge is Array or edge.size() != 2 or not edge.all(Store.number) or edge.any(func(v): return v < 0 or v >= graph.types.size()): return failure("行路图连接损坏。")
		for ids_value in graph.get("boss_assignments", {}).values():
			if not ids_value is Array or ids_value.size() not in [1, 2] or not ids(ids_value, "bosses", db): return failure("首领房组合损坏。")
		if graph.has("secret_entries"):
			if not graph.secret_entries is Array: return failure("断绳入口记录损坏。")
			for entry in graph.secret_entries:
				if not entry is Dictionary or not fields(entry, ["parent", "room", "side"], ["pos"]) or entry.parent < 0 or entry.room < 0 or entry.parent >= graph.types.size() or entry.room >= graph.types.size(): return failure("断绳入口记录损坏。")
		if graph.has("revealed") and (not graph.revealed is Array or not graph.revealed.all(Store.integer)): return failure("断绳显露记录损坏。")
	data.version = RUN_VERSION
	data.content_version = db.catalog.version
	return {"ok": true, "data": data, "migrated": int(source.version) == 1}

static func valid_scenery(object, db) -> bool:
	return object is Dictionary and fields(object, ["hp", "phase", "hit_until", "fuse_until", "group"], ["pos", "cell"], [], [], ["kind", "key"], ["alive", "solid"]) and not db.row("obstacles", object.kind).is_empty() and object.pos.is_finite() and object.cell.x >= 0 and object.cell.x < 18 and object.cell.y >= 0 and object.cell.y < 9

static func validate_choice(choice, db) -> bool:
	if not choice is Dictionary or not fields(choice, ["price"], [], [], [], ["kind", "id"]): return false
	var kinds = {"relic": "relics", "weapon": "weapons", "talent": "talents", "contract": "debt_contracts", "skill": "skills"}
	if kinds.has(choice.kind): return not db.row(kinds[choice.kind], choice.id).is_empty()
	if choice.kind in ["sacrifice", "judgment", "blessing"]:
		if not fields(choice, ["hp_cost"], [], [], [], ["reward_kind"]): return false
		if choice.hp_cost < 0 or choice.hp_cost > 12 or choice.reward_kind not in ["relic", "weapon", "max_hp", "heal", "talent"]: return false
		if choice.reward_kind in ["relic", "weapon", "talent"]:
			var table = {"relic": "relics", "weapon": "weapons", "talent": "talents"}[choice.reward_kind]
			return not db.row(table, choice.id).is_empty()
		return choice.id in ["max_hp", "heal"]
	return choice.kind == "heal" or (choice.kind == "event" and choice.id in ["remember", "interest", "rest"])

static func valid_pickup(pickup) -> bool:
	return pickup is Dictionary and fields(pickup, ["uid", "value", "delay"], ["pos"], [], [], ["kind"], ["natural", "magnet"]) and pickup.kind in ["coin", "ash", "heal"]

static func valid_flags(flags: Dictionary, db) -> bool:
	for key in ["combat_kills", "dash_armor", "summoned", "summon_rewards", "wave_index", "wave_count", "wave_pending_at", "secret_inspect", "debt_fire_at", "entry_slow_until"]:
		if flags.has(key) and not Store.number(flags[key]): return false
	for key in ["chain_pairs", "forced_links"]:
		if flags.has(key) and not flags[key] is Dictionary: return false
	if flags.has("waves"):
		if not flags.waves is Array or not fields(flags, ["wave_index", "wave_count", "wave_pending_at"]) or flags.wave_count != flags.waves.size() or flags.wave_index < 0 or flags.wave_index > flags.waves.size(): return false
		for wave in flags.waves:
			if not wave is Array or not ids(wave, "enemies", db, false): return false
	if flags.has("debt_pair") and (not flags.debt_pair is Array or not flags.debt_pair.all(Store.integer)): return false
	return true

static func valid_settings(settings: Dictionary) -> bool:
	for key in ["muted", "touch", "mirror", "reduce_motion", "fixed_sticks", "fire_toggle", "haptics", "damage_numbers", "hitstop", "shape_cues"]:
		if settings.has(key) and not settings[key] is bool: return false
	for key in ["master_volume", "music_volume", "effects_volume", "deadzone", "control_scale", "control_opacity", "shake_scale", "flash_scale", "particle_scale", "combat_text_scale", "story_text_scale", "pickup_radius_scale"]:
		if settings.has(key) and (not Store.number(settings[key]) or settings[key] < 0 or settings[key] > 4): return false
	if settings.has("aim_mode") and settings.aim_mode not in ["off", "light", "auto"]: return false
	for key in ["bindings", "touch_layout"]:
		if settings.has(key) and not settings[key] is Dictionary: return false
	for device in settings.get("bindings", {}):
		if not settings.bindings[device] is Dictionary: return false
		for binding in settings.bindings[device].values():
			if not binding is Dictionary or not fields(binding, ["code"], [], [], [], ["type"]): return false
			if binding.has("sign") and not Store.number(binding.sign): return false
	for point in settings.get("touch_layout", {}).values():
		if not point is Array or point.size() != 2 or not point.all(Store.number): return false
	return true
