"""Run the real native online menu/input flow against a running native server."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:18777")
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    folder = options.output or ROOT / ".local-tools/online-development" / ("native-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    folder = folder.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    engine = ROOT / ("build/windows/IncenseDebt.exe" if options.packaged else ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    args = [str(engine), "--max-fps", "60", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3", "--resolution", "1280x720", "--position", "-16000,-16000"]
    if not options.packaged:
        args += ["--path", str(ROOT / "game")]
    args += ["--", "--qa-online", "--qa-output=" + str(folder), "--online-url=" + options.url]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    proc = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = proc.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        proc.kill()
        output, _ = proc.communicate(timeout=5)
        (folder / "online-native.log").write_bytes(output)
        raise RuntimeError("Native online QA exceeded its time limit; the test process was closed.")
    log = output.decode("utf8", errors="replace")
    (folder / "online-native.log").write_text(log, "utf8")
    print(log)
    path = folder / "online-native.json"
    if not path.is_file():
        return 1
    report = json.loads(path.read_text("utf8"))
    report.update(recorded_at=datetime.now(timezone.utc).isoformat(), packaged=options.packaged)
    if options.packaged:
        with engine.open("rb") as source:
            report["artifact_sha256"] = hashlib.file_digest(source, "sha256").hexdigest()
    if proc.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
        report["passed"] = False
        report["failures"].append({"id": "native_execution", "passed": False, "detail": "See online-native.log"})
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "captures": len(report["captures"]), "failures": report["failures"], "report": str(path)}, ensure_ascii=False))
    return int(not report["passed"] or not all(c["saved"] for c in report["captures"]))


if __name__ == "__main__":
    raise SystemExit(main())
