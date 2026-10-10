"""Recheck current touch controls with native Windows Godot; never use an emulator.

The review writes its own evidence and isolated QA saves. It does not change the
game, export an APK, or overwrite the earlier 0.2.0/0.2.1 audit records.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
REPORT = ROOT / "docs/incense-debt/reports/android-controls-current-2026-10-09"
FIXTURES = [
    ("phone-16x9", "1280x720", 0),
    ("phone-20x9-density-480", "2400x1080", 480),
    ("tablet-4x3", "1024x768", 0),
    ("phone-density-320", "1280x720", 320),
    ("compact-density-480", "1280x720", 480),
    ("phone-fhd-density-640", "1920x1080", 640),
]


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run_native(script, folder, resolution="1280x720", dpi=0):
    folder.mkdir(parents=True, exist_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    command = [
        str(ENGINE), "--path", str(ROOT / "game"),
        "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
        "--audio-driver", "Dummy", "--resolution", resolution,
        "--position", "-16000,-16000", "--script", str(script), "--",
        "--qa-capture", "--mobile-ui", "--touch-preview",
        "--qa-output=" + str(folder / "fixture-saves"),
        "--audit-output=" + str(folder),
    ]
    if dpi:
        command.append("--audit-dpi=" + str(dpi))
    try:
        process = subprocess.run(
            command, cwd=ROOT / "game", stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, startupinfo=startup,
            creationflags=subprocess.CREATE_NO_WINDOW, timeout=60,
        )
    except subprocess.TimeoutExpired as error:
        (folder / "native.log").write_bytes(error.stdout or b"")
        raise RuntimeError("Native review timed out: " + folder.name) from error
    log = process.stdout.decode("utf8", errors="replace")
    (folder / "native.log").write_text(log, "utf8")
    if "SCRIPT ERROR" in log:
        raise RuntimeError("Review script error:\n" + log[-5000:])
    return process.returncode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probes-only", action="store_true")
    parser.add_argument("--fixture", choices=[entry[0] for entry in FIXTURES])
    args = parser.parse_args()
    REPORT.mkdir(parents=True, exist_ok=True)
    matrix = json.loads((REPORT / "matrix.json").read_text("utf8")) if args.probes_only or args.fixture else []
    for name, resolution, dpi in ([] if args.probes_only else FIXTURES):
        if args.fixture and args.fixture != name:
            continue
        folder = REPORT / name
        code = run_native(ROOT / "tools/runtime/verify_mobile_revision.gd", folder, resolution, dpi)
        report = json.loads((folder / "verification.json").read_text("utf8"))
        images = []
        for png in sorted(folder.glob("*.png")):
            with Image.open(png) as image:
                if sum(ImageStat.Stat(image.convert("RGB")).var) < 10:
                    raise RuntimeError("Blank native evidence: " + str(png))
                images.append({"path": png.relative_to(ROOT).as_posix(), "size": list(image.size)})
        entry = dict(fixture=name, resolution=resolution, density_override=dpi,
                     exit_code=code, checks=len(report["checks"]), passed=report["passed"],
                     failures=report["failures"], images=images)
        matrix = [previous for previous in matrix if previous["fixture"] != name] + [entry]
        (REPORT / "matrix.json").write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + "\n", "utf8")
        print(f"{name}: {entry['checks']} checks; passed={entry['passed']}; failures={entry['failures']}", flush=True)
    probe = REPORT / "interaction-probes"
    code = run_native(ROOT / "tools/runtime/review_android_controls.gd", probe)
    observations = json.loads((probe / "observations.json").read_text("utf8"))
    if code or not observations["probe_completed"]:
        raise RuntimeError("Input review failed; inspect native.log")
    source_paths = [
        "game/project.godot", "game/scripts/main.gd",
        "game/scripts/ui/input_adapter.gd", "game/scripts/ui/aim_assist.gd",
        "game/scripts/ui/touch_tryout.gd", "game/scripts/ui/control_settings.gd",
        "game/scripts/ui/touch_layout_editor.gd", "game/scripts/ui/game_hud.gd",
        "game/scripts/ui/game_renderer.gd", "game/scripts/combat/world.gd",
        "game/scripts/ui/modern_ui.gd", "game/scripts/ui/menu_flow.gd",
        "game/scripts/ui/game_theme.gd", "game/scripts/ui/orientation_guard.gd",
        "game/scripts/ui/equipment_ui.gd", "game/scripts/ui/input_profile.gd",
        "tools/runtime/verify_mobile_revision.gd", "tools/runtime/review_android_controls.gd",
    ]
    artifact = ROOT / "build/android/IncenseDebt.apk"
    scope = dict(
        scope="Current source native Windows Godot rendering and synthetic multi-touch; physical Android acceptance is not claimed.",
        source_hashes={path: sha256(ROOT / path) for path in source_paths},
        android_artifact_sha256=sha256(artifact) if artifact.exists() else None,
        matrix=matrix, interaction_probes=observations,
    )
    (REPORT / "review.json").write_text(json.dumps(scope, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Interaction probes: {len(observations['observations'])}; evidence saved to {REPORT}", flush=True)


if __name__ == "__main__":
    main()
