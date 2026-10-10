"""Capture native store screenshots and smooth video from the published Windows pack."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / ".local-tools/store-publishing-capture"
OUT = ROOT / "output/publishing/incense-debt/store-kit-2026-10-08"
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
ARTIFACT = ROOT / "build/windows/IncenseDebt.exe"
SCRIPT = ROOT / "tools/documentation/capture_store_media.gd"
BOOTSTRAP = ROOT / "tools/documentation/load_capture_pack.gd"
FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")


def probe(path):
    result = subprocess.run([FFPROBE, "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)],
                            capture_output=True, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    return json.loads(result.stdout)


def capture(scenario, seconds):
    target = RAW / scenario
    target.mkdir(parents=True, exist_ok=True)
    project = RAW / "capture-project"
    project.mkdir(parents=True, exist_ok=True)
    # MovieWriter reads its output size before a SceneTree script initializes.
    # Mounting the original embedded pack from this minimal project lets startup
    # use a 1080p canvas without rebuilding or changing the shipped executable.
    (project / "project.godot").write_text('''config_version=5
[application]
config/name="IncenseDebt native publication capture"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1920
window/size/window_height_override=1080
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
[editor]
movie_writer/video_quality=0.85
''', "utf-8")
    args = [str(ENGINE), "--path", str(project), "--script", str(BOOTSTRAP),
            "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
            "--resolution", "1920x1080", "--position", "-16000,-16000", "--disable-vsync", "--fixed-fps", "30"]
    if scenario != "screenshots": args += ["--write-movie", str(target / "native.avi")]
    args += ["--", "--output=" + str(target), "--scenario=" + scenario, "--seconds=" + str(seconds),
             "--bot-script=" + str(ROOT / "game/tests/playthrough_bot.gd"),
             "--artifact=" + str(ARTIFACT), "--harness=" + str(SCRIPT),
             "--renderer-script=" + str(ROOT / "game/scripts/ui/game_renderer.gd")]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    print("Starting native capture: " + scenario, flush=True)
    with (target / "native.log").open("wb") as log:
        process = subprocess.Popen(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            code = process.wait(timeout=max(240, seconds * 5))
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
            raise RuntimeError("Native capture timed out; the owned window was closed")
    logs = (target / "native.log").read_text("utf-8", errors="replace")
    if code or "SCRIPT ERROR" in logs or "ERROR:" in logs:
        raise RuntimeError(logs[-6000:])
    report = json.loads((target / "capture-report.json").read_text("utf-8"))
    report["artifact_sha256"] = json.loads((ROOT / "build/delivery-manifest.json").read_text("utf-8"))["files"][0]["sha256"]
    report["harness"] = SCRIPT.relative_to(ROOT).as_posix()
    renderer = ROOT / "game/scripts/ui/game_renderer.gd"
    report["renderer_source"] = renderer.relative_to(ROOT).as_posix()
    report["renderer_sha256"] = hashlib.sha256(renderer.read_bytes()).hexdigest()
    report["presentation_fix"] = "Skip disappeared/dead debt-chain anchors in current source renderer; no simulation, stats, loot or RNG change"
    report["capture_size"] = [1920, 1080]
    print("Native capture complete: " + scenario, flush=True)
    return target, report


def publish_screenshots(target, report):
    folder = OUT / "screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    from PIL import Image
    assert len(report["screenshots"]) == 12
    for entry in report["screenshots"]:
        source = target / entry["filename"]
        with Image.open(source) as im:
            im.load()
            assert im.size == (1920, 1080), im.size
        shutil.copyfile(source, folder / entry["filename"])
    (folder / "capture-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")


def encode_video(target, report, scenario, seconds):
    folder = OUT / "videos"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / ("IncenseDebt-gameplay-120s.mp4" if scenario == "gameplay" and seconds == 120 else
                     "native-showcase-40s.mp4" if scenario == "showcase" else "native-smoke.mp4")
    raw = target / "native.avi"
    raw_probe = probe(raw)
    video_stream = next(s for s in raw_probe["streams"] if s["codec_type"] == "video")
    assert (video_stream["width"], video_stream["height"]) == (1920, 1080)
    # Scene initialization precedes the first driven frame by two capture frames.
    # Keep exactly the requested count from the real native recording.
    trim_start = report.get("leading_frames", 2) / 30.0
    args = [FFMPEG, "-y", "-hide_banner", "-loglevel", "warning", "-ss", str(trim_start), "-i", str(raw),
            "-map", "0:v:0", "-map", "0:a:0", "-t", str(seconds), "-frames:v", str(round(seconds * 30)),
            "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
            "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", str(path)]
    subprocess.run(args, cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    info = probe(path)
    assert abs(float(info["format"]["duration"]) - seconds) <= .05
    report["raw_capture"] = raw.relative_to(ROOT).as_posix()
    report["source_duration"] = float(raw_probe["format"]["duration"])
    report["trim_start"] = trim_start
    report["final_video"] = path.relative_to(ROOT).as_posix()
    report["final_media"] = info
    (folder / (scenario + "-capture.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(json.dumps({"video": str(path), "seconds": info["format"]["duration"], "bytes": path.stat().st_size}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["screenshots", "gameplay", "showcase", "all"], default="all")
    parser.add_argument("--seconds", type=float)
    args = parser.parse_args()
    jobs = ["screenshots", "gameplay", "showcase"] if args.scenario == "all" else [args.scenario]
    for scenario in jobs:
        seconds = args.seconds or (120 if scenario == "gameplay" else 40)
        target, report = capture(scenario, seconds)
        if scenario == "screenshots": publish_screenshots(target, report)
        else: encode_video(target, report, scenario, seconds)


if __name__ == "__main__":
    main()
