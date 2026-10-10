"""Crash/restart real native server and client processes; corrupt only isolated fixtures."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--packaged-server", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    folder = (args.output or ROOT / ".local-tools/online-development" / ("recovery-" + datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    port = 18877
    reports = []
    for scenario in ("crash", "registry_corruption", "room_corruption", "expiry_takeover"):
        case = folder / scenario
        data = case / "server"
        data.mkdir(parents=True, exist_ok=True)
        log_file = (case / "server.log").open("wb")
        process = None

        def start_server():
            nonlocal process
            command = [str(ROOT / "build/server/IncenseDebtServer.exe"), "--headless", "--max-fps", "60"] if args.packaged_server else [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", str(ROOT / "server/main.gd")]
            command += ["--", "--bind=127.0.0.1", f"--port={port}", "--grace=10", "--data-dir=" + str(data)]
            process = subprocess.Popen(command, cwd=ROOT, stdout=log_file, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("Native server exited during startup; see " + str(case / "server.log"))
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port + 1}/health", timeout=1) as response:
                        if response.status == 200:
                            return
                except OSError:
                    time.sleep(.1)
            raise RuntimeError("Native server health check did not become ready")

        def run_client(stage, mode="restore"):
            command = [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", "res://tests/online_recovery.gd", "--", "--folder=" + str(case / "clients"), "--stage=" + stage, "--mode=" + mode, f"--url=ws://127.0.0.1:{port}"]
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75)
            log = result.stdout.decode("utf8", errors="replace")
            (case / (stage + "-client.log")).write_text(log, "utf8")
            print(log)
            if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
                raise RuntimeError("Native client recovery failed: " + scenario + "/" + stage)
            return json.loads((case / "clients" / (stage + "-" + mode + "-report.json")).read_text("utf8"))

        try:
            start_server()
            prepare = run_client("prepare")
            # This is intentionally an abrupt process termination: no final checkpoint.
            process.kill()
            process.wait(timeout=8)
            if scenario in ("registry_corruption", "room_corruption"):
                registries = [(json.loads(path.read_text("utf8"))["revision"], path) for path in (data / "registry").glob("checkpoint_*.json")]
                _, latest = max(registries)
                if scenario == "registry_corruption":
                    (case / "original-registry.json").write_bytes(latest.read_bytes())
                    latest.write_text("truncated isolated QA checkpoint", "utf8")
                else:
                    registry = json.loads(json.loads(latest.read_text("utf8"))["payload"])
                    room_id = registry["room_ids"][0]
                    revision = int(registry["room_revisions"][room_id])
                    for path in (data / "rooms" / room_id).glob("*.json"):
                        try:
                            envelope = json.loads(path.read_text("utf8"))
                        except ValueError:
                            continue
                        if int(envelope.get("revision", -1)) == revision:
                            path.write_text("truncated isolated QA room", "utf8")
            start_server()
            restore = run_client("restore", "expiry" if scenario == "expiry_takeover" else "restore")
            reports.append({"scenario": scenario, "prepare": prepare, "restore": restore})
            (data / "stop").touch()
            process.wait(timeout=8)
            if process.returncode:
                raise RuntimeError("Native server did not shut down cleanly")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=8)
            log_file.close()
    executable = ROOT / "build/server/IncenseDebtServer.exe" if args.packaged_server else ENGINE
    with executable.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    report = {"passed": all(part["passed"] for case in reports for part in (case["prepare"], case["restore"])), "scenarios": reports, "packaged_server": args.packaged_server, "server_sha256": digest, "recorded_at": datetime.now(timezone.utc).isoformat(), "virtualization": "none"}
    path = folder / "recovery-report.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "scenarios": len(reports), "report": str(path)}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
