"""Render the reviewable content catalog from the authoritative design JSON."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "incense-debt"


def cell(value):
    if value is None:
        return "—"
    if isinstance(value, list):
        value = ", ".join(str(v) for v in value)
    return str(value).replace("|", "／").replace("\n", " ")


def table(headers, rows):
    return ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"] + [
        "| " + " | ".join(cell(v) for v in row) + " |" for row in rows
    ] + [""]


def render(catalog):
    lines = ["# 内容数据库 v" + catalog["version"], "", "本文件由 `tools/design/render_catalog.py` 生成。修改 `data/catalog.json` 后重新生成；数值和行为属于设计规格，运行实现与验证状态另行登记。", ""]
    lines += table(["类别", "数量"], [(key, len(value)) for key, value in catalog.items() if isinstance(value, list)])
    sections = [
        ("还愿簿购买", "meta_unlocks", ["ID", "名称", "类别", "善缘", "前置", "获得"],
         lambda r: [r["id"], r["name"], r["kind"], r["cost"], r["requires"], r["grants"]]),
        ("角色", "characters", ["ID", "名称", "心火", "移速", "武器", "技能", "天赋", "解锁"],
         lambda r: [r["id"], r["name"], r["health"], r["speed"], r["weapon"], r["skills"], r["passive"], r["unlock"]]),
        ("武器", "weapons", ["ID", "名称", "模式", "单弹伤害", "间隔秒", "射程", "弹数", "行为"],
         lambda r: [r["id"], r["name"], r["mode"], r["damage"], r["interval_s"], r["range"], r["pellets"], r["behavior"]]),
        ("焚债与演化", "skills", ["ID", "名称", "角色", "类型", "来源", "消耗", "冷却", "强度", "无标记可施放", "行为"],
         lambda r: [r["id"], r["name"], r["character"], r["variant"], r["evolves_from"], r["energy_cost"], r["cooldown_s"], r["power"], "否" if r["requires_marked_target"] else "是", r["behavior"]]),
        ("遗物", "relics", ["ID", "名称", "路线", "稀有度", "叠加上限", "楼层", "事件", "具体行为"],
         lambda r: [r["id"], r["name"], r["routes"], r["rarity"], r["stack_limit"], f"{r['min_floor']}–{r['max_floor']}", r["trigger"], r["behavior"]]),
        ("行愿节点", "talents", ["ID", "名称", "路线", "阶", "所需该路点数", "具体行为"],
         lambda r: [r["id"], r["name"], r["route"], r["tier"], r["min_route_points"], r["behavior"]]),
        ("债约", "debt_contracts", ["ID", "名称", "奖励", "楼层", "本金", "风险点", "惩罚"],
         lambda r: [r["id"], r["name"], r["reward"], r["min_floor"], r["repay_price"], r["risk_points"], r["penalty"]]),
        ("普通敌人", "enemies", ["ID", "名称", "层", "心火", "移速", "预警ms", "伤害", "攻击", "应对"],
         lambda r: [r["id"], r["name"], r["floor"], r["health"], r["speed"], r["telegraph_ms"], r["damage"], r["pattern"], r["counterplay"]]),
        ("精英", "elite_variants", ["ID", "名称", "来源", "层", "血量倍数", "附加规则"],
         lambda r: [r["id"], r["name"], r["base_enemy"], r["floor"], r["health_multiplier"], r["special_rule"]]),
        ("Boss", "bosses", ["ID", "名称", "层", "心火", "可选", "阶段", "窗口", "固定治疗阶段"],
         lambda r: [r["id"], r["name"], r["floor"], r["health"], "是" if r["optional"] else "否", r["phases"], r["window"], r["fixed_heal_phase_indices"]]),
        ("组合册", "synergies", ["ID", "名称", "主路", "三件遗物", "结果", "限制"],
         lambda r: [r["id"], r["name"], r["route"], r["relics"], r["result"], r["tradeoff"]]),
        ("区域", "regions", ["ID", "名称", "楼层", "主Boss", "敌人"],
         lambda r: [r["id"], r["name"], r["floor"], r["boss"], r["enemy_ids"]]),
        ("NPC", "npcs", ["ID", "名称", "功能", "剪影"],
         lambda r: [r["id"], r["name"], r["function"], r["silhouette"]]),
        ("房间模板规格", "room_templates", ["ID", "布局族", "变体", "格数", "网格尺寸", "状态"],
         lambda r: [r["id"], r["family"], r["variant"], r["grid"], r["tile_size"], r["validation_status"]]),
        ("特殊房间", "special_rooms", ["ID", "名称", "图标", "色板", "音乐层", "可选结果", "行为"],
         lambda r: [r["id"], r["name"], r["icon"], r["palette"], r["music_layer"], r["choices"], r["behavior"]]),
    ]
    for title, key, headers, row in sections:
        lines += ["## " + title, ""] + table(headers, [row(r) for r in catalog[key]])
    lines += ["房间条目目前给出布局族与尺寸规格，实际墙格、通路与遭遇编排需要在引擎中制作并验证。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalog = json.loads((DOCS / "data" / "catalog.json").read_text(encoding="utf-8"))
    target = DOCS / "16-content-catalog.generated.md"
    result = render(catalog)
    if args.check:
        if not target.exists() or target.read_text(encoding="utf-8") != result:
            raise SystemExit("Generated catalog is missing or stale.")
        print("Generated catalog matches current design data.")
    else:
        target.write_text(result, encoding="utf-8")
        print("Wrote the complete reviewable content catalog.")


if __name__ == "__main__":
    main()
