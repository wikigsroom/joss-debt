"""Validate the human balance worksheet without filling in human results."""
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "docs/incense-debt/reports/human-balance-template.csv"
OUT = ROOT / "docs/incense-debt/reports/human-balance-template.json"

EXPECTED = {
    ("c_paper", "fire"), ("c_paper", "thread"),
    ("c_bell", "ash"), ("c_bell", "wind"),
    ("c_lantern", "fire"), ("c_lantern", "ink"),
    ("c_mask", "seal"), ("c_mask", "ash"),
    ("c_umbrella", "wind"), ("c_umbrella", "thread"),
    ("c_ink", "ink"), ("c_ink", "seal"),
}

REQUIRED_COLUMNS = {
    "character_id", "character_name", "route_id", "route_name", "build_version",
    "player_id", "session_id", "platform", "input_device", "weapon_id",
    "evolution_id", "chapter_1_seconds", "chapter_2_seconds", "chapter_3_seconds",
    "damage_taken", "death_room", "result", "difficulty_1_5",
    "build_readability_1_5", "combat_feedback_1_5", "control_comfort_1_5",
    "failure_reason", "notes",
}


def main():
    failures = []
    rows = []
    if not TEMPLATE.is_file():
        failures.append("missing human balance worksheet")
    else:
        with TEMPLATE.open("r", encoding="utf-8-sig", newline="") as source:
            reader = csv.DictReader(source)
            if not reader.fieldnames or not REQUIRED_COLUMNS.issubset(set(reader.fieldnames)):
                missing = sorted(REQUIRED_COLUMNS - set(reader.fieldnames or []))
                failures.append("worksheet is missing required columns: " + ", ".join(missing))
            rows = list(reader)
        seen = {(row.get("character_id", ""), row.get("route_id", "")) for row in rows}
        if len(rows) != 12:
            failures.append(f"expected 12 rows, found {len(rows)}")
        if seen != EXPECTED:
            failures.append("worksheet does not contain exactly the six-character/two-route matrix")
        for row in rows:
            if not row.get("character_name") or not row.get("route_name"):
                failures.append("every matrix row needs a readable character and route label")
            for field in ["build_readability_1_5", "combat_feedback_1_5", "control_comfort_1_5"]:
                value = row.get(field, "")
                if value and (not value.isdigit() or not 1 <= int(value) <= 5):
                    failures.append(f"{field} must remain blank or use a 1-5 score")
    result = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "passed": not failures,
        "rows": len(rows),
        "completed_rows": sum(bool(row.get("result")) for row in rows),
        "failures": failures,
        "scope": "structure-only worksheet validation; blank rows are intentional and do not claim human balance acceptance",
    }
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if not failures else 1)


if __name__ == "__main__":
    main()
