"""Bind cooperative campaign evidence to the exact exported native packages."""
from datetime import datetime, timezone
from pathlib import Path
import json
import re
import shutil

from PIL import Image
from record_online_delivery import ROOT, REPORTS, read, write, digest, require, passed

TARGET = REPORTS / "cooperative-2026-10-11"
LOCAL = ROOT / ".local-tools/cooperative-development"


def main():
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(version == "0.4.0", "This receipt is for the cooperative 0.4.0 delivery")
    windows = read(REPORTS / "platforms/windows-build.json")
    android = read(REPORTS / "platforms/android-build.json")
    server = read(ROOT / "build/server/server-build.json")
    for artifact in (windows, android, server):
        path = ROOT / artifact["path"]
        require(artifact["version"] == version and digest(path) == artifact["sha256"] and path.stat().st_size == artifact["bytes"], "Stale canonical export")
    for relative, sha in server["shared_source_sha256"].items():
        require(digest(ROOT / "game" / relative) == sha, "Shared server source changed: " + relative)

    proofs = {
        "combat.json": LOCAL / "combat-final.json",
        "transport.json": LOCAL / "transport-release-final/cooperative-transport.json",
        "recovery.json": LOCAL / "recovery-release-final/recovery-report.json",
        "storage.json": LOCAL / "storage-release/storage-report.json",
        "load.json": LOCAL / "load-release/load-report.json",
        "native.json": LOCAL / "native-release-packaged/online-native.json",
        "duel-native.json": LOCAL / "duel-native-release/online-native.json",
        "duel-combat.json": LOCAL / "duel-regression.json",
        "offline-core.json": REPORTS / "runtime/core-tests.json",
        "package-parity.json": REPORTS / "action-mobile-2026-10-09/packaged-parity.json",
        "client-server-parity.json": LOCAL / "client-server-parity/report.json",
        "android.json": REPORTS / "platforms/android-verification.json",
        "keyboard.json": REPORTS / "platforms/windows/keyboard/keyboard-flow.json",
        "server-build.json": ROOT / "build/server/server-build.json",
        "privacy-https.json": ROOT / ".local-tools/privacy-policy/deployment-verified.json",
    }
    reports = {name: read(path) for name, path in proofs.items()}
    require(all(passed(value) for value in reports.values()), "Required acceptance failed")
    native, duel, parity, apk, keys = [reports[name] for name in ["native.json", "duel-native.json", "package-parity.json", "android.json", "keyboard.json"]]
    for row in (native, duel):
        require(row["packaged"] and row["artifact_sha256"] == windows["sha256"], "Native flow used other client bytes")
        for capture in row["captures"]:
            source = Path(capture["path"]).resolve()
            require(capture["saved"] and source.is_file() and source.is_relative_to(LOCAL), "Missing or unexpected native capture")
            capture.update(path=source.relative_to(ROOT).as_posix(), source_sha256=digest(source))
    require(len(native["checks"]) >= 25 and len(native["captures"]) >= 31, "Cooperative native flow incomplete")
    required = {"cooperative_right_hand_touch_fire", "real_touch_same_door_transitions_both", "cooperative_number_one_selects_growth", "pause_history_contains_both_growth_logs", "offline_save_kept_separate"}
    require(required <= {item["id"] for item in native["checks"] if item["passed"]}, "Required cooperative controls were not exercised")
    require(parity["windows_sha256"] == keys["artifact_sha256"] == windows["sha256"], "Stale Windows proof")
    shared = reports["client-server-parity.json"]
    require(shared["windows_sha256"] == windows["sha256"] and shared["server_sha256"] == server["sha256"], "Stale shared-bytecode proof")
    require(parity["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Stale Android proof")
    require(apk["internet_expected"] and apk["internet_permission_matches_source"] and all(apk["compiled_online_scripts_packaged"].values()), "Incomplete online APK")
    require(apk["signature_verified"] and apk["upgrade_signer_matches_previous"] and all(apk["display_checks"].values()), "APK signature/display failed")
    for name in ("recovery.json", "storage.json", "load.json"):
        row = reports[name]
        require(row["server_sha256"] == server["sha256"] and row["game_mode"] == "coop" and row["virtualization"] == "none", "Stale or non-cooperative server acceptance")
    privacy = reports["privacy-https.json"]
    require(privacy["policy_version"] == "1.5" and privacy["operator_name"] == "吴国黎" and all(item["status"] == 200 for item in privacy["unauthenticated_https_checks"]), "Privacy publication is incomplete")
    for name, value in reports.items():
        write(TARGET / name, value)

    media = TARGET / "media"
    media.mkdir(exist_ok=True)
    captures = LOCAL / "native-release-packaged"
    records = []
    for name in ["hub", "lobby", "combat", "pause", "map", "reconnect", "wide-touch", "growth", "history", "next-room", "result"]:
        source = captures / ("online-coop-" + name + ".png")
        destination = media / (name + ".webp")
        Image.open(source).convert("RGB").save(destination, "WEBP", quality=88, method=6)
        records.append({"file": destination.relative_to(ROOT).as_posix(), "sha256": digest(destination), "source_png_sha256": digest(source), "capture": name, "execution": "actual Windows 0.4.0 EXE; native input; separate exported server", "proof": "native.json"})
    frames = []
    sources = [captures / ("online-motion-%02d.png" % index) for index in range(20)]
    for source in sources:
        frame = Image.open(source).convert("RGB")
        frame.thumbnail((1200, 540), Image.Resampling.LANCZOS)
        frames.append(frame.quantize(colors=192, method=Image.Quantize.MEDIANCUT))
    gif = media / "cooperative-native.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=False, disposal=2)
    records.append({"file": gif.relative_to(ROOT).as_posix(), "sha256": digest(gif), "frames": len(frames), "source_png_sha256": [digest(source) for source in sources], "capture": "two real network clients fighting shared NPCs; right touchscreen held; silent 100 ms playback", "execution": "actual Windows EXE; automated native input", "proof": "native.json"})
    write(TARGET / "media-manifest.json", {"version": version, "windows_sha256": windows["sha256"], "server_sha256": server["sha256"], "real_transport": True, "physical_android": False, "records": records})

    recovery = reports["recovery.json"]
    recovery_count = sum(len(part["checks"]) for case in recovery["scenarios"] for part in (case["prepare"], case["restore"]))
    checks = {"combat": len(reports["combat.json"]["checks"]), "transport": len(reports["transport.json"]["checks"]), "recovery": recovery_count,
              "storage": len(reports["storage.json"]["checks"]), "native_online": len(native["checks"]), "duel_native": len(duel["checks"]),
              "duel_combat": len(reports["duel-combat.json"]["checks"]), "offline_core": len(reports["offline-core.json"]["checks"]),
              "offline_keyboard": len(keys["checks"]), "package_parity": len(parity["checks"])}
    source_paths = sorted([*list((ROOT / "game/scripts").rglob("*.gd")), *list((ROOT / "game/tests").rglob("*.gd")), *list((ROOT / "game/data").glob("*.json")),
                           ROOT / "game/project.godot", ROOT / "game/export_presets.cfg", ROOT / "game/main.tscn", ROOT / "server/main.gd"])
    receipt = {"passed": True, "version": version, "default_game_mode": "coop", "recorded_at": datetime.now(timezone.utc).isoformat(),
               "windows_sha256": windows["sha256"], "android_sha256": android["sha256"], "server_sha256": server["sha256"], "checks": checks,
               "native_captures": len(native["captures"]), "runtime_resources": len(apk["imported_resources_packaged"]), "matching_compiled_scripts": parity["matching_compiled_scripts"],
               "source_sha256": {path.relative_to(ROOT).as_posix(): digest(path) for path in source_paths},
               "proofs": [{"path": (TARGET / name).relative_to(ROOT).as_posix(), "sha256": digest(TARGET / name)} for name in reports],
               "limits": {"default_rooms": 2, "default_connections": 16, "public_game_server_deployed": False, "physical_android_tested": False, "wan_latency_tested": False, "human_balance_tested": False},
               "virtualization": "none", "browser_used": False}
    write(TARGET / "delivery.json", receipt)

    baseline = TARGET / "baseline-0.3.0"
    baseline.mkdir(exist_ok=True)
    for source in (REPORTS / "current-product-status.json", REPORTS / "current-product-status.md", ROOT / "build/delivery-manifest.json"):
        if not (baseline / source.name).exists(): shutil.copyfile(source, baseline / source.name)
    status = read(baseline / "current-product-status.json")
    for key in ["public_release_commit", "public_release_published_at", "publication_receipt", "release_https_verification"]: status.pop(key, None)
    windows.update(native_runtime_tested=True, device_tested=True, native_runtime_report=(TARGET / "keyboard.json").relative_to(ROOT).as_posix(), native_online_report=(TARGET / "native.json").relative_to(ROOT).as_posix())
    android.update(version_code=7, edge_to_edge=True, signature_verified=True, upgrade_signer_matches_previous=True)
    status.update(recorded_at=receipt["recorded_at"], version=version, status="playable_cooperative_offline_and_optional_duel_alpha",
                  playable_scope="eleven-floor offline roguelite plus authoritative two-player cooperative campaign, optional Duel, shared physical rooms, personal builds, revive and durable recovery",
                  windows=windows, android=android, server=server,
                  online=receipt["limits"] | {"checks": checks, "default_mode": "coop", "modes": ["coop", "duel"], "campaign_floors": 11, "reconnect_seconds": 90, "connected_coop_menu_timeout": None,
                                             "protocol": 2, "ruleset": "cooperative-1-duel-2", "characters": 6, "weapons": 32, "skills": 18},
                  matching_compiled_windows_android_scripts=parity["matching_compiled_scripts"], native_keyboard_checks=len(keys["checks"]), package_checks=len(parity["checks"]),
                  revision_reports=TARGET.relative_to(ROOT).as_posix(), revision_document="docs/incense-debt/42-cooperative-delivery.md",
                  prior_online_acceptance={"version": "0.3.0", "report": (baseline / "current-product-status.json").relative_to(ROOT).as_posix()},
                  public_github_release="v0.4.0-alpha.1", public_release_url="https://github.com/wikigsroom/joss-debt/releases/tag/v0.4.0-alpha.1",
                  public_release_state="prepared_not_yet_published", public_release_manifest="docs/releases/v0.4.0-alpha.1.manifest.json", privacy_policy_version="1.5",
                  privacy={"version": "1.5", "operator": privacy["operator_name"], "email": "carzyg@outlook.com", "url": privacy["public_url"] + "/privacy-policy", "verified_at": privacy["verified_at"], "docx_sha256": privacy["docx_sha256"]})
    write(REPORTS / "current-product-status.json", status)
    write(ROOT / "build/delivery-manifest.json", {"version": version, "status": "verified_cooperative_alpha_prepared", "recorded_at": receipt["recorded_at"],
          "files": [{key: artifact[key] for key in ["path", "sha256", "bytes"]} for artifact in [windows, android, server]],
          "revision_report": (TARGET / "package-parity.json").relative_to(ROOT).as_posix(), "revision_document": "docs/incense-debt/42-cooperative-delivery.md", "revision_reports": TARGET.relative_to(ROOT).as_posix(),
          "runtime_assets": receipt["runtime_resources"], "matching_compiled_scripts": parity["matching_compiled_scripts"], "checks": checks,
          "android_signing": "debug", "android_version_code": 7, "android_physical_device_tested": False, "public_game_server_deployed": False,
          "ios_handoff_version": "0.2.0_historical", "save_schema": 2, "public_github_release": "v0.4.0-alpha.1", "public_release_state": "prepared_not_yet_published",
          "previous_delivery_manifest": (baseline / "delivery-manifest.json").relative_to(ROOT).as_posix()})
    print(json.dumps({"passed": True, "version": version, "checks": checks, "native_captures": len(native["captures"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
