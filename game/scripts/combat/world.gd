extends RefCounted
## Short-lived touch transfer is intentionally absent from run snapshots.
var touch_charge_transfer: Dictionary = {}

func clear_touch_charge() -> void:
	touch_charge_transfer.clear()
	if not player.is_empty(): player.charge = 0.0
const Damage = preload("res://scripts/core/damage_record.gd")
const Impact = preload("res://scripts/combat/impact_control.gd")
## Authoritative fixed-tick combat. No nodes, input devices, audio, or rendering dependencies.

const Content = preload("res://scripts/core/content_db.gd")
const RunRng = preload("res://scripts/core/run_rng.gd")
const Geometry = preload("res://scripts/combat/room_geometry.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const EnemyPattern = preload("res://scripts/combat/enemy_patterns.gd")
const BossPattern = preload("res://scripts/combat/boss_patterns.gd")
const CreatureAction = preload("res://scripts/combat/creature_actions.gd")
const Graph = preload("res://scripts/core/room_graph.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
const Scenery = preload("res://scripts/combat/interactive_scenery.gd")
const ExpandedPattern = preload("res://scripts/combat/expanded_patterns.gd")
const ExpandedWeapons = preload("res://scripts/combat/expanded_weapons.gd")
const Composer = preload("res://scripts/combat/attack_composer.gd")
const Equipment = preload("res://scripts/combat/equipment.gd")
const ProjectileStyles = preload("res://scripts/combat/projectile_styles.gd")
const ROOM_ORDER = ["combat", "combat", "reward", "combat", "debt", "combat", "elite", "shop", "combat", "combat", "boss", "sacrifice", "judge", "angel", "challenge"]

var db = Content.new()
var rng = RunRng.new()
var streams: Dictionary = {}
var geometry = Geometry.new()
var run: Dictionary = {}
var player: Dictionary = {}
var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var zones: Array = []
var delayed: Array = []
var chains: Array = []
var events: Array = []
var enemy_ledger: Dictionary = {}
var reward_ledger: Dictionary = {}
var pair_cooldowns: Dictionary = {}
var choices: Array = []
var choice_queue: Array = []
var mode = "idle"
var time = 0.0
var uid = 0
var attack_uid = 0
var navigation_timer = 0.0
var room_flags: Dictionary = {}
var stats: Dictionary = {}
var active_pulse = ""
var pulse_serial = 0
var proc_ledger: Dictionary = {}
var pending_entry_direction = ""

func start(character_id: String, seed_value: int = 1, floors: int = 1, options: Dictionary = {}) -> void:
	touch_charge_transfer.clear()
	var character = db.row("characters", character_id)
	assert(not character.is_empty())
	pending_entry_direction = ""
	rng = RunRng.new(seed_value)
	streams.clear()
	run = {"id": "%s_%d" % [character_id, seed_value], "seed": seed_value, "character": character_id,
		"floor": 1, "floor_limit": floors, "room": 0, "coins": 10, "xp": 0, "level": 0, "merit": 0,
		"relics": {}, "talents": [], "contracts": [], "consumed": [], "repayments": [], "heal_misses": 0,
		"cleared": 0, "rerolls": 1, "result": "", "room_plan": ROOM_ORDER.duplicate(), "favors_used": {},
		"repay_skill_refunds": 0, "repay_reward_pending": 0, "repay_effects": 0, "contract_combats": 0,
		"evolved": false, "replacement": {}, "bosses_defeated": [], "ending": "", "damage_history": [], "death_cause": {},
		"growth_log": [], "special_rooms": {}, "daily": false, "daily_key": "", "daily_pool_version": ""}
	run.relic_pool = options.get("relic_pool", db.rules.progression.initial_relic_ids).duplicate()
	run.daily = bool(options.get("daily", false))
	run.daily_key = str(options.get("daily_key", "")) if run.daily else ""
	run.daily_pool_version = str(options.get("daily_pool_version", "")) if run.daily else ""
	run.seed_text = str(options.get("seed_text", Seed.text(seed_value)))
	run.random_version = Seed.VERSION
	run.campaign = floors == 11
	run.epilogue_seen = false
	run.coin_pickup_bonus = options.get("coin_pickup_bonus", 0)
	set_pickup_scale(float(options.get("pickup_radius_scale", 1.0)))
	run.optional_bosses = options.get("optional_bosses", []).duplicate()
	run.graph = Campaign.build(db, run.seed_text, 1) if run.campaign else Graph.build(RunRng.new(seed_value + 401), 1, run.optional_bosses)
	run.room_plan = run.graph.types.duplicate()
	run.visited = []
	run.room_history = {}
	run.name_pages = 0
	run.name_page_ids = []
	run.interest_page = false
	player = {"pos": Vector2(640, 585), "aim": Vector2.UP, "move": Vector2.ZERO,
		"hp": int(character.health), "max_hp": int(character.health), "energy": 40.0,
		"weapon": character.weapon, "skill": character.skills[0], "shot_cd": 0.0, "skill_cd": 0.0,
		"dash_cd": 0.0, "dash_left": 0.0, "dash_dir": Vector2.UP, "invulnerable": 0.0,
		"guard": 0.0, "armor": 0, "still": 0.0, "passive_cd": 0.0, "passive_hits": 0,
		"attack_bonus": 0.0, "attack_bonus_until": 0.0, "charge": 0.0, "buffer_dash": 0.0, "buffer_skill": 0.0,
		"dash_start": Vector2(640, 585), "guard_count": 0, "moved_distance": 0.0,
		"facing_direction": Vector2.UP, "last_shot_direction": Vector2.UP}
	if db.row("weapons", options.get("weapon", "")).is_empty() == false: player.weapon = options.weapon
	record_growth_choice("weapon", player.weapon, "initial", player.weapon, 0, 0, "initial")
	record_growth_choice("skill", player.skill, "initial", player.skill, 0, 0, "initial")
	stats = {"shots": 0, "hits": 0, "kills": 0, "detonations": 0, "max_chain": 0, "dodges": 0,
		"damage_taken": 0, "ash_energy": 0.0, "secondary_hits": 0, "elapsed": 0.0}
	Equipment.normalize(self)
	record_growth_choice("active", run.active_item.id, "initial", run.active_item.id, 0, 0, "initial")
	time = 0.0
	uid = 0
	attack_uid = 0
	enemy_ledger.clear()
	reward_ledger.clear()
	choice_queue.clear()
	proc_ledger.clear()
	pulse_serial = 0
	active_pulse = ""
	enter_room()

func begin_pulse(label: String = "effect") -> String:
	pulse_serial += 1
	active_pulse = "%s_%d" % [label, pulse_serial]
	proc_ledger[active_pulse] = {"used": 0, "expires": time + 8.0}
	return active_pulse

func claim_secondary() -> bool:
	if active_pulse.is_empty() or not proc_ledger.has(active_pulse): begin_pulse()
	var pulse = proc_ledger[active_pulse]
	if int(pulse.used) >= 48:
		stats.proc_budget_exhausted = int(stats.get("proc_budget_exhausted", 0)) + 1
		return false
	pulse.used += 1
	stats.max_proc_events = maxi(int(stats.get("max_proc_events", 0)), int(pulse.used))
	return true

func skill_cost() -> int:
	return Effects.skill_cost(self)

func record_growth_choice(kind: String, id: String, reward_kind: String = "", reward_id: String = "", price: int = 0, hp_cost: int = 0, source: String = "choice") -> void:
	if not run.has("growth_log") or not run.growth_log is Array: run.growth_log = []
	var entry = {"room": room_key(), "floor": int(run.floor), "room_index": int(run.room),
		"room_type": room_type(), "type": kind, "id": id, "reward_kind": reward_kind if not reward_kind.is_empty() else kind,
		"reward_id": reward_id if not reward_id.is_empty() else id, "price": price, "hp_cost": hp_cost,
		"at": time, "source": source}
	run.growth_log.append(entry)
	if run.growth_log.size() > 256: run.growth_log.pop_front()

func roll(name: String):
	var key = "f%d/r%d/%s" % [run.floor, run.room, name]
	if not streams.has(key): streams[key] = Seed.derive(run.seed_text, key) if run.get("campaign", false) else RunRng.new(posmod((str(int(run.seed)) + "/" + key).hash(), 2147483646))
	return streams[key]

func region_spec() -> Dictionary:
	if run.get("campaign", false): return Campaign.biome(db, str(run.seed_text), int(run.floor))
	return db.rows("regions")[clampi(int(run.get("floor", 1)) - 1, 0, 2)]

func room_boss_ids() -> Array:
	if run.get("campaign", false): return Campaign.boss_ids(run.graph, int(run.room))
	return [run.graph.optional_boss] if room_type() == "optional_boss" else ["b%02d" % int(run.floor)]

func guest_spec() -> Dictionary:
	return Campaign.guest_biome(db, run.seed_text, int(run.floor)) if run.get("campaign", false) else region_spec()

func encounter_ids(count: int, domain: String, max_index: int = -1) -> Array:
	var local = region_spec().enemy_ids
	var guest = guest_spec().enemy_ids
	if max_index >= 0:
		local = local.slice(0, mini(local.size(), max_index + 1))
		guest = guest.slice(0, mini(guest.size(), max_index + 1))
	var foreign_count = encounter_foreign_count(count)
	var entries: Array = []
	var random = roll(domain + "/mix_v2")
	for i in count: entries.append(random.choose(guest if i < foreign_count else local))
	return random.shuffle(entries)

func encounter_foreign_count(count: int) -> int:
	if not run.get("campaign", false): return 0
	var prefix = Campaign.mob_prefix(run.graph,int(run.floor),int(run.room))
	return roundi((prefix+count)*.4)-roundi(prefix*.4)

func summoned_enemy_id(domain: String) -> String:
	if not run.get("campaign", false): return str(roll(domain).choose(region_spec().enemy_ids))
	var index = int(room_flags.get("mixed_summon_index", 0))
	room_flags.mixed_summon_index = index + 1
	var foreign = roundi((index + 1) * .4) > roundi(index * .4)
	return str(roll(domain + "/mix_v2").choose(guest_spec().enemy_ids if foreign else region_spec().enemy_ids))

func build_geometry(template: String, saved_objects: Array = []) -> void:
	if run.get("campaign", false):
		geometry.configure_biome(region_spec().id, int(run.graph.get("backgrounds", {}).get(str(int(run.room)), 0)))
		geometry.build_procedural(Seed.derive(run.seed_text, "floor/%d/room/%d/obstacles" % [run.floor, run.room]), region_spec().id, room_type())
		if not saved_objects.is_empty(): geometry.restore_objects(saved_objects)
	else: geometry.build(template, int(run.floor))

func player_stat_rows() -> Array:
	var weapon = db.row("weapons", player.weapon)
	var recipe = Composer.recipe(self, weapon)
	var speed = float(db.row("characters", run.character).speed) * (1 + .06 * stack("r33") + .05 * talent("t_wind_1a")) * stat_multiplier("move_speed")
	if room_flags.get("goldbody_slow", false): speed *= .9
	return [{"id": "damage", "label": "伤害", "value": "%.1f" % (float(weapon.damage) * Effects.primary_multiplier(self) * stat_multiplier("damage") * float(recipe.damage_factor)), "icon": "sword"},
		{"id": "fire_rate", "label": "攻速", "value": "%.2f/s" % (1.0 / maxf(.01, recipe.interval)), "icon": "zap"},
		{"id": "shot_speed", "label": "弹速", "value": str(int(recipe.speed)), "icon": "arrow-up-right"},
		{"id": "move_speed", "label": "移速", "value": str(roundi(speed)), "icon": "wind"},
		{"id": "max_health", "label": "血量上限", "value": str(int(player.max_hp)), "icon": "heart"},
		{"id": "range", "label": "射程", "value": str(int(recipe.range)), "icon": "crosshair"}]

func stat_bonus(stat: String) -> float:
	return Equipment.bonus(self, stat)

func stat_multiplier(stat: String) -> float:
	return Equipment.multiplier(self, stat)

func nearby_pickup() -> Dictionary:
	return Equipment.nearest(self)

func interact_pickup() -> bool:
	return Equipment.interact(self)

func use_active_item() -> bool:
	return Equipment.activate(self)

func stack(id: String) -> int:
	return int(run.get("relics", {}).get(id, 0))

func synergy_rows() -> Array:
	## Derived run view for the icon-first combination codex. It never mutates
	## the save; the UI and review tools can ask for the same live truth.
	var result: Array = []
	for source in db.rows("synergies"):
		var row = source.duplicate(true)
		var owned: Array = []
		for relic_id in row.get("relics", []):
			if stack(str(relic_id)) > 0:
				owned.append(str(relic_id))
		row["owned_relics"] = owned
		row["owned_count"] = owned.size()
		row["complete"] = owned.size() == row.get("relics", []).size()
		result.append(row)
	return result

func active_synergies() -> Array:
	return synergy_rows().filter(func(row): return row.get("complete", false))

func talent(id: String) -> int:
	return 1 if run.get("talents", []).has(id) else 0

func contract(id: String) -> bool:
	for entry in run.get("contracts", []):
		if entry.id == id:
			return true
	return false

func chapter_favor_used(kind: String) -> bool:
	var key = "%s_%d" % [kind, int(run.floor)]
	# Older JSON-restored builds wrote integer-valued floors as "1.0".
	return run.favors_used.has(key) or run.favors_used.has(key + ".0")

func emit(kind: String, data: Dictionary = {}) -> void:
	data["kind"] = kind
	data["at"] = time
	events.append(data)

func take_events() -> Array:
	var result = events
	events = []
	return result

func next_uid() -> int:
	uid += 1
	return uid

func room_type() -> String:
	return run.room_plan[int(run.room)]

func next_rooms() -> Array:
	return Graph.frontier(run.graph, run.visited, int(run.room))

func room_connection_direction(destination: int, from_room: int = -1) -> String:
	var current = int(run.room) if from_room < 0 else from_room
	var coords: Array = run.get("graph", {}).get("coords", [])
	if current < 0 or destination < 0 or current >= coords.size() or destination >= coords.size():
		return "north"
	var delta = Vector2(coords[destination]) - Vector2(coords[current])
	if absf(delta.x) > absf(delta.y):
		return "east" if delta.x > 0 else "west"
	if absf(delta.y) > .01:
		if run.get("campaign", false): return "north" if delta.y < 0 else "south"
		# The route graph grows downward while the room's forward door is north.
		return "north" if delta.y > 0 else "south"
	return "north"

static func opposite_direction(direction: String) -> String:
	return {"north": "south", "south": "north", "east": "west", "west": "east"}.get(direction, "south")

static func direction_vector(direction: String) -> Vector2:
	return {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}.get(direction, Vector2.UP)

static func door_position(direction: String) -> Vector2:
	return {"north": Vector2(640, 94), "south": Vector2(640, 626), "east": Vector2(1198, 360), "west": Vector2(82, 360)}.get(direction, Vector2(640, 94))

func room_door_position(direction: String) -> Vector2:
	return geometry.doorway(direction) if run.get("campaign", false) else door_position(direction)

func room_doors() -> Array:
	if mode != "clear" or run.is_empty(): return []
	var current = int(run.room)
	var frontier = next_rooms()
	var result: Array = []
	var seen: Dictionary = {}
	for edge in run.get("graph", {}).get("edges", []):
		if not edge.has(current): continue
		var destination = int(edge[1] if int(edge[0]) == current else edge[0])
		if destination == current or not Graph.visible(run.graph, destination): continue
		var available = frontier.has(destination) or Graph.can_return(run.graph, run.visited, current, destination)
		if not available or seen.has(destination): continue
		seen[destination] = true
		var direction = room_connection_direction(destination, current)
		result.append({"destination": destination, "direction": direction, "pos": room_door_position(direction), "visited": run.visited.has(destination), "type": run.graph.types[destination]})
	return result

func nearby_room_door() -> Dictionary:
	if mode != "clear": return {}
	for door in room_doors():
		var direction = direction_vector(str(door.direction))
		if player.pos.distance_to(door.pos) <= (24 if run.get("campaign", false) else 54) and player.move.dot(direction) > .08 and geometry.clear_segment(player.pos, door.pos):
			return door
	return {}

func room_key() -> String:
	return "%s/f%d/r%d" % [run.id, run.floor, run.room]

func reward_once(slot: String) -> bool:
	var key = room_key() + "/" + slot
	if reward_ledger.has(key):
		return false
	reward_ledger[key] = true
	return true

func enter_room() -> void:
	touch_charge_transfer.clear()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	zones.clear()
	delayed.clear()
	chains.clear()
	pair_cooldowns.clear()
	choices.clear()
	room_flags = {"combat_kills": 0, "dash_armor": 0, "passive_detonate": false, "summoned": 0, "summon_rewards": 0, "chain_pairs": {}, "forced_links": {}}
	var arrival = pending_entry_direction if not pending_entry_direction.is_empty() else "south"
	pending_entry_direction = ""
	player.move = Vector2.ZERO
	player.dash_left = 0.0
	player.guard = 0.0
	player.charge = 0.0
	player.invulnerable = 0.8
	navigation_timer = 0.0
	var templates = db.rows("room_templates").map(func(row): return row.id)
	if run.visited.has(int(run.room)):
		var history = run.get("room_history", {}).get(str(int(run.room)), {})
		build_geometry(str(history.get("template", "room_open_1")), history.get("objects", []))
		player.pos = geometry.nearest_free(room_door_position(arrival), 12)
		geometry.rebuild_flow(player.pos)
		pickups = history.get("pickups", []).duplicate(true)
		room_flags = history.get("flags", room_flags).duplicate(true)
		mode = "clear"
		emit("room_return", {"type": room_type(), "floor": run.floor})
		emit("save_requested", {"simulation_only": true})
		return
	build_geometry("room_open_1" if room_type() != "combat" or int(run.room) < 2 else roll("layout").choose(templates))
	player.pos = geometry.nearest_free(room_door_position(arrival), 12)
	geometry.rebuild_flow(player.pos)
	match room_type():
		"combat":
			mode = "combat"
			prepare_waves()
			spawn_next_wave(false)
			if contract("d01") and not (int(run.floor) == 1 and int(run.room) < 2):
				run.contract_combats = int(run.get("contract_combats", 0)) + 1
				if run.contract_combats % 2 == 0 and enemies.size() < 8:
					var collector = spawn_enemy(summoned_enemy_id("collector") if run.get("campaign", false) else "e01", spawn_position(0, 1))
					collector.arrival = time + .8
			if contract("d02") and enemies.size() >= 2:
				room_flags.debt_pair = [enemies[0].uid, enemies[1].uid]
				room_flags.debt_fire_at = time + 3.0
			if contract("d08"): room_flags.entry_slow_until = time + 3.0
		"elite":
			mode = "combat"
			var variants = db.rows("elite_variants").filter(func(row): return row.floor == clampi(int(run.floor), 1, 3))
			var variant = roll("encounter").choose(variants)
			# The authored variant is passed into the real spawn path so its numeric
			# contract (health, telegraph, damage and ash) is applied before play.
			var pack = encounter_ids(4, "elite")
			var elite_id = str(pack[0]) if run.get("campaign", false) else str(variant.base_enemy)
			var elite = spawn_enemy(elite_id, Vector2(640, 280), true, false, variant.id)
			elite.elite_id = variant.id
			elite.sprite_id = elite_id if run.get("campaign", false) else variant.id
			for i in 3:
				spawn_enemy(str(pack[i + 1]), spawn_position(i, 3))
		"boss":
			mode = "combat"
			spawn_room_bosses()
		"optional_boss":
			mode = "combat"
			spawn_room_bosses()
		"reward":
			mode = "choice"
			Equipment.treasure_cache(self)
			choices = relic_offer(2, true)
			choices.append({"kind": "weapon", "id": roll("loot").choose(["w07", "w08", "w09", "w10", "w11", "w12"]), "price": 0})
		"shop":
			mode = "shop"
			choices = relic_offer(2)
			for entry in choices:
				entry.price = db.rules.loot.shop_prices[db.row("relics", entry.id).rarity]
			choices.append({"kind": "heal", "id": "heal", "price": 15 if contract("d04") else 10})
			choices.append({"kind": "weapon", "id": roll("shop").choose(db.rows("weapons")).id, "price": 35})
		"debt":
			mode = "debt"
			for row in db.rows("debt_contracts"):
				if row.min_floor <= run.floor and row.max_floor >= run.floor and not run.consumed.has(row.reward) and stack(row.reward) < int(db.row("relics", row.reward).stack_limit):
					choices.append({"kind": "contract", "id": row.id, "price": 0})
		"event":
			mode = "choice"
			var story_name = ["为夜归者添一盏灯", "把已还之愿取下秤", "替空白的页留一个名字"][clampi(int(run.floor) - 1, 0, 2)]
			choices = [{"kind": "event", "id": "remember", "price": 0, "name": story_name, "behavior": "收下一张姓名页。回庭后，可以继续追查被撕掉的名字。", "icon": "r48"},
				{"kind": "event", "id": "rest", "price": 6, "name": "续一口心香", "behavior": "消耗6纸钱，恢复2心火。", "icon": "r17"}]
		"secret":
			mode = "choice"
			choices = relic_offer(2, true)
			choices.append({"kind": "event", "id": "interest", "price": 0, "name": "收起利息页", "behavior": "取走总账的利息页。偿还三类债约后，可以追查最后一笔利息。", "icon": "r54"})
		"sacrifice":
			mode = "choice"
			choices = special_room_choices("sacrifice")
		"judge":
			mode = "choice"
			choices = special_room_choices("judge")
		"angel":
			mode = "choice"
			choices = special_room_choices("angel")
		"challenge":
			mode = "combat"
			prepare_challenge_waves()
			spawn_next_wave(false)
	emit("room_enter", {"type": room_type(), "floor": run.floor})
	emit("save_requested")

func special_room_choices(kind: String) -> Array:
	var result: Array = []
	var room_spec = db.row("special_rooms", kind)
	if room_spec.is_empty():
		return result
	var allowed = room_spec.get("choices", [])
	var offers = relic_offer(2, kind == "sacrifice")
	if kind == "sacrifice":
		if allowed.has("relic"):
			for offer in offers:
				var row = db.row("relics", offer.id)
				result.append({"kind": "sacrifice", "id": offer.id, "art_id": offer.id, "reward_kind": "relic", "hp_cost": 2,
					"price": 0, "slot": offer.slot, "name": "献心 · " + str(row.name),
					"behavior": "失去2点心火，换取这件供物；本房间只能完成一次献灯。", "icon": offer.id})
		if allowed.has("max_hp"):
			result.append({"kind": "sacrifice", "id": "max_hp", "art_id": "r25", "reward_kind": "max_hp", "hp_cost": 1,
				"price": 0, "slot": "max_hp", "name": "割页增命", "behavior": "永久失去1点当前心火上限，获得2点最大心火成长。", "icon": "r25"})
	elif kind == "judge":
		if allowed.has("relic"):
			for offer in offers:
				var row = db.row("relics", offer.id)
				result.append({"kind": "judgment", "id": offer.id, "art_id": offer.id, "reward_kind": "relic", "hp_cost": 2,
					"price": 0, "slot": offer.slot, "name": "判契 · " + str(row.name),
					"behavior": "失去2点心火，向判官签下强力供物；本房间只能判一次。", "icon": offer.id})
		if allowed.has("weapon"):
			var weapon_id = str(roll("special").choose(db.rows("weapons")).id)
			result.append({"kind": "judgment", "id": weapon_id, "art_id": weapon_id, "reward_kind": "weapon", "hp_cost": 3,
				"price": 0, "slot": "weapon", "name": "判决 · " + db.name_of("weapons", weapon_id),
				"behavior": "失去3点心火，立即换上这件器具；本房间只能判一次。", "icon": weapon_id})
	else:
		if allowed.has("heal"):
			result.append({"kind": "blessing", "id": "heal", "art_id": "r17", "reward_kind": "heal", "hp_cost": 0,
				"price": 0, "slot": "heal", "name": "观音续灯", "behavior": "恢复4点心火，并清除本章未领取的治疗缺口。", "icon": "r17"})
		if allowed.has("max_hp"):
			result.append({"kind": "blessing", "id": "max_hp", "art_id": "r26", "reward_kind": "max_hp", "hp_cost": 0,
				"price": 0, "slot": "max_hp", "name": "观音添页", "behavior": "获得1点最大心火，并立即恢复1点。", "icon": "r26"})
		var talents = talent_offer()
		if allowed.has("talent") and not talents.is_empty():
			var talent_row = db.row("talents", talents[0].id)
			var route_art = {"fire": "r01", "thread": "r09", "ash": "r17", "seal": "r25", "wind": "r33", "ink": "r41"}.get(str(talent_row.route), "r17")
			result.append({"kind": "blessing", "id": talent_row.id, "art_id": route_art, "reward_kind": "talent", "hp_cost": 0,
				"price": 0, "slot": "talent", "name": "观音点化 · " + str(talent_row.name), "behavior": "点亮一条可组合的成长分支。", "icon": route_art})
	return result

func prepare_waves() -> void:
	var total = 3 + mini(3, int(run.room) / 3) + mini(4, int(run.floor) - 1)
	var counts = [mini(6, total)]
	if int(run.room) >= 8 or (int(run.floor) >= 2 and int(run.room) == 5): counts = [3, maxi(3, total - 3)]
	var plan: Array = []
	var pool = region_spec().enemy_ids
	var mixed = encounter_ids(counts.reduce(func(sum_value, value): return sum_value + value, 0), "encounter", 1 + int(run.room))
	var offset = 0
	for count in counts:
		var ids: Array = []
		for i in count:
			var id = mixed[offset + i] if run.get("campaign", false) else pool[roll("encounter").between(0, mini(pool.size() - 1, 1 + int(run.room)))]
			if not run.get("campaign", false) and int(run.floor) == 1 and int(run.room) < 2: id = "e01" if int(run.room) == 0 or i == 2 else "e02"
			ids.append(id)
		plan.append(ids)
		offset += count
	room_flags.waves = plan
	room_flags.wave_index = 0
	room_flags.wave_count = plan.size()
	room_flags.wave_pending_at = 0.0
	room_flags.encounter_guest = guest_spec().id if run.get("campaign", false) else ""
	room_flags.encounter_local = region_spec().id if run.get("campaign", false) else ""

func prepare_challenge_waves() -> void:
	var pool = region_spec().enemy_ids
	var plan: Array = []
	var base = 4 + int(run.floor)
	var total = mini(7, base) + mini(7, base + 1) + mini(7, base + 2)
	var mixed = encounter_ids(total, "challenge", 2 + int(run.floor))
	var offset = 0
	for wave_index in 3:
		var count = mini(7, base + wave_index)
		var ids: Array = []
		for i in count:
			var id = mixed[offset + i] if run.get("campaign", false) else pool[roll("challenge_%d" % wave_index).between(0, mini(pool.size() - 1, 2 + int(run.floor)))]
			if not run.get("campaign", false) and int(run.floor) == 1 and wave_index == 0: id = "e01" if i % 2 == 0 else "e02"
			ids.append(id)
		plan.append(ids)
		offset += count
	room_flags.waves = plan
	room_flags.wave_index = 0
	room_flags.wave_count = plan.size()
	room_flags.wave_pending_at = 0.0
	room_flags.challenge = true

func spawn_next_wave(telegraph: bool = true) -> void:
	var ids: Array = room_flags.waves[int(room_flags.wave_index)]
	room_flags.wave_index += 1
	room_flags.wave_pending_at = 0.0
	for i in ids.size():
		var point = spawn_position(i, ids.size(), "wave_spawn_%d" % int(room_flags.wave_index))
		if not run.get("campaign", false) and int(run.floor) == 1 and int(run.room) < 2: point = Vector2(500 + i * 120, 290)
		var enemy = spawn_enemy(ids[i], point)
		if telegraph: enemy.arrival = time + .8
	if contract("d02") and enemies.size() >= 2:
		room_flags.debt_pair = [enemies[0].uid, enemies[1].uid]
		room_flags.debt_fire_at = time + 3.0 + (.8 if telegraph else 0)
	if int(room_flags.wave_count) > 1: emit("wave_started", {"index": room_flags.wave_index, "total": room_flags.wave_count})
	if telegraph: emit("save_requested", {"simulation_only": true})

func finish_wave() -> void:
	if int(room_flags.get("wave_index", 1)) >= int(room_flags.get("wave_count", 1)):
		clear_room()
	elif float(room_flags.wave_pending_at) <= 0:
		room_flags.wave_pending_at = time + 1.2
		bullets = bullets.filter(func(b): return b.friendly)
		zones = zones.filter(func(z): return z.friendly)
		emit("wave_incoming", {"index": int(room_flags.wave_index) + 1, "total": room_flags.wave_count})
		emit("save_requested", {"simulation_only": true})
	elif time >= float(room_flags.wave_pending_at):
		spawn_next_wave()

func secret_entry() -> Dictionary:
	for entry in run.get("graph", {}).get("secret_entries", []):
		if int(entry.parent) == int(run.room):
			var result = entry.duplicate()
			if run.get("campaign", false): result.pos = geometry.doorway("east" if int(entry.side) > 0 else "west", 64) - Vector2(0, 44)
			return result
	return {}

func update_secret_discovery(delta: float) -> void:
	if mode != "clear": return
	var entry = secret_entry()
	if entry.is_empty() or Graph.visible(run.graph, int(entry.room)): return
	var near = player.pos.distance_to(entry.pos) <= 80 and geometry.clear_segment(player.pos, entry.pos)
	room_flags.secret_inspect = float(room_flags.get("secret_inspect", 0)) + delta if near else 0.0
	if float(room_flags.secret_inspect) < .45: return
	run.graph.revealed.append(int(entry.room))
	emit("secret_discovered", {"pos": entry.pos, "room": entry.room})
	emit("save_requested", {"simulation_only": true})

func nearby_secret_room(require_direction: bool = false) -> int:
	if mode != "clear": return -1
	var entry = secret_entry()
	if entry.is_empty() or not Graph.visible(run.graph, int(entry.room)): return -1
	if require_direction:
		var outward = Vector2.RIGHT if int(entry.get("side", 1)) > 0 else Vector2.LEFT
		if player.move.dot(outward) <= .08: return -1
	return int(entry.room) if player.pos.distance_to(entry.pos) <= 105 and geometry.clear_segment(player.pos, entry.pos) else -1

func try_enter_secret(require_direction: bool = false) -> bool:
	var destination = nearby_secret_room(require_direction)
	if destination < 0: return false
	var previous = int(run.room)
	var entry = secret_entry()
	var arrival = "west" if int(entry.get("side", 1)) > 0 else "east"
	advance_room(destination, arrival)
	return int(run.room) != previous

func spawn_position(index: int, total: int, stream: String = "encounter", radius: float = 36) -> Vector2:
	var candidates: Array = []
	for y in range(1, 6):
		for x in range(2, 16):
			var position = geometry.center(Vector2i(x, y))
			if geometry.valid_circle(position, radius) and position.distance_to(player.pos) >= 220 and not enemies.any(func(enemy): return enemy.pos.distance_to(position) < radius + enemy.radius + 20):
				candidates.append(position)
	var chosen = roll(stream).choose(candidates)
	if chosen == null:
		return geometry.nearest_free(Vector2(260 + index * 100, 280), radius)
	return chosen

func spawn_enemy(id: String, position: Vector2, elite: bool = false, summoned: bool = false, elite_variant_id: String = "") -> Dictionary:
	if summoned:
		if int(room_flags.summoned) >= 8 or enemies.filter(func(enemy): return not enemy.dead and not enemy.boss).size() >= 6:
			return {}
		room_flags.summoned += 1
	var natural_reward = not summoned or int(room_flags.summon_rewards) < 2
	if summoned and natural_reward:
		room_flags.summon_rewards += 1
	var spec = db.row("enemies", id)
	var variant = db.row("elite_variants", elite_variant_id) if elite and not elite_variant_id.is_empty() else {}
	var health_multiplier = float(variant.get("health_multiplier", 3.0)) if elite else 1.0
	var telegraph_multiplier = float(variant.get("telegraph_multiplier", 0.9)) if elite else 1.0
	var damage_bonus = int(variant.get("damage_bonus", 1)) if elite else 0
	var ash_reward = int(variant.get("natural_ash", db.rules.combat.get("elite_ash", 16))) if elite else int(spec.get("natural_ash", db.rules.combat.get("natural_ash", 8)))
	var health = float(spec.health) * maxf(.1, health_multiplier)
	if run.get("campaign", false): health *= 1.0 + .14 * (int(run.floor) - 1)
	var enemy = {"uid": next_uid(), "id": id, "pos": position, "hp": health, "max_hp": health,
		"radius": 22.0 if elite else float(spec.get("radius", 17)), "speed": float(spec.speed), "elite": elite, "boss": false,
		"elite_id": str(variant.get("id", elite_variant_id)) if elite else "", "sprite_id": str(variant.get("id", elite_variant_id)) if elite and not variant.is_empty() and not run.get("campaign", false) else id,
		"ash_reward": ash_reward, "summoned": summoned, "natural_reward": natural_reward, "dead": false, "mark": 0, "mark_until": 0.0, "mark_energy_at": -10.0,
		"burn": 0, "burn_until": 0.0, "burn_next": 0.0, "hit_flash": 0.0, "primary_hits": 0,
		"attack_cd": 1.2 + roll("enemy_timing_%d" % uid).unit(), "windup": 0.0, "tell": maxf(0.35, float(spec.telegraph_ms) / 1000.0 * telegraph_multiplier),
		"aim": Vector2.DOWN, "target": player.pos, "lunge": 0.0, "damage": int(spec.damage) + damage_bonus,
		"slow_until": 0.0, "first_fire_at": -10.0, "last_attack_id": -1, "phase": 0, "guard_open": 0.0,
		"attack_history": {}, "shield_layers": 2 if elite and id == "e09" else (1 if id == "e09" else 0),
		"stun_until": 0.0, "burn_ticks": 0}
	enemy.render_size = float(spec.get("render_size", 146 if elite else 110))
	enemy.movement = str(spec.get("movement", ""))
	enemy.pattern = str(spec.get("pattern", ""))
	enemy.pos = geometry.nearest_free(position, enemy.radius)
	enemies.append(enemy)
	return enemy

func spawn_room_bosses() -> void:
	var ids = room_boss_ids()
	for i in ids.size():
		var point = spawn_position(i, ids.size(), "boss_positions", float(db.row("bosses", ids[i]).get("radius", 48))) if run.get("campaign", false) else Vector2(640, 330)
		var boss = spawn_boss(str(ids[i]), point)
		var carried = run.get("legacy_boss_health",{}).get(str(int(run.room)),{})
		if carried.get("id","")==boss.id:
			boss.hp=carried.hp; boss.max_hp=carried.max_hp
			run.legacy_boss_health.erase(str(int(run.room)))
		if ids.size() == 2:
			boss.hp *= .68
			boss.max_hp = boss.hp
			boss.attack_cd += i * .9
	room_flags.boss_ids = ids.duplicate()

func spawn_boss(id: String, point: Vector2 = Vector2(640, 330)) -> Dictionary:
	var spec = db.row("bosses", id)
	var enemy = spawn_enemy("e05", point)
	enemy.id = id
	enemy.boss = true
	enemy.sprite_id = id
	enemy.hp = float(spec.health)
	enemy.max_hp = enemy.hp
	if run.get("campaign", false): enemy.hp *= 1.0 + .18 * (int(run.floor) - 1); enemy.max_hp = enemy.hp
	enemy.radius = float(spec.get("radius", 48))
	enemy.pos = geometry.nearest_free(point, enemy.radius)
	enemy.render_size = float(spec.get("size", 256))
	enemy.speed = float(spec.get("speed", 45))
	enemy.movement = str(spec.get("movement", "orbit"))
	enemy.pattern = str(spec.get("attack_family", ""))
	enemy.tell = 0.9
	enemy.attack_cd = 1.6
	enemy.damage = 2
	BossPattern.phase_enter(self, enemy, 0)
	return enemy

func tick(frame: Dictionary, delta: float = 1.0 / 60.0) -> void:
	if mode != "combat" and mode != "clear":
		return
	time += delta
	stats.elapsed += delta
	for key in proc_ledger.keys():
		if time > float(proc_ledger[key].expires): proc_ledger.erase(key)
	for cooldown in ["shot_cd", "skill_cd", "dash_cd", "invulnerable", "guard", "passive_cd", "buffer_dash", "buffer_skill", "item_cd"]:
		player[cooldown] = maxf(0.0, player[cooldown] - delta)
	for key in room_flags.get("composition_ledger", {}).keys():
		if time > float(room_flags.composition_ledger[key]): room_flags.composition_ledger.erase(key)
	if frame.get("dash", false):
		player.buffer_dash = 0.08
	if frame.get("skill", false):
		player.buffer_skill = 0.08
	var move = Vector2(frame.get("move", Vector2.ZERO)).limit_length(1.0)
	var aim = Vector2(frame.get("aim", player.aim))
	if aim.length() > 0.01:
		player.aim = aim.normalized()
		player.facing_direction = player.aim
	player.move = move
	player.still = player.still + delta if move.length() < 0.1 else 0.0
	if player.buffer_dash > 0.0 and player.dash_cd <= 0.0:
		var intended_dash = Vector2(frame.get("dash_direction", Vector2.ZERO))
		start_dash(intended_dash if intended_dash.length() > .1 else (move if move.length() > 0.1 else player.aim))
	if player.buffer_skill > 0.0 and player.skill_cd <= 0.0:
		if cast_skill():
			player.buffer_skill = 0.0
	var speed = float(db.row("characters", run.character).speed) * (1.0 + 0.06 * stack("r33") + 0.05 * talent("t_wind_1a")) * stat_multiplier("move_speed")
	if room_flags.get("goldbody_slow", false): speed *= .9
	if time < float(room_flags.get("entry_slow_until", 0)): speed *= .88
	var previous_position = Vector2(player.pos)
	if player.dash_left > 0.0:
		player.dash_left = maxf(0.0, player.dash_left - delta)
		var distance = 160.0 + 20.0 * stack("r34") + 20.0 * talent("t_wind_1b")
		player.pos = geometry.slide(player.pos, player.dash_dir * distance / 0.2 * delta, 12)
		if player.dash_left <= .00001:
			begin_pulse("dash_landing")
			Effects.dash_end(self)
	else:
		player.pos = geometry.slide(player.pos, move * speed * delta, 12)
	player.moved_distance = float(player.get("moved_distance", 0)) + previous_position.distance_to(player.pos)
	var picked_up = Equipment.interact(self) if frame.get("interact", false) else false
	if frame.get("active_item", false): Equipment.activate(self)
	if mode not in ["combat", "clear"]: return
	if mode == "combat":
		player.energy = minf(100.0, player.energy + (3.0 + talent("t_ash_2b")) * delta)
		navigation_timer -= delta
		if navigation_timer <= 0.0:
			navigation_timer = 0.25
			geometry.rebuild_flow(player.pos)
		update_enemies(delta)
		update_chains()
	shoot_input(frame.get("fire", false), delta, frame.get("charge_hold", false), frame.get("device", "") == "touch")
	Scenery.tick(self)
	update_bullets(delta)
	update_zones(delta)
	update_delayed(delta)
	update_pickups(delta)
	update_secret_discovery(delta)
	enemies = enemies.filter(func(e): return not e.dead)
	if mode == "combat" and enemies.is_empty() and delayed.is_empty():
		finish_wave()
	if mode == "clear":
		var door = nearby_room_door()
		if not door.is_empty():
			advance_room(int(door.destination))
		elif player.move.length() > .08 and not try_enter_secret(true):
			pass
		elif frame.get("interact", false) and not picked_up:
			if not try_enter_secret(): emit("route_hint")

func start_dash(direction: Vector2) -> void:
	room_flags.reflected_dash = false
	room_flags.dash_dodged = false
	player.buffer_dash = 0.0
	player.dash_left = 0.2
	player.dash_dir = direction.normalized()
	player.dash_start = player.pos
	player.dash_cd = 2.0 + (0.3 if contract("d06") else 0.0)
	player.invulnerable = maxf(player.invulnerable, 0.15)
	player.charge = 0.0
	touch_charge_transfer.clear()
	emit("dash", {"pos": player.pos, "dir": direction})

func shoot_input(fire: bool, delta: float, transfer: bool = false, touch_device: bool = false) -> void:
	var weapon = db.row("weapons", player.weapon)
	if not touch_charge_transfer.is_empty() and (time > float(touch_charge_transfer.until) or str(touch_charge_transfer.weapon) != str(player.weapon) or not touch_device): touch_charge_transfer.clear()
	if not fire:
		if touch_device and player.charge > 0:
			touch_charge_transfer = {"amount": player.charge, "until": time + .15, "weapon": player.weapon, "confirmed": transfer}
		elif transfer and not touch_charge_transfer.is_empty(): touch_charge_transfer.confirmed = true
		player.charge = 0.0
		return
	if not touch_charge_transfer.is_empty():
		if touch_charge_transfer.confirmed: player.charge = maxf(player.charge, float(touch_charge_transfer.amount))
		touch_charge_transfer.clear()
	if player.shot_cd > 0.0 or player.dash_left > 0.0: return
	var charge_time = .65 if weapon.mode == "nova" else (.35 if stack("r66") > 0 else (.25 if weapon.mode in ["charged_line", "charged_arc"] else 0.0))
	if charge_time > 0:
		player.charge += delta
		if player.charge < charge_time: return
	player.charge = 0.0
	attack_uid += 1
	begin_pulse("attack_%d" % attack_uid)
	var recipe = Composer.recipe(self, weapon)
	player.shot_cd = float(recipe.interval)
	player.last_shot_direction = player.aim
	stats.shots += 1
	var damage = float(weapon.damage) * stat_multiplier("damage")
	if player.attack_bonus_until >= time: damage *= 1.0 + player.attack_bonus
	player.attack_bonus = 0.0
	var crit = roll("attack_critical").unit() < clampf(.05 + stat_bonus("crit"), 0, .65)
	if crit: damage *= 1.5
	Composer.fire(self, weapon, recipe, damage, crit, player.pos, player.aim)
	Effects.after_shot(self, damage, recipe)

func primary_hit(enemy: Dictionary, damage: float, attack: int, crit: bool = false, travel_direction: Vector2 = Vector2.ZERO, push_distance: float = -1.0, recipe: Dictionary = {}) -> void:
	if enemy.dead or time < float(enemy.get("arrival", 0)):
		return
	damage *= Effects.primary_multiplier(self, enemy)
	# Several shotgun pellets can deal damage but only one mark/proc per target/attack.
	var history = enemy.get("attack_history", {})
	for key in history.keys():
		if time > float(history[key]): history.erase(key)
	var first = not history.has(str(attack))
	history[str(attack)] = time + 8.0
	enemy.attack_history = history
	enemy.last_attack_id = attack
	if first:
		stats.hits += 1
		enemy.primary_hits += 1
		var previously_marked = int(enemy.mark) > 0
		add_mark(enemy, 1)
		if not previously_marked and stack("r20") > 0 and time - enemy.mark_energy_at < .0001:
			Effects.energy(self, 1)
		if not previously_marked and time - enemy.first_fire_at >= 2.0 and (stack("r01") > 0 or talent("t_fire_1a") > 0 or run.character == "c_lantern"):
			enemy.first_fire_at = time
			add_burn(enemy, maxi(1, stack("r01")))
		if run.character == "c_mask":
			player.passive_hits += 1
			if int(player.passive_hits) >= 3 and player.passive_cd <= 0.0:
				player.passive_hits = 0
				player.passive_cd = 12.0
				player.armor = 1
		if str(recipe.get("weapon", player.weapon)) == "w02":
			var neighbor = nearest_enemy(enemy.pos, 52, [enemy.uid])
			if not neighbor.is_empty():
				add_mark(neighbor, 1, false)
		Effects.primary_after(self, enemy, damage, attack)
	if push_distance < 0: push_distance = Impact.distance(self, "primary", crit)
	if int(enemy.get("shield_layers", 0)) > 0 and enemy.aim.dot(enemy.pos.direction_to(player.pos)) > .35:
		damage *= .2
		push_distance *= .2
		emit("deflect", {"pos": enemy.pos})
	damage_enemy(enemy, damage, "primary", crit, travel_direction, push_distance if first else 0.0)
	if first and not recipe.is_empty(): Composer.hit_effects(self, enemy.pos, damage, recipe)

func add_mark(enemy: Dictionary, count: int, grants_energy: bool = true) -> void:
	if enemy.dead or time < float(enemy.get("arrival", 0)):
		return
	var first = int(enemy.mark) == 0
	enemy.mark = mini(3, int(enemy.mark) + count)
	enemy.mark_until = time + Effects.mark_duration(self)
	if first: emit("mark_added", {"pos": enemy.pos})
	if first and grants_energy and time - enemy.mark_energy_at >= 2.0 and not contract("d07"):
		enemy.mark_energy_at = time
		player.energy = minf(100.0, player.energy + 2.0)

func add_burn(enemy: Dictionary, count: int) -> void:
	if enemy.dead or time < float(enemy.get("arrival", 0)):
		return
	if int(enemy.burn) == 0:
		enemy.burn_next = time + 1.0
	enemy.burn = mini(3, int(enemy.burn) + count)
	enemy.burn_until = time + 3.0

func nearest_enemy(position: Vector2, radius: float = 99999, excluded: Array = []) -> Dictionary:
	var nearest: Dictionary = {}
	var best = radius * radius
	for enemy in enemies:
		if enemy.dead or time < float(enemy.get("arrival", 0)) or excluded.has(enemy.uid):
			continue
		var distance = enemy.pos.distance_squared_to(position)
		if distance < best or (is_equal_approx(distance, best) and (nearest.is_empty() or enemy.uid < nearest.uid)):
			best = distance
			nearest = enemy
	return nearest

func nearest_unmarked(position: Vector2, radius: float, excluded: Array = []) -> Dictionary:
	var closest: Dictionary = {}
	var best = radius * radius
	for enemy in enemies:
		if enemy.dead or time < float(enemy.get("arrival", 0)) or enemy.mark > 0 or excluded.has(enemy.uid): continue
		var distance = position.distance_squared_to(enemy.pos)
		if distance < best or (is_equal_approx(distance, best) and (closest.is_empty() or enemy.uid < closest.uid)):
			closest = enemy
			best = distance
	return closest

func update_chains() -> void:
	var marked = enemies.filter(func(e): return not e.dead and int(e.mark) > 0)
	marked.sort_custom(func(a, b): return a.uid < b.uid)
	var available = marked.duplicate()
	var result: Array = []
	var new_pairs: Dictionary = {}
	var cap = mini(6, (4 if run.character == "c_bell" else 2) + stack("r09") + talent("t_thread_1a"))
	var radius = (200 if run.character == "c_bell" else 160) + 30 * stack("r10") + 35 * talent("t_thread_1b")
	while not available.is_empty():
		var group: Array = [available.pop_front()]
		while group.size() < cap:
			var best: Dictionary = {}
			var best_distance = float(radius * radius) + 0.001
			for candidate in available:
				for current in group:
					var distance = current.pos.distance_squared_to(candidate.pos)
					var forced = float(room_flags.forced_links.get("%d:%d" % [mini(candidate.uid, current.uid), maxi(candidate.uid, current.uid)], -1)) > time
					if forced: distance = minf(distance, radius * radius - .01)
					if distance < best_distance or (is_equal_approx(distance, best_distance) and (best.is_empty() or candidate.uid < best.uid)):
						best = candidate
						best_distance = distance
			if best.is_empty():
				break
			group.append(best)
			available.erase(best)
		if group.size() > 1:
			result.append(group.map(func(e): return int(e.uid)))
			stats.max_chain = maxi(int(stats.max_chain), group.size())
			for i in range(1, group.size()):
				var b = group[i]
				var a = group[0]
				for j in i:
					if group[j].pos.distance_squared_to(b.pos) < a.pos.distance_squared_to(b.pos):
						a = group[j]
				var pair = "%d:%d" % [mini(a.uid, b.uid), maxi(a.uid, b.uid)]
				new_pairs[pair] = true
				if not room_flags.chain_pairs.has(pair):
					emit("chain_formed", {"pos": a.pos, "pair": pair, "size": group.size(), "links": group.size() - 1})
				if stack("r11") > 0 and not room_flags.chain_pairs.has(pair) and time >= float(pair_cooldowns.get(pair, -1)):
					pair_cooldowns[pair] = time + 1.0
					# Pair cooldown plus no recursion keeps chain-form damage bounded.
					damage_enemy(a, 4, "secondary")
					damage_enemy(b, 4, "secondary")
	chains = result
	room_flags.chain_pairs = new_pairs

func enemy_by_uid(value: int) -> Dictionary:
	for enemy in enemies:
		if int(enemy.uid) == value:
			return enemy
	return {}

func skill_targets() -> Array:
	var selected: Array = []
	var skill = player.skill
	var radius = 320.0
	if skill in ["s04", "s05", "s06"]: radius = 400.0
	elif skill in ["s10", "s11", "s12"]: radius = 200.0
	elif skill in ["s13", "s14", "s15"]: radius = 420.0
	elif skill == "s02": radius = 480.0
	var bonus = 60.0 if stack("r38") > 0 and player.get("moved_distance", 0.0) >= 160 else 0.0
	for enemy in enemies:
		if enemy.dead or int(enemy.mark) <= 0:
			continue
		if skill in ["s08", "s16", "s17", "s18"]:
			var length = (520 if skill == "s08" else 480) + bonus
			var width = 36.0 if skill == "s08" else (22.0 if skill == "s17" else 40.0)
			var hit = false
			for angle in ([-.18, 0.0, .18] if skill == "s17" else [0.0]):
				if Geometry.segment_circle(player.pos, player.pos + player.aim.rotated(angle) * length, enemy.pos, width): hit = true
			if hit:
				selected.append(int(enemy.uid))
		elif skill == "s03":
			var relative = enemy.pos - player.pos
			if relative.length() <= radius + bonus and (absf(relative.x) < 36 or absf(relative.y) < 36): selected.append(int(enemy.uid))
		elif enemy.pos.distance_to(player.pos) <= radius + bonus:
			selected.append(int(enemy.uid))
	if skill == "s02":
		selected.sort_custom(func(a, b): return player.pos.distance_squared_to(enemy_by_uid(a).pos) < player.pos.distance_squared_to(enemy_by_uid(b).pos))
		selected = selected.slice(0, 2)
	if skill in ["s04", "s05", "s06"] and not selected.is_empty():
		var largest: Array = [selected[0]]
		for group in chains:
			if group.any(func(value): return selected.has(value)) and group.size() > largest.size():
				largest = group.duplicate()
		selected = largest
	# Snapshot complete groups before consumption. New marks during effects are excluded.
	var snapshot = selected.duplicate()
	for group in chains:
		if group.any(func(value): return snapshot.has(value)):
			for value in group:
				if not selected.has(value):
					selected.append(value)
	if stack("r16") > 0:
		for group in chains:
			if group.size() >= 6 or not group.any(func(value): return selected.has(value)): continue
			var extra: Dictionary = {}
			for enemy in enemies:
				if enemy.dead or enemy.mark > 0 or selected.has(enemy.uid): continue
				for i in range(1, group.size()):
					var a = enemy_by_uid(group[i - 1])
					var b = enemy_by_uid(group[i])
					if not a.is_empty() and not b.is_empty() and Geometry.segment_circle(a.pos, b.pos, enemy.pos, 20):
						if extra.is_empty() or enemy.uid < extra.uid: extra = enemy
			if not extra.is_empty():
				group.append(extra.uid)
				selected.append(extra.uid)
	return selected

func cast_skill() -> bool:
	var spec = db.row("skills", player.skill)
	var cost = skill_cost()
	if player.energy < cost:
		return false
	var targets = skill_targets()
	if bool(spec.requires_marked_target) and targets.is_empty():
		return false
	player.energy -= cost
	room_flags.free_skill_pending = false
	player.skill_cd = float(spec.cooldown_s)
	player.visual_cast_at = time
	player.moved_distance = 0.0
	player.guard_count = 0
	begin_pulse("skill")
	stats.detonations += 1
	room_flags.passive_detonate = false
	var snapshot: Array = []
	for value in targets:
		var enemy = enemy_by_uid(value)
		if not enemy.is_empty() and not enemy.dead:
			snapshot.append({"uid": value, "marks": int(enemy.mark), "burn": int(enemy.burn), "pos": enemy.pos, "chain_index": 0, "group_uid": value})
	var aligned = snapshot.filter(func(item): return item.marks > 0 and Geometry.segment_circle(player.pos, player.pos + player.aim * 600, item.pos, 36)).size() >= 3
	for item in snapshot:
		for group in chains:
			if group.has(item.uid):
				item.chain_index = group.find(item.uid)
				item.group_uid = group[0]
		var falloff = [1.0, .85, .72][mini(2, int(item.chain_index))]
		falloff = maxf(falloff, .9 * int(stack("r15") > 0))
		falloff = maxf(falloff, .85 * talent("t_thread_3a"))
		item.damage = (20 + 8 * item.marks) * float(spec.power) * falloff * Effects.detonation_multiplier(self, item, aligned)
	for item in snapshot:
		var enemy = enemy_by_uid(item.uid)
		enemy.mark = 0
		enemy.mark_until = 0.0
		if talent("t_thread_2a") > 0 and not enemy.boss: enemy.slow_until = time + .6
		if (player.skill == "s12" or talent("t_seal_3a") > 0) and enemy.shield_layers > 0: enemy.shield_layers -= 1
	match player.skill:
		"s05":
			for item in snapshot:
				var enemy = enemy_by_uid(item.uid)
				Impact.root(self, enemy, .5)
			delayed.append({"time": time + .5, "type": "skill_first", "items": snapshot.duplicate(true), "factor": 1.0, "pulse": active_pulse})
		"s11":
			player.guard = .4
			delayed.append({"time": time + .4, "type": "guard_counter", "items": snapshot.duplicate(true), "pulse": active_pulse})
		"s14":
			execute_skill_snapshot(snapshot, true, .25)
			for i in range(1, 4): delayed.append({"time": time + i * .6, "type": "skill_replay", "items": snapshot.duplicate(true), "factor": .25, "pulse": active_pulse})
		_:
			execute_skill_snapshot(snapshot, true)
	if player.skill in ["s06", "s18"]:
		delayed.append({"time": time + (.5 if player.skill == "s06" else 1.0), "type": "skill_replay", "items": snapshot.duplicate(true), "factor": .55, "pulse": active_pulse})
	if player.skill == "s09":
		add_zone(player.pos, 78, Effects.fire_duration(self, 2.5), 6, true)
		zones[-1].follows_player = true
		zones[-1].mark_once = true
		zones[-1].marked = []
	if player.skill == "s10": player.guard = .16
	if player.skill == "s15":
		for bullet in bullets:
			if bullet.friendly and bullet.can_return and not bullet.get("wind_accelerated", false):
				bullet.speed *= 1.25
				bullet.wind_accelerated = true
	if player.skill == "s13":
		for pickup in pickups:
			if pickup.kind == "ash" and pickup.pos.distance_to(player.pos) <= 420:
				pickup.delay = 0.0
				pickup.magnet = true
	Effects.after_skill(self, targets, snapshot)
	chains.clear()
	emit("skill", {"pos": player.pos, "dir": player.aim, "points": snapshot.map(func(item): return item.pos), "targets": snapshot.size(), "character": run.character, "skill": player.skill})
	return true

func execute_skill_snapshot(snapshot: Array, first_segment: bool, factor: float = 1.0) -> void:
	var targets = snapshot.map(func(item): return item.uid)
	for item in snapshot:
		var enemy = enemy_by_uid(item.uid)
		if enemy.is_empty() or enemy.dead: continue
		var damage = item.damage * factor
		damage_enemy(enemy, damage, "detonate" if first_segment else "secondary")
		if first_segment:
			Effects.detonation_after(self, item, damage, targets)
			if player.skill == "s07": add_zone(item.pos, 68, Effects.fire_duration(self, 3.0), 6, true)
		var blast_radius = 45.0 + 10 * item.marks
		Scenery.area_hit(self, item.pos, blast_radius, damage)
		emit("burst", {"pos": item.pos, "radius": blast_radius})

func damage_enemy(enemy: Dictionary, amount: float, source: String, crit: bool = false, travel_direction: Vector2 = Vector2.ZERO, push_distance: float = -1.0) -> void:
	if enemy.dead or time < float(enemy.get("arrival", 0)):
		return
	if source == "secondary" and not claim_secondary(): return
	var damage = maxf(1.0, amount)
	if enemy.boss and enemies.any(func(e): return not e.dead and e.get("guarding_boss", -1) == enemy.uid) and time > enemy.guard_open:
		damage *= .45
	BossPattern.hit(self, enemy, source)
	enemy.hp -= damage
	enemy.hit_flash = 0.07
	CreatureAction.hurt(enemy, time, enemy.pos.direction_to(player.pos))
	if source == "secondary":
		stats.secondary_hits += 1
	var weapon_mode = str(db.row("weapons", player.weapon).get("mode", "")) if not player.weapon.is_empty() else ""
	emit("hit", {"pos": enemy.pos, "uid": enemy.uid, "damage": damage, "source": source, "crit": crit,
		"heavy": source == "detonate", "weapon": player.weapon, "weapon_mode": weapon_mode})
	if enemy.hp <= 0.0:
		kill_enemy(enemy, source)
	else:
		var direction = travel_direction if travel_direction.length_squared() > .0001 else player.pos.direction_to(enemy.pos)
		Impact.push(self, enemy, direction, Impact.distance(self, source, crit) if push_distance < 0 else push_distance)

func kill_enemy(enemy: Dictionary, source: String) -> void:
	if enemy.dead:
		return
	enemy.dead = true
	enemy.push_left = 0.0
	enemy.push_remaining = Vector2.ZERO
	var key = room_key() + "/enemy_" + str(int(enemy.uid))
	if enemy_ledger.has(key):
		return
	enemy_ledger[key] = true
	if enemy.boss and not run.bosses_defeated.has(enemy.id): run.bosses_defeated.append(enemy.id)
	stats.kills += 1
	room_flags.combat_kills += 1
	var natural = bool(enemy.natural_reward)
	var ash = int(db.rules.combat.get("boss_ash", 30)) if enemy.boss else int(enemy.get("ash_reward", db.rules.combat.get("elite_ash", 16) if enemy.elite else db.rules.combat.get("natural_ash", 8)))
	if not natural:
		ash = 4
	pickups.append({"uid": next_uid(), "kind": "ash", "pos": enemy.pos, "value": ash, "delay": 0.6 + (0.5 if contract("d03") else 0.0), "natural": natural, "magnet": false})
	var drop_random = roll("kill_drops" if run.get("campaign", false) else "loot")
	if natural and drop_random.unit() < 0.6:
		pickups.append({"uid": next_uid(), "kind": "coin", "pos": enemy.pos + Vector2(14, 0), "value": drop_random.between(1, 2), "delay": 0.15, "natural": true, "magnet": false})
	# Secondary kills never start the gray-bullet kill cascade.
	if natural and source != "secondary" and stack("r18") > 0:
		var target = nearest_enemy(enemy.pos, 500, [enemy.uid])
		if not target.is_empty():
			secondary_bullet(enemy.pos, enemy.pos.direction_to(target.pos), float(db.row("weapons", player.weapon).damage) * 0.35)
	if source == "detonate" and run.character == "c_paper" and not room_flags.passive_detonate:
		room_flags.passive_detonate = true
		player.energy = minf(100.0, player.energy + 4.0)
	Effects.on_death(self, enemy, source)
	Equipment.death_drop(self, enemy)
	BossPattern.guard_destroyed(self, enemy)
	if enemy.boss:
		for guard in enemies:
			if guard.get("guarding_boss", -1) == enemy.uid and not guard.dead: kill_enemy(guard, "secondary")
	emit("death", {"uid": enemy.uid, "pos": enemy.pos, "boss": enemy.boss, "id": enemy.id, "sprite_id": enemy.get("sprite_id", enemy.id), "elite": enemy.elite})

func secondary_bullet(position: Vector2, direction: Vector2, damage: float) -> Dictionary:
	if bullets.size() >= 240 or not claim_secondary():
		return {}
	var bullet = {"uid": next_uid(), "pos": geometry.constrain_floor(position, 5), "dir": direction.normalized(), "speed": 550.0, "range": 500.0, "travel": 0.0,
		"damage": damage, "radius": 5.0, "friendly": true, "primary": false, "attack": -1, "crit": false,
		"mode": "ash", "pierce": 0, "hits": [], "returning": false, "bounces": 0, "age": 0.0, "can_return": false, "target_index": 0, "pulse": active_pulse}
	bullets.append(bullet)
	return bullet

func source_of(enemy: Dictionary, kind: String) -> Dictionary:
	return Damage.from_enemy(self, enemy, kind)

func enemy_bullet(position: Vector2, direction: Vector2, speed: float, damage: int = 1, radius: float = 7.0, source: Dictionary = {}) -> void:
	if bullets.size() >= 240:
		return
	var profile = ProjectileStyles.enemy(source)
	radius = ProjectileStyles.radius(profile, radius)
	bullets.append({"uid": next_uid(), "pos": geometry.constrain_floor(position, radius), "dir": direction.normalized(), "speed": speed,
		"range": 1600.0, "travel": 0.0, "damage": damage, "radius": radius, "friendly": false,
		"primary": false, "attack": -1, "crit": false, "mode": "enemy", "pierce": 0,
		"hits": [], "returning": false, "bounces": 0, "age": 0.0, "can_return": false,
		"source": Damage.normalize(source, position, "projectile"), "visual_profile": profile})

func update_bullets(delta: float) -> void:
	var next: Array = []
	var processed: Dictionary = {}
	for bullet in bullets.duplicate():
		processed[bullet.uid] = true
		active_pulse = str(bullet.get("pulse", ""))
		bullet.age += delta
		ExpandedPattern.projectile(bullet, delta)
		var composed_steering = Composer.tick(self, bullet, delta)
		if not composed_steering: ExpandedWeapons.tick(self, bullet, delta)
		if bullet.returning:
			bullet.dir = bullet.pos.direction_to(player.pos)
		elif not composed_steering and bullet.mode == "controlled" and bullet.get("controllable", false) and player.aim.length_squared() > .01:
			# The paper moth follows the live aim vector with a short, readable
			# steering lag. It remains deterministic because the input frame is fixed.
			bullet.dir = bullet.dir.slerp(player.aim.normalized(), minf(1.0, delta * 7.0)).normalized()
		elif not composed_steering and bullet.mode == "seeker" and bullet.age > 0.2:
			var target = nearest_enemy(bullet.pos, 300)
			if not target.is_empty():
				bullet.dir = bullet.dir.slerp(bullet.pos.direction_to(target.pos), 0.04).normalized()
		var previous = Vector2(bullet.pos)
		bullet.pos += bullet.dir * bullet.speed * delta
		bullet.travel += bullet.speed * delta
		var remove = false
		if bullet.friendly and Scenery.segment_hit(self, previous, bullet.pos, bullet.damage):
			projectile_impact(bullet, bullet.pos)
			continue
		if not geometry.clear_swept_segment(previous, bullet.pos, bullet.radius):
			var bounce_limit = int(bullet.get("recipe", {}).get("bounces", 2 if bullet.mode == "ricochet" else 0))
			if not bullet.friendly or int(bullet.bounces) >= bounce_limit: projectile_impact(bullet, previous)
			if not bullet.friendly and int(bullet.get("hostile_bounces", 0)) > 0:
				bullet.dir = -Vector2(bullet.dir)
				bullet.pos = previous
				bullet.hostile_bounces -= 1
				next.append(bullet)
				continue
			if not bullet.friendly and bullet.get("splits_on_wall", false):
				var source = Damage.normalize(bullet.get("source", {}), previous, "split")
				source.kind = "split"
				for angle in [-.65, 0, .65]: enemy_bullet(previous, -bullet.dir.rotated(angle), 145, int(bullet.damage), 6, source)
			if bullet.friendly and int(bullet.bounces) < bounce_limit:
				var clamped = geometry.constrain_floor(bullet.pos, bullet.radius)
				if not is_equal_approx(clamped.x, bullet.pos.x):
					bullet.dir.x *= -1
				else:
					bullet.dir.y *= -1
				bullet.pos = previous
				bullet.bounces += 1
			elif bullet.friendly and bullet.can_return and not bullet.returning:
				start_return(bullet)
				bullet.pos = previous
			else:
				remove = true
		if remove:
			continue
		if bullet.friendly:
			var collided: Array = []
			for enemy in enemies:
				if not enemy.dead and time >= float(enemy.get("arrival", 0)) and not bullet.hits.has(enemy.uid) and Geometry.segment_circle(previous, bullet.pos, enemy.pos, enemy.radius + bullet.radius):
					collided.append(enemy)
			collided.sort_custom(func(a, b): return previous.distance_squared_to(a.pos) < previous.distance_squared_to(b.pos))
			for enemy in collided:
				bullet.hits.append(enemy.uid)
				bullet.target_index = int(bullet.get("target_index", 0)) + 1
				if bullet.primary:
					primary_hit(enemy, bullet.damage, bullet.attack, bullet.crit, bullet.dir, float(bullet.get("push_distance", -1.0)), bullet.get("recipe", {}))
					if bullet.target_index == 3 and stack("r48") > 0 and Effects.ready(self, "empty_ledger", 3.0): add_mark(enemy, 3, false)
				else:
					damage_enemy(enemy, bullet.damage, "secondary", false, bullet.dir)
					if bullet.has("recipe"): Composer.hit_effects(self, enemy.pos, bullet.damage, bullet.recipe)
					if bullet.get("applies_mark", false): add_mark(enemy, 1, false)
				if bullet.mode == "returning":
					continue
				if int(bullet.pierce) > 0:
					bullet.pierce -= 1
					bullet.damage *= .85 + .15 * int(stack("r44") > 0)
				else:
					projectile_impact(bullet, bullet.pos)
					if bullet.can_return and not bullet.returning: start_return(bullet)
					else: remove = true
					break
			if bullet.returning and bullet.pos.distance_to(player.pos) < 18:
				remove = true
		else:
			if Geometry.segment_circle(previous, bullet.pos, player.pos, 12 + bullet.radius):
				if player.guard > 0 and player.aim.dot(player.pos.direction_to(bullet.pos)) > -0.1:
					deflect(bullet)
				elif player.dash_left > (.12 if stack("r30") > 0 else .14) and (talent("t_seal_1b") > 0 or stack("r30") > 0) and not room_flags.get("reflected_dash", false):
					room_flags.reflected_dash = true
					deflect(bullet)
					Effects.dodge(self)
				elif player.invulnerable > 0:
					if player.dash_left > 0 and not room_flags.get("dash_dodged", false):
						Effects.dodge(self)
				else:
					damage_player(int(bullet.damage), bullet.get("source", Damage.normalize({}, previous, "projectile")), previous)
				remove = true
		if bullet.travel >= bullet.range:
			projectile_impact(bullet, bullet.pos)
			if bullet.friendly and bullet.can_return and not bullet.returning:
				start_return(bullet)
			else:
				remove = true
		if not remove:
			next.append(bullet)
	# Preserve bullets spawned by hit/death effects while iterating a stable snapshot.
	for bullet in bullets:
		if not processed.has(bullet.uid):
			next.append(bullet)
	bullets = next

func projectile_impact(bullet: Dictionary, point: Vector2) -> void:
	if not Composer.impact(self, bullet, point): ExpandedWeapons.impact(self, bullet, point)

func start_return(bullet: Dictionary) -> void:
	bullet.returning = true
	bullet.primary = false
	bullet.travel = 0.0
	bullet.hits = []
	bullet.damage *= (.65 + .25 * stack("r35")) if bullet.mode == "returning" else .35
	bullet.damage *= 1.0 + .2 * talent("t_wind_2a")

func deflect(bullet: Dictionary) -> void:
	begin_pulse("deflect")
	Effects.deflect(self)
	secondary_bullet(player.pos, -bullet.dir, float(bullet.damage) * 12)
	emit("deflect", {"pos": player.pos})

func damage_player(amount: int, source: Dictionary = {}, incoming = null) -> void:
	if player.invulnerable > 0.0 or mode not in ["combat", "clear"]:
		return
	var raw = amount
	var hp_before = int(player.hp)
	var revived = false
	if int(player.armor) > 0:
		player.armor = 0
		amount = maxi(0, amount - 1)
		Effects.armor_break(self)
		emit("armor_break", {"pos": player.pos})
	if amount > 0:
		var key = "goldbody_" + str(int(run.floor))
		if stack("r32") > 0 and not chapter_favor_used("goldbody"):
			run.favors_used[key] = true
			amount = maxi(0, amount - 1)
			room_flags.goldbody_slow = true
		player.hp = maxi(0, int(player.hp) - amount)
		stats.damage_taken += amount
		if player.hp <= 0 and stack("r29") > 0 and not run.consumed.has("r29"):
			player.hp = 1
			revived = true
			run.relics.erase("r29")
			run.consumed.append("r29")
			emit("revive", {"pos": player.pos})
	player.invulnerable = 0.8
	player.visual_hurt_at = time
	var origin = Damage.normalize(source, player.pos)
	var direction = player.pos.direction_to(incoming if incoming is Vector2 else origin.origin)
	if raw > 0:
		var record = {"source": origin, "raw": raw, "damage": amount, "absorbed": raw - amount, "hp_before": hp_before, "hp_after": int(player.hp),
			"revived": revived, "lethal": player.hp <= 0, "pos": Vector2(player.pos), "direction": direction, "at": time, "floor": int(run.floor), "room": int(run.room)}
		if not run.has("damage_history"): run.damage_history = []
		run.damage_history.append(record)
		if run.damage_history.size() > 12: run.damage_history.pop_front()
		if record.lethal: run.death_cause = record.duplicate(true)
	emit("player_hurt", {"pos": player.pos, "hp": player.hp, "damage": amount, "source": origin, "direction": direction})
	if player.hp <= 0:
		player.visual_death_at = time
		mode = "result"
		run.result = "defeat"
		emit("run_end", {"win": false})
		emit("save_requested")

func update_enemies(delta: float) -> void:
	if contract("d02") and room_type() == "combat" and time >= float(room_flags.get("debt_fire_at", INF)):
		room_flags.debt_fire_at = time + 3.0
		var pair = room_flags.get("debt_pair", [])
		if pair.size() == 2:
			var a = enemy_by_uid(pair[0])
			var b = enemy_by_uid(pair[1])
			if not a.is_empty() and not b.is_empty() and not a.dead and not b.dead:
				var origin = (a.pos + b.pos) * .5
				delayed.append({"type": "debt_bullet", "time": time + .8, "pos": origin, "aim": origin.direction_to(player.pos), "pair": pair.duplicate()})
				emit("debt_warning", {"pos": origin, "aim": origin.direction_to(player.pos), "duration": .8})
	for enemy in enemies.duplicate():
		if enemy.dead:
			continue
		if time < float(enemy.get("arrival", 0)): continue
		var pushed = Impact.tick(self, enemy, delta)
		enemy.hit_flash = maxf(0.0, enemy.hit_flash - delta)
		if time >= enemy.mark_until:
			enemy.mark = 0
		if time > enemy.burn_until:
			enemy.burn = 0
		if int(enemy.burn) > 0 and time >= enemy.burn_next:
			begin_pulse("burn_%d" % enemy.uid)
			enemy.burn_next += 1.0
			damage_enemy(enemy, 3.0 * int(enemy.burn), "burn")
			Effects.burn_tick(self, enemy)
			if enemy.dead:
				continue
		if time < float(enemy.get("stun_until", 0)): continue
		if enemy.boss:
			var phase = mini(2, int((1.0 - enemy.hp / enemy.max_hp) * 3.0))
			if phase > int(enemy.phase):
				enemy.phase = phase
				if enemy.windup > 0: enemy.visual_prepare_state = CreatureAction.next_attack_state(enemy)
				enemy.visual_phase_at = time
				emit("boss_phase", {"phase": phase, "pos": enemy.pos})
				var spec = db.row("bosses", enemy.id)
				BossPattern.phase_enter(self, enemy, phase)
				if spec.fixed_heal_phase_indices.has(phase) and reward_once("boss_heal_%d" % phase):
					pickups.append({"uid": next_uid(), "kind": "heal", "pos": Vector2(640, 520), "value": 2, "delay": 0.0, "natural": false, "magnet": false})
		if enemy.lunge > 0:
			enemy.visual_lunge_attack = true
			enemy.lunge -= delta
			if enemy.lunge <= 0: enemy.visual_attack_recovery_at = time
			enemy.pos = geometry.slide(enemy.pos, enemy.aim * 490 * delta, enemy.radius)
			if enemy.pos.distance_to(player.pos) < enemy.radius + 12:
				if player.invulnerable > 0 and player.dash_left > 0: Effects.dodge(self)
				else: damage_player(int(enemy.damage), source_of(enemy, "lunge"))
			continue
		if enemy.windup > 0:
			enemy.windup -= delta
			if enemy.windup <= 0:
				enemy_attack(enemy)
			continue
		enemy.attack_cd -= delta
		if enemy.attack_cd <= 0:
			enemy.windup = enemy.tell
			enemy.target = player.pos
			enemy.aim = enemy.pos.direction_to(player.pos)
			CreatureAction.prepare(enemy, time)
			emit("telegraph", {"pos": enemy.pos, "enemy": enemy.id})
			continue
		var distance = enemy.pos.distance_to(player.pos)
		if ExpandedPattern.eligible(enemy):
			if not pushed: ExpandedPattern.move(self, enemy, delta)
			if enemy.pos.distance_to(player.pos) < enemy.radius + 12: damage_player(int(enemy.damage), source_of(enemy, "contact"))
			continue
		var wants_move = distance > (200 if enemy.boss else 240)
		if enemy.id in ["e02", "e04", "e13", "e17", "e21", "e23"]:
			wants_move = distance > 110
		if enemy.id in ["e15", "e20"] or enemy.get("sigil", false): wants_move = false
		if enemy.boss and enemies.any(func(e): return not e.dead and e.get("guarding_boss", -1) == enemy.uid): wants_move = false
		if wants_move and not pushed:
			var direction = geometry.toward(enemy.pos, player.pos)
			direction = EnemyPattern.movement(enemy, direction, time)
			var speed = enemy.speed * (0.75 if time < enemy.slow_until else 1.0)
			if not enemy.boss and stack("r12") > 0 and chains.any(func(group): return group.has(enemy.uid)): speed *= .85
			# Gentle separation avoids enemies occupying the same firing point.
			for other in enemies:
				if other.uid != enemy.uid and not other.dead and enemy.pos.distance_to(other.pos) < enemy.radius + other.radius + 6:
					direction += other.pos.direction_to(enemy.pos) * 0.5
			enemy.pos = geometry.slide(enemy.pos, direction.limit_length() * speed * delta, enemy.radius)
		if enemy.pos.distance_to(player.pos) < enemy.radius + 12:
			damage_player(int(enemy.damage), source_of(enemy, "contact"))

func enemy_attack(enemy: Dictionary) -> void:
	CreatureAction.strike(enemy, time)
	enemy.attack_cd = 1.4 + roll("enemy_timing_%d" % int(enemy.uid)).unit() * 0.6
	if enemy.boss:
		if ExpandedPattern.eligible(enemy): ExpandedPattern.attack(self, enemy)
		else: BossPattern.attack(self, enemy)
	else:
		if ExpandedPattern.eligible(enemy): ExpandedPattern.attack(self, enemy)
		else: EnemyPattern.attack(self, enemy)
	CreatureAction.finish_attack_setup(enemy, time)

func add_zone(position: Vector2, radius: float, duration: float, damage: float, friendly: bool, warning: float = 0.0, source: Dictionary = {}) -> void:
	if zones.size() >= 48: return
	zones.append({"uid": next_uid(), "pos": position, "radius": radius, "until": time + warning + duration,
		"active": time + warning, "born": time, "next": time + warning, "damage": damage, "friendly": friendly, "pulse": active_pulse})
	if not friendly: zones[-1].source = Damage.normalize(source, position, "zone")

func update_zones(unused_delta: float) -> void:
	for zone in zones.duplicate():
		active_pulse = str(zone.get("pulse", ""))
		if zone.get("follows_player", false): zone.pos = player.pos
		if time > zone.until:
			zones.erase(zone)
			continue
		if time < zone.active or time < zone.next:
			continue
		if zone.get("anticipation_only", false): continue
		zone.next = time + (1.0 if zone.friendly else 0.6)
		if zone.friendly:
			for enemy in enemies.duplicate():
				var inside = Geometry.segment_circle(zone.from, zone.to, enemy.pos, float(zone.width) + enemy.radius) if zone.get("shape", "") == "line" else enemy.pos.distance_to(zone.pos) < enemy.radius + zone.radius
				if not enemy.dead and inside and geometry.clear_segment(zone.pos, enemy.pos):
					if zone.get("item_slow", false): enemy.slow_until = maxf(enemy.slow_until, time + 1.1)
					if zone.get("mark_once", false) and not zone.marked.has(enemy.uid):
						zone.marked.append(enemy.uid)
						add_mark(enemy, 1, false)
					damage_enemy(enemy, zone.damage, "secondary")
		elif (Geometry.segment_circle(zone.from, zone.to, player.pos, zone.width + 12) if zone.get("shape", "") == "line" else player.pos.distance_to(zone.pos) < zone.radius + 12):
			if player.invulnerable > 0 and player.dash_left > 0: Effects.dodge(self)
			else: damage_player(int(zone.damage), zone.get("source", Damage.normalize({}, zone.pos, "zone")), zone.pos)

func update_delayed(unused_delta: float) -> void:
	for action in delayed.duplicate():
		if time < action.time:
			continue
		delayed.erase(action)
		active_pulse = str(action.get("pulse", ""))
		if Composer.delayed(self, action): continue
		if ExpandedWeapons.delayed(self, action): continue
		if action.type == "fixed_damage":
			for enemy in enemies.duplicate():
				if not enemy.dead and enemy.pos.distance_to(action.pos) <= action.radius + enemy.radius:
					damage_enemy(enemy, action.damage, "secondary")
			Scenery.area_hit(self, action.pos, action.radius, action.damage)
			emit("burst", {"pos": action.pos, "radius": action.radius, "small": true})
		elif action.type == "fixed_target":
			var enemy = enemy_by_uid(action.target)
			if not enemy.is_empty(): damage_enemy(enemy, action.damage, "secondary")
		elif action.type in ["skill_first", "skill_replay", "guard_counter"]:
			var factor = float(action.get("factor", 1.0))
			if action.type == "guard_counter": factor += .15 * mini(3, int(player.guard_count))
			execute_skill_snapshot(action.items, action.type != "skill_replay", factor)
		elif action.type == "repeat_attack":
			replay_attack(action)
		elif action.type == "enemy_fan":
			var enemy = enemy_by_uid(action.uid)
			if enemy.is_empty() or enemy.dead: continue
			var from = action.get("pos", enemy.pos)
			var aim = action.get("aim", enemy.aim)
			CreatureAction.strike(enemy, time, aim)
			for i in int(action.count): enemy_bullet(from, aim.rotated((i - (int(action.count) - 1) / 2.0) * action.spread), action.speed, enemy.damage, 7, source_of(enemy, "projectile"))
		elif action.type == "enemy_lunge":
			var enemy = enemy_by_uid(action.uid)
			if not enemy.is_empty() and not enemy.dead:
				enemy.aim = enemy.pos.direction_to(player.pos)
				enemy.windup = .45
				CreatureAction.prepare(enemy, time, .45)
		elif action.type == "debt_bullet":
			if action.pair.all(func(id): var e = enemy_by_uid(id); return not e.is_empty() and not e.dead):
				enemy_bullet(action.pos, action.aim, 165, 1, 7, Damage.normalize({"id": "d02", "table": "debt_contracts", "kind": "debt"}, action.pos))

func replay_attack(action: Dictionary) -> void:
	var weapon = db.row("weapons", action.weapon)
	if action.has("recipe"):
		Composer.fire(self, weapon, action.recipe, action.damage, false, action.pos, action.aim)
		return
	if weapon.mode in ["cone", "arc", "charged_arc"]:
		for enemy in enemies.duplicate():
			var width = 1.05 if weapon.mode == "charged_arc" else .8
			if not enemy.dead and enemy.pos.distance_to(action.pos) <= weapon.range and action.aim.dot(action.pos.direction_to(enemy.pos)) >= cos(width):
				damage_enemy(enemy, action.damage, "secondary")
			emit("slash", {"pos": action.pos, "dir": action.aim, "range": weapon.range, "weapon": action.weapon, "mode": weapon.mode, "charged": weapon.mode == "charged_arc"})
	elif weapon.mode == "ray":
		var ray_width = 14.0 + 4.0 * stack("r41")
		var ray_origin = geometry.constrain_floor(action.pos,ray_width)
		var ray_end = geometry.clipped_ray(ray_origin, ray_origin + action.aim * float(weapon.range), ray_width)
		for enemy in enemies.duplicate():
			if not enemy.dead and geometry.clear_segment(ray_origin, enemy.pos) and Geometry.segment_circle(ray_origin, ray_end, enemy.pos, enemy.radius + ray_width):
				damage_enemy(enemy, action.damage, "secondary", false, action.aim)
		emit("ray", {"pos": ray_origin, "end": ray_end, "dir": action.aim, "range": ray_origin.distance_to(ray_end), "width": ray_width, "weapon": action.weapon, "heavy": true, "style": "beam_ink"})
	else:
		for i in int(weapon.pellets):
			var direction = action.aim.rotated((i - (int(weapon.pellets) - 1) / 2.0) * float(weapon.get("spread", .15)))
			var bullet = secondary_bullet(action.pos, direction, action.damage)
			if bullet.is_empty(): break
			bullet.mode = weapon.mode
			bullet.range = weapon.range
			bullet.speed = weapon.projectile_speed
			bullet.pierce = int(weapon.pierce) + stack("r41") + talent("t_ink_1a") + int(run.character == "c_ink")
			bullet.can_return = weapon.mode == "returning"

func set_pickup_scale(value: float) -> void:
	if not run.is_empty(): run.pickup_radius_scale = clampf(value if is_finite(value) else 1.0, .5, 1.25)

func update_pickups(delta: float) -> void:
	for pickup in pickups.duplicate():
		pickup.delay = maxf(0.0, pickup.delay - delta)
		if pickup.delay > 0 or pickup.kind in Equipment.MANUAL_KINDS:
			continue
		var radius = 120.0
		if pickup.kind == "ash":
			radius = Effects.ash_radius(self)
		elif pickup.kind == "coin": radius = minf(160, 120 + float(run.get("coin_pickup_bonus", 0)))
		elif pickup.kind == "heal":
			radius = 24.0
		if pickup.kind != "heal": radius *= clampf(float(run.get("pickup_radius_scale", 1.0)), .5, 1.25) * stat_multiplier("pickup_radius")
		if pickup.magnet or pickup.pos.distance_to(player.pos) < radius or (mode == "clear" and pickup.kind != "heal"):
			pickup.magnet = true
			pickup.pos = pickup.pos.move_toward(player.pos, 650 * delta)
			if pickup.pos.distance_to(player.pos) < 20:
				collect(pickup)
				pickups.erase(pickup)

func collect(pickup: Dictionary) -> void:
	match pickup.kind:
		"ash":
			var amount = float(pickup.value)
			if pickup.natural:
				amount += 2 * stack("r17") + talent("t_ash_1a") + int(run.character == "c_umbrella")
			player.energy = minf(100.0, player.energy + amount)
			stats.ash_energy += amount
			Effects.on_ash(self, pickup)
		"coin":
			run.coins += int(pickup.value)
		"heal":
			if int(player.hp) >= int(player.max_hp):
				run.coins += 3
			else:
				player.hp = mini(int(player.max_hp), int(player.hp) + int(pickup.value))
			run.heal_misses = 0
	emit("pickup", {"pos": pickup.pos, "type": pickup.kind})

func clear_room() -> void:
	if int(room_flags.get("wave_index", 1)) < int(room_flags.get("wave_count", 1)): return
	if not reward_once("clear"):
		return
	mode = "clear"
	bullets = bullets.filter(func(b): return b.friendly)
	zones = zones.filter(func(z): return z.friendly)
	run.cleared += 1
	var room_kind = room_type()
	var type = "boss" if room_kind == "optional_boss" else room_kind
	run.coins += maxi(1, int(db.rules.loot.clear_coins.get(type, 0)) - int(type == "combat" and contract("d05")))
	run.merit += int(db.rules.progression.meta_currency.get(type, 0))
	run.xp += int(db.rules.progression.xp.get(type, 0))
	if stack("r26") > 0:
		player.armor = 1
	Effects.clear_room(self, type)
	Equipment.charge(self, 2.0 if type == "boss" else 1.0)
	for pickup in pickups:
		if pickup.kind in ["ash", "coin"]:
			pickup.delay = 0.0
			collect(pickup)
	pickups = pickups.filter(func(p): return p.kind not in ["ash", "coin"])
	Equipment.rare_drop(self, "room_clear", "room", geometry.nearest_free(player.pos + Vector2(42, -30), 16))
	if type in ["combat", "elite", "challenge"]:
		generate_heal()
	while int(run.level) < db.rules.progression.level_thresholds.size() and int(run.xp) >= db.rules.progression.level_thresholds[int(run.level)]:
		run.level += 1
		choice_queue.append({"kind": "talent", "items": []})
	if type == "elite":
		choice_queue.append({"kind": "relic", "items": relic_offer(3)})
	elif type == "challenge":
		choice_queue.append({"kind": "relic", "items": challenge_offer(3)})
	elif type == "boss":
		player.max_hp = mini(12, int(player.max_hp) + 1)
		player.hp = mini(int(player.max_hp), int(player.hp) + 2)
		choice_queue.append({"kind": "relic", "items": relic_offer(2)})
		if room_kind == "boss": choice_queue.append({"kind": "floor_end", "items": []})
	emit("room_clear", {"type": type})
	open_next_choice()
	emit("save_requested")

func generate_heal() -> bool:
	var low = int(player.hp) <= float(player.max_hp) * 0.5
	if not low:
		run.heal_misses = 0
	var chance = minf(0.44, 0.12 + 0.08 * int(run.heal_misses))
	var guaranteed = low and int(run.heal_misses) >= 2
	if guaranteed or roll("loot").unit() < chance:
		if reward_once("heal_drop"):
			run.heal_misses = 0
			pickups.append({"uid": next_uid(), "kind": "heal", "pos": Vector2(640, 360), "value": 2, "delay": 0.0, "natural": false, "magnet": false})
			return true
	elif low:
		run.heal_misses += 1
	return false

func relic_offer(count: int = 3, first_affinity: bool = false) -> Array:
	var offer_rng = roll("shop" if mode == "shop" else "loot")
	var candidates: Array = []
	var weights: Array = []
	var rarity = db.rules.loot.rarity_by_floor[str(int(run.floor))]
	var repayment_offer = int(run.get("repay_reward_pending", 0)) > 0
	for id in run.get("relic_pool", db.rules.progression.initial_relic_ids):
		var row = db.row("relics", id)
		if stack(id) >= int(row.stack_limit) or run.consumed.has(id):
			continue
		if row.min_floor > run.floor or row.max_floor < run.floor:
			continue
		if repayment_offer and row.rarity not in ["rare", "mythic"]: continue
		# Oil-paper only enters the initial offer when a persistent fire field exists.
		if id == "r03" and run.character != "c_lantern" and stack("r04") == 0 and talent("t_fire_3a") == 0 and stack("r50") == 0:
			continue
		if id == "r25" and run.character != "c_mask" and talent("t_seal_1b") == 0 and stack("r30") == 0:
			continue
		candidates.append(id)
		weights.append(0.0)
	var counts: Dictionary = {}
	if repayment_offer and candidates.is_empty():
		var pending_count = run.repay_reward_pending
		run.repay_reward_pending = 0
		var fallback = relic_offer(count, first_affinity)
		run.repay_reward_pending = pending_count
		return fallback
	for id in candidates:
		var grade = str(db.row("relics", id).rarity)
		counts[grade] = int(counts.get(grade, 0)) + 1
	for i in candidates.size():
		var grade = str(db.row("relics", candidates[i]).rarity)
		weights[i] = float(rarity.get(grade, 0)) / int(counts[grade])
	var result: Array = []
	if repayment_offer and not candidates.is_empty(): run.repay_reward_pending -= 1
	for i in mini(count, candidates.size()):
		var value = ""
		if first_affinity and i == 0:
			var affinity = candidates.filter(func(id): return db.row("relics", id).routes.any(func(route): return db.row("characters", run.character).routes.has(route)))
			value = str(offer_rng.choose(affinity)) if not affinity.is_empty() else str(offer_rng.weighted(candidates, weights))
		else:
			value = str(offer_rng.weighted(candidates, weights))
		if value == "<null>" or value.is_empty():
			break
		result.append({"kind": "relic", "id": value, "price": 0, "slot": str(next_uid())})
		var at = candidates.find(value)
		candidates.remove_at(at)
		weights.remove_at(at)
	return result

func challenge_offer(count: int = 3) -> Array:
	var candidates: Array = []
	for id in run.get("relic_pool", db.rules.progression.initial_relic_ids):
		var row = db.row("relics", id)
		if row.is_empty() or stack(id) >= int(row.stack_limit) or run.consumed.has(id): continue
		if row.min_floor > run.floor or row.max_floor < run.floor: continue
		candidates.append(id)
	var rare = candidates.filter(func(id): return db.row("relics", id).rarity in ["rare", "mythic"])
	if rare.size() >= count: candidates = rare
	var result: Array = []
	while result.size() < mini(count, candidates.size()):
		var picked = str(roll("challenge_loot").choose(candidates))
		if picked.is_empty() or picked == "<null>": break
		result.append({"kind": "relic", "id": picked, "price": 0, "slot": str(next_uid()), "challenge": true})
		candidates.erase(picked)
	return result

func talent_offer() -> Array:
	var available: Array = []
	var weights: Array = []
	for row in db.rows("talents"):
		var points = 0
		for id in run.talents: points += int(db.row("talents", id).route == row.route)
		if not run.talents.has(row.id) and points >= int(row.min_route_points):
			available.append({"kind": "talent", "id": row.id, "price": 0, "slot": str(next_uid())})
			weights.append(minf(1.6, 1.0 + 0.15 * points))
	var result: Array = []
	var target_tier = clampi(ceili(float(run.level) / 2.0), 1, 3)
	for i in mini(3, available.size()):
		var preferred: Array = []
		var preferred_weights: Array = []
		for j in available.size():
			if db.row("talents", available[j].id).tier == target_tier:
				preferred.append(available[j])
				preferred_weights.append(weights[j])
		var picked = roll("loot").weighted(preferred, preferred_weights) if not preferred.is_empty() else roll("loot").weighted(available, weights)
		var at = available.find(picked)
		result.append(picked)
		available.remove_at(at)
		weights.remove_at(at)
	return result

func open_next_choice() -> void:
	if choice_queue.is_empty():
		mode = "clear"
		choices.clear()
		return
	var next = choice_queue.pop_front()
	if next.kind == "floor_end":
		if int(run.floor) >= int(run.floor_limit):
			mode = "epilogue" if run.get("campaign", false) and not run.get("epilogue_seen", false) else "result"
			run.result = "victory"
			emit("run_end", {"win": true})
		else:
			mode = "checkpoint"
			choices = []
		return
	mode = "choice"
	choices = talent_offer() if next.kind == "talent" else next.items
	if choices.is_empty():
		open_next_choice()

func take_choice(index: int) -> bool:
	if mode not in ["choice", "shop", "debt"] or index < 0 or index >= choices.size():
		return false
	var choice = choices[index]
	if not choice_reason(choice).is_empty(): return false
	if choice.get("taken", false) or int(run.coins) < int(choice.price):
		return false
	if choice.kind in ["sacrifice", "judgment", "blessing"]:
		var hp_cost = int(choice.get("hp_cost", 0))
		if player.hp <= hp_cost or not reward_once("special_%s" % str(choice.get("slot", index))): return false
		player.hp -= hp_cost
		var reward_kind = str(choice.get("reward_kind", "relic"))
		match reward_kind:
			"relic":
				run.relics[choice.id] = stack(choice.id) + 1
			"weapon": player.weapon = choice.id
			"max_hp":
				player.max_hp = mini(14, int(player.max_hp) + (2 if choice.kind == "sacrifice" else 1))
				player.hp = mini(int(player.max_hp), int(player.hp) + 1)
			"heal":
				player.hp = mini(int(player.max_hp), int(player.hp) + 4)
				run.heal_misses = 0
			"talent":
				if not run.talents.has(choice.id): run.talents.append(choice.id)
		run.special_rooms[room_key()] = {"type": room_type(), "choice": choice.id, "reward_kind": reward_kind, "at": time}
		record_growth_choice(choice.kind, choice.id, reward_kind, choice.id, 0, hp_cost, "special")
		choice.taken = true
		emit("special_choice", {"id": choice.id, "type": choice.kind, "reward": reward_kind, "hp_cost": hp_cost})
		for other in choices: other.taken = true
		choices.clear()
		mode = "clear"
		emit("save_requested")
		return true
	if choice.kind == "heal" and player.hp >= player.max_hp: return false
	if choice.kind == "event" and choice.id == "rest" and player.hp >= player.max_hp: return false
	if choice.kind == "talent":
		var row = db.row("talents", choice.id)
		var points = run.talents.filter(func(id): return db.row("talents", id).route == row.route).size()
		if run.talents.has(choice.id) or points < row.min_route_points: return false
	if choice.kind == "contract":
		var debt = db.row("debt_contracts", choice.id)
		var risk = 0
		for entry in run.contracts:
			risk += int(db.row("debt_contracts", entry.id).risk_points)
		if run.contracts.size() >= 2 or risk + int(debt.risk_points) > 4:
			return false
		if run.contracts.any(func(entry): return entry.id == choice.id):
			return false
		if stack(debt.reward) >= int(db.row("relics", debt.reward).stack_limit):
			return false
		if run.relics.size() >= 12 and stack(debt.reward) == 0:
			run.replacement = {"choice": choice.duplicate(true), "index": index, "return_mode": mode}
			mode = "replace"
			emit("save_requested")
			return true
		if not reward_once("contract_%s" % choice.id):
			return false
		run.contracts.append({"id": choice.id, "interest": 0})
		run.relics[debt.reward] = stack(debt.reward) + 1
	else:
		if choice.kind == "relic":
			if stack(choice.id) >= int(db.row("relics", choice.id).stack_limit):
				return false
			if run.relics.size() >= 12 and stack(choice.id) == 0:
				run.replacement = {"choice": choice.duplicate(true), "index": index, "return_mode": mode}
				mode = "replace"
				emit("save_requested")
				return true
		if not reward_once("offer_%s_%s" % [choice.kind, str(choice.get("slot", index))]):
			return false
		run.coins -= int(choice.price)
		match choice.kind:
			"relic":
				run.relics[choice.id] = stack(choice.id) + 1
			"weapon":
				player.weapon = choice.id
			"talent":
				run.talents.append(choice.id)
			"heal":
				player.hp = mini(int(player.max_hp), int(player.hp) + 2)
				run.heal_misses = 0
			"skill":
				player.skill = choice.id
				run.evolved = true
			"event":
				match choice.id:
					"remember":
						run.name_pages += 1
						if not run.name_page_ids.has("name_page_%d" % run.floor): run.name_page_ids.append("name_page_%d" % run.floor)
					"interest": run.interest_page = true
					"rest": player.hp = mini(player.max_hp, player.hp + 2)
	var logged_reward_kind = str(choice.kind)
	var logged_reward_id = str(choice.id)
	if choice.kind == "contract":
		logged_reward_kind = "relic"
		logged_reward_id = str(db.row("debt_contracts", choice.id).reward)
	record_growth_choice(choice.kind, choice.id, logged_reward_kind, logged_reward_id, int(choice.price), 0, "choice")
	choice.taken = true
	emit("choice_taken", {"id": choice.id, "type": choice.kind})
	if choice.kind == "skill": enter_room()
	elif mode == "choice":
		open_next_choice()
	emit("save_requested")
	return true

func choice_reason(choice: Dictionary) -> String:
	if choice.get("taken", false): return "已取走"
	if int(choice.price) > int(run.coins): return "还差%d纸钱" % (int(choice.price) - int(run.coins))
	if choice.kind in ["sacrifice", "judgment", "blessing"]:
		if player.hp <= int(choice.get("hp_cost", 0)): return "心火不足"
		if choice.get("reward_kind", "") == "relic" and run.relics.size() >= 12 and stack(choice.id) == 0: return "愿簿已满"
		if choice.get("reward_kind", "") == "talent" and run.talents.has(choice.id): return "已点亮"
		return ""
	if choice.kind == "heal" or (choice.kind == "event" and choice.id == "rest"):
		if player.hp >= player.max_hp: return "心火已满"
	if choice.kind == "relic" and stack(choice.id) >= int(db.row("relics", choice.id).stack_limit): return "已达叠加上限"
	if choice.kind == "contract":
		if run.contracts.any(func(entry): return entry.id == choice.id): return "已借此愿"
		if run.contracts.size() >= 2: return "最多两份债约"
		var risk = 0
		for entry in run.contracts: risk += int(db.row("debt_contracts", entry.id).risk_points)
		if risk + int(db.row("debt_contracts", choice.id).risk_points) > 4: return "合计风险不得超过4"
	return ""

func skip_choice() -> void:
	if mode == "choice":
		if not choices.is_empty() and choices[0].kind == "skill": return
		open_next_choice()
	elif mode in ["shop", "debt"]:
		mode = "clear"
		choices.clear()
	emit("save_requested")

func advance_room(destination: int = -1, arrival_direction: String = "") -> void:
	if mode not in ["clear", "checkpoint"]:
		return
	if mode == "checkpoint":
		if int(run.floor) >= int(run.floor_limit):
			mode = "result"
			run.result = "victory"
			return
		if run.get("campaign", false):
			run.transition = {"to_floor": int(run.floor) + 1, "cursor": 0}
			mode = "transition"
			emit("save_requested", {"simulation_only": true})
			return
		run.floor += 1
		run.room = 0
		run.graph = Graph.build(RunRng.new(int(run.seed) + 401 * int(run.floor)), int(run.floor), run.optional_bosses)
		run.room_plan = run.graph.types.duplicate()
		run.visited = []
		run.room_history = {}
		for debt in run.contracts:
			debt.interest = mini(12, int(debt.interest) + 6)
		if run.floor == 2 and not run.get("evolved", false):
			mode = "choice"
			choices = []
			for id in db.row("characters", run.character).skills.slice(1):
				choices.append({"kind": "skill", "id": id, "price": 0, "slot": "evolution_" + id})
			emit("save_requested")
			return
	else:
		var frontier = next_rooms()
		if destination == -1:
			if frontier.is_empty(): return
			destination = frontier[0]
		if not frontier.has(destination) and not Graph.can_return(run.graph, run.visited, int(run.room), destination): return
		var exit_direction = room_connection_direction(destination, int(run.room))
		pending_entry_direction = arrival_direction if not arrival_direction.is_empty() else opposite_direction(exit_direction)
		if not run.has("room_history"): run.room_history = {}
		run.room_history[str(int(run.room))] = {"template": geometry.template_id, "pickups": pickups.duplicate(true), "flags": room_flags.duplicate(true), "objects": geometry.objects.duplicate(true)}
		if not run.visited.has(int(run.room)): run.visited.append(int(run.room))
		run.room = destination
	enter_room()

func continue_transition() -> void:
	if mode != "transition": return
	run.floor = int(run.transition.to_floor)
	run.room = 0
	run.graph = Campaign.build(db, run.seed_text, int(run.floor))
	run.room_plan = run.graph.types.duplicate()
	run.visited = []
	run.room_history = {}
	run.erase("transition")
	for debt in run.contracts: debt.interest = mini(12, int(debt.interest) + 6)
	if run.floor == 2 and not run.get("evolved", false):
		mode = "choice"
		choices = []
		for id in db.row("characters", run.character).skills.slice(1): choices.append({"kind": "skill", "id": id, "price": 0, "slot": "evolution_" + id})
	else: enter_room()
	emit("save_requested", {"simulation_only": true})

func finish_epilogue() -> void:
	if mode != "epilogue": return
	run.epilogue_seen = true
	mode = "result"
	emit("save_requested")

func replace_relic(old_id: String = "") -> bool:
	if mode != "replace" or run.replacement.is_empty(): return false
	var pending = run.replacement
	mode = pending.return_mode
	run.replacement = {}
	if pending.has("ground_uid"):
		if old_id.is_empty():
			emit("save_requested")
			return true
		var found = pickups.filter(func(drop): return int(drop.uid) == int(pending.ground_uid))
		if not found.is_empty() and Equipment.take(self, found[0], old_id): return true
		mode = "replace"
		run.replacement = pending
		return false
	if old_id.is_empty():
		emit("save_requested")
		return true
	if not run.relics.has(old_id) or old_id == pending.choice.id:
		mode = "replace"
		run.replacement = pending
		return false
	var held = run.relics[old_id]
	run.relics.erase(old_id)
	if not take_choice(int(pending.index)):
		run.relics[old_id] = held
		mode = "replace"
		run.replacement = pending
		return false
	return true

func reroll() -> bool:
	if mode not in ["choice", "shop"] or choices.is_empty(): return false
	var kind = choices[0].kind
	if kind not in ["relic", "talent"]: return false
	if mode == "shop" and choices.any(func(c): return c.get("taken", false)): return false
	if mode == "shop":
		if run.coins < 12: return false
		run.coins -= 12
	else:
		if run.rerolls <= 0: return false
		run.rerolls -= 1
	if kind == "talent": choices = talent_offer()
	else:
		var fresh = relic_offer(2 if mode == "shop" else choices.size())
		if mode == "shop":
			for c in fresh: c.price = db.rules.loot.shop_prices[db.row("relics", c.id).rarity]
			fresh.append({"kind": "heal", "id": "heal", "price": 15 if contract("d04") else 10})
			fresh.append({"kind": "weapon", "id": roll("shop").choose(db.rows("weapons")).id, "price": 35})
		choices = fresh
	emit("save_requested")
	return true

func repay(index: int) -> bool:
	if mode != "checkpoint" or index < 0 or index >= run.contracts.size():
		return false
	var entry = run.contracts[index]
	var price = int(db.row("debt_contracts", entry.id).repay_price) + int(entry.interest)
	if int(run.coins) < price:
		return false
	if not reward_once("repay_" + entry.id):
		return false
	run.coins -= price
	run.repayments.append(entry.id)
	if stack("r54") > 0 and int(run.get("repay_effects", 0)) < 2:
		run.repay_effects = int(run.get("repay_effects", 0)) + 1
		run.repay_skill_refunds = int(run.get("repay_skill_refunds", 0)) + 1
		run.repay_reward_pending = int(run.get("repay_reward_pending", 0)) + 1
	run.contracts.remove_at(index)
	record_growth_choice("repay", entry.id, "contract", entry.id, price, 0, "repay")
	emit("debt_repaid", {"id": entry.id})
	emit("save_requested")
	return true

func snapshot() -> Dictionary:
	var stream_states: Dictionary = {}
	for key in streams: stream_states[key] = streams[key].state
	return {"version": Migration.RUN_VERSION, "content_version": db.catalog.version, "run": run.duplicate(true), "player": player.duplicate(true), "rng": rng.state,
		"streams": stream_states,
		"time": time, "uid": uid, "attack_uid": attack_uid, "enemies": enemies.duplicate(true), "bullets": bullets.duplicate(true),
		"pickups": pickups.duplicate(true), "zones": zones.duplicate(true), "delayed": delayed.duplicate(true),
		"chains": chains.duplicate(true), "enemy_ledger": enemy_ledger.duplicate(true), "reward_ledger": reward_ledger.duplicate(true),
		"pair_cooldowns": pair_cooldowns.duplicate(true), "choices": choices.duplicate(true), "choice_queue": choice_queue.duplicate(true),
		"mode": mode, "template": geometry.template_id, "scenery": geometry.objects.duplicate(true), "room_flags": room_flags.duplicate(true), "stats": stats.duplicate(true),
		"active_pulse": active_pulse, "pulse_serial": pulse_serial, "proc_ledger": proc_ledger.duplicate(true)}

func upgrade_early_boss_rooms() -> void:
	if not run.get("campaign",false) or int(run.floor)>5 or int(run.graph.get("campaign",1))>=2: return
	var exit_room = str(run.graph.types.find("boss"))
	for room in run.graph.get("boss_assignments",{}):
		if run.graph.boss_assignments[room].size()>1: run.graph.boss_assignments[room]=run.graph.boss_assignments[room].slice(0,1)
		if run.graph.room_roles.get(room,"")=="double_boss": run.graph.room_roles[room]="side_boss"
	var current = enemies.filter(func(e): return e.boss and not e.dead)
	if current.size()>1:
		# Carry the displaced boss's real remaining health into the unvisited exit.
		# Existing coins, build, explored rooms and the ongoing first boss stay intact.
		var displaced = current[1]
		if not run.visited.has(int(exit_room)) and int(exit_room)!=int(run.room):
			run.graph.boss_assignments[exit_room]=[displaced.id]
			if not run.has("legacy_boss_health"): run.legacy_boss_health={}
			run.legacy_boss_health[exit_room]={"id":displaced.id,"hp":displaced.hp,"max_hp":displaced.max_hp}
		for i in range(1,current.size()): enemies.erase(current[i])
		room_flags.boss_ids=[current[0].id]
	run.graph.guest_biome=Campaign.guest_biome(db,str(run.seed_text),int(run.floor)).id
	run.graph.encounter_mix=.4
	run.graph.campaign=2

func restore(data: Dictionary) -> bool:
	touch_charge_transfer.clear()
	var migrated = Migration.world(data)
	if not migrated.ok or migrated.data.is_empty(): return false
	data = migrated.data
	run = data.run.duplicate(true)
	player = data.player.duplicate(true)
	rng.state = int(data.rng)
	streams.clear()
	for key in data.get("streams", {}):
		streams[key] = RunRng.new()
		streams[key].state = int(data.streams[key])
	time = float(data.time)
	uid = int(data.uid)
	attack_uid = int(data.attack_uid)
	for name in ["enemies", "bullets", "pickups", "zones", "delayed", "chains", "choices", "choice_queue"]:
		set(name, data.get(name, []).duplicate(true))
	for name in ["enemy_ledger", "reward_ledger", "pair_cooldowns", "room_flags", "stats"]:
		set(name, data.get(name, {}).duplicate(true))
	mode = str(data.mode)
	active_pulse = str(data.get("active_pulse", ""))
	pulse_serial = int(data.get("pulse_serial", 0))
	proc_ledger = data.get("proc_ledger", {}).duplicate(true)
	if not room_flags.has("forced_links"): room_flags.forced_links = {}
	if not run.has("favors_used"): run.favors_used = {}
	var defaults = {"relic_pool": db.rules.progression.initial_relic_ids.duplicate(), "replacement": {}, "bosses_defeated": [], "ending": "", "contract_combats": 0, "optional_bosses": [], "name_pages": 0, "name_page_ids": [], "interest_page": false, "visited": [], "damage_history": [], "death_cause": {}, "growth_log": [], "special_rooms": {}}
	for key in defaults:
		if not run.has(key): run[key] = defaults[key]
	Equipment.normalize(self)
	set_pickup_scale(float(run.get("pickup_radius_scale", 1.0)))
	if not run.has("room_history"): run.room_history = {}
	if not run.has("graph"):
		run.graph = Graph.build(RunRng.new(int(run.seed) + 401 * int(run.floor)), int(run.floor), run.optional_bosses)
		run.room_plan = run.graph.types.duplicate()
		for i in int(run.room): run.visited.append(i)
	Graph.normalize(run.graph)
	run.visited = run.visited.map(func(room): return int(room))
	upgrade_early_boss_rooms()
	if not player.has("dash_start"): player.dash_start = player.pos
	build_geometry(str(data.template), data.get("scenery", []))
	player.pos = geometry.nearest_free(player.pos, 12)
	for enemy in enemies:
		if not enemy.dead: enemy.pos = geometry.nearest_free(enemy.pos, enemy.radius)
	for bullet in bullets:
		if not bullet.friendly: bullet.visual_profile = ProjectileStyles.enemy(bullet.get("source", {}))
	geometry.rebuild_flow(player.pos)
	player.buffer_dash = 0.0
	player.buffer_skill = 0.0
	events.clear()
	return true
