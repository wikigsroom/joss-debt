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
    parser.add_argument("--cooperative", action="store_true")
    parser.add_argument("--scenarios", nargs="+", choices=["crash", "registry_corruption", "room_corruption", "expiry_takeover"], default=["crash", "registry_corruption", "room_corruption", "expiry_takeover"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    folder = (args.output or ROOT / ".local-tools/online-development" / ("recovery-" + datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    if folder.exists(): raise RuntimeError('Use a new recovery directory; this fixture must start without prior checkpoints or stop markers')
    folder.mkdir(parents=True)
    port = 18877
    reports = []
    for scenario in args.scenarios:
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
            deadline = time.monotonic() + 30
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
            command = [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", "res://tests/cooperative_recovery.gd" if args.cooperative else "res://tests/online_recovery.gd", "--", "--folder=" + str(case / "clients"), "--stage=" + stage, "--mode=" + mode, f"--url=ws://127.0.0.1:{port}"]
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75)
            log = result.stdout.decode("utf8", errors="replace")
            (case / (stage + "-client.log")).write_text(log, "utf8")
            print(log)
            if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log or "mbedtls error:" in log:
                raise RuntimeError("Native client recovery failed: " + scenario + "/" + stage)
            return json.loads((case / "clients" / (stage + "-" + mode + "-report.json")).read_text("utf8"))

        try:
            start_server()
            prepare = run_client("prepare")
            if args.cooperative:
                # Exact-state corruption assertions need two committed copies
                # of the same frozen state. A valid fallback during live combat
                # can intentionally lose the most recent uncommitted tail.
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    copies = []
                    for path in (data / "registry").glob("checkpoint_*.json"):
                        try:
                            registry = json.loads(json.loads(path.read_text("utf8"))["payload"])
                            revisions = registry.get("room_revisions", {})
                            if len(revisions) != 1:
                                continue
                            room_id, revision = next(iter(revisions.items()))
                            archive = data / "rooms" / room_id / ("revision_%016d.json" % int(revision))
                            if archive.is_file():
                                room = json.loads(json.loads(archive.read_text("utf8"))["payload"])
                                copies.append((int(revision), room))
                        except (OSError, ValueError, KeyError):
                            # The native writer can briefly own/replace a file on
                            # Windows. Retry observation within the same deadline;
                            # do not mistake a sharing violation for stable data.
                            copies = []
                            break
                    if len(copies) == 2 and copies[0][0] != copies[1][0] and all(room["suspended"] for _, room in copies) and copies[0][1]["match"] == copies[1][1]["match"]:
                        break
                    time.sleep(.1)
                else:
                    raise RuntimeError("Two independent stable paused generations were not committed")
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
            for part, stage in [(prepare, "prepare"), (restore, "restore")]:
                text = (case / (stage + "-client.log")).read_text("utf8", errors="replace")
                part["native_execution_errors"] = text.count("SCRIPT ERROR") + text.count("ERROR:") + text.count("mbedtls error:")
                part["passed"] = part["passed"] and part["native_execution_errors"] == 0
            reports.append({"scenario": scenario, "prepare": prepare, "restore": restore})
            (data / "stop").touch()
            process.wait(timeout=8)
            if process.returncode:
                raise RuntimeError("Native server did not shut down cleanly")
            log_file.flush()
            server_text = (case / "server.log").read_text("utf8", errors="replace")
            if "SCRIPT ERROR" in server_text or "ERROR:" in server_text or "mbedtls error:" in server_text:
                restore["passed"] = False
                restore["server_native_execution_errors"] = server_text.count("SCRIPT ERROR") + server_text.count("ERROR:") + server_text.count("mbedtls error:")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=8)
            log_file.close()
    executable = ROOT / "build/server/IncenseDebtServer.exe" if args.packaged_server else ENGINE
    with executable.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    report = {"passed": all(part["passed"] for case in reports for part in (case["prepare"], case["restore"])), "scenarios": reports, "stable_paused_generations_verified": args.cooperative, "game_mode": "coop" if args.cooperative else "duel", "packaged_server": args.packaged_server, "server_sha256": digest, "recorded_at": datetime.now(timezone.utc).isoformat(), "virtualization": "none"}
    path = folder / "recovery-report.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "scenarios": len(reports), "report": str(path)}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
