"""Bind current online evidence, native captures and installable bytes to delivery.

Run after native exports and their acceptance tests. Only reports, approved
screenshots and hashes leave .local-tools; credentials and room stores do not.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
TARGET = REPORTS / "online-2026-10-11"
LOCAL = ROOT / ".local-tools/online-development"


def read(path):
    return json.loads(path.read_text("utf8"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(value, message):
    if not value:
        raise RuntimeError(message)


def passed(report):
    failures = report.get("failures", [])
    return report.get("passed", not failures) and not failures


def normalized_native(source):
    value = read(source)
    require(passed(value), "Native online acceptance failed: " + source.name)
    require(len(value["checks"]) >= 30 and len(value["captures"]) >= 33, "Native flow incomplete")
    for capture in value["captures"]:
        path = Path(capture["path"])
        require(capture["saved"] and path.is_file(), "Missing native capture")
        require(path.resolve().is_relative_to(LOCAL), "Unexpected native capture path")
        capture["source_sha256"] = digest(path)
        capture["path"] = path.relative_to(ROOT).as_posix()
    return value


def main():
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(version == "0.3.0", "This delivery is for 0.3.0")
    windows = read(REPORTS / "platforms/windows-build.json")
    android = read(REPORTS / "platforms/android-build.json")
    server = read(ROOT / "build/server/server-build.json")
    for artifact in (windows, android, server):
        path = ROOT / artifact["path"]
        require(artifact["sha256"] == digest(path) and artifact["bytes"] == path.stat().st_size, "Canonical artifact differs")
        require(artifact["version"] == version, "Stale export version")
    for relative, sha in server["shared_source_sha256"].items():
        require(digest(ROOT / "game" / relative) == sha, "Server shared rule source changed: " + relative)

    combat = read(LOCAL / "combat-release.json")
    transport = read(LOCAL / "transport-release/transport-report.json")
    recovery = read(LOCAL / "recovery-release/recovery-report.json")
    storage = read(LOCAL / "storage-release/storage-report.json")
    load = read(LOCAL / "load-release/load-report.json")
    native = normalized_native(LOCAL / "native-release-packaged/online-native.json")
    source_native = normalized_native(LOCAL / "native-release-source/online-native.json")
    touch_native = normalized_native(LOCAL / "native-release-touch/online-native.json")
    parity = read(REPORTS / "action-mobile-2026-10-09/packaged-parity.json")
    apk = read(REPORTS / "platforms/android-verification.json")
    keys = read(REPORTS / "platforms/windows/keyboard/keyboard-flow.json")
    require(all(passed(row) for row in [combat, transport, recovery, storage, load, native, source_native, touch_native, parity, apk, keys]), "Required acceptance did not pass")
    require(native["packaged"] and native["artifact_sha256"] == windows["sha256"], "Stale native client evidence")
    require(touch_native["packaged_game_used"] and touch_native["artifact_sha256"] == windows["sha256"], "Stale compiled-pack touch evidence")
    require(len(touch_native["checks"]) >= 33 and any(item["id"] == "right_touch_continuous_fire_keeps_captured_finger" and item["passed"] for item in touch_native["checks"]), "Continuous touchscreen firing not verified")
    require(touch_native["driver_sha256"] == digest(ROOT / "tools/runtime/capture_online_touch.gd"), "Touch capture driver changed")
    require(parity["windows_sha256"] == keys["artifact_sha256"] == windows["sha256"], "Stale Windows package proof")
    require(parity["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Stale Android proof")
    require(apk["internet_expected"] and apk["internet_permission_matches_source"] and all(apk["compiled_online_scripts_packaged"].values()), "Online APK is incomplete")
    require(apk["signature_verified"] and apk["upgrade_signer_matches_previous"] and all(apk["display_checks"].values()), "Android signature/display acceptance failed")
    require(all(row["server_sha256"] == server["sha256"] and row["virtualization"] == "none" for row in [recovery, storage, load]), "Server evidence belongs to other bytes")

    # Every copied report is explicitly selected. Never copy client identities,
    # raw room checkpoints, expected-state fixtures or whole test directories.
    reports = {"combat.json": combat, "transport.json": transport, "recovery.json": recovery,
               "storage.json": storage, "load.json": load, "native.json": native,
               "native-source.json": source_native, "native-touch.json": touch_native, "package-parity.json": parity,
               "android.json": apk, "keyboard.json": keys, "server-build.json": server,
               "privacy-https.json": read(ROOT / ".local-tools/privacy-policy/deployment-verified.json")}
    for name, value in reports.items():
        write(TARGET / name, value)
    # Earlier 180-second soak uses the pre-fault-notification server hash.
    # Keep its identity and label; it is supporting history, not final SHA proof.
    prior_load = LOCAL / "load-final/load-report.json"
    if prior_load.is_file():
        write(TARGET / "load-180s-prior-build.json", read(prior_load))

    captures = LOCAL / "native-release-packaged"
    media = TARGET / "media"
    media.mkdir(exist_ok=True)
    media_manifest = []
    for name in ["hub", "connection-consent", "lobby", "draft", "combat", "build", "wide-mobile", "reconnect", "result"]:
        source = captures / ("online-" + name + ".png")
        destination = media / (name + ".webp")
        Image.open(source).convert("RGB").save(destination, "WEBP", quality=88, method=6)
        media_manifest.append({"file": destination.relative_to(ROOT).as_posix(), "sha256": digest(destination),
                               "source_png_sha256": digest(source), "capture": name, "codec": "WebP quality 88",
                               "execution": "actual Windows EXE; automated native flow", "proof": "native.json"})
    # Compiled scripts/resources come from the same accepted Windows pack.
    # The external driver holds the real right stick and saves PNGs off-thread;
    # blocking PNG encoding would trip the stale-link input safety gate.
    motion_captures = LOCAL / "native-release-touch"
    frames = []
    for index in range(20):
        source = motion_captures / ("online-motion-%02d.png" % index)
        image = Image.open(source).convert("RGB")
        image.thumbnail((1200, 540), Image.Resampling.LANCZOS)
        frames.append(image.quantize(colors=192, method=Image.Quantize.MEDIANCUT))
    gif = media / "duel-native.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=False, disposal=2)
    media_manifest.append({"file": gif.relative_to(ROOT).as_posix(), "sha256": digest(gif), "frames": 20,
                           "source_png_sha256": [digest(motion_captures / ("online-motion-%02d.png" % i)) for i in range(20)],
                           "capture": "native live combat; real right touchscreen stick; silent; 100 ms comparison playback",
                           "execution": touch_native["execution"], "proof": "native-touch.json", "driver_sha256": touch_native["driver_sha256"]})
    write(TARGET / "media-manifest.json", {"version": version, "windows_sha256": windows["sha256"], "real_transport": True,
                                         "physical_android": False, "records": media_manifest})

    source_paths = sorted([*list((ROOT / "game/scripts").rglob("*.gd")), *list((ROOT / "game/data").glob("*.json")),
                           ROOT / "game/project.godot", ROOT / "game/export_presets.cfg", ROOT / "game/main.tscn"])
    source_hashes = {path.relative_to(ROOT).as_posix(): digest(path) for path in source_paths}
    recovery_count = sum(len(part["checks"]) for case in recovery["scenarios"] for part in [case["prepare"], case["restore"]])
    checks = {"combat": len(combat["checks"]), "transport": len(transport["checks"]), "recovery": recovery_count,
              "storage": len(storage["checks"]), "native_online": len(native["checks"]), "native_source": len(source_native["checks"]), "native_touch": len(touch_native["checks"]),
              "offline_keyboard": len(keys["checks"]), "package_parity": len(parity["checks"])}
    receipt = {"passed": True, "version": version, "recorded_at": datetime.now(timezone.utc).isoformat(),
               "windows_sha256": windows["sha256"], "android_sha256": android["sha256"], "server_sha256": server["sha256"],
               "checks": checks, "native_captures": len(native["captures"]), "native_touch_captures": len(touch_native["captures"]), "runtime_resources": len(apk["imported_resources_packaged"]),
               "matching_compiled_scripts": parity["matching_compiled_scripts"], "source_sha256": source_hashes,
               "proofs": [{"path": (TARGET / name).relative_to(ROOT).as_posix(), "sha256": digest(TARGET / name)} for name in reports],
               "limits": {"default_rooms": 2, "default_connections": 16, "public_game_server_deployed": False,
                          "physical_android_tested": False, "wan_latency_tested": False, "human_balance_tested": False},
               "virtualization": "none", "browser_used": False}
    write(TARGET / "delivery.json", receipt)

    # Preserve old acceptance as an explicit baseline instead of presenting
    # its 368/282 checks as new verification of this online build.
    status = read(TARGET / "baseline-0.2.3/current-product-status.json")
    old_counts = {key: status.get(key) for key in ["mobile_checks", "widescreen_source_checks", "widescreen_packaged_checks"]}
    for key in ["mobile_checks", "mobile_native_screenshots", "mobile_regression_report", "widescreen_source_checks", "widescreen_packaged_checks",
                "widescreen_native_evidence", "widescreen_native_report", "widescreen_fixtures", "widescreen_captures_per_matrix", "revision_report", "public_release_commit", "public_release_published_at",
                "publication_receipt"]:
        status.pop(key, None)
    windows.update(native_runtime_tested=True, device_tested=True,
                   native_runtime_report=(TARGET / "keyboard.json").relative_to(ROOT).as_posix(),
                   native_online_report=(TARGET / "native.json").relative_to(ROOT).as_posix())
    android.update(version_code=6, edge_to_edge=True, signature_verified=True, upgrade_signer_matches_previous=True)
    status.update(recorded_at=receipt["recorded_at"], version=version, status="playable_offline_and_two_player_online_alpha",
                  playable_scope="eleven-floor offline roguelite plus two-player authoritative Duel with quick matching and six-digit open rooms",
                  windows=windows, android=android, server=server, online=receipt["limits"] | {"checks": checks, "reconnect_seconds": 90,
                  "protocol": 1, "ruleset": "duel-2", "characters": 6, "weapons": 32, "skills": 18, "relics": 32},
                  matching_compiled_windows_android_scripts=parity["matching_compiled_scripts"], native_keyboard_checks=len(keys["checks"]),
                  revision_reports=TARGET.relative_to(ROOT).as_posix(), revision_document="docs/incense-debt/40-online-delivery.md",
                  prior_mobile_acceptance={"version": "0.2.3", "report": (TARGET / "baseline-0.2.3/current-product-status.json").relative_to(ROOT).as_posix(), "counts": old_counts},
                  public_github_release="v0.3.0-alpha.1", public_release_url="https://github.com/wikigsroom/joss-debt/releases/tag/v0.3.0-alpha.1",
                  public_release_state="prepared_not_yet_published", privacy_policy_version="1.4",
                  public_release_manifest="docs/releases/v0.3.0-alpha.1.manifest.json", package_checks=len(parity["checks"]))
    privacy = reports["privacy-https.json"]
    status["privacy"] = {"version": privacy["policy_version"], "operator": privacy["operator_name"], "email": "carzyg@outlook.com",
                         "url": privacy["public_url"] + "/privacy-policy", "verified_at": privacy["verified_at"], "docx_sha256": privacy["docx_sha256"]}
    status["pending"] = [*status["pending"], "public persistent game host/TLS, real WAN latency and longer deployment-host load acceptance"]
    write(REPORTS / "current-product-status.json", status)
    write(ROOT / "build/delivery-manifest.json", {"version": version, "status": "verified_alpha_prepared", "recorded_at": receipt["recorded_at"],
          "files": [{key: artifact[key] for key in ["path", "sha256", "bytes"]} for artifact in [windows, android, server]],
          "revision_report": (TARGET / "package-parity.json").relative_to(ROOT).as_posix(),
          "revision_document": "docs/incense-debt/40-online-delivery.md", "revision_reports": TARGET.relative_to(ROOT).as_posix(),
          "runtime_assets": receipt["runtime_resources"], "matching_compiled_scripts": parity["matching_compiled_scripts"],
          "checks": checks, "android_signing": "debug", "android_version_code": 6, "android_physical_device_tested": False,
          "public_game_server_deployed": False, "ios_handoff_version": "0.2.0_historical", "save_schema": 2,
          "public_github_release": "v0.3.0-alpha.1", "public_release_state": "prepared_not_yet_published",
          "previous_delivery_manifest": (TARGET / "baseline-0.2.3/delivery-manifest.json").relative_to(ROOT).as_posix()})
    print(json.dumps({"passed": True, "version": version, "checks": checks, "native_captures": receipt["native_captures"],
                      "windows_sha256": windows["sha256"], "android_sha256": android["sha256"], "server_sha256": server["sha256"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
