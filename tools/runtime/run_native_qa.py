"""Launch and close a real native Windows renderer, hidden and outside the desktop.

This uses neither a browser nor a VM. Viewport PNGs come from Godot itself.
"""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
REPORTS = ROOT / "docs/incense-debt/reports/runtime"
CAPTURE_NAMES = ["menu", "chains", "detonate", "choices", "boss-touch", "inventory", "settings", "obstacles", "debt", "evolution", "coin-vault", "ownerless-temple", "hub", "personal", "endings", "route", "mobile-choice", "mobile-settings", "audio-mix", "story", "training-phase3", "debt-warning", "mobile-route", "animation-sheet", "controls-mapping", "controls-pad", "assistance", "touch-layout", "reading-settings", "story-large", "rotation-guard", "wave-incoming", "wave-arrival", "secret-clue", "secret-open", "secret-route", "secret-room", "mobile-secret-entry", "save-transfer", "save-paste", "save-preview", "mobile-save-transfer", "mobile-save-preview", "held-tools-1", "held-tools-2", "held-tools-back-1", "held-tools-back-2", "held-tools-left", "held-tools-right", "held-brush-charge", "held-brush-fire"]
INTERACTION_CHECKS = 75
CAPTURE_NAMES[CAPTURE_NAMES.index("held-brush-charge"):CAPTURE_NAMES.index("held-brush-charge")] = ["held-tools-left-2", "held-tools-right-1"]
CAPTURE_NAMES += ["inventory-detail", "modern-pause", "run-history", "utility-help", "modern-menu-mobile", "modern-result", "hud-extended", "ui-style"]
CAPTURE_NAMES += ["door-navigation"]
CAPTURE_NAMES += ["character-details", "character-evolution", "character-training", "character-training-cast", "character-locked-mobile", "character-skills-mobile"]
CAPTURE_NAMES += ["achievements"]
CAPTURE_NAMES += ["hurt-direction", "result-source", "result-build", "run-damage", "run-pages", "result-source-mobile", "run-damage-mobile", "run-pages-mobile"]
CAPTURE_NAMES += ["impact-heavy-before", "impact-heavy-after", "root-bound", "root-release", "elite-source"]
CAPTURE_NAMES += ["shop-trial", "shop-trial-live", "shop-trial-return", "inventory-synergy"]
CAPTURE_NAMES += ["special-sacrifice", "special-judge", "special-angel", "special-challenge"]


def main():
    engine, reports = ENGINE, REPORTS
    if "--packaged" in sys.argv:
        engine = ROOT / "build/windows/IncenseDebt.exe"
        reports = ROOT / "docs/incense-debt/reports/platforms/windows"
    reports.mkdir(parents=True, exist_ok=True)
    args = [str(engine), "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
            "--resolution", "1280x720", "--position", "-16000,-16000", "--", "--qa-capture", "--qa-output=" + str(reports)]
    if "--packaged" not in sys.argv:
        args[1:1] = ["--path", str(ROOT / "game")]
    if "--verbose" in sys.argv:
        args.insert(1, "--verbose")
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    if "--packaged" not in sys.argv:
        preflight = subprocess.run([str(engine), "--headless", "--path", str(ROOT / "game"),
                                    "--check-only", "--script", "res://scripts/main.gd"],
                                   capture_output=True, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW,
                                   timeout=20)
        diagnostics = (preflight.stdout + preflight.stderr).decode("utf-8", errors="replace")
        if preflight.returncode or "SCRIPT ERROR" in diagnostics or "ERROR:" in diagnostics:
            print(diagnostics)
            return 1
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup,
                               creationflags=subprocess.CREATE_NO_WINDOW, cwd=ROOT / "game")
    try:
        output, _ = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=5)
        (reports / "native-render.log").write_text(output.decode("utf-8", errors="replace"), "utf-8")
        raise RuntimeError("Native QA timed out; process was terminated.")
    text = output.decode("utf-8", errors="replace")
    (reports / "native-render.log").write_text(text, "utf-8")
    print(text)
    if process.returncode or "SCRIPT ERROR" in text or "ERROR:" in text:
        return 1
    report = json.loads((reports / "native-render.json").read_text("utf-8"))
    if len(report["captures"]) != len(CAPTURE_NAMES) or {capture["name"] for capture in report["captures"]} != set(CAPTURE_NAMES) or not all(capture["saved"] and capture.get("state_stable") for capture in report["captures"]) or report.get("asset_failures"):
        return 1
    if len(report.get("interaction_checks", [])) != INTERACTION_CHECKS or not all(check["passed"] for check in report["interaction_checks"]):
        print(json.dumps(report.get("interaction_checks", []), ensure_ascii=False))
        return 1
    if report["stress"].get("godot_static_memory_bytes", 0) <= 0:
        report["stress"]["godot_static_memory_bytes"] = None
        report["stress"]["static_memory_available"] = False
    if "--packaged" in sys.argv:
        import hashlib
        with engine.open("rb") as binary:
            report["artifact_sha256"] = hashlib.file_digest(binary, "sha256").hexdigest()
        build_file = ROOT / "docs/incense-debt/reports/platforms/windows-build.json"
        build = json.loads(build_file.read_text("utf8"))
        if report["artifact_sha256"] != build["sha256"]:
            raise RuntimeError("Native viewport capture belongs to a different executable")
        build["native_runtime_tested"] = True
        build["native_runtime_report"] = "docs/incense-debt/reports/platforms/windows/native-render.json"
        build["device_tested"] = True
        build_file.write_text(json.dumps(build, ensure_ascii=False, indent=2) + "\n", "utf8")
    (reports / "native-render.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Native Windows viewport: {len(CAPTURE_NAMES)} screenshots saved; runtime assets loaded; process exited.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
