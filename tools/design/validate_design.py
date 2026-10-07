"""Validate design references and mathematics, without claiming runtime verification."""
from __future__ import annotations
from collections import Counter
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import random
import re
import statistics
import struct
import xml.etree.ElementTree as ET

from render_catalog import render

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "incense-debt"
EXPECTED = {"meta_unlocks": 22, "npcs": 5, "routes": 6, "characters": 6, "weapons": 32, "skills": 18,
            "relics": 54, "talents": 36, "debt_contracts": 9, "enemies": 296,
            "elite_variants": 6, "bosses": 99, "synergies": 24, "regions": 3, "room_templates": 18,
            "special_rooms": 4, "obstacles": 6}
EVENTS = {"stat", "primary_hit", "detonate_hit", "natural_kill", "detonate_complete", "burn_tick",
          "chain_form", "detonate_start", "ash_pickup", "mark_first", "elite_clear", "deflect",
          "room_clear", "lethal_damage", "dash_start", "player_damage", "dash_path", "dodge_success",
          "distance_moved", "contract_repay", "armor_break"}
RARITIES = ["common", "uncommon", "rare", "mythic"]
ERRORS = []
CHECKS = 0


def check(condition, message):
    global CHECKS
    CHECKS += 1
    if not condition:
        ERRORS.append(message)


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sample_offer(rng, relics, rarity_weights, floor):
    remaining = [r for r in relics if r["min_floor"] <= floor <= r["max_floor"]]
    selected = []
    for _ in range(3):
        kinds = [k for k in RARITIES if any(r["rarity"] == k for r in remaining) and rarity_weights[k] > 0]
        kind = rng.choices(kinds, weights=[rarity_weights[k] for k in kinds], k=1)[0]
        choices = [r for r in remaining if r["rarity"] == kind]
        pick = rng.choice(choices)
        selected.append(pick)
        remaining = [r for r in remaining if r["id"] != pick["id"]]
    return selected


def simulations(catalog, rules):
    rng = random.Random(20261003)
    frequencies = {}
    for floor in range(1, 12):
        weights = rules["loot"]["rarity_by_floor"][str(floor)]
        counts = Counter()
        for _ in range(10000):
            choices = sample_offer(rng, catalog["relics"], weights, floor)
            check(len({r["id"] for r in choices}) == 3, "Reward offer repeated an item")
            check(all(r["min_floor"] <= floor <= r["max_floor"] for r in choices), "Reward violated floor eligibility")
            counts[choices[0]["rarity"]] += 1
        for kind in RARITIES:
            expected = weights[kind] * 10000
            deviation = max(5, 6 * math.sqrt(10000 * weights[kind] * (1 - weights[kind])))
            check(abs(counts[kind] - expected) <= deviation, f"Floor {floor} first-draw rarity drift: {kind}")
        frequencies[str(floor)] = dict(counts)
    initial = [r for r in catalog["relics"] if r["id"] in rules["progression"]["initial_relic_ids"]]
    for floor in range(1, 12):
        for _ in range(1000):
            choices = sample_offer(rng, initial, rules["loot"]["rarity_by_floor"][str(floor)], floor)
            check(len({r["id"] for r in choices}) == 3 and all(r in initial for r in choices), "Initial unlock pool failed normalized offer generation")
    heal = rules["loot"]["heal"]
    misses = 0
    longest_interval = 0
    since_heal = 0
    guarantees = 0
    for _ in range(10000):
        since_heal += 1
        guaranteed = misses >= heal["miss_limit"] - 1
        probability = min(heal["chance_cap"], heal["base_chance"] + misses * heal["per_missed_clear"])
        received = guaranteed or rng.random() < probability
        if received:
            longest_interval = max(longest_interval, since_heal)
            guarantees += int(guaranteed)
            misses = since_heal = 0
        else:
            misses += 1
        check(misses < heal["miss_limit"], "Low-health healing guarantee missed its deadline")
    # Explicit bounded natural-enemy model: six ordinary rooms and two elite adds per floor.
    enemies_per_floor = sum([4, 4, 5, 5, 5, 6]) + 2 + 1
    floors = rules["floors"]["count"]
    reward = rules["loot"]["clear_coins"]
    base = rules["loot"]["coins_start"] + floors * (6 * reward["combat"] + reward["elite"] + reward["boss"])
    totals = []
    for _ in range(10000):
        total = base
        for _ in range(enemies_per_floor * floors):
            if rng.random() < rules["loot"]["enemy_coin_chance"]:
                total += rng.randint(*rules["loot"]["enemy_coin_range"])
        totals.append(total)
    totals.sort()
    mean = statistics.mean(totals)
    check(180 <= mean <= 230, "Economy mean escaped the documented design target")
    first_store_minimum = rules["loot"]["coins_start"] + 2 * reward["combat"]
    check(first_store_minimum >= rules["loot"]["shop_prices"]["heal"], "First-store treatment is unaffordable from guaranteed income")
    full_xp = floors * (6 * rules["progression"]["xp"]["combat"] + rules["progression"]["xp"]["elite"] + rules["progression"]["xp"]["boss"])
    main_xp = floors * (rules["floors"]["min_main_path_combat_rooms"] * rules["progression"]["xp"]["combat"] + rules["progression"]["xp"]["elite"] + rules["progression"]["xp"]["boss"])
    # This bounded formula is the preserved three-floor baseline. Full eleven-floor
    # growth is measured by the separate actual simulation, rather than this formula.
    check(full_xp >= rules["progression"]["level_thresholds"][5], "Legacy full exploration cannot reach six choices")
    check(main_xp >= rules["progression"]["level_thresholds"][4], "Legacy main path cannot reach five choices")
    return {"seed": 20261003, "reward_offers_per_floor": 10000, "initial_pool_offers_per_floor": 1000,
            "first_draw_rarity_counts": frequencies,
            "low_health_clears": 10000, "max_clears_between_heals": longest_interval, "guaranteed_heals": guarantees,
            "economy_runs": 10000, "economy_model": "3 floors; 6 normal rooms with 4,4,5,5,5,6 enemies; 1 elite with 2 adds; fixed clear rewards",
            "coins_mean": round(mean, 2), "coins_p10": totals[999], "coins_p90": totals[8999],
            "first_store_guaranteed_coins": first_store_minimum, "full_exploration_xp": full_xp, "minimum_main_path_xp": main_xp,
            "scope": "Design formulas only; runtime drops and balancing are unverified."}


