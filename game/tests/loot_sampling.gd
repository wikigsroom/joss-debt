extends SceneTree

const World = preload("res://scripts/combat/world.gd")
const RunRng = preload("res://scripts/core/run_rng.gd")

const REWARD_SAMPLES_PER_FLOOR := 10000
const OFFER_SAMPLES := 1000
const HEAL_SAMPLES := 10000
const ECONOMY_SAMPLES := 10000
const RELIC_POOL := [
	"r01", "r02", "r03", "r04", "r05", "r06", "r07", "r08", "r09", "r10", "r11", "r12", "r13", "r14", "r15", "r16", "r17", "r18", "r19", "r20", "r21", "r22", "r23", "r24", "r25", "r26", "r27", "r28", "r29", "r30", "r31", "r32", "r33", "r34", "r35", "r36", "r37", "r38", "r39", "r40", "r41", "r42", "r43", "r44", "r45", "r46", "r47", "r48", "r49", "r50", "r51", "r52", "r53", "r54"
]

var checks: Array = []
var failures: Array = []


func expect(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures.append(name)


func _initialize() -> void:
	call_deferred("run_suite")


func _fixture() -> World:
	var world = World.new()
	world.start("c_lantern", 481516, 3, {"relic_pool": RELIC_POOL.duplicate()})
	world.mode = "choice"
	world.run.relic_pool = RELIC_POOL.duplicate()
	world.run.relics = {}
	world.run.consumed = []
	world.run.repay_reward_pending = 0
	return world


func _eligible(world: World, floor_id: int) -> Array:
	var result: Array = []
	for row in world.db.rows("relics"):
		var id = str(row.id)
		if int(row.min_floor) > floor_id or int(row.max_floor) < floor_id:
			continue
		# Keep these two authored restrictions in the independent oracle. They are
		# the same restrictions used by World.relic_offer(), not a second loot rule.
		if id == "r03" and world.run.character != "c_lantern" and world.stack("r04") == 0 and world.talent("t_fire_3a") == 0 and world.stack("r50") == 0:
			continue
		if id == "r25" and world.run.character != "c_mask" and world.talent("t_seal_1b") == 0 and world.stack("r30") == 0:
			continue
		result.append(id)
	return result


func _expected_distribution(world: World, floor_id: int, ids: Array) -> Dictionary:
	var rarity_rules: Dictionary = world.db.rules.loot.rarity_by_floor[str(floor_id)]
	var counts: Dictionary = {}
	for id in ids:
		var grade = str(world.db.row("relics", id).rarity)
		counts[grade] = int(counts.get(grade, 0)) + 1
	var total = 0.0
	var expected: Dictionary = {}
	for grade in counts:
		var weight = float(rarity_rules.get(grade, 0.0))
		if weight > 0.0:
			total += weight
			expected[grade] = weight
	if total > 0.0:
		for grade in expected:
			expected[grade] = float(expected[grade]) / total
	return {"counts": counts, "candidate_count": ids.size(), "effective_candidate_count": ids.filter(func(id): return float(rarity_rules.get(str(world.db.row("relics", id).rarity), 0.0)) > 0.0).size(), "expected": expected}


func _sample_rarity(world: World, floor_id: int) -> Dictionary:
	world.run.floor = floor_id
	world.run.room = 600 + floor_id
	world.streams.clear()
	var ids = _eligible(world, floor_id)
	var oracle = _expected_distribution(world, floor_id, ids)
	var observed: Dictionary = {}
	for i in REWARD_SAMPLES_PER_FLOOR:
		var offer = world.relic_offer(1)
		if offer.is_empty():
			continue
		var grade = str(world.db.row("relics", str(offer[0].id)).rarity)
		observed[grade] = int(observed.get(grade, 0)) + 1
	var shares: Dictionary = {}
	var errors: Dictionary = {}
	for grade in oracle.expected:
		var share = float(observed.get(grade, 0)) / float(REWARD_SAMPLES_PER_FLOOR)
		shares[grade] = snappedf(share, 0.0001)
		errors[grade] = snappedf(absf(share - float(oracle.expected[grade])), 0.0001)
	var max_error = 0.0
	for grade in errors:
		max_error = maxf(max_error, float(errors[grade]))
	return {"floor": floor_id, "samples": REWARD_SAMPLES_PER_FLOOR, "candidate_count": oracle.candidate_count, "effective_candidate_count": oracle.effective_candidate_count, "candidate_rarity_counts": oracle.counts, "expected_share": oracle.expected, "observed_counts": observed, "observed_share": shares, "absolute_error": errors, "max_absolute_error": snappedf(max_error, 0.0001)}


func _route_affinity(world: World, relic_id: String) -> bool:
	var relic = world.db.row("relics", relic_id)
	var routes = world.db.row("characters", world.run.character).routes
	for route in relic.routes:
		if routes.has(route):
			return true
	return false


func _sample_offer_integrity(world: World) -> Dictionary:
	world.run.floor = 2
	world.run.room = 700
	world.streams.clear()
	var ids = _eligible(world, 2)
	var duplicate_offers = 0
	var invalid_items = 0
	var affinity_offers = 0
	var affinity_hits = 0
	for i in OFFER_SAMPLES:
		var offer = world.relic_offer(3)
		var seen: Dictionary = {}
		for entry in offer:
			var id = str(entry.id)
			if seen.has(id):
				duplicate_offers += 1
			seen[id] = true
			if not ids.has(id):
				invalid_items += 1
		var affinity = world.relic_offer(1, true)
		if not affinity.is_empty():
			affinity_offers += 1
			if _route_affinity(world, str(affinity[0].id)):
				affinity_hits += 1
	return {"samples": OFFER_SAMPLES, "three_choice_duplicate_offers": duplicate_offers, "invalid_items": invalid_items, "first_affinity_offers": affinity_offers, "first_affinity_hits": affinity_hits, "first_affinity_rate": snappedf(float(affinity_hits) / float(maxi(1, affinity_offers)), 0.0001), "floor": 2, "candidate_count": ids.size()}


func _prepare_heal(world: World, missed: int) -> void:
	world.run.floor = 1
	world.run.room = 800
	world.run.heal_misses = missed
	world.reward_ledger.clear()
	world.pickups.clear()
	world.player.hp = int(world.player.max_hp / 2)


func _sample_heal(world: World) -> Dictionary:
	world.streams.clear()
	var base_hits = 0
	var second_hits = 0
	var guaranteed_hits = 0
	var heal = world.db.rules.loot.heal
	for i in HEAL_SAMPLES:
		_prepare_heal(world, 0)
		if world.generate_heal():
			base_hits += 1
	for i in HEAL_SAMPLES:
		_prepare_heal(world, 1)
		if world.generate_heal():
			second_hits += 1
	for i in 1000:
		_prepare_heal(world, 2)
		if world.generate_heal():
			guaranteed_hits += 1
	return {"samples": HEAL_SAMPLES, "base_expected": float(heal.base_chance), "base_observed": snappedf(float(base_hits) / float(HEAL_SAMPLES), 0.0001), "miss_one_expected": float(heal.base_chance) + float(heal.per_missed_clear), "miss_one_observed": snappedf(float(second_hits) / float(HEAL_SAMPLES), 0.0001), "guarantee_samples": 1000, "guarantee_hits": guaranteed_hits, "chance_cap": float(heal.chance_cap), "low_health_ratio": float(heal.low_health_ratio)}


func _combat_enemy_count(room_index: int, floor_id: int) -> int:
	var total = 3 + mini(3, int(room_index / 3)) + floor_id - 1
	if room_index >= 8 or (floor_id >= 2 and room_index == 5):
		return 3 + maxi(3, total - 3)
	return total


func _natural_enemy_quota(floor_id: int) -> Dictionary:
	var combat_rooms = [0, 1, 3, 5, 8, 9]
	var combat_total = 0
	for room_index in combat_rooms:
		combat_total += _combat_enemy_count(room_index, floor_id)
	# Elite room is one authored elite plus three escorts. A boss contributes
	# itself and the first two natural_reward summons; later summons are capped
	# to ash only by the runtime reward ledger.
	return {"combat": combat_total, "elite": 4, "boss": 3, "total": combat_total + 7}


func _coin_draw(random: RunRng, enemy_count: int, chance: float, low: int, high: int) -> int:
	var coins = 0
	for i in enemy_count:
		if random.unit() < chance:
			coins += random.between(low, high)
	return coins


func _percentile(values: Array, fraction: float) -> float:
	var sorted = values.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return 0.0
	var index = clampi(int(round(float(sorted.size() - 1) * fraction)), 0, sorted.size() - 1)
	return float(sorted[index])


func _sample_economy(world: World) -> Dictionary:
	var loot = world.db.rules.loot
	var chance = float(loot.enemy_coin_chance)
	var coin_range = loot.enemy_coin_range
	var clear = loot.clear_coins
	var final_coins: Array = []
	var pre_shop: Dictionary = {"1": [], "2": [], "3": []}
	var quota: Dictionary = {}
	for floor_id in [1, 2, 3]:
		quota[str(floor_id)] = _natural_enemy_quota(floor_id)
	for sample in ECONOMY_SAMPLES:
		var random = RunRng.new(910000 + sample)
		var coins = int(loot.coins_start)
		for floor_id in [1, 2, 3]:
			var counts: Dictionary = quota[str(floor_id)]
			var pre_shop_enemies = _combat_enemy_count(0, floor_id) + _combat_enemy_count(1, floor_id) + _combat_enemy_count(3, floor_id) + _combat_enemy_count(5, floor_id) + int(counts.elite)
			coins += _coin_draw(random, pre_shop_enemies, chance, int(coin_range[0]), int(coin_range[1]))
			coins += int(clear.combat) * 4 + int(clear.elite)
			pre_shop[str(floor_id)].append(coins)
			var remaining = int(counts.total) - pre_shop_enemies
			coins += _coin_draw(random, remaining, chance, int(coin_range[0]), int(coin_range[1]))
			coins += int(clear.combat) * 2 + int(clear.boss)
		final_coins.append(coins)
	var shop_prices: Dictionary = loot.shop_prices
	var affordability: Dictionary = {}
	for floor_id in [1, 2, 3]:
		var values: Array = pre_shop[str(floor_id)]
		var rates: Dictionary = {}
		for item in ["heal", "reroll", "common", "uncommon", "rare", "mythic", "weapon"]:
			var price = int(shop_prices.get(item, 0))
			if item == "heal": price = int(shop_prices.heal)
			var affordable = 0
			for coins in values:
				if int(coins) >= price: affordable += 1
			rates[item] = snappedf(float(affordable) / float(values.size()), 0.0001)
		affordability[str(floor_id)] = rates
	var guaranteed_pre_shop: Array = []
	var guaranteed = int(loot.coins_start)
	for floor_id in [1, 2, 3]:
		guaranteed += int(clear.combat) * 4 + int(clear.elite)
		guaranteed_pre_shop.append(guaranteed)
		guaranteed += int(clear.combat) * 2 + int(clear.boss)
	return {"scenario_samples": ECONOMY_SAMPLES, "natural_enemy_quota_by_floor": quota, "enemy_coin_chance": chance, "enemy_coin_range": coin_range, "clear_coins_per_floor": int(clear.combat) * 6 + int(clear.elite) + int(clear.boss), "guaranteed_coins_before_shop": guaranteed_pre_shop, "guaranteed_final_coins": guaranteed, "final_coins": {"mean": snappedf(float(final_coins.reduce(func(a, b): return a + b, 0)) / float(final_coins.size()), 0.01), "p10": _percentile(final_coins, 0.10), "p90": _percentile(final_coins, 0.90), "min": final_coins.min(), "max": final_coins.max()}, "shop_affordability_rate": affordability, "assumptions": ["三层主路径每层六普通房、一个精英房、一个Boss房；不把可选支路、合同利息、掉落治疗兑换算入保守现金底线。", "普通房敌数直接复用World.prepare_waves的固定房号公式；精英房按1个精英加3个护卫。", "Boss按首领本体加前两名natural_reward召唤物计入纸钱，后续召唤只给余烬。", "随机经济样本只模拟敌人纸钱掉落，清房纸钱按rules.json固定发放。"]}


func _write_report(payload: Dictionary) -> void:
	var report_path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/loot-sampling-tests.json")
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var lines: Array = [
		"# 掉落与经济固定种子抽样",
		"",
		"本报告由 Godot 运行时直接调用 `World.relic_offer()`、`World.generate_heal()` 和 rules.json 经济参数生成。每层奖励抽样 10,000 次，另以 10,000 个完整三层主路径情景检查现金曲线；这是一份公式与实现的一致性基线，不是玩家胜率。",
		"",
		"## 稀有度与候选池",
		"",
		"| 层数 | 抽样 | 候选/有效候选 | 期望分布 | 观察分布 | 最大误差 |",
		"| --- | ---: | ---: | --- | --- | ---: |",
	]
	for row in payload.rarity_by_floor:
		lines.append("| %d | %d | %d / %d | %s | %s | %.4f |" % [int(row.floor), int(row.samples), int(row.candidate_count), int(row.effective_candidate_count), JSON.stringify(row.expected_share), JSON.stringify(row.observed_share), float(row.max_absolute_error)])
	lines += [
		"",
		"三选一去重：%d 次抽样，重复候选 %d 次，无效 ID %d 次。路线偏好首选：%d/%d 命中角色路线（%.2f%%）。" % [int(payload.offer_integrity.samples), int(payload.offer_integrity.three_choice_duplicate_offers), int(payload.offer_integrity.invalid_items), int(payload.offer_integrity.first_affinity_hits), int(payload.offer_integrity.first_affinity_offers), float(payload.offer_integrity.first_affinity_rate) * 100.0],
		"",
		"## 低血治疗",
		"",
		"基础概率 %.2f%%，观察 %.2f%%；连续漏取一次后的期望 %.2f%%，观察 %.2f%%；第三次低血触发保底 %d/%d。" % [float(payload.heal.base_expected) * 100.0, float(payload.heal.base_observed) * 100.0, float(payload.heal.miss_one_expected) * 100.0, float(payload.heal.miss_one_observed) * 100.0, int(payload.heal.guarantee_hits), int(payload.heal.guarantee_samples)],
		"",
		"## 三层主路径经济",
		"",
		"| 指标 | 数值 |",
		"| --- | ---: |",
		"| 每层固定清房纸钱 | %d |" % int(payload.economy.clear_coins_per_floor),
		"| 不含敌人掉落的三层最终底线 | %d |" % int(payload.economy.guaranteed_final_coins),
		"| 敌人掉落情景均值 / P10 / P90 | %.2f / %.0f / %.0f |" % [float(payload.economy.final_coins.mean), float(payload.economy.final_coins.p10), float(payload.economy.final_coins.p90)],
		"| 敌人掉落情景最小 / 最大 | %d / %d |" % [int(payload.economy.final_coins.min), int(payload.economy.final_coins.max)],
		"",
		"各层灯摊前的保守纸钱为：第1层 %d、第2层 %d、第3层 %d。完整购买率在 JSON 的 `shop_affordability_rate` 中按治疗、重掷、四档稀有度和武器分别记录。经济情景排除了可选支路、债约利息、治疗补偿和真人购买行为，后续真人局记录应与该基线并列比较。" % [int(payload.economy.guaranteed_coins_before_shop[0]), int(payload.economy.guaranteed_coins_before_shop[1]), int(payload.economy.guaranteed_coins_before_shop[2])],
		"",
		"固定种子、候选去重、路线偏好、保底与经济情景均由同一份运行规则生成；规则变化后应重新运行 `res://tests/loot_sampling.gd`。",
	]
	var markdown_path = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/loot-sampling-tests.md")
	var markdown = FileAccess.open(markdown_path, FileAccess.WRITE)
	markdown.store_string("\n".join(lines) + "\n")
	markdown.close()


func run_suite() -> void:
	var world = _fixture()
	var rarity_rows: Array = []
	for floor_id in [1, 2, 3]:
		var row = _sample_rarity(world, floor_id)
		rarity_rows.append(row)
		expect(float(row.max_absolute_error) <= 0.03, "floor %d rarity shares stay within three percentage points of the configured distribution" % floor_id)
		expect(int(row.effective_candidate_count) > 0 and float(row.expected_share.values().reduce(func(a, b): return a + b, 0.0)) > 0.999, "floor %d has a non-empty effective candidate pool and normalized weights" % floor_id)
	var offer_integrity = _sample_offer_integrity(world)
	expect(int(offer_integrity.three_choice_duplicate_offers) == 0, "three-choice relic offers never duplicate an item")
	expect(int(offer_integrity.invalid_items) == 0, "offers only contain effective relic IDs")
	expect(int(offer_integrity.first_affinity_hits) == int(offer_integrity.first_affinity_offers), "affinity reward first slot honors the character route")
	var heal = _sample_heal(world)
	expect(absf(float(heal.base_observed) - float(heal.base_expected)) <= 0.03, "base low-health heal rate matches the configured chance")
	expect(absf(float(heal.miss_one_observed) - float(heal.miss_one_expected)) <= 0.03, "one-miss low-health heal rate matches the configured chance")
	expect(int(heal.guarantee_hits) == int(heal.guarantee_samples), "the third low-health miss always guarantees a heal")
	var economy = _sample_economy(world)
	expect(int(economy.scenario_samples) == ECONOMY_SAMPLES and int(economy.guaranteed_final_coins) == 124, "the three-floor main-path economy has a reproducible conservative floor")
	expect(float(economy.final_coins.p10) >= float(economy.guaranteed_final_coins), "enemy coin samples never fall below the guaranteed economy floor")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "method": "fixed-seed Godot runtime sampling; three 10000-sample floor distributions, 1000 three-choice offers, 10000 heal probability samples and 10000 three-floor economy scenarios", "rarity_by_floor": rarity_rows, "offer_integrity": offer_integrity, "heal": heal, "economy": economy, "limitations": ["This is an implementation/formula baseline, not human balance acceptance.", "Economy covers the authored three-floor main path; optional rooms, contracts, purchases and real player routing need separate telemetry.", "Enemy coin samples use the configured reward quota and do not claim physical device performance."]}
	_write_report(report)
	print("Loot sampling: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
