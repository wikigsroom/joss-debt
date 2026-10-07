"""Verify that the Windows source, Android APK and iOS handoff share core content.

This is a static packaging check. It compares the source JSON bytes (and parsed
JSON values) with the copies shipped in the Android APK and the portable iOS
source ZIP. It also binds the check to the current artifact hashes and existing
platform verification reports. It does not claim a physical Android/iOS run or
prove the opaque Windows executable's embedded PCK byte-for-byte contents.
"""

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/incense-debt/reports/platforms/platform-parity.json"
REPORTS = ROOT / "docs/incense-debt/reports/platforms"

CORE_FILES = {
    "game/data/equipment.json": "assets/data/equipment.json",
    "game/data/projectile_profiles.json": "assets/data/projectile_profiles.json",
    "game/data/fx_presets.json": "assets/data/fx_presets.json",
    "game/assets/fx/equipment-polish/manifest.json": "assets/assets/fx/equipment-polish/manifest.json",
    "game/data/arena_boundaries.json": "assets/data/arena_boundaries.json",
    "game/assets/fx/combat-revision/manifest.json": "assets/assets/fx/combat-revision/manifest.json",
    "game/data/catalog.json": "assets/data/catalog.json",
    "game/data/expansion.json": "assets/data/expansion.json",
    "game/data/achievements.json": "assets/data/achievements.json",
    "game/data/rules.json": "assets/data/rules.json",
    "game/data/runtime_assets.json": "assets/data/runtime_assets.json",
    "game/data/music_scores.json": "assets/data/music_scores.json",
    "game/data/story.zh_CN.json": "assets/data/story.zh_CN.json",
    "game/assets/weapon-rig.json": "assets/assets/weapon-rig.json",
}


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def digest(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def load_json_bytes(data: bytes, label: str):
    try:
        return json.loads(data.decode("utf8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON: {exc}") from exc


def read_zip_member(bundle: zipfile.ZipFile, member: str, label: str) -> bytes:
    try:
        return bundle.read(member)
    except KeyError as exc:
        raise ValueError(f"{label} is missing {member}") from exc


def source_tree_hashes() -> dict[str, str]:
    result: dict[str, str] = {}
    for path in (ROOT / "game").rglob("*"):
        if not path.is_file() or ".godot" in path.parts or path.suffix == ".tmp":
            continue
        result[path.relative_to(ROOT).as_posix()] = digest(path)
    return result


def tree_fingerprint(entries: dict[str, str]) -> str:
    hasher = hashlib.sha256()
    for path in sorted(entries):
        hasher.update(path.encode("utf8"))
        hasher.update(b"\0")
        hasher.update(entries[path].encode("ascii"))
        hasher.update(b"\n")
    return hasher.hexdigest()


def artifact_entry(report: dict, label: str, failures: list[str]) -> dict:
    relative = report.get("path") or report.get("source_zip")
    path = ROOT / relative if relative else ROOT / "__missing__"
    actual = digest(path) if path.is_file() else ""
    expected = report.get("sha256") or report.get("source_sha256", "")
    if not path.is_file():
        failures.append(f"{label} artifact is missing: {relative}")
    elif actual != expected:
        failures.append(f"{label} artifact SHA-256 differs from its platform report")
    return {
        "path": relative or "",
        "bytes": path.stat().st_size if path.is_file() else 0,
        "sha256": actual,
        "expected_sha256": expected,
        "device_tested": bool(report.get("device_tested", report.get("physical_device_tested", False))),
    }


def main() -> None:
    failures: list[str] = []
    windows_report = json.loads((REPORTS / "windows-build.json").read_text("utf8")) if (REPORTS / "windows-build.json").is_file() else {}
    android_report = json.loads((REPORTS / "android-build.json").read_text("utf8")) if (REPORTS / "android-build.json").is_file() else {}
    android_check = json.loads((REPORTS / "android-verification.json").read_text("utf8")) if (REPORTS / "android-verification.json").is_file() else {}
    ios_report = json.loads((REPORTS / "ios-handoff.json").read_text("utf8")) if (REPORTS / "ios-handoff.json").is_file() else {}
    ios_check = json.loads((REPORTS / "ios-handoff-verification.json").read_text("utf8")) if (REPORTS / "ios-handoff-verification.json").is_file() else {}

    source_data: dict[str, bytes] = {}
    for source_path in CORE_FILES:
        path = ROOT / source_path
        if not path.is_file():
            failures.append(f"Windows source member is missing: {source_path}")
            continue
        source_data[source_path] = path.read_bytes()

    android_path = ROOT / android_report.get("path", "")
    ios_path = ROOT / ios_report.get("source_zip", "")
    android_members: dict[str, bytes] = {}
    ios_members: dict[str, bytes] = {}
    if android_path.is_file():
        try:
            with zipfile.ZipFile(android_path) as bundle:
                if bundle.testzip() is not None:
                    failures.append("Android APK CRC check failed")
                for source_path, apk_path in CORE_FILES.items():
                    try:
                        android_members[source_path] = bundle.read(apk_path)
                    except KeyError:
                        failures.append(f"Android APK is missing {apk_path}")
        except zipfile.BadZipFile:
            failures.append("Android artifact is not a readable APK/ZIP")
    else:
        failures.append("Android APK is missing")
    if ios_path.is_file():
        try:
            with zipfile.ZipFile(ios_path) as bundle:
                if bundle.testzip() is not None:
                    failures.append("iOS source ZIP CRC check failed")
                for source_path in CORE_FILES:
                    try:
                        ios_members[source_path] = bundle.read(source_path)
                    except KeyError:
                        failures.append(f"iOS source ZIP is missing {source_path}")
        except zipfile.BadZipFile:
            failures.append("iOS source artifact is not a readable ZIP")
    else:
        failures.append("iOS source ZIP is missing")

    source_tree = source_tree_hashes()
    ios_tree: dict[str, str] = {}
    if ios_path.is_file():
        try:
            with zipfile.ZipFile(ios_path) as bundle:
                for member in bundle.namelist():
                    if member.startswith("game/") and not member.endswith("/"):
                        ios_tree[member] = digest_bytes(bundle.read(member))
        except zipfile.BadZipFile:
            pass
    missing_ios_members = sorted(set(source_tree) - set(ios_tree))
    extra_ios_members = sorted(set(ios_tree) - set(source_tree))
    mismatched_ios_members = sorted(path for path in set(source_tree).intersection(ios_tree) if source_tree[path] != ios_tree[path])
    if missing_ios_members:
        failures.append("iOS source ZIP is missing game members: " + ", ".join(missing_ios_members[:8]))
    if extra_ios_members:
        failures.append("iOS source ZIP has unexpected game members: " + ", ".join(extra_ios_members[:8]))
    if mismatched_ios_members:
        failures.append("iOS source ZIP game members differ from Windows source: " + ", ".join(mismatched_ios_members[:8]))

    imported_resources = android_check.get("imported_resources_packaged", {})
    compiled_scripts = android_check.get("compiled_ui_and_weapon_scripts_packaged", {})
    android_packaging = {
        "verification_passed": bool(android_check.get("passed")),
        "runtime_registry_matches_source": bool(android_check.get("runtime_registry_matches_source")),
        "imported_resource_count": len(imported_resources),
        "all_imported_resources_packaged": bool(imported_resources) and all(imported_resources.values()),
        "weapon_rig_matches_source": bool(android_check.get("weapon_rig_matches_source")),
        "music_configuration_matches_source": bool(android_check.get("music_configuration_matches_source")),
        "all_music_stems_packaged": bool(android_check.get("music_stems_packaged")) and all(android_check.get("music_stems_packaged", {}).values()),
        "compiled_ui_and_weapon_scripts_packaged": bool(compiled_scripts) and all(compiled_scripts.values()),
    }
    if not all(android_packaging.values()):
        failures.append("Android package resource registry/imported asset parity is incomplete")

    files = {}
    for source_path in CORE_FILES:
        source = source_data.get(source_path, b"")
        android = android_members.get(source_path, b"")
        ios = ios_members.get(source_path, b"")
        source_json = load_json_bytes(source, source_path) if source else None
        android_json = load_json_bytes(android, f"Android {source_path}") if android else None
        ios_json = load_json_bytes(ios, f"iOS {source_path}") if ios else None
        raw_match = bool(source and source == android == ios)
        parsed_match = bool(source_json is not None and source_json == android_json == ios_json)
        if not raw_match:
            failures.append(f"core content bytes differ across platforms: {source_path}")
        if not parsed_match:
            failures.append(f"core content JSON values differ across platforms: {source_path}")
        files[source_path] = {
            "source_sha256": digest_bytes(source) if source else "",
            "android_apk_member": CORE_FILES[source_path],
            "android_sha256": digest_bytes(android) if android else "",
            "ios_zip_member": source_path,
            "ios_sha256": digest_bytes(ios) if ios else "",
            "raw_bytes_match": raw_match,
            "parsed_json_match": parsed_match,
            "bytes": len(source),
        }

    catalog = load_json_bytes(source_data.get("game/data/catalog.json", b"{}"), "source catalog")
    rules = load_json_bytes(source_data.get("game/data/rules.json", b"{}"), "source rules")
    counts = {key: len(catalog.get(key, [])) for key in ["characters", "weapons", "skills", "relics", "talents", "synergies", "routes", "regions", "room_templates", "special_rooms", "enemies", "bosses"]}
    if counts["characters"] != 6 or counts["skills"] != 18 or counts["relics"] != 54 or counts["special_rooms"] != 4:
        failures.append("source catalog does not contain the Direction 01 content baseline")
    equipment = load_json_bytes(source_data.get("game/data/equipment.json", b"{}"), "equipment catalog")
    counts["base_relics"] = counts["relics"]
    counts["relics"] += len(equipment.get("relics", []))
    counts["active_items"] = len(equipment.get("active_items", []))
    counts["trinkets"] = len(equipment.get("trinkets", []))
    if counts["relics"] != 66 or counts["active_items"] != 12 or counts["trinkets"] != 12:
        failures.append("equipment extension does not match the current gameplay catalog")
    if rules.get("platforms", {}).get("orientation") != "landscape" or rules.get("save", {}).get("schema_version") != 2:
        failures.append("source rules do not expose the pinned landscape/schema2 baseline")
    if not android_check.get("passed") or android_check.get("apk_sha256") != android_report.get("sha256"):
        failures.append("Android static verification does not match the current APK report")
    if not ios_check.get("passed") or ios_check.get("source_sha256") != ios_report.get("source_sha256"):
        failures.append("iOS handoff verification does not match the current source ZIP report")

    REPORTS.mkdir(parents=True, exist_ok=True)
    report = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "passed": not failures,
        "scope": "Static shared-content parity only; no physical Android/iOS run and no opaque Windows executable PCK byte comparison",
        "virtualization": "none",
        "platforms": {
            "windows_source": {"path": "game", "device_tested": bool(windows_report.get("device_tested")), "native_runtime_tested": bool(windows_report.get("native_runtime_tested")), "artifact": artifact_entry(windows_report, "Windows", failures)},
            "android_apk": artifact_entry(android_report, "Android", failures),
            "ios_shared_source": artifact_entry(ios_report, "iOS", failures),
        },
        "platform_reports": {
            "android_verification": {"passed": bool(android_check.get("passed")), "report": "docs/incense-debt/reports/platforms/android-verification.json"},
            "ios_handoff_verification": {"passed": bool(ios_check.get("passed")), "report": "docs/incense-debt/reports/platforms/ios-handoff-verification.json"},
        },
        "source_tree": {
            "windows_game_member_count": len(source_tree),
            "windows_game_tree_sha256": tree_fingerprint(source_tree),
            "ios_game_member_count": len(ios_tree),
            "ios_game_tree_sha256": tree_fingerprint(ios_tree),
            "all_members_match": not missing_ios_members and not extra_ios_members and not mismatched_ios_members,
            "missing_ios_members": missing_ios_members,
            "extra_ios_members": extra_ios_members,
            "mismatched_ios_members": mismatched_ios_members,
        },
        "android_packaging": android_packaging,
        "core_files": files,
        "catalog_counts": counts,
        "rules_baseline": {"version": rules.get("version"), "orientation": rules.get("platforms", {}).get("orientation"), "save_schema_version": rules.get("save", {}).get("schema_version"), "engine_baseline": rules.get("platforms", {}).get("engine_baseline")},
        "failures": failures,
    }
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "core_files": len(files), "failures": failures}, ensure_ascii=False))
    if failures:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
