"""Inspect mobile controls in native Godot; never starts a browser, VM, or emulator."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
SCRIPT = ROOT / "tools/runtime/audit_mobile_controls.gd"
REPORTS = ROOT / "docs/incense-debt/reports/mobile-audit-2026-10-09"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", choices=["phone-16x9", "phone-20x9", "tablet-4x3"])
    parser.add_argument("--verbose", action="store_true")
    options = parser.parse_args()
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    matrix = [("phone-16x9", "1280x720"), ("phone-20x9", "2400x1080"), ("tablet-4x3", "1024x768")]
    results = []
    for name, resolution in matrix:
        if options.fixture and options.fixture != name:
            continue
        folder = REPORTS / name
        folder.mkdir(parents=True, exist_ok=True)
        args = [str(ENGINE), "--path", str(ROOT / "game"), "--rendering-method", "gl_compatibility",
                "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--resolution", resolution,
                "--position", "-16000,-16000", "--script", str(SCRIPT), "--", "--qa-capture",
                "--mobile-ui", "--touch-preview", "--qa-output=" + str(folder / "fixture-saves"),
                "--audit-output=" + str(folder), "--audit-ui"]
        if options.verbose:
            args.insert(1, "--verbose")
        process = subprocess.Popen(args, cwd=ROOT / "game", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            output, _ = process.communicate(timeout=50)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate(timeout=5)
            raise RuntimeError(f"Audit {name} timed out; native process was terminated.")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
        diagnostic = output.decode("utf-8", errors="replace")
        (folder / "native.log").write_text(diagnostic, encoding="utf-8")
        if process.returncode or "SCRIPT ERROR" in diagnostic or "ERROR:" in diagnostic:
            raise RuntimeError(f"{name} failed:\n{diagnostic}")
        report = json.loads((folder / "observations.json").read_text(encoding="utf-8"))
        from PIL import Image, ImageStat
        images = []
        for png in sorted(folder.glob("*.png")):
            with Image.open(png) as image:
                variance = sum(ImageStat.Stat(image.convert("RGB")).var)
                if variance < 10:
                    raise RuntimeError(f"Blank native capture: {png}")
                images.append({"path": str(png.relative_to(ROOT)), "size": list(image.size), "variance": variance})
        results.append({"fixture": name, "resolution": resolution, "observations": report["observations"],
                        "settings": report["settings"], "images": images})
        print(f"{name}: {len(report['observations'])} observations, {len(images)} nonblank captures; native process exited.", flush=True)
    (REPORTS / "matrix.json").write_text(json.dumps({"scope": "native desktop fixtures, not physical Android acceptance",
                                                    "fixtures": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
