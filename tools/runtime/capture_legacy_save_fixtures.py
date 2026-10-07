"""Freeze actual pre-migration QA journals, never the player's profile or real run."""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path(__file__).resolve().parents[2]


def main():
    destination = ROOT / "game/tests/fixtures"
    destination.mkdir(parents=True, exist_ok=True)
    qa_root = Path(os.environ["APPDATA"]) / "IncenseDebt"
    records = []
    for kind, folder in [("profile", "qa_profile"), ("run", "qa_saves")]:
        candidates = []
        for slot in range(2):
            path = qa_root / folder / f"checkpoint_{slot}.json"
            if not path.is_file(): continue
            raw = path.read_bytes()
            envelope = json.loads(raw)
            payload = envelope["payload"]
            if envelope["schema"] != 1 or hashlib.sha256(payload.encode()).hexdigest() != envelope["sha256"]: continue
            if json.loads(payload)["version"] != 1: continue
            candidates.append((envelope["revision"], raw))
        if not candidates: raise ValueError("No genuine legacy v1 QA journal: " + folder)
        _, raw = max(candidates, key=lambda row: row[0])
        target = destination / f"legacy_{kind}_v1.json"
        if target.exists() and target.read_bytes() != raw: raise ValueError("Frozen v1 fixture must not be overwritten")
        target.write_bytes(raw)
        records.append({"path": target.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(raw).hexdigest(),
                        "source": folder + " pre-migration native viewport fixture; not player data", "envelope_schema": 1, "payload_version": 1})
    report = {"fixtures": records, "scope": "actual old QA journals preserved before v2 migration"}
    (ROOT / "docs/incense-debt/reports/runtime/legacy-save-fixtures.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
