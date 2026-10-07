"""Capture actual native Godot equipment, timeline and effects; no browser or VM."""
from pathlib import Path
import json
import hashlib
import subprocess
import sys
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
PACKAGED = "--packaged" in sys.argv
ENGINE = ROOT / ("build/windows/IncenseDebt.exe" if PACKAGED else ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
REPORTS = ROOT / "docs/incense-debt/reports" / ("platforms/windows/equipment-polish" if PACKAGED else "runtime/equipment-polish")
def main():
    REPORTS.mkdir(parents=True, exist_ok=True)
    report_file = REPORTS / "native.json"
    report_file.unlink(missing_ok=True)
    args = [str(ENGINE), "--max-fps", "60", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3", "--resolution", "1280x720", "--position", "-16000,-16000"]
    if not PACKAGED: args += ["--path", str(ROOT / "game")]
    args += ["--", "--qa-equipment", "--qa-output=" + str(REPORTS)]
    startup = subprocess.STARTUPINFO(); startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    try: output, _ = process.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        process.kill(); output, _ = process.communicate(timeout=5)
        (REPORTS / "native.log").write_text(output.decode("utf8", "replace"), "utf8")
        raise RuntimeError("Native equipment fixture timed out; process terminated.")
    log = output.decode("utf8", "replace"); (REPORTS / "native.log").write_text(log, "utf8")
    print(log)
    if not report_file.exists(): return 1
    report = json.loads(report_file.read_text("utf8")); report["packaged"] = PACKAGED
    if PACKAGED:
        with ENGINE.open("rb") as stream:
            report["artifact_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log: report["passed"] = False
    for prefix in ["motion-combined"] + ["fx-" + family for family in ["ember", "ink", "thread", "prism", "lotus", "smoke", "frost", "storm", "void", "brass"]]:
        paths = sorted(REPORTS.glob(prefix + "-*.png"))
        frames = [Image.open(p).convert("RGB").resize((960, 540), Image.Resampling.LANCZOS) for p in paths]
        if frames: frames[0].save(REPORTS / (prefix + ".gif"), save_all=True, append_images=frames[1:], duration=85 if prefix == "motion-combined" else 140, loop=0)
    report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "captures": len(report["captures"]), "atlas_frames_loaded": report["atlas_frames_loaded"], "stress": report["stress"]}, ensure_ascii=False))
    return int(not report["passed"])
if __name__ == "__main__": sys.exit(main())
