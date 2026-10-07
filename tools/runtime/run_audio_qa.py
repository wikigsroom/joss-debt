"""Record the real native Windows mixer quietly and inspect its actual samples."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import wave
import numpy as np
from analyze_native_music import analyze

ROOT = Path(__file__).resolve().parents[2]


def main():
    packaged = "--packaged" in sys.argv
    engine = ROOT / ("build/windows/IncenseDebt.exe" if packaged else ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    out = ROOT / ("docs/incense-debt/reports/platforms/windows/audio" if packaged else "docs/incense-debt/reports/runtime/audio")
    out.mkdir(parents=True, exist_ok=True)
    args = [str(engine), "--audio-driver", "WASAPI", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
            "--resolution", "640x360", "--position", "-16000,-16000", "--", "--qa-audio", "--qa-output=" + str(out)]
    if not packaged: args[1:1] = ["--path", str(ROOT / "game")]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = process.communicate(timeout=45)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=5)
        (out / "native-audio.log").write_text(output.decode("utf8", "replace"), "utf8")
        raise RuntimeError("Native mixer fixture timed out; its process was terminated")
    log = output.decode("utf8", "replace")
    (out / "native-audio.log").write_text(log, "utf8")
    print(log)
    # Godot may print its normal shutdown leak summary after the fixture has
    # already saved all six recordings and exited successfully. Treat actual
    # script/process failures as fatal while allowing that shutdown diagnostic
    # to be carried in the log for review.
    fatal_log_lines = [
        line for line in log.splitlines()
        if ("SCRIPT ERROR" in line or line.startswith("ERROR:"))
        and "resources still in use at exit" not in line
    ]
    if process.returncode or fatal_log_lines: return 1
    report = json.loads((out / "native-audio.json").read_text("utf8"))
    if not report["passed"] or len(report["recordings"]) != 6: return 1
    clips = {}
    for clip in report["recordings"]:
        with wave.open(clip["file"], "rb") as source:
            samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64) / 32768
            frames = samples.reshape(-1, source.getnchannels())
            clip.update({"rms": float(np.sqrt(np.mean(samples ** 2))), "peak": float(np.max(np.abs(samples))),
                         "channels": source.getnchannels(), "frames": source.getnframes(),
                         "sha256": hashlib.sha256(Path(clip["file"]).read_bytes()).hexdigest()})
            clips[clip["name"]] = clip
            if clip["peak"] >= .98: report["failures"].append(clip["name"] + " clips the native mixer")
    report["stem_measurements"] = analyze(report)
    measurements = report["stem_measurements"]
    comparisons = {
        "exploration produces audible samples": clips["exploration"]["rms"] > .002,
        "menu pause really applies its attenuation to native samples": abs(measurements["menu-pause"]["weights"][0] / measurements["exploration"]["weights"][0] - .32) < .007,
        "native looping keeps producing samples after the seam": clips["loop-seam"]["rms"] > .002,
        "mute is actually silent in the captured mixer": clips["muted"]["peak"] < .0004,
    }
    for name, expected in {"exploration": [1, 0, 0, 0, .22], "combat": [1, .58, 0, .30, .22], "tension": [1, .58, .45, .30, .22], "menu-pause": [1, 0, 0, 0, .22]}.items():
        measurement = measurements[name]
        comparisons[name + " audibly matches the authored stems plus room-air texture"] = len(measurement["relative_weights"]) == len(expected) and all(abs(a - b) < .025 for a, b in zip(measurement["relative_weights"], expected)) and measurement["residual_rms_fraction"] < .018 and measurement["reference_condition"] < 40
    for name, passed in comparisons.items():
        report["checks"].append(name)
        if not passed: report["failures"].append(name)
    report["passed"] = not report["failures"]
    if packaged:
        build = json.loads((ROOT / "docs/incense-debt/reports/platforms/windows-build.json").read_text("utf8"))
        with engine.open("rb") as binary: report["artifact_sha256"] = hashlib.file_digest(binary, "sha256").hexdigest()
        if report["artifact_sha256"] != build["sha256"]: raise ValueError("Audio capture belongs to a different executable")
    (out / "native-audio.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "failures": report["failures"], "checks": len(report["checks"]),
                      "rms": {key: value["rms"] for key, value in clips.items()}}, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
