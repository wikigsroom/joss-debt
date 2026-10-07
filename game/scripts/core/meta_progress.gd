extends RefCounted
## A separate account journal credits each run only up to its highest recorded progress.
const Store = preload("res://scripts/core/save_store.gd")
const Content = preload("res://scripts/core/content_db.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
var db = Content.new()
var store
var data: Dictionary = {}
var recovery_message = ""
var read_only = false
const MASTERY = {
	"c_paper": ["完成六次焚债", "detonations", 6],
	"c_bell": ["连接四名敌人", "max_chain", 4],
	"c_lantern": ["击退十二名恶愿", "kills", 12],
	"c_mask": ["完成八次招架或预警闪避", "defenses", 8],
	"c_umbrella": ["单局回收二百香火", "ash_energy", 200],
	"c_ink": ["完成四十次主攻击命中", "hits", 40]
}

func _init(path: String = "user://profile", storage = null) -> void:
	store = Store.new(path) if storage == null else storage
	var migrated = Migration.profile(store.read())
	if migrated.ok: data = migrated.data
	else:
		data = Migration.profile({}).data
		read_only = true
		recovery_message = migrated.message

func save() -> bool:
	return not read_only and store.write(data)

func relic_pool() -> Array:
	var pool = db.rules.progression.initial_relic_ids.duplicate()
	for id in data.unlocks:
		for relic in db.row("meta_unlocks", id).grants.get("relic_ids", []):
			if not pool.has(relic): pool.append(relic)
	return pool

func has_feature(id: String) -> bool:
	for purchase in data.unlocks:
		if db.row("meta_unlocks", purchase).grants.get("feature", "") == id: return true
	return false

func coin_bonus() -> int:
	return 40 if data.unlocks.has("u_coin_pickup") else 0

func optional_bosses() -> Array:
	var result: Array = []
	if data.name_page_ids.size() >= 3: result.append("b04")
	if data.interest_page and data.repaid_ids.size() >= 3: result.append("b05")
	return result

func starting_weapons(character: String) -> Array:
	var result = [db.row("characters", character).weapon]
	if int(data.personal[character].stage) >= 2:
		var alternatives = {"c_paper": "w07", "c_bell": "w08", "c_lantern": "w09", "c_mask": "w10", "c_umbrella": "w11", "c_ink": "w12"}
		result.append(alternatives[character])
	return result

func reason(row: Dictionary) -> String:
	var requires = row.requires
	if requires.has("boss_defeated") and not data.bosses.has(requires.boss_defeated): return "先击败「%s」" % db.name_of("bosses", requires.boss_defeated)
	for id in requires.get("unlocks", []):
		if not data.unlocks.has(id): return "先取得「%s」" % db.name_of("meta_unlocks", id)
	if requires.has("route_pair_chosen"):
		var pair = requires.route_pair_chosen.duplicate()
		pair.sort()
		if not data.route_pairs.has("/".join(pair)): return "同局选择「%s」与「%s」各一点" % [db.name_of("routes", pair[0]), db.name_of("routes", pair[1])]
	return ""

func purchase(id: String) -> bool:
	var row = db.row("meta_unlocks", id)
	if row.is_empty() or data.unlocks.has(id) or not reason(row).is_empty() or data.merit < row.cost: return false
	var previous = data.duplicate(true)
	data.merit -= int(row.cost)
	data.unlocks.append(id)
	if not save():
		data = previous
		return false
	return true

func discover(kind: String, id: String) -> void:
	if data.seen.has(kind) and not data.seen[kind].has(id): data.seen[kind].append(id)

func achievement_unlocked(id: String) -> bool:
	return data.achievements.has(id)

func achievement_rows(character_id: String = "") -> Array:
	return db.achievement_rows().filter(func(row): return character_id.is_empty() or str(row.get("character", "")) == character_id)

func achievement_progress(row: Dictionary) -> Dictionary:
	var stats: Dictionary = data.achievement_stats
	var value = 0
	if row.get("scope", "global") == "character":
		var character = str(row.get("character", ""))
		var character_stats: Dictionary = stats.character_stats.get(character, {})
		value = character_stats.get(row.metric, 0)
		if row.metric == "routes": value = character_stats.get("route_ids", []).size()
		elif row.metric == "personal_stage": value = int(data.personal.get(character, {}).get("stage", 0))
	else:
		match str(row.get("metric", "")):
			"character_victories": value = stats.character_victories.values().filter(func(count): return int(count) > 0).size()
			"endings", "routes", "bosses": value = stats.get(row.metric, []).size()
			"relics": value = data.seen.get("relics", []).size()
			_: value = stats.get(row.metric, 0)
	var target = maxi(1, int(row.get("target", 1)))
	return {"value": mini(target, int(value)), "raw_value": int(value), "target": target, "unlocked": achievement_unlocked(str(row.id))}

func achievement_summary(character_id: String = "") -> Dictionary:
	var rows = achievement_rows(character_id)
	var unlocked = rows.filter(func(row): return achievement_unlocked(str(row.id))).size()
	return {"unlocked": unlocked, "total": rows.size(), "percent": (float(unlocked) / float(maxi(1, rows.size()))) * 100.0}

func _achievement_character_defaults() -> Dictionary:
	return {"runs": 0, "victories": 0, "detonations": 0, "max_chain": 0, "kills": 0, "defenses": 0, "ash_energy": 0, "hits": 0, "route_ids": [], "personal_stage": 0}

func _routes_for_world(w) -> Array:
	var routes: Array = []
	for talent in w.run.talents:
		var route = db.row("talents", talent).route
		if not routes.has(route): routes.append(route)
	routes.sort()
	return routes

func _update_achievements(w, routes: Array, record: Dictionary) -> Array:
	var messages: Array = []
	var stats: Dictionary = data.achievement_stats
	var character = str(w.run.character)
	if not stats.character_stats.has(character): stats.character_stats[character] = _achievement_character_defaults()
	var character_stats: Dictionary = stats.character_stats[character]
	var counted_run = bool(record.get("achievement_counted", false))
	if not counted_run:
		stats.runs = int(stats.runs) + 1
		character_stats.runs = int(character_stats.runs) + 1
		record.achievement_counted = true
	character_stats.detonations = maxi(int(character_stats.detonations), int(w.stats.get("detonations", 0)))
	character_stats.max_chain = maxi(int(character_stats.max_chain), int(w.stats.get("max_chain", 0)))
	character_stats.kills = maxi(int(character_stats.kills), int(w.stats.get("kills", 0)))
	character_stats.defenses = maxi(int(character_stats.defenses), int(w.stats.get("parries", 0)) + int(w.stats.get("dodges", 0)))
	character_stats.ash_energy = maxi(int(character_stats.ash_energy), int(w.stats.get("ash_energy", 0)))
	character_stats.hits = maxi(int(character_stats.hits), int(w.stats.get("hits", 0)))
	for route in routes:
		if not character_stats.route_ids.has(route): character_stats.route_ids.append(route)
		if not stats.routes.has(route): stats.routes.append(route)
	character_stats.personal_stage = maxi(int(character_stats.personal_stage), int(data.personal.get(character, {}).get("stage", 0)))
	if w.run.get("result", "") == "victory" and not bool(record.get("achievement_victory_counted", false)):
		stats.victories = int(stats.victories) + 1
		stats.character_victories[character] = int(stats.character_victories.get(character, 0)) + 1
		character_stats.victories = int(character_stats.victories) + 1
		record.achievement_victory_counted = true
	for boss in w.run.get("bosses_defeated", []):
		if not stats.bosses.has(boss): stats.bosses.append(boss)
	var ending = str(w.run.get("ending", ""))
	if not ending.is_empty() and not stats.endings.has(ending): stats.endings.append(ending)
	stats.relics = data.seen.get("relics", []).size()
	for row in db.achievement_rows():
		var id = str(row.id)
		if achievement_unlocked(id): continue
		var progress = achievement_progress(row)
		if int(progress.value) >= int(progress.target):
			data.achievements.append(id)
			messages.append("成就解锁 · " + str(row.name))
	return messages

func observe(w) -> Array:
	if w.run.is_empty() or w.run.get("training", false): return []
	# Daily challenges are deliberately comparable: they save and resume like a
	# normal run, but never convert a fixed-pool attempt into account power.
	if w.run.get("daily", false): return []
	var previous = data.duplicate(true)
	var before = JSON.stringify(data)
	var messages: Array = []
	var id = w.run.id
	var record = data.runs.get(id, {"merit": 0, "defenses": 0, "repayments": 0, "bosses": []})
	for field in ["personal_pages", "characters_unlocked", "new_bosses"]:
		if not record.has(field): record[field] = []
	if not record.has("bonus_merit"): record.bonus_merit = 0
	data.name_pages += maxi(0, int(w.run.get("name_pages", 0)) - int(record.get("name_pages", 0)))
	record.name_pages = maxi(int(record.get("name_pages", 0)), int(w.run.get("name_pages", 0)))
	data.interest_page = data.interest_page or w.run.get("interest_page", false)
	for page in w.run.get("name_page_ids", []):
		if not data.name_page_ids.has(page): data.name_page_ids.append(page)
	data.merit += maxi(0, int(w.run.merit) - int(record.merit))
	record.merit = maxi(int(record.merit), int(w.run.merit))
	var defenses = int(w.stats.get("parries", 0)) + int(w.stats.get("dodges", 0))
	data.defenses += maxi(0, defenses - int(record.defenses))
	record.defenses = maxi(int(record.defenses), defenses)
	data.repayments += maxi(0, w.run.repayments.size() - int(record.repayments))
	record.repayments = maxi(int(record.repayments), w.run.repayments.size())
	for debt in w.run.repayments:
		if not data.repaid_ids.has(debt): data.repaid_ids.append(debt)
	for boss in w.run.get("bosses_defeated", []):
		if not data.bosses.has(boss):
			data.bosses.append(boss)
			data.merit += 8
			record.bonus_merit += 8
			record.new_bosses.append(boss)
			messages.append("初次还愿 · 善缘 +8")
		if not record.bosses.has(boss): record.bosses.append(boss)
	data.runs[id] = record
	for enemy in w.enemies: discover("bosses" if enemy.boss else "enemies", enemy.id)
	for relic in w.run.relics: discover("relics", relic)
	discover("weapons", w.player.weapon)
	var routes = _routes_for_world(w)
	for a in routes.size():
		for b in range(a + 1, routes.size()):
			var pair = "/".join([routes[a], routes[b]])
			if not data.route_pairs.has(pair): data.route_pairs.append(pair)
	var unlock_conditions = {"c_bell": w.stats.max_chain >= 3, "c_lantern": data.bosses.has("b01") or (w.run.get("campaign", false) and not data.bosses.is_empty()),
		"c_mask": data.defenses >= 20, "c_umbrella": w.stats.ash_energy >= 200, "c_ink": data.repayments >= 3}
	for character in unlock_conditions:
		if unlock_conditions[character] and not data.characters.has(character):
			data.characters.append(character)
			record.characters_unlocked.append(character)
			messages.append("新还愿人 · " + db.name_of("characters", character))
	var personal = data.personal[w.run.character]
	var mastery = MASTERY[w.run.character]
	personal.progress = maxf(float(personal.progress), defenses if mastery[1] == "defenses" else float(w.stats.get(mastery[1], 0)))
	var own_routes = db.row("characters", w.run.character).routes
	personal.cross = personal.cross or own_routes.all(func(route): return routes.has(route))
	personal.final = personal.final or w.run.get("bosses_defeated", []).has("b37" if w.run.get("campaign", false) else "b03")
	while int(personal.stage) < 3:
		var done = [personal.progress >= mastery[2], personal.cross, personal.final][int(personal.stage)]
		if not done: break
		personal.stage += 1
		data.merit += int(personal.stage) * 5
		record.bonus_merit += int(personal.stage) * 5
		record.personal_pages.append(int(personal.stage))
		messages.append("个人愿页 · 第%d页完成" % personal.stage)
	messages.append_array(_update_achievements(w, routes, record))
	data.runs[id] = record
	if JSON.stringify(data) != before and not save():
		data = previous
		messages = ["还愿簿暂未存下，请稍后重试。"]
	return messages

func ending_reason(id: String) -> String:
	if id == "repay" and data.repaid_ids.size() < 3: return "还需偿还%d类债约" % (3 - data.repaid_ids.size())
	if id == "rewrite" and not data.personal.values().all(func(page): return int(page.stage) >= 3): return "先完成六位还愿人的个人页"
	return ""

func finish(w, id: String) -> bool:
	if id not in ["burn", "repay", "rewrite"] or not ending_reason(id).is_empty(): return false
	if w.run.result != "victory" or not w.run.get("bosses_defeated", []).has("b37" if w.run.get("campaign", false) else "b03"): return false
	if not w.run.get("ending", "").is_empty(): return false
	var previous = data.duplicate(true)
	w.run.ending = id
	if not data.endings.has(id): data.endings.append(id)
	var achievement_record = data.runs.get(w.run.id, {"achievement_counted": true, "achievement_victory_counted": true})
	_update_achievements(w, _routes_for_world(w), achievement_record)
	data.runs[w.run.id] = achievement_record
	if not save():
		data = previous
		w.run.ending = ""
		return false
	return true
