"""Exercise handset aspect ratios using native Godot, never a VM, emulator or browser."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess
from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
REPORTS = ROOT / "docs/incense-debt/reports/widescreen-2026-10-11"
MATRIX = [
    ("phone-16x9", "1280x720", 160, "none"),
    ("phone-20x9", "2400x1080", 400, "none"),
    ("phone-20x9-left-cutout", "2400x1080", 400, "left"),
    ("phone-20x9-right-cutout", "2400x1080", 400, "right"),
    ("phone-20x9-punch-hole", "2400x1080", 400, "punch-left"),
    ("phone-19_5x9", "2340x1080", 400, "none"),
    ("phone-21x9", "2520x1080", 480, "none"),
    ("tablet-4x3", "1024x768", 160, "none"),
]

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="store_true", help="Render the preserved IncenseDebt-previous.exe pack.")
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--fixture", choices=[row[0] for row in MATRIX])
    args = parser.parse_args()
    packaged = args.packaged or args.baseline
    artifact = ROOT / "build/windows" / ("IncenseDebt-previous.exe" if args.baseline else "IncenseDebt.exe")
    if packaged and not artifact.is_file():
        raise SystemExit("The required exported application is missing: " + str(artifact))
    mode = "before" if args.baseline else ("windows" if args.packaged else "native")
    matrix = []
    for name, resolution, dpi, cutout in MATRIX:
        if args.fixture and name != args.fixture:
            continue
        if args.baseline and name != "phone-20x9":
            continue
        folder = REPORTS / mode / name
        folder.mkdir(parents=True, exist_ok=True)
        command = [str(ENGINE), "--max-fps", "60", "--rendering-method", "gl_compatibility",
                   "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--resolution", resolution,
                   "--position", "-16000,-16000"]
        command += (["--main-pack", str(artifact)] if packaged else
                    ["--path", str(ROOT / "game")])
        command += ["--script", str(ROOT / "tools/runtime/verify_widescreen.gd"), "--", "--qa-capture", "--qa-display",
                    "--mobile-ui", "--touch-preview", "--qa-output=" + str(folder / "isolated-saves"),
                    "--display-output=" + str(folder), "--display-dpi=" + str(dpi), "--display-cutout=" + cutout]
        if args.baseline:
            command.append("--display-baseline")
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=55)
        log = process.stdout.decode("utf8", "replace")
        (folder / "native.log").write_text(log, "utf8")
        if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            raise RuntimeError(name + " failed:\n" + log[-6000:])
        report = json.loads((folder / "native.json").read_text("utf8"))
        if not report["passed"]:
            raise RuntimeError(name + " has failing checks")
        for row in report["captures"]:
            path = folder / (row["name"] + ".png")
            row["sha256"] = digest(path)
            with Image.open(path) as im:
                if sum(ImageStat.Stat(im.convert("RGB")).var) < 10:
                    raise RuntimeError("Blank native frame: " + str(path))
                if row["name"] == "combat":
                    w, h = im.size
                    row["side_band_variance"] = [sum(ImageStat.Stat(im.crop(box).convert("RGB")).var)
                        for box in [(8, h*.28, w*.065, h*.62), (w*.935, h*.28, w-8, h*.62)]]
                    if not args.baseline and name != "phone-16x9" and min(row["side_band_variance"]) < 25:
                        raise RuntimeError("Unpainted combat side band: " + name)
        report.update(recorded_at=datetime.now(timezone.utc).isoformat(), packaged=packaged)
        if not args.baseline:
            report["source_script_sha256"] = {p.relative_to(ROOT).as_posix(): digest(p) for p in
                [ROOT / "game/scripts/main.gd", ROOT / "game/scripts/ui/game_renderer.gd", ROOT / "game/scripts/ui/mobile_surface.gd"]}
        if packaged:
            report["artifact_sha256"] = digest(artifact)
        (folder / "native.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
        matrix.append({"fixture": name, "resolution": resolution, "dpi": dpi, "cutout": cutout,
                       "checks": len(report["checks"]), "captures": len(report["captures"]), "passed": True,
                       "report": (folder / "native.json").relative_to(ROOT).as_posix()})
        print(f"{name}: {len(report['checks'])} checks passed, {len(report['captures'])} native captures", flush=True)
    (REPORTS / (mode + "-matrix.json")).write_text(json.dumps({"passed": True, "fixtures": matrix,
        "scope": "Actual native graphics and touch events; handset insets simulated; physical handset acceptance pending"},
        ensure_ascii=False, indent=2) + "\n", "utf8")

if __name__ == "__main__":
    main()
