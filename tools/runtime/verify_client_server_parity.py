"""Verify all shared bytecode in the actual exported client and server."""
from datetime import datetime, timezone
from pathlib import Path
import json
import subprocess

from record_online_delivery import ROOT, digest, require


def main():
    folder = ROOT / ".local-tools/cooperative-development/client-server-parity"
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / "report.json"
    output.unlink(missing_ok=True)
    client = ROOT / "build/windows/IncenseDebt.exe"
    server = ROOT / "build/server/IncenseDebtServer.exe"
    command = [str(ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"), "--headless", "--main-pack", str(server),
               "--script", str(ROOT / "tools/runtime/verify_client_server_parity.gd"), "--", "--client=" + str(client),
               "--manifest=" + str(ROOT / "build/server/server-build.json"), "--output=" + str(output)]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
    log = result.stdout.decode("utf8", errors="replace")
    (folder / "execution.log").write_text(log, "utf8")
    require(output.is_file(), "Compiled parity did not produce a report: " + log[-2000:])
    report = json.loads(output.read_text("utf8"))
    report.update(recorded_at=datetime.now(timezone.utc).isoformat(), windows_sha256=digest(client), server_sha256=digest(server), virtualization="none")
    report["passed"] = report["passed"] and result.returncode == 0 and "SCRIPT ERROR" not in log and "ERROR:" not in log
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "compiled_shared_modules": report["compiled_shared_modules"], "failures": [row for row in report["checks"] if not row["passed"]]}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
