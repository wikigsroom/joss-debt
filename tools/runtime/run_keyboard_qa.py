"""Drive native Godot with keyboard events only, in isolated save slots."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PACKAGED = "--packaged" in sys.argv
ENGINE = ROOT / ("build/windows/IncenseDebt.exe" if PACKAGED else
                 ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
REPORTS = ROOT / "docs/incense-debt/reports" / ("platforms/windows" if PACKAGED else "runtime") / "keyboard"


def main():
    REPORTS.mkdir(parents=True, exist_ok=True)
    report_path = REPORTS / "keyboard-flow.json"
    report_path.unlink(missing_ok=True)
    # Match rendered fixture waits to the fixed physics clock. Unbounded
    # offscreen rendering can otherwise send Enter during a modal rebuild.
    args = [str(ENGINE), "--max-fps", "60", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
            "--resolution", "1280x720", "--position", "-16000,-16000"]
    if not PACKAGED:
        args += ["--path", str(ROOT / "game")]
    args += ["--", "--qa-keyboard", "--qa-output=" + str(REPORTS)]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, cwd=ROOT)
    try:
        output, _ = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=5)
        (REPORTS / "keyboard-flow.log").write_text(output.decode("utf8", errors="replace"), "utf8")
        raise RuntimeError("Keyboard flow timed out. Native process closed.")
    log = output.decode("utf8", errors="replace")
    (REPORTS / "keyboard-flow.log").write_text(log, "utf8")
    print(log)
    if not report_path.is_file():
        return 1
    report = json.loads(report_path.read_text("utf8"))
    required = {"title_to_files", "file_to_main", "disabled_continue_skipped", "keyboard_slider",
                "rebind_cancel_stays_in_controls", "pause_achievement_filter_parent", "keyboard_physical_door",
                "number_choice_1", "number_choice_2", "number_choice_3", "number_choice_4", "skill_arrow_enter",
                "keyboard_shop_trial_return", "keyboard_shop_purchase", "keyboard_special_sacrifice",
                "keyboard_special_judge", "keyboard_special_angel", "replacement_keyboard_complete",
                "build_returns_review", "keyboard_ending_commit", "keyboard_import_commit", "keyboard_import_undo",
                "slot_3_independent_defaults", "compact_character_actions_do_not_overlap", "menu_notice_does_not_cover_actions"}
    missing = required - {item["id"] for item in report["checks"]}
    if missing:
        report["passed"] = False
        report["failures"].append({"id": "incomplete_flow", "passed": False, "detail": sorted(missing)})
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
        report["passed"] = False
        report["failures"].append({"id": "native_execution", "passed": False, "detail": "See keyboard-flow.log"})
    report["recorded_at"] = datetime.now(timezone.utc).isoformat()
    report["packaged"] = PACKAGED
    report["render_cap_fps"] = 60
    if PACKAGED:
        report["artifact_sha256"] = hashlib.file_digest(ENGINE.open("rb"), "sha256").hexdigest()
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]),
                      "failures": report["failures"], "report": str(report_path)}, ensure_ascii=False))
    return int(bool(process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log
                    or not report["passed"] or not all(item["saved"] for item in report["captures"])))


if __name__ == "__main__":
    sys.exit(main())
