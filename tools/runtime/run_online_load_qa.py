"""Load native servers with production ENet/DTLS sessions and real campaigns."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import platform
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
SERVER = ROOT / "build/server/IncenseDebtServer.exe"


class MemoryCounters(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("faults", wintypes.DWORD)] + [(name, ctypes.c_size_t) for name in (
        "peak_working_set", "working_set", "peak_paged", "paged", "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile", "private")]


def native_child_pid(pid):
    """Godot's Windows console executable launches the actual engine as a child."""
    class Entry(ctypes.Structure):
        _fields_ = [("size", wintypes.DWORD), ("usage", wintypes.DWORD), ("pid", wintypes.DWORD),
                    ("heap", ctypes.c_size_t), ("module", wintypes.DWORD), ("threads", wintypes.DWORD),
                    ("parent", wintypes.DWORD), ("priority", wintypes.LONG), ("flags", wintypes.DWORD),
                    ("exe", wintypes.WCHAR * 260)]
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    snapshot = kernel.CreateToolhelp32Snapshot(2, 0)
    if snapshot == ctypes.c_void_p(-1).value: return pid
    try:
        entry = Entry(); entry.size = ctypes.sizeof(entry)
        valid = kernel.Process32FirstW(snapshot, ctypes.byref(entry))
        while valid:
            if entry.parent == pid and entry.exe.lower().startswith("godot"):
                return int(entry.pid)
            valid = kernel.Process32NextW(snapshot, ctypes.byref(entry))
        return pid
    finally:
        kernel.CloseHandle(snapshot)


def memory(pid):
    pid = native_child_pid(pid)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)
    counters = MemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    try:
        psapi = ctypes.WinDLL("psapi")
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
        if handle and psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return {"working_set_bytes": counters.working_set, "private_bytes": counters.private, "measurement_pid": pid}
        return {}
    finally:
        if handle:
            kernel.CloseHandle(handle)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rooms", type=int, nargs="+", default=[2])
    parser.add_argument("--seconds", type=float, default=45)
    parser.add_argument("--weapons", default="w01,w04,w07,w11,w16,w21,w25,w30")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cooperative", action="store_true")
    parser.add_argument("--source-server", action="store_true")
    parser.add_argument("--port", type=int, default=18977)
    args = parser.parse_args()
    folder = (args.output or ROOT / ".local-tools/online-development" / ("load-" + datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    reports = []
    source_hashes = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted((ROOT / "game/scripts").rglob("*.gd"))}
    for rooms in args.rooms:
        case = folder / f"rooms-{rooms}"
        case.mkdir(exist_ok=True)
        data = case / "server"
        data.mkdir(exist_ok=True)
        port = args.port
        server_log = (case / "server.log").open("wb")
        client_log = (case / "traffic.log").open("wb")
        server_command = [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", str(ROOT / "server/main.gd")] if args.source_server else [str(SERVER), "--headless", "--max-fps", "60"]
        server = subprocess.Popen(server_command + ["--", "--bind=127.0.0.1", f"--port={port}", f"--max-rooms={rooms}", f"--max-connections={rooms * 2 + 4}", "--data-dir=" + str(data)], cwd=ROOT, stdout=server_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        traffic = None
        samples = []

        def health():
            with urllib.request.urlopen(f"http://127.0.0.1:{port + 1}/health", timeout=3) as response:
                return json.loads(response.read())

        try:
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    raise RuntimeError("Server exited; see " + str(case / "server.log"))
                try:
                    health()
                    break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError("Server did not become ready")
            traffic = subprocess.Popen([str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", "res://tests/udp_soak.gd", "--", f"--url=ws://127.0.0.1:{port}", f"--rooms={rooms}", f"--seconds={args.seconds}", "--weapons=" + args.weapons, "--game-mode=" + ("coop" if args.cooperative else "duel"), "--output=" + str(case / "clients.json")], cwd=ROOT, stdout=client_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + args.seconds + 80
            while traffic.poll() is None and time.monotonic() < deadline:
                snapshot = health()
                snapshot.update(sample_monotonic=time.monotonic(), **memory(server.pid))
                samples.append(snapshot)
                time.sleep(1)
            if traffic.poll() is None:
                raise RuntimeError("Traffic generator exceeded its time limit")
            clients = json.loads((case / "clients.json").read_text("utf8"))
            # Exclude connection/draft setup; evaluate the steady traffic period.
            steady = [sample for sample in samples if sample["connections"] == rooms * 2 and sample["uptime"] > 10]
            if len(steady) < 5:
                raise RuntimeError("Insufficient steady-state load samples")
            first, last = steady[0], steady[-1]
            tick_hz = (last["tick"] - first["tick"]) / (last["sample_monotonic"] - first["sample_monotonic"])
            clean_logs = all("SCRIPT ERROR" not in path.read_text("utf8", errors="replace") and "ERROR:" not in path.read_text("utf8", errors="replace") for path in (case / "server.log", case / "traffic.log"))
            passed = clients["passed"] and traffic.returncode == 0 and clean_logs and tick_hz >= 58 and last["lifetime_step"].get("p990_ms_upper_bound", 999) < 8 and last["lifetime_step"].get("p999_ms_upper_bound", 999) < 16.7 and last["combat_stalls_over_100ms"] == 0 and all(sample["persistence_errors"] == 0 and not sample["storage_fault"] for sample in steady)
            report = {"passed": passed, "clients": clients, "tick_hz": tick_hz,
                "step_p95_ms": max(s["step_p95_ms"] for s in steady), "step_p99_ms": max(s["step_p99_ms"] for s in steady), "step_max_ms": max(s["step_max_ms"] for s in steady),
                "process_p95_ms": max(s["process_p95_ms"] for s in steady), "process_p99_ms": max(s["process_p99_ms"] for s in steady), "process_max_ms": max(s["process_max_ms"] for s in steady),
                "working_set_peak_bytes": max(s.get("working_set_bytes", 0) for s in steady), "buffered_peak_bytes": max(s["buffered_bytes"] for s in steady), "bytes_sent": last["bytes_sent"], "samples": samples}
            report.update(lifetime_step=last["lifetime_step"], lifetime_process=last["lifetime_process"], combat_stalls_over_100ms=last["combat_stalls_over_100ms"])
            reports.append(report)
            (case / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
            print(json.dumps({k: v for k, v in report.items() if k != "samples"}, ensure_ascii=False), flush=True)
            (data / "stop").touch()
            server.wait(timeout=15)
        finally:
            for process in (traffic, server):
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait(timeout=8)
            client_log.close()
            server_log.close()
    with (ENGINE if args.source_server else SERVER).open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    result = {"recorded_at": datetime.now(timezone.utc).isoformat(), "game_mode": "coop" if args.cooperative else "duel", "server_sha256": digest, "host": platform.platform(), "virtualization": "none", "runs": reports, "passed": all(run["passed"] for run in reports)}
    result.update(source_server=args.source_server, transport="ENet/DTLS")
    result["source_hashes_at_start"] = source_hashes
    (folder / "load-report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf8")
    return int(not result["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
