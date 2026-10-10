"""Smoke-test the actual ZIP's Windows launch/stop scripts in a path with spaces."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="v0.3.0-alpha.1")
    args = parser.parse_args()
    payload = ROOT / "build/release" / args.tag / "assets"
    manifest = json.loads((payload / "release-manifest.json").read_text("utf8"))
    archive = payload / f"IncenseDebt-{args.tag}-server-windows-x64.zip"
    row = next(item for item in manifest["files"] if item["name"] == archive.name)
    with archive.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == row["sha256"]
    folder = ROOT / ".local-tools/release-package-verification" / (args.tag + " space " + datetime.now().strftime("%H%M%S"))
    folder.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            if not (folder / name).resolve().is_relative_to(folder.resolve()):
                raise RuntimeError("Unexpected archive member")
        package.extractall(folder)
    server_folder = folder / "IncenseDebtServer"
    with (server_folder / "IncenseDebtServer.exe").open("rb") as stream:
        executable_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    assert executable_sha == manifest["server"]["exe_sha256"]
    for port in (18777, 18778):
        import socket
        with socket.socket() as probe:
            if probe.connect_ex(("127.0.0.1", port)) == 0:
                raise RuntimeError("Test ports are in use; stop only your own prior test server first")
    log = (folder / "launch.log").open("wb")
    process = subprocess.Popen(["cmd.exe", "/d", "/c", "StartServer.cmd"], cwd=server_folder, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    checks = []
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen("http://127.0.0.1:18778/health", timeout=1) as response:
                    health = json.loads(response.read())
                break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError("ZIP launcher did not reach healthy state")
        checks.append({"id": "zip_launch_in_space_path", "passed": response.status == 200 and not health["storage_fault"] and health["rooms"] == 0})
        stop = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(server_folder / "StopServer.ps1")], cwd=server_folder, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
        process.wait(timeout=15)
        checks.append({"id": "zip_stop_script_clean_exit", "passed": stop.returncode == 0 and process.returncode == 0})
        log.flush()
        text = (folder / "launch.log").read_text("utf8", errors="replace")
        checks.append({"id": "zip_durable_shutdown_and_no_runtime_errors", "passed": "checkpoints_flushed=true" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text})
        checks.append({"id": "zip_config_uses_adjacent_persistent_data", "passed": (server_folder / "data/registry/checkpoint_0.json").is_file() or (server_folder / "data/registry/checkpoint_1.json").is_file()})
        report = {"passed": all(item["passed"] for item in checks), "tag": args.tag, "server_zip_sha256": row["sha256"],
                  "server_exe_sha256": executable_sha, "recorded_at": datetime.now(timezone.utc).isoformat(), "checks": checks,
                  "native_windows": True, "virtualization": "none", "path_with_spaces": True}
        (ROOT / "docs/releases" / (args.tag + ".package-smoke.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
        print(json.dumps(report, ensure_ascii=False))
        return int(not report["passed"])
    finally:
        if process.poll() is None:
            (server_folder / "data").mkdir(exist_ok=True)
            (server_folder / "data/stop").touch()
            try: process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                # Native process-tree termination is scoped to the one helper
                # launched by this test, never to a process name or unrelated game.
                subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"], capture_output=True, timeout=8, creationflags=subprocess.CREATE_NO_WINDOW)
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
