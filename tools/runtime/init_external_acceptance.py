"""Create honest, hash-pinned starting records for physical acceptance.

The generated records intentionally remain pending. This tool only removes
copy/paste drift in the current artifact hash and required field names; it
never sets a device result to passed and never creates fake evidence files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pending_record(platform: str) -> tuple[Path, dict]:
    now = datetime.now(timezone.utc).isoformat()
    if platform == "android":
        artifact = ROOT / "build/android/IncenseDebt.apk"
        record = {
            "platform": "android",
            "result": "pending",
            "physical_device_tested": False,
            "device_model": "",
            "os_version": "",
            "artifact_sha256": sha256(artifact) if artifact.is_file() else "",
            "install_ok": False,
            "launch_ok": False,
            "touch_ok": False,
            "background_resume_ok": False,
            "file_picker_ok": False,
            "clipboard_ok": False,
            "audio_ok": False,
            "thermal_minutes": 0,
            "evidence_files": [],
            "created_at": now,
            "artifact": "build/android/IncenseDebt.apk",
            "notes": "Bootstrap only. Replace fields with observations from a physical Android device.",
        }
        return REPORTS / "platforms/android-device/acceptance.json", record

    artifact = ROOT / "build/ios-handoff/IncenseDebt-shared-source.zip"
    record = {
        "platform": "ios",
        "result": "pending",
        "physical_device_tested": False,
        "device_model": "",
        "os_version": "",
        "source_sha256": sha256(artifact) if artifact.is_file() else "",
        "xcode_project_created": False,
        "signed_ipa_created": False,
        "iphone_run_ok": False,
        "ipad_run_ok": False,
        "touch_ok": False,
        "orientation_ok": False,
        "background_resume_ok": False,
        "file_picker_ok": False,
        "clipboard_ok": False,
        "audio_ok": False,
        "thermal_minutes": 0,
        "ipa_sha256": "",
        "evidence_files": [],
        "created_at": now,
        "artifact": "build/ios-handoff/IncenseDebt-shared-source.zip",
        "notes": "Bootstrap only. Replace fields with observations from macOS/Xcode and physical iPhone/iPad runs.",
    }
    return REPORTS / "platforms/ios-device/acceptance.json", record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["android", "ios", "all"], default="all")
    parser.add_argument("--force", action="store_true", help="replace an existing record after an intentional new acceptance cycle")
    args = parser.parse_args()
    platforms = ["android", "ios"] if args.platform == "all" else [args.platform]
    written = []
    existing = []
    for platform in platforms:
        path, record = pending_record(platform)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_file() and not args.force:
            existing.append(path.relative_to(ROOT).as_posix())
            continue
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
        written.append(path.relative_to(ROOT).as_posix())
    print(json.dumps({"written": written, "existing": existing, "result": "pending_only", "force": args.force}, ensure_ascii=False))


if __name__ == "__main__":
    main()
