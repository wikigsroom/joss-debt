"""Verify only the already deployed native service; never starts virtualization."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
ENDPOINT = "wss://xhz-server.sidcloud.cn/play"
HEALTH = "https://xhz-server.sidcloud.cn/health"

def health():
    with urllib.request.urlopen(HEALTH, timeout=10) as response: return json.load(response)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["recovery", "load"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    folder = args.output.resolve(); folder.mkdir(parents=True, exist_ok=True)
    before = health()
    deadline = time.monotonic() + 100
    while before["connections"] == 0 and before["active_rooms"] and time.monotonic() < deadline:
        time.sleep(1)
        before = health()
    if before["connections"] or before["active_rooms"] or before["queued"]:
        raise RuntimeError("Deployed service has users or rooms; do not restart/load it now")
    log_path = folder / "native.log"
    with log_path.open("wb") as log:
        script = "res://tests/public_server_recovery.gd" if args.mode == "recovery" else "res://tests/public_session_load.gd"
        output = str(folder)
        command = [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", script, "--", "--output=" + output]
        if args.mode == "load": command += ["--url=" + ENDPOINT, "--rooms=2", "--seconds=60", "--weapons=w14,w07", "--game-mode=coop", "--code-base=" + str(500000 + time.time_ns() % 400000)]
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        samples = []
        try:
            if args.mode == "recovery":
                deadline = time.monotonic() + 40
                while not (folder / "restart-ready").exists():
                    if process.poll() is not None or time.monotonic() > deadline: raise RuntimeError("Recovery clients did not become ready")
                    time.sleep(.25)
                snapshot = health()
                if snapshot["connections"] != 2: raise RuntimeError("Unexpected users; refuse restart")
                # Credentials remain private DPAPI. This helper never prints them.
                spec = importlib.util.spec_from_file_location("private_ssh", ROOT / ".local-tools/public-server-2026-10-13/remote.py")
                module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
                client = module.connect()
                try:
                    _, stdout, stderr = client.exec_command("sudo systemctl restart incense-debt.service", timeout=30)
                    if stdout.channel.recv_exit_status(): raise RuntimeError("Scoped service restart failed")
                finally: client.close()
                process.wait(timeout=60)
                report = json.loads((folder / "public-recovery.json").read_text("utf8"))
            else:
                deadline = time.monotonic() + 120
                while process.poll() is None:
                    if time.monotonic() > deadline: raise RuntimeError("Public load timed out")
                    sample = health(); sample["sample_monotonic"] = time.monotonic(); samples.append(sample)
                    time.sleep(1)
                clients = json.loads((folder / "clients.json").read_text("utf8"))
                steady = [s for s in samples if s["connections"] == 4][5:]
                if len(steady) < 20: raise RuntimeError("Insufficient load samples")
                first, last = steady[0], steady[-1]
                tick_hz = (last["tick"] - first["tick"]) / (last["sample_monotonic"] - first["sample_monotonic"])
                report = {"passed": clients["passed"] and tick_hz >= 58 and all(not s["storage_fault"] and not s["persistence_errors"] for s in samples), "clients": clients,
                          "tick_hz": tick_hz, "max_step_ms": max(s["step_max_ms"] for s in steady), "max_process_ms": max(s["process_max_ms"] for s in steady), "samples": samples}
            report.update(endpoint=ENDPOINT, server_version="0.5.0", recorded_at=datetime.now(timezone.utc).isoformat(), real_public_wss=True)
            report["passed"] = report["passed"] and process.returncode == 0 and "SCRIPT ERROR" not in log_path.read_text("utf8", errors="replace")
            (folder / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
            print(json.dumps({k: v for k, v in report.items() if k != "samples"}, ensure_ascii=False))
            return int(not report["passed"])
        finally:
            if process.poll() is None: process.kill(); process.wait(timeout=5)

if __name__ == "__main__": raise SystemExit(main())
