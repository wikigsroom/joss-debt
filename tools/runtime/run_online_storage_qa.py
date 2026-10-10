"""Inject a reversible file-write failure only into this run's isolated native server."""
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
SERVER = ROOT / "build/server/IncenseDebtServer.exe"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    folder = (args.output or ROOT / ".local-tools/online-development" / ("storage-" + datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    if not folder.is_relative_to(ROOT / ".local-tools"):
        raise RuntimeError("Storage fault tests must use an isolated .local-tools directory")
    data, clients = folder / "server", folder / "clients"
    data.mkdir(parents=True, exist_ok=True)
    with SERVER.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    server_log = (folder / "server.log").open("wb")
    client_log = (folder / "client.log").open("wb")
    server = subprocess.Popen([str(SERVER), "--headless", "--max-fps", "60", "--", "--bind=127.0.0.1", "--port=18877", "--data-dir=" + str(data)], cwd=ROOT, stdout=server_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    client = None
    blockers = [data / "registry" / f"checkpoint_{slot}.json.tmp" for slot in range(2)]

    def wait_for(predicate, seconds=20):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.1)
        raise RuntimeError("Storage fault test timed out; see " + str(folder))

    def ready():
        try:
            with urllib.request.urlopen("http://127.0.0.1:18878/health", timeout=1) as response:
                return response.status == 200
        except OSError:
            return False

    try:
        wait_for(ready, 10)
        client = subprocess.Popen([str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", "res://tests/online_storage.gd", "--", "--folder=" + str(clients)], cwd=ROOT, stdout=client_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        wait_for(lambda: (clients / "fault-ready").is_file())
        # Directory placeholders make FileAccess.open(..., WRITE) fail, leaving
        # both committed generations intact. No ACL or system-wide change.
        for path in blockers:
            path.mkdir()
        wait_for(lambda: (clients / "fault-observed").is_file())
        for path in blockers:
            path.rmdir()  # Owned, checked, empty directory only.
        client.wait(timeout=20)
        report = json.loads((clients / "storage-report.json").read_text("utf8"))
        report.update(server_sha256=digest, packaged_server=True, recorded_at=datetime.now(timezone.utc).isoformat(), virtualization="none")
        if client.returncode:
            report["passed"] = False
        (folder / "storage-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
        print(json.dumps(report, ensure_ascii=False))
        (data / "stop").touch()
        server.wait(timeout=10)
        return int(not report["passed"])
    finally:
        for path in blockers:
            if path.is_dir() and not any(path.iterdir()): path.rmdir()
        for process in (client, server):
            if process is not None and process.poll() is None:
                process.kill(); process.wait(timeout=8)
        client_log.close(); server_log.close()


if __name__ == "__main__":
    raise SystemExit(main())
