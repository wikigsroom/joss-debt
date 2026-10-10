"""Record real touch combat using compiled scripts/resources from the accepted EXE."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    folder = ROOT / ".local-tools/online-development/native-release-touch"
    folder.mkdir(parents=True, exist_ok=True)
    engine = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
    game = ROOT / "build/windows/IncenseDebt.exe"
    command = [str(engine), "--main-pack", str(game), "--script", str(ROOT / "tools/runtime/online_pack_capture.gd"),
        "--max-fps", "60", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
        "--resolution", "1280x720", "--position", "-16000,-16000", "--", "--qa-online", "--qa-output=" + str(folder),
        "--capture-driver=" + str(ROOT / "tools/runtime/capture_online_touch.gd"), "--online-url=ws://127.0.0.1:18777"]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = process.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate(timeout=8)
        (folder / "capture.log").write_bytes(output)
        raise RuntimeError("Native compiled-pack touch capture timed out")
    log = output.decode("utf8", errors="replace")
    (folder / "capture.log").write_text(log, "utf8")
    path = folder / "online-native.json"
    if not path.exists(): raise RuntimeError("Capture produced no report: " + log[-3000:])
    report = json.loads(path.read_text("utf8"))
    with game.open("rb") as stream:
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    report.update(recorded_at=datetime.now(timezone.utc).isoformat(), artifact_sha256=sha, packaged_game_used=True,
                  execution="matching native Godot runner opens accepted EXE pack; compiled game; external touchscreen capture driver",
                  driver_sha256=hashlib.sha256((ROOT / "tools/runtime/capture_online_touch.gd").read_bytes()).hexdigest())
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
        report["passed"] = False
        report["failures"].append({"id": "native_execution", "passed": False})
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "failures": report["failures"], "captures": len(report["captures"]), "artifact_sha256": sha}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
