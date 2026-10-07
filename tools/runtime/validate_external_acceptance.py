"""Validate human and physical-device acceptance evidence without fabricating it.

The software checks already live in the normal runtime reports. This script is
the narrow bridge for evidence that can only come from a real player or a real
Android/macOS/iOS device. It accepts completed records only when their artifact
hashes and required manual observations match the current deliverables.
Missing records stay pending and never upgrade the product by themselves.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
BALANCE = REPORTS / "human-balance-template.csv"
OUT_JSON = REPORTS / "external-acceptance.json"
OUT_MD = REPORTS / "external-acceptance.md"

EXPECTED_MATRIX = {
    ("c_paper", "fire"), ("c_paper", "thread"),
    ("c_bell", "ash"), ("c_bell", "wind"),
    ("c_lantern", "fire"), ("c_lantern", "ink"),
    ("c_mask", "seal"), ("c_mask", "ash"),
    ("c_umbrella", "wind"), ("c_umbrella", "thread"),
    ("c_ink", "ink"), ("c_ink", "seal"),
}
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path, default=None):
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text("utf8"))
    except (OSError, json.JSONDecodeError):
        return default


def balance_status() -> dict:
    failures: list[str] = []
    rows: list[dict] = []
    if BALANCE.is_file():
        with BALANCE.open("r", encoding="utf-8-sig", newline="") as source:
            rows = list(csv.DictReader(source))
    else:
        failures.append("human balance worksheet is missing")

    seen = {(row.get("character_id", ""), row.get("route_id", "")) for row in rows}
    if len(rows) != 12:
        failures.append(f"expected exactly 12 character-route rows, found {len(rows)}")
    if seen != EXPECTED_MATRIX:
        failures.append("worksheet matrix does not match the six-character/two-route contract")

    required_completed = [
        "build_version", "player_id", "session_id", "platform", "input_device",
        "weapon_id", "evolution_id", "chapter_1_seconds", "chapter_2_seconds",
        "chapter_3_seconds", "damage_taken", "result", "difficulty_1_5",
        "build_readability_1_5", "combat_feedback_1_5", "control_comfort_1_5",
    ]
    current_status = read_json(REPORTS / "current-product-status.json", {}) or {}
    current_version = str(current_status.get("version", "")).strip()
    completed = []
    for index, row in enumerate(rows, start=2):
        result = str(row.get("result", "")).strip().lower()
        if not result:
            continue
        completed.append(row)
        if result not in {"victory", "defeat"}:
            failures.append(f"row {index}: result must be victory or defeat")
        for field in required_completed:
            if not str(row.get(field, "")).strip():
                failures.append(f"row {index}: missing {field}")
        if current_version and str(row.get("build_version", "")).strip() != current_version:
            failures.append(f"row {index}: build_version does not match current product version {current_version}")
        for field in [
            "chapter_1_seconds", "chapter_2_seconds", "chapter_3_seconds",
        ]:
            value = str(row.get(field, "")).strip()
            try:
                if float(value) <= 0:
                    failures.append(f"row {index}: {field} must be positive")
            except ValueError:
                failures.append(f"row {index}: {field} must be numeric")
        damage = str(row.get("damage_taken", "")).strip()
        try:
            if float(damage) < 0:
                failures.append(f"row {index}: damage_taken must be non-negative")
        except ValueError:
            failures.append(f"row {index}: damage_taken must be numeric")
        for field in [
            "difficulty_1_5", "build_readability_1_5", "combat_feedback_1_5",
            "control_comfort_1_5",
        ]:
            value = str(row.get(field, "")).strip()
            try:
                if not 1 <= int(value) <= 5:
                    failures.append(f"row {index}: {field} must be 1-5")
            except ValueError:
                failures.append(f"row {index}: {field} must be 1-5")
        if result == "defeat" and not str(row.get("failure_reason", "")).strip():
            failures.append(f"row {index}: defeat requires failure_reason")
        if result == "victory" and not str(row.get("notes", "")).strip():
            failures.append(f"row {index}: victory requires notes describing the build and feel")

    players = {str(row.get("player_id", "")).strip() for row in completed if str(row.get("player_id", "")).strip()}
    sessions = {str(row.get("session_id", "")).strip() for row in completed if str(row.get("session_id", "")).strip()}
    if completed and len(players) < 3 and len(sessions) < 3:
        failures.append("human balance needs at least three independent players or session IDs")
    ready = len(rows) == 12 and len(completed) == 12 and not failures
    return {
        "status": "passed" if ready else "pending_human",
        "passed": ready,
        "rows": len(rows),
        "completed_rows": len(completed),
        "distinct_players": len(players),
        "distinct_sessions": len(sessions),
        "failures": failures,
        "evidence": "docs/incense-debt/reports/human-balance-template.csv",
    }


def device_status(platform: str) -> dict:
    directory = REPORTS / "platforms" / f"{platform}-device"
    record_path = directory / "acceptance.json"
    record = read_json(record_path, {}) or {}
    failures: list[str] = []
    if not record:
        failures.append(f"missing {record_path.relative_to(ROOT).as_posix()}")
    if record.get("platform") != platform:
        failures.append("platform field does not match the device acceptance directory")
    if record.get("result") != "passed":
        failures.append("result must be passed after a real-device run")
    if not record.get("physical_device_tested"):
        failures.append("physical_device_tested must be true")

    if platform == "android":
        artifact = ROOT / "build/android/IncenseDebt.apk"
        required = [
            "device_model", "os_version", "artifact_sha256", "install_ok", "launch_ok",
            "touch_ok", "background_resume_ok", "file_picker_ok", "clipboard_ok",
            "audio_ok", "thermal_minutes", "evidence_files",
        ]
        minimum_minutes = 45
        if not artifact.is_file():
            failures.append("current Android APK is missing")
        elif record.get("artifact_sha256") and record["artifact_sha256"] != digest(artifact):
            failures.append("Android artifact_sha256 does not match the current APK")
    else:
        artifact = ROOT / "build/ios-handoff/IncenseDebt-shared-source.zip"
        required = [
            "device_model", "os_version", "source_sha256", "xcode_project_created",
            "signed_ipa_created", "iphone_run_ok", "ipad_run_ok", "touch_ok",
            "orientation_ok", "background_resume_ok", "file_picker_ok", "clipboard_ok",
            "audio_ok", "thermal_minutes", "ipa_sha256", "evidence_files",
        ]
        minimum_minutes = 45
        if not artifact.is_file():
            failures.append("current iOS handoff ZIP is missing")
        elif record.get("source_sha256") and record["source_sha256"] != digest(artifact):
            failures.append("iOS source_sha256 does not match the current handoff ZIP")

    for field in required:
        value = record.get(field)
        if value is None or value == "" or value is False or value == []:
            failures.append(f"missing {field}")
    boolean_fields = [
        field for field in required
        if field.endswith("_ok") or field in {"physical_device_tested", "xcode_project_created", "signed_ipa_created"}
    ]
    for field in boolean_fields:
        if record.get(field) is not True:
            failures.append(f"{field} must be the JSON boolean true")
    try:
        if float(record.get("thermal_minutes", 0)) < minimum_minutes:
            failures.append(f"thermal_minutes must be at least {minimum_minutes}")
    except (TypeError, ValueError):
        failures.append("thermal_minutes must be numeric")
    for evidence in record.get("evidence_files", []) if isinstance(record.get("evidence_files", []), list) else []:
        if not (ROOT / str(evidence)).is_file():
            failures.append(f"missing evidence file: {evidence}")
    if platform == "ios" and not SHA256_RE.fullmatch(str(record.get("ipa_sha256", ""))):
        failures.append("ipa_sha256 must be a 64-character SHA-256 hex string")
    passed = bool(record) and not failures
    return {
        "status": "passed" if passed else "pending_device",
        "passed": passed,
        "record": record_path.relative_to(ROOT).as_posix(),
        "failures": failures,
    }


def main() -> None:
    human = balance_status()
    android = device_status("android")
    ios = device_status("ios")
    result = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "human_balance": human,
        "android_device": android,
        "ios_device": ios,
        "release_ready": bool(human["passed"] and android["passed"] and ios["passed"]),
        "scope": "external human/device evidence only; software checks remain in release-readiness.json",
        "virtualization": "none",
    }
    OUT_JSON.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 外部验收证据审计", "", f"记录时间：{result['recorded_at']}。",
        "", "| 门 | 状态 | 完成行/失败数 |", "| --- | --- | --- |",
        f"| 真人六角色双路线 | `{human['status']}` | {human['completed_rows']}/{human['rows']}，{len(human['failures'])} 个问题 |",
        f"| Android 真机 | `{android['status']}` | {len(android['failures'])} 个问题 |",
        f"| iOS 真机 | `{ios['status']}` | {len(ios['failures'])} 个问题 |",
        "", f"总体正式发布证据：`{'passed' if result['release_ready'] else 'pending_external_acceptance'}`。",
        "", "该报告只接受真实玩家/设备记录；空表、桌面模拟触控、自动 Bot 和模拟器不会被升级为通过。",
        "", "重新生成：", "", "```powershell", "python -X utf8 tools/runtime/validate_external_acceptance.py", "```", "",
    ]
    OUT_MD.write_text("\n".join(lines), "utf8")
    print(json.dumps({
        "human_balance": human["status"], "android_device": android["status"],
        "ios_device": ios["status"], "release_ready": result["release_ready"],
        "json": OUT_JSON.relative_to(ROOT).as_posix(),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
