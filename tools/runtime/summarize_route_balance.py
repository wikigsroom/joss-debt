"""Summarize the fixed-tick route matrix for balance work.

The output is a comparison baseline, never a human-balance verdict. It keeps
the raw route-matrix report authoritative and only aggregates its measurements.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports/runtime"
SOURCE = REPORTS / "route-matrix-tests.json"
CATALOG = ROOT / "game/data/catalog.json"
OUT_JSON = REPORTS / "route-balance-baseline.json"
OUT_MD = REPORTS / "route-balance-baseline.md"


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    low = int(index)
    high = min(low + 1, len(ordered) - 1)
    weight = index - low
    return round(ordered[low] * (1.0 - weight) + ordered[high] * weight, 2)


def metric_summary(rows: list[dict], getter) -> dict:
    values = [float(getter(row)) for row in rows]
    return {
        "mean": round(sum(values) / len(values), 2) if values else 0.0,
        "min": round(min(values), 2) if values else 0.0,
        "max": round(max(values), 2) if values else 0.0,
        "p10": percentile(values, 0.10),
        "p90": percentile(values, 0.90),
    }


def summarize(rows: list[dict]) -> dict:
    catalog = json.loads(CATALOG.read_text("utf8"))
    route_names = {str(row.get("id", "")): str(row.get("name", row.get("id", ""))) for row in catalog.get("routes", [])}
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    characters: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[(str(row.get("character_name", row.get("character", ""))), str(row.get("focus_route", "")))].append(row)
        characters[str(row.get("character_name", row.get("character", "")))].append(row)

    def build_group(key: str, group_rows: list[dict]) -> dict:
        victories = sum(str(row.get("result", "")) == "victory" for row in group_rows)
        return {
            "key": key,
            "samples": len(group_rows),
            "victories": victories,
            "victory_rate": round(victories / len(group_rows), 3) if group_rows else 0.0,
            "combat_seconds": metric_summary(group_rows, lambda row: row.get("combat_seconds", 0.0)),
            "damage_taken": metric_summary(group_rows, lambda row: row.get("stats", {}).get("damage_taken", 0)),
            "kills": metric_summary(group_rows, lambda row: row.get("stats", {}).get("kills", 0)),
            "health_remaining": metric_summary(group_rows, lambda row: row.get("health", 0)),
        }

    route_rows = []
    for (character, route), group_rows in sorted(groups.items()):
        entry = build_group(f"{character}/{route}", group_rows)
        entry.update({"character": character, "route": route, "route_name": route_names.get(route, route)})
        route_rows.append(entry)
    character_rows = []
    for character, group_rows in sorted(characters.items()):
        entry = build_group(character, group_rows)
        entry["character"] = character
        character_rows.append(entry)

    times = [row["combat_seconds"]["mean"] for row in route_rows]
    return {
        "passed": True,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "source": "docs/incense-debt/reports/runtime/route-matrix-tests.json",
        "source_samples": len(rows),
        "source_victories": sum(str(row.get("result", "")) == "victory" for row in rows),
        "method": "aggregate fixed-tick route matrix by character/route; two skill evolutions per route",
        "route_rows": route_rows,
        "character_rows": character_rows,
        "overall": {
            "route_time_mean_min": round(min(times), 2) if times else 0.0,
            "route_time_mean_max": round(max(times), 2) if times else 0.0,
            "route_time_ratio": round(max(times) / min(times), 3) if times and min(times) > 0 else 0.0,
        },
        "limitations": [
            "Bot route preferences are coverage fixtures, not player behavior",
            "The matrix excludes optional side bosses and human decision time",
            "No balance status is promoted by this aggregation",
        ],
    }


def main() -> None:
    source = json.loads(SOURCE.read_text("utf8"))
    payload = summarize(source.get("runs", []))
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 角色路线自动平衡基线",
        "",
        f"记录时间：{payload['recorded_at']}。来源样本 {payload['source_samples']} 局，胜利 {payload['source_victories']} 局。",
        "",
        "这张表只聚合固定 Tick 路线矩阵，帮助后续真人测试定位时间、受击和资源差异；它不代表玩家胜率、难度或最终平衡。",
        "",
        "## 角色 × 路线",
        "",
        "| 角色 | 路线 | 样本 | 胜率 | 平均战斗秒 | P10–P90 | 平均受击 | 平均击杀 | 平均剩余心火 |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in payload["route_rows"]:
        lines.append("| {character} | {route_name} (`{route}`) | {samples} | {victory_rate:.0%} | {time:.1f} | {p10:.1f}–{p90:.1f} | {damage:.1f} | {kills:.1f} | {health:.1f} |".format(
            character=row["character"], route_name=row["route_name"], route=row["route"], samples=row["samples"], victory_rate=row["victory_rate"],
            time=row["combat_seconds"]["mean"], p10=row["combat_seconds"]["p10"], p90=row["combat_seconds"]["p90"],
            damage=row["damage_taken"]["mean"], kills=row["kills"]["mean"], health=row["health_remaining"]["mean"],
        ))
    lines += [
        "",
        "## 使用方式",
        "",
        "真人测试时沿用同一组角色/路线，记录完整整局与失败原因，再与本表的战斗时长、受击和剩余心火对照。出现差异时先查构筑理解、操作路径和掉落选择，再决定是否改数值。",
        "",
        "机器来源：`route-matrix-tests.json`；自动样本不替代外部验收。",
    ]
    OUT_MD.write_text("\n".join(lines) + "\n", "utf8")
    print(json.dumps({"passed": True, "samples": payload["source_samples"], "routes": len(payload["route_rows"]), "json": str(OUT_JSON), "markdown": str(OUT_MD)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
