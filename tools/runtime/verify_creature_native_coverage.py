"""Bind every current creature pose to a successful native Godot capture.

Read each immutable run once. An older screenshot or a capture made against
different atlas metadata is not evidence for the currently installed art.
"""
from pathlib import Path
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "game/assets/creature-actions.json"
FRAMES = ROOT / ".local-tools/native-creature-frames"
DEFAULT_REPORT = ROOT / "docs/incense-debt/reports/creature-actions-2026-10-10/native-coverage.json"
DIRECTIONS = ("down", "left", "right", "up")


def frame_names(identity, actor):
    return {
        f"{identity}-{state}-{direction}-{frame}.png"
        for state in actor["states"]
        for direction in DIRECTIONS
        for frame in range(6)
    }


def verify(allow_incomplete=False, report_path=DEFAULT_REPORT):
    manifest_bytes = MANIFEST.read_bytes()
    manifest = json.loads(manifest_bytes)
    actors = manifest["actors"]
    if not allow_incomplete and (
        not manifest.get("complete")
        or manifest.get("compiled_actors") != 402
        or manifest.get("compiled_action_poses") != 24048
    ):
        raise RuntimeError("Full creature coverage requires all 402 identities and 24,048 poses")

    candidates = {}
    failures = []
    runs = sorted((FRAMES / "runs").glob("*/asset-bindings.json"))
    for binding_path in runs:
        data = json.loads(binding_path.read_text("utf8"))
        matched = {
            identity: entry["screenshots_sha256"]
            for identity, entry in data.get("actors", {}).items()
            if identity in actors and entry.get("asset_binding") == actors[identity]
        }
        del data
        if not matched:
            continue
        run = binding_path.parent
        logs = [(run / name).read_text("utf8", errors="replace") for name in ("native.log", "import.log")]
        if any("ERROR:" in log or "SCRIPT ERROR" in log for log in logs):
            failures.append({"run": run.name, "reason": "Native capture or import logged an error"})
            continue
        capture = json.loads((run / "capture.json").read_text("utf8"))
        entries = capture.get("frames", [])
        if capture.get("count") != len(entries) or capture.get("virtualization") != "none":
            failures.append({"run": run.name, "reason": "Invalid capture count or native environment"})
            continue
        captured = {}
        for entry in entries:
            expected_name = "{actor}-{state}-{direction}-{frame}.png".format(**entry)
            if entry.get("file") != expected_name:
                continue
            captured.setdefault(entry["actor"], set()).add(expected_name)
        for identity, screenshots in matched.items():
            expected = frame_names(identity, actors[identity])
            if (
                identity in capture.get("actors", [])
                and captured.get(identity) == expected
                and set(screenshots) == expected
            ):
                candidates[identity] = {"run": run.name, "screenshots": screenshots}

    accepted = {}
    for identity, candidate in candidates.items():
        invalid = []
        for name, expected_hash in candidate["screenshots"].items():
            path = FRAMES / name
            if not path.is_file():
                invalid.append({"file": name, "reason": "Missing native frame"})
                continue
            with path.open("rb") as stream:
                actual_hash = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual_hash != expected_hash:
                invalid.append({"file": name, "reason": "Current screenshot differs from the bound capture"})
        if invalid:
            failures.append({"identity": identity, "run": candidate["run"], "frames": invalid})
        else:
            accepted[identity] = {
                "kind": actors[identity]["kind"],
                "run": candidate["run"],
                "frames": len(candidate["screenshots"]),
                "screenshots_sha256": candidate["screenshots"],
            }
    if MANIFEST.read_bytes() != manifest_bytes:
        raise RuntimeError("Creature manifest changed while checking native evidence")
    missing = sorted(set(actors) - set(accepted))
    count = sum(entry["frames"] for entry in accepted.values())
    complete = manifest.get("complete", False) and len(accepted) == 402 and count == 24048 and not failures
    report = {
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "complete": complete,
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "expected_identities": 402,
        "expected_frames": 24048,
        "installed_identities": len(actors),
        "matched_native_identities": len(accepted),
        "matched_native_frames": count,
        "kinds": dict(Counter(entry["kind"] for entry in accepted.values())),
        "missing_native_identities": missing,
        "failures": failures,
        "immutable_runs_examined": len(runs),
        "source": "Native Godot OpenGL game renderer; exact actor metadata and all captured frame SHA-256 values",
        "virtualization": "none",
        "android_device_tested": False,
        "actors": accepted,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Native creature evidence: {len(accepted)}/{len(actors)} installed identities, {count:,} frames; full shipping coverage: {complete}")
    print("Report: " + str(report_path))
    if missing or failures or (not allow_incomplete and not complete):
        raise RuntimeError(f"Native coverage failed: {len(missing)} missing identities, {len(failures)} evidence failures")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow-incomplete", action="store_true")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    verify(args.allow_incomplete, args.report)


if __name__ == "__main__":
    main()