def main():
    catalog = load(DOCS / "data" / "catalog.json")
    rules = load(DOCS / "data" / "rules.json")
    campaign_floors = load(ROOT / "game" / "data" / "expansion.json")["campaign_floors"]
    manifest = load(DOCS / "data" / "asset-manifest.json")
    lookup = {key: {r["id"]: r for r in catalog[key]} for key in EXPECTED}
    ids = [r["id"] for key in EXPECTED for r in catalog[key]]
    check(len(ids) == len(set(ids)), "Content IDs are not globally unique")
    check(all(re.fullmatch(r"[a-z][a-z0-9_]*", value) for value in ids), "A content ID is not stable ASCII")
    for key, count in EXPECTED.items():
        check(len(catalog[key]) == count, f"Content count mismatch: {key}")
    check(catalog["version"] == rules["version"] == manifest["version"], "Design versions disagree")
    combat = rules["combat"]
    check(0 < combat["energy_start"] <= combat["energy_max"], "Invalid starting energy")
    check(0 < combat["dash_invulnerable_s"] <= combat["dash_duration_s"] < combat["dash_cooldown_s"], "Invalid dash window")
    check(combat["chain_group_base"] <= combat["chain_group_cap"] == 6, "Invalid chain target cap")
    check(combat["proc_depth_cap"] == 2 and combat["chain_event_cap"] == 48, "Chain event budget diverged from design")
    check(0 < combat["rewarded_summons_per_room_cap"] <= combat["summons_per_room_cap"], "Summon reward quota is invalid")
    control = combat["control"]
    check(20 <= control["light_push_distance"] <= 30 and 50 <= control["heavy_push_distance"] <= 80, "Impact strength diverged from the authored light/heavy range")
    check(0 < control["push_duration_s"] <= .2 and control["heavy_push_distance"] <= control["push_distance_cap"] <= 160, "Invalid physical impulse duration or bound")
    check(control["elite_scale"] == .5 and combat["boss_control_resistance"] == .85, "Elite/boss impact resistance diverged from design")
    check(control["ordinary_root_cap_s"] == .8 and control["elite_root_cap_s"] == .3, "Root duration caps diverged from design")
    for char in catalog["characters"]:
        check(char["weapon"] in lookup["weapons"], f"Unknown initial weapon: {char['id']}")
        check(0 < char["health"] <= combat["health_max_cap"], f"Invalid health: {char['id']}")
        check(char["speed"] > 0 and char["hit_radius"] == combat["health_hit_radius"], f"Invalid movement/hit circle: {char['id']}")
        check(all(r in lookup["routes"] for r in char["routes"]), f"Unknown character route: {char['id']}")
        check(len(char["skills"]) == 3, f"Wrong skill count: {char['id']}")
        for sid in char["skills"]:
            check(sid in lookup["skills"] and lookup["skills"][sid]["character"] == char["id"], f"Skill ownership mismatch: {sid}")
        row = re.search(r"\|\s*" + char["name"] + " / " + char["id"] + r"\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|", (DOCS / "03-playable-characters.md").read_text(encoding="utf-8"))
        check(bool(row) and (int(row[1]), int(row[2])) == (char["health"], char["speed"]), f"Character document stats stale: {char['id']}")
    for weapon in catalog["weapons"]:
        check(weapon["damage"] > 0 and weapon["interval_s"] > 0 and weapon["range"] > 0, f"Invalid weapon: {weapon['id']}")
        check(weapon["pellets"] >= 1 and weapon["pierce"] >= 0, f"Invalid weapon multiplicity: {weapon['id']}")
    for skill in catalog["skills"]:
        check(skill["character"] in lookup["characters"], f"Unknown skill character: {skill['id']}")
        check(skill["energy_cost"] >= combat["skill_cost_floor"] and skill["cooldown_s"] > 0 and skill["power"] > 0, f"Invalid skill cost or strength: {skill['id']}")
        check(not skill["secondary_can_proc"] and skill["max_generation_depth"] <= combat["proc_depth_cap"], f"Unbounded secondary skill: {skill['id']}")
        if skill["variant"] == "base":
            check(skill["evolves_from"] is None and skill["energy_cost"] <= combat["energy_start"], f"Base skill unusable initially: {skill['id']}")
        else:
            source = lookup["skills"].get(skill["evolves_from"])
            check(bool(source) and source["variant"] == "base" and source["character"] == skill["character"], f"Invalid evolution: {skill['id']}")
    for relic in catalog["relics"]:
        check(all(r in lookup["routes"] for r in relic["routes"]), f"Unknown relic route: {relic['id']}")
        check(relic["rarity"] in RARITIES and 1 <= relic["stack_limit"] <= 2, f"Invalid relic rarity/stack: {relic['id']}")
        check(1 <= relic["min_floor"] <= relic["max_floor"] <= campaign_floors, f"Invalid relic floor: {relic['id']}")
        check(relic["trigger"] in EVENTS and bool(relic["behavior"]), f"Unsupported relic event: {relic['id']}")
        check(not relic["proc_policy"]["secondary_can_proc"] and relic["proc_policy"]["once_per_target_per_pulse"], f"Unbounded relic proc: {relic['id']}")
    for route in lookup["routes"]:
        route_relics = [r for r in catalog["relics"] if r["routes"] == [route]]
        check(len(route_relics) == 8, f"A route lacks eight dedicated relics: {route}")
        nodes = [t for t in catalog["talents"] if t["route"] == route]
        check(len(nodes) == 6 and Counter(t["tier"] for t in nodes) == {1: 2, 2: 2, 3: 2}, f"Talent tiers incomplete: {route}")
        check(all(t["min_route_points"] == t["tier"] - 1 and t["stack_limit"] == 1 for t in nodes), f"Invalid talent prerequisites: {route}")
    initial = rules["progression"]["initial_relic_ids"]
    check(len(initial) == len(set(initial)) == 18 and all(r in lookup["relics"] for r in initial), "Invalid initial relic pool")
    for route in lookup["routes"]:
        check(sum(lookup["relics"][r]["routes"] == [route] for r in initial) == 3, f"Initial route lacks three startup relics: {route}")
    unlock_grants = []
    for unlock in catalog["meta_unlocks"]:
        requires = unlock["requires"]
        check(unlock["cost"] > 0 and unlock["kind"] in {"relic_pack", "convenience"}, f"Invalid meta purchase: {unlock['id']}")
        check(requires.get("boss_defeated", "b01") in lookup["bosses"], f"Unknown meta boss condition: {unlock['id']}")
        check(all(r in lookup["routes"] for r in requires.get("route_pair_chosen", [])), f"Unknown meta route condition: {unlock['id']}")
        check(all(u in lookup["meta_unlocks"] for u in requires.get("unlocks", [])), f"Unknown meta prerequisite: {unlock['id']}")
        granted = unlock["grants"].get("relic_ids", [])
        check(all(r in lookup["relics"] for r in granted), f"Unknown meta reward: {unlock['id']}")
        unlock_grants.extend(granted)
    check(len(initial + unlock_grants) == len(set(initial + unlock_grants)) == 54, "Relic unlock coverage is incomplete or duplicated")
    check(sum(u["cost"] for u in catalog["meta_unlocks"] if u["kind"] == "relic_pack") == 540, "Meta price total differs from documented 540")
    check(sum(u["cost"] for u in catalog["meta_unlocks"] if u["kind"] == "convenience") == 48, "Convenience price total differs from documented 48")
    check(not rules["progression"]["meta_purchases_repeatable"], "Meta purchases can be accidentally repeated")
    visited, visiting = set(), set()
    def visit(uid):
        if uid in visiting:
            check(False, "Circular meta unlock dependency: " + uid)
            return
        if uid in visited or uid not in lookup["meta_unlocks"]:
            return
        visiting.add(uid)
        for dependency in lookup["meta_unlocks"][uid]["requires"].get("unlocks", []):
            visit(dependency)
        visiting.remove(uid)
        visited.add(uid)
    for uid in lookup["meta_unlocks"]:
        visit(uid)
    contract_doc = (DOCS / "06-loot-economy-debt.md").read_text(encoding="utf-8")
    for contract in catalog["debt_contracts"]:
        reward = lookup["relics"].get(contract["reward"])
        check(bool(reward) and reward["min_floor"] <= contract["min_floor"] <= reward["max_floor"], f"Contract gives inactive reward: {contract['id']}")
        check(0 < contract["risk_points"] <= rules["debt"]["risk_points_cap"] and contract["repay_price"] > 0, f"Invalid contract risk/price: {contract['id']}")
        check(contract["interest_per_floor"] == rules["debt"]["interest_per_floor"] and contract["max_interest"] == rules["debt"]["max_interest"], f"Contract interest drift: {contract['id']}")
        lines = [line for line in contract_doc.splitlines() if line.startswith("|") and contract["id"] in line]
        cells = [v.strip() for v in lines[0].split("|")[1:-1]] if lines else []
        check(len(cells) == 5 and contract["reward"] in cells[1] and cells[3] == str(contract["repay_price"]) and cells[4] == str(contract["min_floor"]), f"Contract document is stale: {contract['id']}")
    for combo in catalog["synergies"]:
        check(combo["route"] in lookup["routes"] and len(set(combo["relics"])) == 3, f"Invalid combo: {combo['id']}")
        check(all(item in lookup["relics"] for item in combo["relics"]), f"Unknown combo item: {combo['id']}")
        check(not combo["extra_set_bonus"] and bool(combo["tradeoff"]), f"Hidden bonus or missing tradeoff: {combo['id']}")
    for enemy in catalog["enemies"]:
        check(enemy["health"] > 0 and enemy["damage"] > 0, f"Invalid enemy numbers: {enemy['id']}")
        check(enemy["telegraph_ms"] >= combat["telegraph_floor_ms"] and bool(enemy["counterplay"]), f"Unreadable enemy: {enemy['id']}")
    for elite in catalog["elite_variants"]:
        base = lookup["enemies"].get(elite["base_enemy"])
        check(bool(base) and base["floor"] == elite["floor"], f"Unknown elite source/floor: {elite['id']}")
        check(base["telegraph_ms"] * elite["telegraph_multiplier"] >= combat["telegraph_floor_ms"], f"Elite tell too short: {elite['id']}")
    for boss in catalog["bosses"]:
        check(len(boss["phases"]) == 3 and boss["health"] > 0 and bool(boss["window"]), f"Incomplete boss: {boss['id']}")
        check(all(0 < p < len(boss["phases"]) for p in boss["fixed_heal_phase_indices"]), f"Invalid healing phase: {boss['id']}")
    for region in catalog["regions"]:
        check(region["boss"] in lookup["bosses"] and not lookup["bosses"][region["boss"]]["optional"], f"Invalid region boss: {region['id']}")
        check(len(region["enemy_ids"]) == 8 and all(lookup["enemies"][eid]["floor"] == region["floor"] for eid in region["enemy_ids"]), f"Wrong regional roster: {region['id']}")
    for room in catalog["room_templates"]:
        check(room["grid"] == rules["floors"]["room_grid"] and room["tile_size"] == rules["floors"]["tile_size"], f"Room dimension drift: {room['id']}")
    special_room_icons = {"flame", "circle-dot", "sun", "swords"}
    special_room_layers = {"region_base", "region_tension"}
    for room in catalog["special_rooms"]:
        check(room["icon"] in special_room_icons and room["palette"] in {"vermilion", "gold", "jade"}, f"Invalid special room presentation: {room['id']}")
        check(room["music_layer"] in special_room_layers and bool(room["behavior"]), f"Special room lacks audio/behavior contract: {room['id']}")
        check(len(room["choices"]) >= 2 and all(isinstance(choice, str) and choice for choice in room["choices"]), f"Special room choices are incomplete: {room['id']}")
    check({room["id"] for room in catalog["special_rooms"]} == {"sacrifice", "judge", "angel", "challenge"}, "Special room roster drifted from the authored room graph")
    graph_source = (ROOT / "game/scripts/core/room_graph.gd").read_text(encoding="utf-8")
    world_source = (ROOT / "game/scripts/combat/world.gd").read_text(encoding="utf-8")
    for room_id in ["sacrifice", "judge", "angel", "challenge"]:
        check(f'"{room_id}":' in graph_source and f'types.append("{room_id}")' in graph_source, f"Room graph is missing the {room_id} special branch")
        check(f'"{room_id}":' in world_source, f"World resolver is missing the {room_id} special branch")
    check([v * rules["floors"]["tile_size"] for v in rules["floors"]["room_grid"]] == rules["floors"]["walkable"], "Walkable dimensions do not match grid")
    for floor, weights in rules["loot"]["rarity_by_floor"].items():
        check(set(weights) == set(RARITIES) and abs(sum(weights.values()) - 1) < 1e-9, f"Invalid rarity probabilities on floor {floor}")
    check(rules["platforms"]["mobile_projectile_cap"] == rules["platforms"]["pc_projectile_cap"], "Mechanical budgets differ by platform")
    check(not rules["platforms"]["local_virtualization_allowed"] and rules["platforms"]["ios_requires_macos_xcode"], "Platform constraints missing")
    check(rules["save"]["resume_paused"] and rules["save"]["copies"] >= 2, "Save/resume contract incomplete")
    check(rules["loot"]["coin_pickup_radius"] + lookup["meta_unlocks"]["u_coin_pickup"]["grants"]["coin_pickup_radius_bonus"] == rules["loot"]["coin_pickup_radius_cap"], "Coin convenience exceeds its stated cap")
    check(rules["debt"]["grant_locked_relic_for_current_run"] and rules["debt"]["exclude_rewards_at_stack_cap"], "Contract reward filtering is unspecified")
    asset_ids = [a["id"] for a in manifest["assets"]]
    check(len(asset_ids) == len(set(asset_ids)), "Duplicate asset IDs")
    for asset in manifest["assets"]:
        path = (ROOT / asset["file"]).resolve()
        check(path.is_relative_to(ROOT), f"Asset escaped workspace: {asset['id']}")
        if asset.get("content_id"):
            check(asset["content_id"] in ids, f"Unknown asset content ID: {asset['id']}")
        if asset["kind"] == "concept":
            check(path.is_file(), f"Missing generated concept: {asset['id']}")
            content = path.read_bytes()
            check(content[:8] == b"\x89PNG\r\n\x1a\n" and list(struct.unpack(">II", content[16:24])) == asset["size"], f"Wrong concept format/dimensions: {asset['id']}")
            check(hashlib.sha256(content).hexdigest() == asset["sha256"], f"Concept provenance changed: {asset['id']}")
        if asset["engine_ready"]:
            check(asset["status"] == "engine_verified" and path.is_file(), f"False engine-ready asset claim: {asset['id']}")
    for key in ("weapons", "relics", "enemies", "bosses", "skills", "elite_variants", "npcs"):
        check(all("asset_" + item in asset_ids for item in lookup[key]), f"Missing production specifications: {key}")
    for char in catalog["characters"]:
        check(all(char["id"] + "_" + state in asset_ids for state in ("idle", "run", "cast", "dash", "hurt", "death")), f"Incomplete character animation specification: {char['id']}")
    prompts = load(DOCS / "assets" / "production-prompts.json")["prompts"]
    for prompt in prompts:
        check(prompt["asset_id"] in asset_ids and (ROOT / prompt["prompt"]).is_file(), f"Invalid production prompt: {prompt['asset_id']}")
        check(prompt["model"] == "gpt-image-2.5" and prompt["generation_status"] == "prompt_only", f"Wrong provider/status: {prompt['asset_id']}")
    for name, dimensions in [("pc", (1280, 720)), ("mobile", (1560, 720))]:
        svg = ET.parse(DOCS / "assets" / "wireframes" / (name + ".svg")).getroot()
        check((int(svg.attrib["width"]), int(svg.attrib["height"])) == dimensions, f"Invalid SVG viewport: {name}")
    docs = sorted(DOCS.glob("*.md"))
    check(len(docs) >= 28 and (DOCS / "26-combat-boundary-mixed-encounters.md").is_file(), "Expected complete design chapters including calibrated inner walls, mixed encounters and independent early boss chambers")
    links_checked = 0
    for doc in docs:
        content = doc.read_text(encoding="utf-8")
        check(len(content) > 700, f"A design chapter is unexpectedly empty: {doc.name}")
        check(not re.search(r"\b(TODO|TBD)\b", content), f"Unresolved template placeholder: {doc.name}")
        for target in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", content):
            if re.match(r"[a-z]+://", target) or target.startswith("#"):
                continue
            links_checked += 1
            check((doc.parent / target.split("#")[0]).is_file(), f"Broken document link: {doc.name}: {target}")
    generated = DOCS / "16-content-catalog.generated.md"
    check(generated.read_text(encoding="utf-8") == render(catalog), "Generated catalog is stale")
    sim = simulations(catalog, rules)
    pending = ["每角色完整双路线与全部示例组合的人类手感和平衡验收", "Android真实设备安装、三指触控、生命周期、文件选择器/软键盘/剪贴板和45分钟热稳定", "iOS真实macOS/Xcode签名构建与iPhone/iPad运行", "低端真机的透明边、屏幕安全区和完整UI触控范围", "长局音乐与手机扬声器/耳机的人类听测", "已实现96种手持搭配的真人动作观感与移动透明边验收"]
    report = {"date": date.today().isoformat(), "version": catalog["version"],
              "status": "design_constraints_passed" if not ERRORS else "design_constraints_failed",
              "checks": CHECKS, "errors": ERRORS, "content_counts": {key: len(catalog[key]) for key in EXPECTED},
              "design_chapters_including_index": len(docs), "local_links_checked": links_checked,
              "asset_status_counts": dict(Counter(a["status"] for a in manifest["assets"])),
              "production_prompt_count": len(prompts), "simulations": sim, "unverified_product_requirements": pending,
              "completion_claim": "Design checks only. The full playable multi-platform product is not complete."}
    folder = DOCS / "reports"
    folder.mkdir(exist_ok=True)
    (folder / "design-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 设计基线校验报告", "", "日期：" + report["date"] + "。数据版本：" + catalog["version"], "",
             "结果：" + ("设计约束通过" if not ERRORS else "设计约束失败"), "",
             f"共检查 {CHECKS} 项约束，包括跨表引用、独立事件枚举、角色与合同文档一致性、来源预算、素材规格、文件哈希、文档链接、SVG结构，以及掉落数学抽样。", "",
             f"共{len(docs)}份设计与索引文档；{len(prompts)}份历史素材提示词规格；扩展实际图源另见assets/expansion-production.json。素材状态：{report['asset_status_counts']}。", "",
             f"十一层每层抽样10000组奖励；固定种子20261003。低血状态10000次清房，最长{sim['max_clears_between_heals']}次清房出现治疗。保留的三章经济数学模型10000局均值{sim['coins_mean']}纸钱，P10={sim['coins_p10']}、P90={sim['coins_p90']}。十一层实战成长见runtime/expanded-full-run.json。", "",
             "这些检查证明文档、内容数据与所检查数学约束的一致性。实际模拟、通关、编译程序、资源与APK证据见runtime和platforms；设计绿色结果不替代移动设备验收。", "", "## 未验证的成品要求", ""]
    lines += ["- " + value for value in pending]
    if ERRORS:
        lines += ["", "## 错误", ""] + ["- " + value for value in ERRORS]
    (folder / "design-validation.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "errors": ERRORS, "content_counts": report["content_counts"],
                      "asset_status_counts": report["asset_status_counts"], "prompt_count": len(prompts), "coins_mean": sim["coins_mean"]}, ensure_ascii=False))
    if ERRORS:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
