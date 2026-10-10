"""Native desktop pickup screenshots and behavior validation; never launches a browser/VM."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports/consumables-2026-10-11"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--packaged", action="store_true")
    args = parser.parse_args()
    folder = REPORTS / ("before" if args.baseline else ("windows" if args.packaged else "native"))
    folder.mkdir(parents=True, exist_ok=True)
    engine = ROOT / ("build/windows/IncenseDebt.exe" if args.packaged else
                     ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    command = [str(engine), "--max-fps", "60", "--rendering-method", "gl_compatibility",
               "--rendering-driver", "opengl3", "--resolution", "1280x720", "--position", "-16000,-16000"]
    if not args.packaged:
        command += ["--path", str(ROOT / "game")]
    command += ["--", "--qa-consumables", "--qa-output=" + str(folder)]
    if args.baseline:
        command += ["--qa-consumable-baseline"]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = process.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=5)
        (folder / "native.log").write_bytes(output)
        raise RuntimeError("Native pickup QA timed out; process terminated")
    (folder / "native.log").write_bytes(output)
    log = output.decode("utf8", "replace")
    print(log[-6000:])
    report_file = folder / "native.json"
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log or not report_file.exists():
        return 1
    report = json.loads(report_file.read_text("utf8"))
    report.update(recorded_at=datetime.now(timezone.utc).isoformat(), packaged=args.packaged,
                  source_script_sha256={path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in [ROOT / "game/scripts/ui/pickup_art.gd", ROOT / "game/scripts/ui/game_renderer.gd",
                                   ROOT / "game/scripts/ui/game_hud.gd", ROOT / "game/scripts/ui/consumable_native_qa.gd"]})
    if args.packaged:
        with engine.open("rb") as stream:
            report["artifact_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    for entry in report["captures"]:
        path = folder / (entry["name"] + ".png")
        entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    for prefix in ["idle", "collect"]:
        paths = sorted(folder.glob(prefix + "-*.png"))
        frames = [Image.open(path).convert("RGB").resize((960, 540), Image.Resampling.LANCZOS) for path in paths]
        if frames:
            palette = Image.new("RGB", (960, 540 * len(frames)))
            for index, frame in enumerate(frames):
                palette.paste(frame, (0, index * 540))
            palette = palette.quantize(colors=256)
            indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
            indexed[0].save(folder / (prefix + ".gif"), save_all=True, append_images=indexed[1:],
                            duration=85 if prefix == "idle" else 67, loop=0, optimize=False)
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]),
                      "captures": len(report["captures"]), "folder": str(folder)}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
