"""Inspect the generated APK and available physical devices; no emulator is used."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import zipfile
import argparse

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description="Inspect an Android APK without using an emulator.")
    parser.add_argument(
        "--apk",
        default="build/android/IncenseDebt.apk",
        help="APK path relative to the workspace (default: the canonical debug package).",
    )
    parser.add_argument(
        "--report",
        default="docs/incense-debt/reports/platforms/android-verification.json",
        help="Verification JSON path relative to the workspace.",
    )
    args = parser.parse_args()
    sdk = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk"
    apk = Path(args.apk)
    if not apk.is_absolute():
        apk = ROOT / apk
    apk = apk.resolve()
    try:
        relative_apk = apk.relative_to(ROOT).as_posix()
    except ValueError as error:
        raise SystemExit("--apk must be inside the workspace so package paths can be audited") from error
    report_path = Path(args.report)
    if not report_path.is_absolute():
        report_path = ROOT / report_path
    report_path = report_path.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["JAVA_HOME"] = "C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
    def run(args):
        return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, encoding="utf8", errors="replace", env=env, timeout=30)
    # AAPT's legacy Windows path reader cannot open an absolute path containing Chinese.
    # Keep its input relative to the verified workspace, without copying the artifact.
    badging = run([str(sdk / "build-tools/35.0.0/aapt.exe"), "dump", "badging", relative_apk])
    permissions = run([str(sdk / "build-tools/35.0.0/aapt.exe"), "dump", "permissions", relative_apk])
    signing = run([str(sdk / "build-tools/35.0.0/apksigner.bat"), "verify", "--verbose", str(apk)])
    devices = run([str(sdk / "platform-tools/adb.exe"), "devices", "-l"])
    with zipfile.ZipFile(apk) as bundle:
        names = bundle.namelist()
        required = {name: any(p.endswith(name) for p in names) for name in ["story.zh_CN.json", "arena_boundaries.json", "fx/combat-revision/manifest.json", "expansion.json", "achievements.json", "runtime_assets.json", "music_scores.json", "rules.json", "OFL.txt", "ResourceHanRounded-OFL.txt", "SmileySans-OFL.txt", "Lucide-LICENSE.txt", "Godot-THIRDPARTY.txt", "weapon-rig.json"]}
        registry = json.loads(bundle.read("assets/data/runtime_assets.json"))
        registry_matches = registry == json.loads((ROOT / "game/data/runtime_assets.json").read_text("utf8"))
        imported_resources = {}
        for row in registry["assets"]:
            mapping = "assets/" + row["file"].removeprefix("res://") + ".import"
            text = bundle.read(mapping).decode("utf8") if mapping in names else ""
            target = re.search(r'path="(res://[^"]+)"', text)
            imported_resources[row["file"]] = target is not None and "assets/" + target[1].removeprefix("res://") in names
        rig_matches = json.loads(bundle.read("assets/assets/weapon-rig.json")) == json.loads((ROOT / "game/assets/weapon-rig.json").read_text("utf8"))
        ui_scripts = {name: all(any(p.endswith(name + suffix) for p in names) for suffix in [".gdc", ".gd.remap"])
                      for name in ["game_theme", "modern_ui", "rounded_button", "character_sheet", "run_review", "weapon_trial_ui", "damage_record", "impact_control", "weapon_trial", "game_hud", "route_map", "weapon_motion", "expanded_campaign", "derived_seed", "expanded_patterns", "expanded_weapons", "interactive_scenery", "expanded_visuals", "combat_fx", "room_geometry", "campaign_cinematic"]}
        license_bytes_match = all("assets/" + path in names and bundle.read("assets/" + path) == (ROOT / "game" / path).read_bytes() for path in ["assets/fonts/ResourceHanRounded-OFL.txt", "assets/fonts/SmileySans-OFL.txt", "assets/ui/icons/Lucide-LICENSE.txt"])
        rules_path = next((p for p in names if p.endswith("data/rules.json")), None)
        packed_rules = json.loads(bundle.read(rules_path)) if rules_path else {}
        expected_rules = json.loads((ROOT / "game/data/rules.json").read_text("utf8"))
        rules_match = packed_rules == expected_rules
        save_rules_match = packed_rules.get("save") == expected_rules["save"] and packed_rules.get("save", {}).get("schema_version") == 2
        save_scripts = {name: all(any(p.endswith(name + suffix) for p in names) for suffix in [".gdc", ".gd.remap"])
                        for name in ["save_store", "save_migrations", "save_session", "save_slots", "save_transfer", "save_transfer_ui"]}
        score_path = next((p for p in names if p.endswith("music_scores.json")), None)
        scores = json.loads(bundle.read(score_path)) if score_path else {}
        expected_scores = json.loads((ROOT / "game/data/music_scores.json").read_text("utf8"))
        music_config_matches = scores == expected_scores
        stems = [stem for score in scores.get("scores", {}).values() for stem in score.get("stems", [])]
        expected_stem_count = sum(len(score.get("stems", [])) for score in expected_scores.get("scores", {}).values())
        music_stems_packaged = {stem: any(Path(p).name.startswith(stem + ".ogg-") and p.endswith(".oggvorbisstr") for p in names) for stem in stems}
        forbidden = [p for p in names if any(t in p.lower() for t in [".codex", "sub2_image_gen", "api_key", "keystore", "production-prompts", "tests/smoke_core", "tests/full_run"])]
        libraries = [p for p in names if p.startswith("lib/")]
    passed = all(r.returncode == 0 for r in [badging, permissions, signing]) and all(required.values()) and not forbidden and music_config_matches and len(stems) == expected_stem_count and all(music_stems_packaged.values()) and rules_match and save_rules_match and all(save_scripts.values()) and registry_matches and all(imported_resources.values()) and rig_matches and all(ui_scripts.values()) and license_bytes_match
    with apk.open("rb") as file: digest = hashlib.file_digest(file, "sha256").hexdigest()
    report = {"passed": passed, "apk_sha256": digest, "signature_verified": signing.returncode == 0,
              "signature_diagnostics": signing.stdout.strip(), "package": next((l for l in badging.stdout.splitlines() if l.startswith("package:")), ""),
              "platform_fields": [l for l in badging.stdout.splitlines() if l.startswith(("sdkVersion", "targetSdkVersion", "native-code", "supports-screens"))],
              "permissions": permissions.stdout.strip(), "manifest_diagnostics": badging.stderr.strip(), "required_data_and_licenses": required, "native_libraries": libraries,
              "unexpected_sensitive_files": forbidden, "adb_devices": devices.stdout.strip(), "physical_device_tested": False, "virtualization": "none"}
    report.update({"music_configuration_matches_source": music_config_matches, "music_themes": len(scores.get("scores", {})), "music_stems_expected": expected_stem_count, "music_stems_packaged": music_stems_packaged})
    report.update({"save_schema": 2, "save_rules_match_source": save_rules_match, "compiled_save_scripts_packaged": save_scripts})
    report.update({"all_rules_match_source": rules_match, "combat_control_rules": packed_rules.get("combat", {}).get("control", {})})
    report.update({"runtime_registry_matches_source": registry_matches, "imported_resources_packaged": imported_resources,
                   "weapon_rig_matches_source": rig_matches, "compiled_ui_and_weapon_scripts_packaged": ui_scripts,
                   "new_font_and_icon_license_bytes_match": license_bytes_match})
    report["artifact"] = relative_apk
    report["build_variant"] = "release" if Path(relative_apk).name.endswith("-release.apk") else "debug"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    # This task started ADB for device discovery; release its idle server when no device is present.
    if not any("\tdevice" in line for line in devices.stdout.splitlines()):
        run([str(sdk / "platform-tools/adb.exe"), "kill-server"])
    print(json.dumps({"passed": passed, "apk": relative_apk, "report": report_path.relative_to(ROOT).as_posix() if report_path.is_relative_to(ROOT) else report_path.as_posix(), "apk_sha256": digest, "signature_verified": report["signature_verified"], "runtime_resources": len(imported_resources), "missing_resources": [p for p, ok in imported_resources.items() if not ok], "fonts": sum(r["kind"] == "font" for r in registry["assets"]), "vector_icons": sum(r.get("format") == "svg" for r in registry["assets"]), "ui_and_weapon_scripts": ui_scripts, "physical_device_tested": False}, ensure_ascii=False, indent=2))
    if not passed: raise SystemExit(1)


if __name__ == "__main__":
    main()
