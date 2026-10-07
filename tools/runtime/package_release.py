"""Export and package the current Alpha for GitHub Releases using native tools.

Canonical, previously verified builds remain intact. Release export and native
QA are written under ignored build/release/<tag>/, with no save-slot access by
the packaging process and no virtualization or browser dependencies.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import zipfile

from run_native_qa import CAPTURE_NAMES, INTERACTION_CHECKS

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
TAG = "v0.2.0-alpha.1"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf8").strip()


def native(args, log, timeout=240):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, startupinfo=startup,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=10)
        log.write_bytes(output)
        raise RuntimeError(f"Native operation timed out and was closed: {log.name}")
    log.write_bytes(output)
    text = output.decode("utf8", errors="replace")
    if process.returncode or "SCRIPT ERROR" in text or "ERROR:" in text:
        raise RuntimeError(f"Native operation failed; inspect {log}")


def verify_baseline():
    if git("status", "--porcelain", "--", "game"):
        raise RuntimeError("Commit gameplay changes before preparing a release")
    parity = json.loads((ROOT / "docs/incense-debt/reports/platforms/platform-parity.json").read_text("utf8"))
    full_run = json.loads((ROOT / "docs/incense-debt/reports/runtime/expanded-full-run.json").read_text("utf8"))
    if not parity["passed"] or not full_run["passed"]:
        raise RuntimeError("Current gameplay baseline has no passing parity/full-run evidence")
    for path, expected in full_run["gameplay_sources"].items():
        if digest(ROOT / path) != expected:
            raise RuntimeError(f"Game source no longer matches full-run evidence: {path}")
    entries = {}
    for path in (ROOT / "game").rglob("*"):
        if path.is_file() and ".godot" not in path.parts and path.suffix != ".tmp":
            entries[path.relative_to(ROOT).as_posix()] = digest(path)
    tree = hashlib.sha256()
    for path in sorted(entries):
        tree.update(path.encode("utf8") + b"\0" + entries[path].encode("ascii") + b"\n")
    if tree.hexdigest() != parity["source_tree"]["windows_game_tree_sha256"]:
        raise RuntimeError("Current game tree differs from the verified platform baseline")
    delivery = json.loads((ROOT / "build/delivery-manifest.json").read_text("utf8"))
    for item in delivery["files"]:
        path = ROOT / item["path"]
        if path.stat().st_size != item["bytes"] or digest(path) != item["sha256"]:
            raise RuntimeError(f"Canonical artifact differs from verified delivery: {path.name}")
    return {"built_from_commit": git("rev-parse", "HEAD"),
            "game_git_tree": git("rev-parse", "HEAD:game"),
            "game_tree_sha256": tree.hexdigest(),
            "game_member_count": len(entries)}


def native_qa(executable, directory):
    # Exporting an identical binary does not invalidate actual native tests.
    # Reuse only evidence bound to these exact bytes, with every check/capture
    # complete; otherwise run the fresh export through the native fixtures.
    canonical = ROOT / "build/windows/IncenseDebt.exe"
    current_sha = digest(executable)
    reports = ROOT / "docs/incense-debt/reports/platforms/windows"
    if current_sha == digest(canonical):
        gui_report = json.loads((reports / "native-render.json").read_text("utf8"))
        key_report = json.loads((reports / "keyboard/keyboard-flow.json").read_text("utf8"))
        gear_report = json.loads((reports / "equipment-polish/native.json").read_text("utf8"))
        exact = all(r.get("artifact_sha256") == current_sha for r in [gui_report, key_report, gear_report])
        valid = not gui_report.get("asset_failures") and len(gui_report["interaction_checks"]) == 75 and all(c["passed"] for c in gui_report["interaction_checks"])
        valid = valid and len(gui_report["captures"]) == 90 and all(c["saved"] and c["state_stable"] for c in gui_report["captures"])
        valid = valid and key_report["passed"] and len(key_report["checks"]) == 107 and all(c["passed"] for c in key_report["checks"]) and all(c["saved"] for c in key_report["captures"])
        valid = valid and gear_report["passed"] and len(gear_report["checks"]) == 29 and all(c["passed"] for c in gear_report["checks"]) and len(gear_report["captures"]) == 111 and all(c["saved"] and c["state_stable"] for c in gear_report["captures"])
        valid = valid and gear_report["atlas_frames_loaded"] == 480 and gear_report["stress"]["p95_ms"] < 50
        expected_assets = len(json.loads((ROOT / "game/data/runtime_assets.json").read_text("utf8"))["assets"])
        if exact and valid and gui_report["asset_loads"] == expected_assets:
            print("Release export is byte-identical to the fully tested application; reusing exact-SHA native evidence.", flush=True)
            return {"passed": True, "windows_exe_sha256": current_sha, "native_interaction_checks": 75, "native_captures": 90,
                    "native_resource_count": expected_assets, "keyboard_checks": 107, "keyboard_captures": len(key_report["captures"]),
                    "keyboard_render_cap_fps": 60, "equipment_checks": 29, "equipment_captures": 111,
                    "generated_equipment_fx_frames": 480, "equipment_stress": gear_report["stress"],
                    "temporary_native_windows_closed": True, "evidence_reuse": "byte-identical native-tested executable",
                    "canonical_reports": ["docs/incense-debt/reports/platforms/windows/" + name for name in
                                          ["native-render.json", "keyboard/keyboard-flow.json", "equipment-polish/native.json"]]}
    base = [str(executable), "--rendering-method", "gl_compatibility",
            "--rendering-driver", "opengl3", "--resolution", "1280x720",
            "--position", "-16000,-16000", "--"]
    gui = directory / "native"
    keyboard = directory / "keyboard"
    gui.mkdir(parents=True, exist_ok=True)
    keyboard.mkdir(parents=True, exist_ok=True)
    print("Checking the exported executable with native GUI and keyboard actions...", flush=True)
    native(base + ["--qa-capture", "--qa-output=" + str(gui)], directory / "gui.log")
    report = json.loads((gui / "native-render.json").read_text("utf8"))
    assert not report.get("asset_failures"), "Native resource loading failed"
    expected_assets = len(json.loads((ROOT / "game/data/runtime_assets.json").read_text("utf8"))["assets"])
    assert report["asset_loads"] == expected_assets, "Native runtime did not load the full asset registry"
    assert {row["name"] for row in report["captures"]} == set(CAPTURE_NAMES)
    assert all(row["saved"] and row.get("state_stable") for row in report["captures"])
    assert len(report["interaction_checks"]) == INTERACTION_CHECKS
    assert all(row["passed"] for row in report["interaction_checks"])
    # The embedded fixture advances UI preparation by rendered frames. Bound
    # rendering to the 60 Hz physics clock so Enter cannot arrive while the
    # next physics tick is still rebuilding the choice modal and its focus.
    native([base[0], "--max-fps", "60", *base[1:], "--qa-keyboard",
            "--qa-output=" + str(keyboard)], directory / "keyboard.log")
    keys = json.loads((keyboard / "keyboard-flow.json").read_text("utf8"))
    assert keys["passed"] and not keys.get("failures")
    assert len(keys["checks"]) == 107 and all(row["passed"] for row in keys["checks"])
    assert all(row["saved"] for row in keys["captures"])
    equipment = directory / "equipment"
    equipment.mkdir(parents=True, exist_ok=True)
    print("Checking active items, single trinket slot, floor timeline and generated effects...", flush=True)
    native([base[0], "--max-fps", "60", *base[1:], "--qa-equipment",
            "--qa-output=" + str(equipment)], directory / "equipment.log")
    gear = json.loads((equipment / "native.json").read_text("utf8"))
    assert gear["passed"] and not gear.get("failures")
    assert len(gear["checks"]) == 29 and all(row["passed"] for row in gear["checks"])
    assert len(gear["captures"]) == 111 and all(row["saved"] and row["state_stable"] for row in gear["captures"])
    assert gear["atlas_frames_loaded"] == 480
    assert gear["stress"]["p95_ms"] < 50.0
    return {"passed": True, "windows_exe_sha256": digest(executable),
            "native_interaction_checks": len(report["interaction_checks"]),
            "native_captures": len(report["captures"]),
            "native_resource_count": report["asset_loads"],
            "keyboard_checks": len(keys["checks"]),
            "keyboard_captures": len(keys["captures"]),
            "keyboard_render_cap_fps": 60,
            "equipment_checks": len(gear["checks"]),
            "equipment_captures": len(gear["captures"]),
            "generated_equipment_fx_frames": gear["atlas_frames_loaded"],
            "equipment_stress": gear["stress"],
            "temporary_native_windows_closed": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reuse-export", action="store_true",
                        help="Reuse this release's export and passing native checks when only packaging changes")
    args = parser.parse_args()
    if not ENGINE.exists():
        raise RuntimeError("Fetch native Godot 4.7.2 and export templates first")
    provenance = verify_baseline()
    directory = ROOT / "build/release" / TAG
    payload = directory / "assets"
    windows = directory / "windows"
    payload.mkdir(parents=True, exist_ok=True)
    windows.mkdir(parents=True, exist_ok=True)
    executable = windows / "IncenseDebt.exe"
    qa_file = directory / "verification.json"
    if args.reuse_export:
        verification = json.loads(qa_file.read_text("utf8"))
        if not verification["passed"] or digest(executable) != verification["windows_exe_sha256"]:
            raise RuntimeError("Reused release export differs from its passing native checks")
        if verification["game_tree_sha256"] != provenance["game_tree_sha256"]:
            raise RuntimeError("Gameplay changed since the reused release export")
    else:
        print("Exporting Windows release from the verified current game tree...", flush=True)
        native([str(ENGINE), "--headless", "--path", str(ROOT / "game"),
                "--export-release", "Windows Desktop", str(executable)], directory / "export.log")
        if git("status", "--porcelain", "--", "game"):
            raise RuntimeError("Export changed tracked game files; review before publication")
        verification = native_qa(executable, directory)
        verification["game_tree_sha256"] = provenance["game_tree_sha256"]
        qa_file.write_text(json.dumps(verification, ensure_ascii=False, indent=2) + "\n", "utf8")

    print("Packaging applications, notices, and bilingual player instructions...", flush=True)
    notices = {
        "NotoSansSC-OFL.txt": "game/assets/fonts/OFL.txt",
        "ResourceHanRounded-OFL.txt": "game/assets/fonts/ResourceHanRounded-OFL.txt",
        "SmileySans-OFL.txt": "game/assets/fonts/SmileySans-OFL.txt",
        "Lucide-LICENSE.txt": "game/assets/ui/icons/Lucide-LICENSE.txt",
        "Godot-THIRDPARTY.txt": "game/assets/licenses/Godot-THIRDPARTY.txt",
    }
    for name, source in notices.items():
        shutil.copyfile(ROOT / source, windows / name)
    guide = ROOT / "docs/releases/START-HERE.md"
    ios_guide = ROOT / "docs/releases/iOS-HANDOFF.md"
    shutil.copyfile(guide, windows / "START-HERE.md")
    shutil.copyfile(guide, payload / "START-HERE.md")
    shutil.copyfile(ios_guide, payload / "iOS-HANDOFF.md")
    archive = payload / f"IncenseDebt-{TAG}-windows-x64.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(windows.iterdir()):
            if path.is_file():
                bundle.write(path, "IncenseDebt/" + path.name)
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert hashlib.sha256(bundle.read("IncenseDebt/IncenseDebt.exe")).hexdigest() == digest(executable)
        for name, source in notices.items():
            assert bundle.read("IncenseDebt/" + name) == (ROOT / source).read_bytes()
    shutil.copyfile(ROOT / "build/android/IncenseDebt.apk", payload / f"IncenseDebt-{TAG}-android-arm64-debug.apk")
    shutil.copyfile(ROOT / "build/ios-handoff/IncenseDebt-shared-source.zip", payload / f"IncenseDebt-{TAG}-ios-shared-source.zip")
    files = []
    names = [archive.name, f"IncenseDebt-{TAG}-android-arm64-debug.apk",
             f"IncenseDebt-{TAG}-ios-shared-source.zip", "START-HERE.md", "iOS-HANDOFF.md"]
    for name in names:
        path = payload / name
        files.append({"name": name, "bytes": path.stat().st_size, "sha256": digest(path)})
    manifest = {"tag": TAG, "version": "0.2.0", "prerelease": True,
                "repository": "wikigsroom/joss-debt", "engine": "Godot 4.7.2",
                **provenance, "windows_verification": verification,
                "android": {"build": "debug", "signature_verified": True, "physical_device_tested": False},
                "ios": {"kind": "shared source handoff", "signed_ipa_created": False, "physical_device_tested": False},
                "files": files}
    manifest_path = payload / "release-manifest.json"
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    manifest_path.write_text(manifest_text, "utf8")
    (ROOT / "docs/releases" / (TAG + ".manifest.json")).write_text(manifest_text, "utf8")
    checksums = "".join(digest(payload / name) + "  " + name + "\n"
                        for name in [*names, "release-manifest.json"])
    (payload / "SHA256SUMS.txt").write_text(checksums, "utf8")
    print(json.dumps({"tag": TAG, "assets_directory": str(payload),
                      "assets": [{"name": p.name, "bytes": p.stat().st_size} for p in sorted(payload.iterdir()) if p.is_file()],
                      "verification": verification}, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
