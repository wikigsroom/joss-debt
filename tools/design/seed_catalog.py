"""Create the v0.1 authoring data once; subsequent edits belong in data/*.json."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs" / "incense-debt" / "data"


def write(name, value):
    path = DEST / name
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite authoring data: {path}")
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    if any((DEST / name).exists() for name in ("catalog.json", "rules.json", "asset-manifest.json")):
        raise FileExistsError("The baseline already exists; edit the JSON and run the validator.")
    routes = [
        {"id": rid, "name": name, "verbs": verbs}
        for rid, name, verbs in [
            ("fire", "烬火", "灼烧、区域、烧尽"),
            ("thread", "红绳", "连债、控制、传播"),
            ("ash", "归灰", "拾灰、能量、返击"),
            ("seal", "镇印", "招架、纸甲、破阵"),
            ("wind", "游风", "身法、回旋、路径"),
            ("ink", "墨契", "穿透、延迟、勾销"),
        ]
    ]
    character_rows = [
        ("c_paper", "纸童", 6, 240, "w01", ["ash", "fire"], "每次焚债首个击杀额外恢复4香火", "初始", "纸面具、短朱袍、香炉"),
        ("c_bell", "铃师", 5, 260, "w02", ["thread", "wind"], "基础连债上限4、连接距离200", "首次三目标连债", "菱形面具、双铃、红绳圈"),
        ("c_lantern", "灯客", 5, 240, "w03", ["fire", "ink"], "主攻击首次命中增加1层灼烧", "首次击败b01", "灯笼头、细长灯杆、黑红外套"),
        ("c_mask", "傩面", 8, 200, "w04", ["seal", "ash"], "三次主攻击命中获得1纸甲；12秒冷却、最多1层", "二十次预警闪避或招架", "木面具、方铜印、玉灰披风"),
        ("c_umbrella", "伞灵", 5, 265, "w05", ["wind", "ash"], "自然香灰额外恢复1香火；拾灰半径220", "单局回收200香火", "宽红伞、纸灵、长飘带"),
        ("c_ink", "墨吏", 6, 230, "w06", ["ink", "thread"], "余烬持续+2秒；可穿透主弹穿透+1", "累计偿还三份债约", "高纸帽、粗笔、空白账卷"),
    ]
    characters = []
    for i, (cid, name, hp, speed, weapon, affinity, passive, unlock, silhouette) in enumerate(character_rows):
        characters.append({"id": cid, "name": name, "health": hp, "speed": speed, "hit_radius": 12,
                           "weapon": weapon, "routes": affinity, "passive": passive, "unlock": unlock,
                           "silhouette": silhouette, "skills": [f"s{3*i+j:02d}" for j in (1, 2, 3)]})
    weapon_rows = [
        ("w01", "香炉丸", "orb", 12, .25, 620, 460, 1, 0, "单发稳定香火弹"),
        ("w02", "牵魂铃", "bell", 8, .22, 720, 360, 1, 0, "主目标命中后给52范围内一名邻敌轻挂1层余烬，无额外主攻击事件"),
        ("w03", "留夜灯", "flame_orb", 18, .40, 420, 420, 1, 0, "命中产生42半径火点，次级目标按50%伤害，无派生"),
        ("w04", "镇门印", "cone", 24, .50, 0, 140, 1, 0, "近距正面扇形重击，可击退轻敌"),
        ("w05", "碎骨伞", "returning", 10, .25, 600, 380, 1, 0, "去程100%、返程65%；各阶段每目标一次"),
        ("w06", "勾账笔", "piercing", 16, .34, 900, 520, 1, 2, "线形弹穿透，后续每目标衰减15%"),
        ("w07", "纸钱散", "fan", 5, .45, 580, 320, 5, 0, "五发扇形散射，共用一个攻击ID"),
        ("w08", "爆竹筒", "explosive", 32, .75, 550, 380, 1, 0, "80半径爆裂；范围伤害不能再触发火花遗物"),
        ("w09", "铜钱轮", "ricochet", 9, .18, 840, 500, 1, 0, "最多弹墙两次；同一目标1秒内最多命中一次"),
        ("w10", "招魂幡", "seeker", 14, .38, 400, 420, 1, 0, "0.2秒后有限追踪，优先瞄准方向的目标"),
        ("w11", "判官笔", "charged_line", 26, .60, 950, 600, 1, 4, "0.25秒蓄力，穿透四目标，可被身法取消"),
        ("w12", "灰骨刃", "arc", 20, .38, 0, 120, 1, 0, "近距弧斩；同一挥击每目标一次"),
    ]
    weapons = [{"id": wid, "name": name, "mode": mode, "damage": damage, "interval_s": interval,
                "projectile_speed": speed, "range": distance, "pellets": pellets, "pierce": pierce,
                "behavior": behavior, "mark_stacks": 1, "min_floor": 1, "max_floor": 3}
               for wid, name, mode, damage, interval, speed, distance, pellets, pierce, behavior in weapon_rows]
    skill_rows = [
        ("撒灰", 30, 5, 1.00, "radius", "320范围内引爆余烬并取得相连债链", True),
        ("纸燕", 30, 5, .90, "seek_marked", "两只灰燕合计90%强度；固定目标集合、每敌仅一次", True),
        ("爆竹", 36, 6, 1.20, "cross", "四向窄道集中引爆；通道外只保留债链伤害", True),
        ("铃断", 32, 5, .85, "chain", "优先引爆最大的一组债链，选取范围400", True),
        ("赤网", 34, 6, .75, "chain_root", "债链收紧0.5秒后爆发；Boss免疫定身", True),
        ("回音", 34, 6, .85, "chain_echo", "首段后0.5秒对固定集合追加55%首段伤害；次段无派生", True),
        ("灯宴", 36, 6, .90, "fire_field", "爆发后留下3秒火区，每秒6伤害，无次级派生", True),
        ("烛龙", 36, 6, 1.30, "narrow_line", "长线范围520、宽72集中引爆", True),
        ("走马灯", 34, 6, .70, "mobile_fire", "火区随玩家2.5秒；每秒6伤害，首次接触只挂一次余烬", False),
        ("镇印", 35, 6, 1.25, "guard_radius", "200范围引爆；前0.16秒正面招架可格挡弹", False),
        ("护门", 35, 6, .85, "guard_cone", "0.4秒正面阻挡；最多记录三颗格挡弹强化反击", False),
        ("破阵", 38, 7, 1.35, "heavy_radius", "强化近距击退并移除一层可破铜盾", True),
        ("回伞", 24, 4, .85, "recall_radius", "420范围回收自然香灰并引爆已标记目标", False),
        ("雨帐", 28, 5, .70, "rain", "1.8秒内四段定点落灰；每目标首段可派生，其余不派生", True),
        ("借风", 28, 5, .90, "push_recall", "轻推普通敌人、加快回旋主弹返程；不移动Boss", True),
        ("勾销", 28, 5, 1.10, "line", "当前瞄准线长480宽80，合并债链后引爆", True),
        ("飞白", 30, 5, .70, "triple_line", "三条窄线，每目标在首段最多命中一次", True),
        ("重书", 34, 6, 1.00, "line_echo", "一秒后沿原固定线追加55%首段伤害；次段无派生", True),
    ]
    skills = []
    for i, (name, cost, cd, power, mode, behavior, requires_mark) in enumerate(skill_rows):
        base = 3 * (i // 3) + 1
        skills.append({"id": f"s{i+1:02d}", "name": name, "character": characters[i//3]["id"],
                       "variant": "base" if i % 3 == 0 else "evolution", "evolves_from": None if i % 3 == 0 else f"s{base:02d}",
                       "energy_cost": cost, "cooldown_s": cd, "power": power, "targeting": mode,
                       "requires_marked_target": requires_mark, "behavior": behavior,
                       "secondary_can_proc": False, "max_generation_depth": 2})
    # Stable item IDs r01-r48 are eight items per route; r49-r54 span two routes.
    item_rows = [
        ("灯芯屑", "fire", "common", 2, "primary_hit", "首次给无余烬目标挂标记时附加1灼烧，每目标2秒冷却"),
        ("火星灯", "fire", "uncommon", 1, "detonate_hit", "首段给80范围内一名未标记敌人挂1余烬；新标记留给下一次技能"),
        ("油纸笼", "fire", "common", 2, "stat", "自身火区持续时间每层+0.75秒"),
        ("蜡泪珠", "fire", "common", 2, "natural_kill", "烧着的敌人死亡留下1秒微火区，每秒3伤害，不派生"),
        ("纸爆竹", "fire", "uncommon", 1, "detonate_hit", "首段命中生成两枚25%伤害火星，不派生，每敌每链一次"),
        ("烧尽符", "fire", "rare", 1, "detonate_hit", "目标有3灼烧时焚债伤害+20%，结算后清空灼烧"),
        ("不灭灯", "fire", "rare", 1, "detonate_complete", "每房首次单技能击杀至少3敌返还12香火"),
        ("三昧余烬", "fire", "mythic", 1, "burn_tick", "每目标第三次灼烧跳伤爆出80范围6伤害；6秒冷却、无派生"),
        ("红绳结", "thread", "common", 2, "stat", "连债上限每层+1，最终最多6"),
        ("绳结铃", "thread", "common", 2, "stat", "连债距离每层+30"),
        ("牵命签", "thread", "uncommon", 1, "chain_form", "新连接两端各受4伤害，同一目标对1秒冷却，不派生"),
        ("锁愿钩", "thread", "uncommon", 1, "chain_form", "处于债链的普通敌人减速15%，脱链恢复"),
        ("同债钱", "thread", "rare", 1, "primary_hit", "主攻命中向债链另一端传35%伤害，不派生"),
        ("八字扣", "thread", "uncommon", 1, "primary_hit", "同一目标第三次主攻命中给邻近未标记者挂1余烬，2秒冷却"),
        ("群愿册", "thread", "rare", 1, "detonate_hit", "债链传播伤害系数最低0.90"),
        ("赤线天罗", "thread", "mythic", 1, "detonate_start", "一次焚债每组最多把债线穿过的一名额外目标纳入集合，每组目标上限6"),
        ("灰囊", "ash", "common", 2, "ash_pickup", "每份自然香灰额外恢复2香火/层"),
        ("回魂灰", "ash", "uncommon", 1, "natural_kill", "自然击杀生成一枚35%武器伤害灰弹；灰弹击杀不再生成灰弹"),
        ("回炉瓦", "ash", "common", 2, "stat", "焚债消耗每层-3，最终最低18"),
        ("余温香", "ash", "uncommon", 1, "mark_first", "首次给无余烬目标挂标记额外恢复1香火，每目标2秒冷却"),
        ("还魂碟", "ash", "rare", 1, "elite_clear", "每层首次精英清房恢复1心火，满血时给4纸钱"),
        ("聚灰盘", "ash", "uncommon", 2, "stat", "拾灰半径每层+80，最终上限420"),
        ("逆灰轮", "ash", "rare", 1, "ash_pickup", "每第三份自然香灰释放一枚30%武器伤害灰弹，可挂标记但无派生"),
        ("百愿回炉", "ash", "mythic", 1, "detonate_complete", "每房首次单技能击杀至少3敌，下一次技能免香火，最多兑现一次"),
        ("铜印裂纹", "seal", "common", 2, "deflect", "招架后2秒内下一次主攻伤害+25%/层，一次攻击兑现"),
        ("纸甲扣", "seal", "common", 1, "room_clear", "清房获得1纸甲，已有纸甲则不叠加"),
        ("门槛石", "seal", "uncommon", 1, "primary_hit", "原地停留0.4秒后的主攻击退+30%"),
        ("挡灾钱", "seal", "uncommon", 1, "deflect", "成功招架恢复8香火，2秒冷却"),
        ("护愿符", "seal", "rare", 1, "lethal_damage", "致死时保留1心火并消耗此遗物；每局最多一次，消耗后不再入池"),
        ("反账镜", "seal", "uncommon", 1, "dash_start", "身法前0.08秒反射一枚可格挡弹，2秒冷却；反射弹无派生"),
        ("镇门钉", "seal", "rare", 1, "detonate_complete", "落点留1.5秒铜印区，每秒6伤害，无派生"),
        ("无债金身", "seal", "mythic", 1, "player_damage", "每层首次受伤免除1心火，该房清场前移速-10%"),
        ("风纸翅", "wind", "common", 2, "stat", "移速+6%/层"),
        ("折步签", "wind", "common", 2, "stat", "身法距离+20/层"),
        ("燕返骨", "wind", "uncommon", 1, "primary_hit", "主弹尽头返程35%伤害；已有返程提升25%；近战改为身后25%回击"),
        ("掠灰羽", "wind", "uncommon", 1, "dash_path", "吸收身法路径96范围内自然香灰"),
        ("回身铃", "wind", "rare", 1, "dodge_success", "成功穿过预警攻击后，下一次主攻追加两枚50%侧弹，3秒冷却"),
        ("游愿旗", "wind", "uncommon", 1, "distance_moved", "累计移动160后下一次焚债范围+60，施放后重计"),
        ("风过留痕", "wind", "rare", 1, "dash_path", "身法留2秒纸痕，每秒5伤害，无派生"),
        ("千纸回旋", "wind", "mythic", 1, "primary_hit", "每第二次主攻0.3秒后追加45%攻击重演，无遗物派生"),
        ("墨点", "ink", "common", 2, "stat", "可穿透主弹穿透+1/层；近战攻击宽度+10%/层"),
        ("留白页", "ink", "common", 2, "stat", "余烬持续+1.5秒/层"),
        ("迟账符", "ink", "uncommon", 1, "detonate_hit", "首段储存15%伤害，1秒后在固定命中点结算，无派生"),
        ("穿名签", "ink", "uncommon", 1, "primary_hit", "穿透伤害衰减减少15个百分点；不穿透武器对满余烬目标伤害+10%"),
        ("勾销章", "ink", "rare", 1, "detonate_start", "同一窄直线上至少三名已标记者，本次技能伤害+20%"),
        ("黑契纸", "ink", "uncommon", 1, "stat", "每份生效债约主攻+10%最多2份；无债约时余烬持续+1秒"),
        ("重书卷", "ink", "rare", 1, "detonate_complete", "每房首次技能1秒后追加35%原形态回放，固定集合、无派生"),
        ("空名总账", "ink", "mythic", 1, "primary_hit", "穿透后的第三目标挂满3余烬；其他武器改为第三次攻击的首个命中目标；3秒冷却"),
        ("灰线绣", "ash,thread", "rare", 1, "ash_pickup", "拾灰时刷新最近债链两端余烬持续，每链1秒冷却"),
        ("走灯鞋", "wind,fire", "rare", 1, "dash_path", "身法路径留2秒窄火区，每秒6伤害，无派生"),
        ("铜灰砚", "seal,ash", "rare", 1, "deflect", "招架时回收160范围内自然香灰，每次事件一次"),
        ("红墨印", "thread,ink", "rare", 1, "primary_hit", "穿透命中可把260距离内一名已标记者接入债链，上限仍为6"),
        ("护灯绳", "seal,fire", "rare", 1, "armor_break", "纸甲碎裂时给近身两敌加1灼烧，2秒冷却"),
        ("借愿香", "ink,ash", "mythic", 1, "contract_repay", "偿还后下一个安全奖励位多一稀有候选，下次技能返香10；每局最多2次"),
    ]
    relics = []
    for i, (name, route, rarity, stack, trigger, behavior) in enumerate(item_rows, 1):
        relics.append({"id": f"r{i:02d}", "name": name, "routes": route.split(","), "rarity": rarity,
                       "stack_limit": stack, "trigger": trigger, "behavior": behavior,
                       "min_floor": 1 if rarity != "mythic" else 2, "max_floor": 3,
                       "proc_policy": {"primary_only": trigger in {"primary_hit", "mark_first"},
                                       "secondary_can_proc": False, "max_generation_depth": 2,
                                       "once_per_target_per_pulse": True}, "implementation_status": "specified"})
    # A repay-reward item must remain available before the last safe reward.
    relics[-1]["min_floor"] = 1
    relics[-1]["max_floor"] = 2
    talent_rows = {
        "fire": [("余烬入灯", "主攻首次挂标记附加1灼烧"), ("暖芯", "火区持续+0.5秒"),
                 ("流火", "灼烧目标被焚债后邻敌挂1灼烧，每链最多2敌"), ("催燃", "焚债对2层以上灼烧目标+15%伤害"),
                 ("烧尽还愿", "三层灼烧消耗时生成短火区，无派生"), ("长明", "一房首次三目标焚债返香10")],
        "thread": [("牵线", "连债上限+1"), ("远结", "连接距离+35"),
                   ("收紧", "焚债起手对链上普通敌人减速25%持续0.6秒"), ("共担", "主弹命中另一端传递20%无派生伤害"),
                   ("群愿", "传播系数最低0.85"), ("补结", "首段击杀向最近未标记者挂1余烬，留到下次技能")],
        "ash": [("惜灰", "自然香灰额外返香1"), ("归途", "拾灰范围+60"),
                ("灰击", "每第三份香灰发射25%伤害灰弹，无派生"), ("稳炉", "战斗被动香火恢复+1/秒"),
                ("复燃", "每房首个三目标技能返香8"), ("留温", "技能消耗-4，最终最低18")],
        "seal": [("纸甲", "每房前两次清晰预警闪避后得1纸甲，最多1层"), ("反印", "身法前0.06秒可反射一枚可格挡弹"),
                 ("印鸣", "招架后下一次主攻+20%"), ("守门", "纸甲碎裂时恢复6香火"),
                 ("破阵", "焚债移除一层可破铜盾"), ("铜身", "每层首次精英清房得1纸甲与1心火")],
        "wind": [("轻步", "移速+5%"), ("折身", "身法距离+20"),
                 ("回旋", "已有返程攻击+20%伤害；其他武器在第三次命中追加后向轻弹"), ("掠愿", "身法路径吸灰半径+40"),
                 ("双返", "成功闪避后下一次主攻追加40%返程，无派生"), ("留风", "身法路径留1.5秒低伤纸痕")],
        "ink": [("落点", "可穿透弹穿透+1；近战宽度+10%"), ("留白", "余烬持续+1秒"),
                ("迟书", "技能首段10%伤害延后0.8秒，无派生"), ("明契", "有债约时主攻+10%，无债约时技能+5%"),
                ("勾销", "一条窄线三目标技能+15%伤害"), ("复写", "每房首次技能追加25%固定回放，无派生")],
    }
    talents = []
    for route, rows in talent_rows.items():
        for i, (name, behavior) in enumerate(rows):
            tier = i // 2 + 1
            talents.append({"id": f"t_{route}_{tier}{'ab'[i%2]}", "name": name, "route": route,
                            "tier": tier, "min_route_points": tier - 1, "stack_limit": 1,
                            "behavior": behavior, "secondary_can_proc": False})
    contract_rows = [
        ("d01", "借火", "r02", 1, 18, 1, "每两间普通战房多一名催账鬼，有0.8秒入场预告"),
        ("d02", "牵线", "r09", 1, 20, 1, "普通战房一组敌方债线定时发射一枚预警弹"),
        ("d03", "借灰", "r18", 1, 22, 1, "自然香灰开始吸引额外延迟0.5秒"),
        ("d04", "借命", "r29", 2, 28, 2, "商店疗愈槽价格+50%"),
        ("d05", "铜息", "r13", 2, 28, 1, "普通清房保底纸钱-1，最终不少于1"),
        ("d06", "行债", "r38", 2, 26, 1, "身法冷却+0.3秒"),
        ("d07", "空名", "r48", 3, 36, 2, "首次挂余烬的基础2香火返还失效"),
        ("d08", "镇门", "r32", 3, 34, 2, "进入普通战房前3秒移速-12%"),
        ("d09", "总账", "r49", 3, 36, 2, "无主神阶段转换多一枚可破护印；全战最多两枚"),
    ]
    contracts = [{"id": cid, "name": name, "reward": reward, "min_floor": floor, "max_floor": floor,
                  "repay_price": price, "risk_points": risk, "penalty": penalty,
                  "interest_per_floor": 6, "max_interest": 12, "keep_reward_on_repay": True}
                 for cid, name, reward, floor, price, risk, penalty in contract_rows]
    enemy_rows = [
        ("e01", "灯笼鬼", 1, 40, 90, 600, 1, "单向慢弹", "横移后挂标"),
        ("e02", "纸犬", 1, 28, 180, 600, 1, "停顿后直线扑咬", "预警后侧向闪避"),
        ("e03", "铜钱精", 1, 48, 110, 650, 1, "三发扇形钱弹", "绕外侧或把它接入链"),
        ("e04", "折纸蝠", 1, 24, 210, 550, 1, "折线掠过后单发", "提前引向火区"),
        ("e05", "供台童", 1, 60, 60, 900, 2, "高抛标记地面纸炮", "离开显形圆区"),
        ("e06", "绳结怨", 1, 32, 80, 750, 1, "拉线减速与慢弹", "优先击破或反向身法"),
        ("e07", "灰袋客", 1, 56, 100, 700, 1, "投掷扇形灰包", "压近逼出投掷窗口"),
        ("e08", "灯油匠", 1, 52, 70, 800, 1, "铺短时敌方油区", "从预留空道绕行"),
        ("e09", "钱盾卫", 2, 92, 100, 650, 1, "正面铜盾与短刺", "侧打、破盾或链入背面目标"),
        ("e10", "算盘蛛", 2, 60, 160, 850, 1, "横竖交替棋盘弹", "站入下一拍空格"),
        ("e11", "金纸蛾", 2, 45, 220, 600, 1, "绕圈俯冲弹", "有限追踪或提前余烬"),
        ("e12", "称愿鬼", 2, 100, 60, 900, 2, "重钱球封窄路", "利用宽侧绕过"),
        ("e13", "收钱犬", 2, 52, 210, 650, 1, "两段冲锋", "第二段前保留身法"),
        ("e14", "碎币匠", 2, 72, 90, 750, 1, "抵墙后分裂的钱弹", "观察落点、离墙留空"),
        ("e15", "悬钱铃", 2, 70, 0, 600, 1, "定点节拍弹环留缺口", "从固定缺口接近"),
        ("e16", "讨债账房", 2, 80, 80, 800, 1, "有限召纸犬与催账弹", "优先断召唤；全房召唤上限八"),
        ("e17", "无名纸卫", 3, 105, 140, 700, 1, "抬刀后窄线斩", "离线后反击"),
        ("e18", "墨页虫", 3, 64, 190, 900, 1, "固定位置延迟墨弹", "记住预警位置后移动"),
        ("e19", "空面灯", 3, 98, 95, 650, 1, "环绕弹在标记时散开", "先标记后沿缺口靠近"),
        ("e20", "封愿柱", 3, 150, 0, 900, 2, "可打断的印区施法", "留一次焚债打断"),
        ("e21", "断线傀", 3, 70, 200, 800, 1, "显形后短距移位扑击", "看显形圈、保持距离"),
        ("e22", "催息吏", 3, 120, 100, 900, 1, "累积两拍后扇形催息", "优先集火打断节拍"),
        ("e23", "卷账兽", 3, 160, 80, 1000, 2, "长前摇重冲与纸页屏障", "用身法穿过侧边开口"),
        ("e24", "灰愿影", 3, 88, 160, 900, 1, "预告后模仿最近主攻方向", "改变站位，把旧方向留空"),
    ]
    enemies = [{"id": eid, "name": name, "floor": floor, "health": hp, "speed": speed,
                "telegraph_ms": telegraph, "damage": damage, "pattern": pattern, "counterplay": counter,
                "can_mark": True, "natural_ash": 8, "reward_once": True}
               for eid, name, floor, hp, speed, telegraph, damage, pattern, counter in enemy_rows]
    elite_variants = [{"id": f"x{i+1:02d}", "name": name, "base_enemy": base, "floor": floor,
                       "health_multiplier": 3, "telegraph_multiplier": .90, "damage_bonus": 1,
                       "special_rule": rule, "natural_ash": 16}
                      for i, (name, base, floor, rule) in enumerate([
                          ("长明灯鬼", "e01", 1, "两段弹阵之间留固定缺口"),
                          ("守门纸犬", "e02", 1, "三次冲锋后长恢复"),
                          ("镀金盾卫", "e09", 2, "铜盾分两层，侧面仍可直接命中"),
                          ("多足算盘", "e10", 2, "交替棋盘增加一行，缺口预告"),
                          ("空名封柱", "e20", 3, "两印轮替，连续焚债可打断其中一印"),
                          ("总账卷兽", "e23", 3, "纸屏先开一个可破缺口再冲锋"),
                      ])]
    bosses = [
        {"id": "b01", "name": "债主判官", "floor": 1, "health": 1400, "optional": False,
         "phases": ["算盘弧：沿外侧钱弹，中央留空", "朱印封路：0.9秒预告两处印区", "借据护体：打破纸签可连债到本体"],
         "window": "纸签断裂或落印后1.2秒", "unlock_condition": "主线", "natural_ash": 30},
        {"id": "b02", "name": "铁算盘", "floor": 2, "health": 2400, "optional": False,
         "phases": ["拨珠：横竖弹阵交替留空", "称愿：重钱球落地后让出侧路", "铜盾账架：侧面挂标再连债"],
         "window": "拨珠结束和称愿落地后1.0秒", "unlock_condition": "主线", "natural_ash": 30},
        {"id": "b03", "name": "无主神", "floor": 3, "health": 3800, "optional": False,
         "phases": ["翻账：护印与可见安全道", "催息：两拍标记后落印，可打断", "空名：三种已学阵型组合，核心开放"],
         "window": "护印被破后1.5秒；大招后1.2秒", "unlock_condition": "主线", "natural_ash": 30},
        {"id": "b04", "name": "无名债主", "floor": 2, "health": 2600, "optional": True,
         "phases": ["揭名：分身均有可辨轮廓", "错账：复制标记位置，延迟攻击", "还名：对齐两个已标记分身暴露本体"],
         "window": "同次焚债命中两个分身后1.4秒", "unlock_condition": "发现三张姓名页", "natural_ash": 30},
        {"id": "b05", "name": "息页巨灵", "floor": 3, "health": 3200, "optional": True,
         "phases": ["堆息：页面形成可破掩体", "倒印：预告后旋转危险区", "撕页：连续击破三角纸封开放心室"],
         "window": "纸封全破后1.6秒", "unlock_condition": "偿还三类债约且发现利息页", "natural_ash": 30},
    ]
    combo_rows = [
        ("火链初成", "fire", ["r01", "r02", "r09"], "主攻挂火并成链，焚债爆发后补下一轮标记", "分散敌人需重新组织"),
        ("烧尽灯宴", "fire", ["r03", "r06", "r07"], "累积灼烧后一次烧尽，延长火区维持回收", "移动Boss会离开火区"),
        ("火花纸爆", "fire", ["r02", "r05", "r10"], "扩大连债距离并用小火星补侧面伤害", "火星无递归派生"),
        ("走灯火路", "fire", ["r01", "r04", "r50"], "沿身法路径点火，死亡微火区连接后续攻击", "地面覆盖短，不能原地等"),
        ("红绳同债", "thread", ["r09", "r10", "r13"], "射前排也能伤另一端，焚债收整组", "盾面仍需侧向处理"),
        ("收紧赤网", "thread", ["r09", "r12", "r14"], "连续命中补结，减速让链保持完整", "Boss免疫定身"),
        ("群愿远结", "thread", ["r10", "r11", "r15"], "跨阵建立连接并减少焚债衰减", "上限仍为六目标"),
        ("红墨穿线", "thread", ["r09", "r41", "r52"], "穿透一次挂多点，自动接入更远链端", "需要对齐射击"),
        ("回魂灰环", "ash", ["r17", "r18", "r19"], "击杀返灰弹、自然灰补能、降低技能门槛", "次级灰弹不再产灰弹"),
        ("逆灰双轮", "ash", ["r17", "r22", "r23"], "扩大拾取并把第三份香灰转为返击", "Boss少小怪时依赖基础恢复"),
        ("稳炉留温", "ash", ["r19", "r20", "r21"], "持续标记补能，精英恢复心火", "伤害需要主武器支撑"),
        ("灰线回愿", "ash", ["r18", "r22", "r49"], "收灰刷新链两端，方便下一次技能", "必须保留目标活到下一轮"),
        ("铜印反账", "seal", ["r25", "r28", "r30"], "身法招架得香火并强化下一次主攻", "地面范围攻击不能招架"),
        ("纸甲护灯", "seal", ["r26", "r31", "r53"], "纸甲碎时点火，近距印区收尾", "背面围攻仍危险"),
        ("铜灰守门", "seal", ["r25", "r30", "r51"], "反射弹同时回收周围自然香灰", "需要看准可格挡攻击"),
        ("留命破阵", "seal", ["r26", "r27", "r29"], "纸甲争取重击窗口，一次致死保护兜底", "护愿符消费后不可再抽"),
        ("风纸掠灰", "wind", ["r33", "r34", "r36"], "更长位移收沿途灰，不停步补技能", "进危险区必须看前摇"),
        ("燕返双攻", "wind", ["r34", "r35", "r37"], "穿过弹阵后侧弹与返程覆盖两侧", "返程方向取决于先前位置"),
        ("游愿留痕", "wind", ["r33", "r38", "r39"], "持续移动扩技能范围，身后纸痕收追兵", "直线跑易被预判"),
        ("风火并行", "wind", ["r35", "r36", "r50"], "返程主弹沿火路攻击，再收灰续爆", "单体爆发较弱"),
        ("穿账勾销", "ink", ["r41", "r44", "r45"], "对齐多个目标，穿透保持伤害后焚债", "围攻时需要位移补强"),
        ("迟账重书", "ink", ["r42", "r43", "r47"], "长标记窗口积累目标，延后和回放补第二拍", "回放位置固定、不能自动追敌"),
        ("黑契回炉", "ink", ["r19", "r20", "r46"], "持约提高主攻，再用标记回能驱动爆发", "必须承受合同明示惩罚"),
        ("红墨余灰", "ink", ["r41", "r49", "r52"], "穿透连接与拾灰刷新组成长线持续输出", "远端敌人离线会断链"),
    ]
    synergies = [{"id": f"combo{i+1:02d}", "name": name, "route": route, "relics": items,
                  "result": result, "tradeoff": tradeoff, "extra_set_bonus": False}
                 for i, (name, route, items, result, tradeoff) in enumerate(combo_rows)]
    regions = [{"id": rid, "name": name, "floor": floor, "boss": boss,
                "enemy_ids": [e["id"] for e in enemies if e["floor"] == floor]}
               for rid, name, floor, boss in [("paper_lane", "纸灯巷", 1, "b01"),
                                               ("coin_vault", "铜钱库", 2, "b02"),
                                               ("ownerless_temple", "无主神殿", 3, "b03")]]
    room_templates = [{"id": f"room_{family}_{variant}", "family": family, "variant": variant,
                       "grid": [18, 9], "tile_size": 64, "required_doors": ["north", "south"],
                       "validation_status": "specified"}
                      for family in ("open", "pillars", "zigzag", "loop", "bridge", "side_doors")
                      for variant in range(1, 4)]
    for boss in bosses:
        boss["fixed_heal_phase_indices"] = [2] if boss["id"] == "b03" else [1]
    npcs = [{"id": nid, "name": name, "function": role, "silhouette": silhouette} for nid, name, role, silhouette in [
        ("n01", "织愿婆", "还愿簿与主线回顾", "矮纸婆婆、拼纸围裙、针线盘"),
        ("n02", "铜算盘", "图鉴与训练场", "直立铜算盘、两只纸手、墨色短脚"),
        ("n03", "无面账房", "债约与偿还", "方帽、空白面孔、宽账册"),
        ("n04", "灯摊小贩", "商店与试武器", "背灯架的纸狸、短围裙、钱串"),
        ("n05", "留名牌", "个人任务与结局收藏", "可翻面木牌、纸脚架、朱印角")]]
    meta_unlocks = []
    for i, route in enumerate(routes):
        rid = route["id"]
        start = i * 8 + 1
        meta_unlocks.append({"id": f"u_{rid}_mid", "name": route["name"] + "进阶页", "kind": "relic_pack", "cost": 20,
                             "requires": {"boss_defeated": "b01"}, "grants": {"relic_ids": [f"r{j:02d}" for j in range(start+3, start+6)]}})
        meta_unlocks.append({"id": f"u_{rid}_end", "name": route["name"] + "终页", "kind": "relic_pack", "cost": 45,
                             "requires": {"boss_defeated": "b02", "unlocks": [f"u_{rid}_mid"]}, "grants": {"relic_ids": [f"r{j:02d}" for j in range(start+6, start+8)]}})
    for relic in relics[-6:]:
        meta_unlocks.append({"id": "u_hybrid_" + relic["id"][1:], "name": relic["name"] + "页", "kind": "relic_pack", "cost": 25,
                             "requires": {"route_pair_chosen": relic["routes"]}, "grants": {"relic_ids": [relic["id"]]}})
    for uid, name, cost, requirement, grants in [
        ("u_memory_index", "愿页索引", 8, {}, {"feature": "story_filter_by_character"}),
        ("u_training", "铜盘演阵", 12, {"boss_defeated": "b01"}, {"feature": "seen_boss_pattern_training"}),
        ("u_loadout", "常用器具签", 16, {"boss_defeated": "b01"}, {"feature": "remember_unlocked_starting_weapon"}),
        ("u_coin_pickup", "拾钱绳", 12, {}, {"coin_pickup_radius_bonus": 40})]:
        meta_unlocks.append({"id": uid, "name": name, "cost": cost, "kind": "convenience", "requires": requirement, "grants": grants})
    catalog = {"version": "0.1.0", "status": "design_baseline", "meta_unlocks": meta_unlocks, "npcs": npcs, "routes": routes, "characters": characters,
               "weapons": weapons, "skills": skills, "relics": relics, "talents": talents,
               "debt_contracts": contracts, "enemies": enemies, "elite_variants": elite_variants,
               "bosses": bosses, "synergies": synergies, "regions": regions, "room_templates": room_templates}
    rules = {
        "version": "0.1.0", "units": "world units; seconds; integer health",
        "combat": {"tick_hz": 60, "health_hit_radius": 12, "health_max_cap": 12, "energy_start": 40, "energy_max": 100,
                   "energy_regen_combat_s": 3, "first_mark_energy": 2, "first_mark_icd_s": 2,
                   "natural_ash": 8, "elite_ash": 16, "boss_ash": 30, "ash_delay_s": .6,
                   "ash_radius": 120, "ash_radius_cap": 420, "skill_cost_floor": 18,
                   "mark_cap": 3, "mark_duration_s": 5, "burn_cap": 3, "burn_duration_s": 3,
                   "burn_damage_per_stack_s": 3, "detonate_base": 20, "detonate_per_mark": 8,
                   "chain_radius": 160, "chain_group_base": 2, "chain_group_cap": 6,
                   "chain_falloff": [1, .85, .72], "dash_distance": 160, "dash_duration_s": .20,
                   "dash_invulnerable_s": .15, "dash_cooldown_s": 2, "hurt_invulnerable_s": .8,
                   "input_buffer_ms": 80, "crit_chance": .05, "crit_multiplier": 1.5,
                   "proc_depth_cap": 2, "chain_event_cap": 48, "boss_control_resistance": .85,
                   "telegraph_floor_ms": 350, "active_enemies_cap": 8, "boss_adds_cap": 6,
                   "summons_per_room_cap": 8, "rewarded_summons_per_room_cap": 2, "unrewarded_summon_ash": 4},
        "progression": {"initial_relic_ids": [f"r{route*8+j:02d}" for route in range(6) for j in (1,2,3)],
                        "meta_purchases_repeatable": False,
                        "level_thresholds": [20, 50, 90, 140, 200, 270], "xp": {"combat": 10, "elite": 18, "boss": 30},
                        "relic_slots": 12, "level_choices": 3, "evolution_floor": 2,
                        "meta_currency": {"combat": 1, "elite": 2, "boss": 5, "boss_first": 8},
                        "route_affinity_increment": .15, "route_affinity_cap": 1.6},
        "loot": {"coin_pickup_radius": 120, "coin_pickup_radius_cap": 160,
                 "coins_start": 10, "enemy_coin_chance": .60, "enemy_coin_range": [1, 2],
                 "clear_coins": {"combat": 3, "elite": 8, "boss": 12},
                 "heal": {"base_chance": .12, "per_missed_clear": .08, "chance_cap": .44,
                          "low_health_ratio": .5, "miss_limit": 3, "amount": 2,
                          "eligible_rooms": ["combat", "elite"], "full_health_compensation_coins": 3},
                 "reward_choices": 3, "boss_health_upgrade": 1, "boss_fixed_heal_amount": 2,
                 "rerolls_start": 1, "rerolls_cap": 3,
                 "rarity_by_floor": {"1": {"common": .65, "uncommon": .30, "rare": .05, "mythic": 0},
                                     "2": {"common": .45, "uncommon": .35, "rare": .17, "mythic": .03},
                                     "3": {"common": .30, "uncommon": .40, "rare": .25, "mythic": .05}},
                 "shop_prices": {"common": 18, "uncommon": 30, "rare": 48, "mythic": 72,
                                 "weapon": 35, "heal": 10, "reroll": 12},
                 "enemy_ledger_key": ["run_id", "room_id", "enemy_uid"],
                 "reward_ledger_key": ["run_id", "room_id", "reward_slot"]},
        "debt": {"grant_locked_relic_for_current_run": True, "exclude_rewards_at_stack_cap": True,
                 "active_contracts_cap": 2, "risk_points_cap": 4, "boss_extra_collectors": False,
                 "interest_per_floor": 6, "max_interest": 12, "repay_at": "safe_floor_checkpoint"},
        "floors": {"count": 3, "base_rooms": {"combat": 6, "elite": 1, "reward": 1, "shop": 1, "debt": 1, "boss": 1},
                   "optional_rooms_range": [0, 2], "min_main_path_combat_rooms": 4,
                   "reward_before_combat_room": 3, "room_grid": [18, 9], "tile_size": 64,
                   "canvas": [1280, 720], "walkable": [1152, 576], "spawn_player_distance": 220},
        "platforms": {"engine": "Godot", "engine_baseline": "4.7.2", "language": "GDScript",
                      "renderer": "gl_compatibility", "orientation": "landscape",
                      "pc_target_fps": 60, "mobile_target_fps": 60, "mobile_low_fps": 30,
                      "mobile_projectile_cap": 240, "pc_projectile_cap": 240,
                      "mobile_vfx_particle_cap": 120, "pc_vfx_particle_cap": 320,
                      "texture_memory_mb_budget": 128, "working_set_mb_budget": 350,
                      "package_mb_budget": 180, "android_touch_dp_min": 48, "ios_touch_pt_min": 44,
                      "target_touch_size": 56, "safe_area_runtime": True, "ios_requires_macos_xcode": True,
                      "local_virtualization_allowed": False, "runtime_verification_status": "pending"},
        "event_names": sorted({r["trigger"] for r in relics}),
        "save": {"schema_version": 2, "mode": "joint_account_run_journal", "copies": 2,
                 "checksum": "sha256", "resume_paused": True, "migrate_content_by_id": True,
                 "legacy_schema_versions": [1], "preserve_legacy_files": True,
                 "manual_transfer": ["checked_json_file", "compressed_text"], "preview_before_import": True,
                 "import_undo_backup": True, "keep_local_settings_by_default": True},
    }
    assets = [
        {"id": "concept_roster", "kind": "concept", "status": "reviewed_concept", "engine_ready": False,
         "file": "output/imagegen/incense-debt/characters-roster.png", "size": [1536, 1024],
         "prompt": "docs/incense-debt/assets/prompts/characters-roster.txt", "provider": "sub2-image-gen", "model": "gpt-image-2.5"},
        {"id": "concept_paper_room", "kind": "concept", "status": "reviewed_concept", "engine_ready": False,
         "file": "output/imagegen/incense-debt/paper-lantern-asset-board.png", "size": [1536, 1024],
         "prompt": "docs/incense-debt/assets/prompts/paper-lantern-asset-board.txt", "provider": "sub2-image-gen", "model": "gpt-image-2.5"},
    ]
    for char in characters:
        for state, frames in [("idle", 4), ("run", 6), ("cast", 4), ("dash", 3), ("hurt", 2), ("death", 5)]:
            assets.append({"id": f"{char['id']}_{state}", "kind": "character_strip", "content_id": char["id"],
                           "state": state, "frames_per_direction": frames, "directions": 4,
                           "frame_size": [96, 96], "source_cell": [256, 256], "anchor": [.5, .84],
                           "alpha_required": True, "status": "planned", "engine_ready": False,
                           "file": f"game/assets/characters/{char['id']}/{state}.png"})
    for group, kind, frame, folder in [(weapons, "weapon", [96, 96], "weapons"),
                                       (relics, "relic_icon", [64, 64], "relics"),
                                       (enemies, "enemy_bundle", [128, 128], "enemies"),
                                       (bosses, "boss_bundle", [256, 256], "bosses")]:
        for entry in group:
            assets.append({"id": "asset_" + entry["id"], "kind": kind, "content_id": entry["id"],
                           "frame_size": frame, "alpha_required": True, "anchor": [.5, .84],
                           "status": "planned", "engine_ready": False, "file": f"game/assets/{folder}/{entry['id']}.png"})
    for region in regions:
        for part, size in [("floor", [64, 64]), ("wall", [128, 128]), ("door", [128, 192]),
                           ("props", [128, 128]), ("boss_room", [1280, 720])]:
            assets.append({"id": region["id"] + "_" + part, "kind": "environment", "region": region["id"],
                           "frame_size": size, "alpha_required": part != "floor",
                           "status": "planned", "engine_ready": False, "file": f"game/assets/regions/{region['id']}/{part}.png"})
    for name in ("ember_mark", "burn", "debt_link", "detonate", "ash_return", "guard", "enemy_telegraph", "player_hit"):
        assets.append({"id": "vfx_" + name, "kind": "vfx", "frame_size": [128, 128], "alpha_required": True,
                       "status": "planned", "engine_ready": False, "file": "game/assets/vfx/" + name + ".png"})
    for name in ("health_lantern", "energy_incense", "coin", "route_badges", "menu_paper", "controller_glyphs", "touch_controls", "chinese_font", "app_icon"):
        assets.append({"id": "ui_" + name, "kind": "ui", "status": "planned", "engine_ready": False,
                       "file": "game/assets/ui/" + name + (".ttf" if name == "chinese_font" else ".png")})
    for name in ("hub", "paper_lane", "coin_vault", "ownerless_temple", "boss", "ending"):
        assets.append({"id": "music_" + name, "kind": "music", "loop": True, "sample_rate": 48000,
                       "status": "planned", "engine_ready": False, "file": "game/assets/audio/music/" + name + ".ogg"})
    for name in ("shot", "paper_hit", "copper_hit", "ignite", "link_tension", "detonate", "ash_pickup", "dash", "guard", "player_hurt", "enemy_death", "boss_warning", "reward", "contract", "repay", "menu"):
        assets.append({"id": "sfx_" + name, "kind": "sfx", "sample_rate": 48000,
                       "status": "planned", "engine_ready": False, "file": "game/assets/audio/sfx/" + name + ".wav"})
    write("catalog.json", catalog)
    write("rules.json", rules)
    write("asset-manifest.json", {"version": "0.1.0", "source_policy": "sub2-image-gen for generated raster art; native code for layouts and diagrams", "assets": assets})
    print(json.dumps({"content_counts": {k: len(v) for k, v in catalog.items() if isinstance(v, list)}, "asset_entries": len(assets)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
