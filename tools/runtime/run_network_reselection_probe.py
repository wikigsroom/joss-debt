"""Probe native ENet/DTLS through a real loopback UDP loss/delay/jitter proxy."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import heapq
import json
import random
import select
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def free_udp_port(excluded):
    for port in random.SystemRandom().sample(range(47000, 62000), 150):
        if port in excluded:
            continue
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.bind(("127.0.0.1", port))
            return port
        except OSError:
            continue
    raise RuntimeError("No isolated UDP port available")


def run_case(engine, folder, index, name, delay_ms, jitter_ms, loss):
    server_port = free_udp_port(set())
    proxy_port = free_udp_port({server_port})
    backend_port = free_udp_port({server_port, proxy_port})
    rng = random.Random(20261011 + index)
    report_path = folder / (name + ".json")
    stats = {"received_datagrams": 0, "dropped_datagrams": 0, "forwarded_datagrams": 0, "max_datagram_bytes": 0}
    queue = []
    serial = 0
    client_address = None
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as back, (folder / (name + ".log")).open("wb") as log:
        front.bind(("127.0.0.1", proxy_port))
        back.bind(("127.0.0.1", backend_port))
        front.setblocking(False)
        back.setblocking(False)
        process = subprocess.Popen([str(engine), "--headless", "--max-fps", "120", "--path", str(ROOT / "game"), "--script", str(ROOT / "tools/runtime/probe_network_reselection.gd"), "--", "--output=" + str(report_path), "--server-port=" + str(server_port), "--proxy-port=" + str(proxy_port)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            while process.poll() is None:
                now = time.monotonic()
                if now - started > 32:
                    raise TimeoutError("Native ENet probe exceeded its bounded deadline")
                timeout = min(.005, max(0, queue[0][0] - now)) if queue else .005
                readable, _, _ = select.select([front, back], [], [], timeout)
                for stream in readable:
                    while True:
                        try:
                            raw, address = stream.recvfrom(65535)
                        except (BlockingIOError, ConnectionResetError):
                            break
                        stats["received_datagrams"] += 1
                        stats["max_datagram_bytes"] = max(stats["max_datagram_bytes"], len(raw))
                        if stream is front:
                            client_address = address
                            target_stream, target = back, ("127.0.0.1", server_port)
                        else:
                            if client_address is None:
                                continue
                            target_stream, target = front, client_address
                        if rng.random() < loss:
                            stats["dropped_datagrams"] += 1
                            continue
                        due = time.monotonic() + max(0, delay_ms + rng.uniform(-jitter_ms, jitter_ms)) / 1000
                        serial += 1
                        heapq.heappush(queue, (due, serial, target_stream, target, raw))
                now = time.monotonic()
                while queue and queue[0][0] <= now:
                    _, _, target_stream, target, raw = heapq.heappop(queue)
                    target_stream.sendto(raw, target)
                    stats["forwarded_datagrams"] += 1
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=8)
    if not report_path.is_file():
        raise RuntimeError("Native probe did not produce a report; inspect " + str(folder / (name + ".log")))
    report = json.loads(report_path.read_text("utf8"))
    report.update(case=name, injected_one_way_delay_ms=delay_ms, injected_jitter_ms=jitter_ms, injected_datagram_loss_probability=loss, proxy=stats, process_exit_code=process.returncode)
    report["passed"] = report["passed"] and process.returncode == 0
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({key: report[key] for key in ["case", "passed", "state_received", "state_age_p95_ms", "state_gap_p95_ms", "input_round_trip_p95_ms", "reliable_requests", "unique_replies_received"]}), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--output", type=Path, default=ROOT / ".local-tools/network-reselection-2026-10-11/enet-probe")
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    cases = [("loopback", 0, 0, 0), ("rtt100-loss3", 50, 20, .03), ("rtt200-loss5", 100, 35, .05)]
    results = [run_case(args.godot.resolve(), folder, index, *case) for index, case in enumerate(cases)]
    report = {"passed": all(case["passed"] for case in results), "recorded_at": datetime.now(timezone.utc).isoformat(), "scope": "Native Windows Godot ENet+DTLS viability probe; actual datagram impairment on loopback. Synthetic payloads, one connection, six-second send windows. Not a TCP comparison, gameplay benchmark, WAN or Android acceptance.", "production_modified": False, "virtualization": "none", "cases": results}
    (folder / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
