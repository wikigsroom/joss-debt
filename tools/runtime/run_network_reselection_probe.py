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


def run_case(engine, folder, index, name, delay_ms, jitter_ms, loss, script=None, deadline=32, duplicates=0, burst_seconds=0, duration_seconds=8, main_pack=None):
    server_port = free_udp_port(set())
    proxy_port = free_udp_port({server_port})
    rng = random.Random(20261011 + index)
    report_path = folder / (name + ".json")
    burst_marker = report_path.with_suffix(".burst-start")
    burst_marker.unlink(missing_ok=True)
    burst_started = None
    stats = {"received_datagrams": 0, "dropped_datagrams": 0, "duplicated_datagrams": 0, "burst_dropped_datagrams": 0,
             "forwarded_datagrams": 0, "max_datagram_bytes": 0, "reordered_datagrams": 0}
    last_forwarded = {}
    queue = []
    serial = 0
    backends = {}
    clients = {}
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, (folder / (name + ".log")).open("wb") as log:
        front.bind(("127.0.0.1", proxy_port))
        front.setblocking(False)
        resource_args = ['--main-pack', str(main_pack)] if main_pack else ['--path', str(ROOT / 'game')]
        process = subprocess.Popen([str(engine), "--headless", "--max-fps", "120", *resource_args, "--script", str(script or ROOT / "tools/runtime/probe_network_reselection.gd"), "--", "--output=" + str(report_path), "--server-port=" + str(server_port), "--proxy-port=" + str(proxy_port), "--burst-seconds=" + str(burst_seconds), "--seconds=" + str(duration_seconds)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            while process.poll() is None:
                now = time.monotonic()
                if burst_seconds and burst_started is None and burst_marker.is_file():
                    burst_started = now
                if now - started > deadline:
                    raise TimeoutError("Native ENet probe exceeded its bounded deadline")
                timeout = min(.005, max(0, queue[0][0] - now)) if queue else .005
                readable, _, _ = select.select([front, *clients], [], [], timeout)
                for stream in readable:
                    while True:
                        try:
                            raw, address = stream.recvfrom(65535)
                        except (BlockingIOError, ConnectionResetError):
                            break
                        stats["received_datagrams"] += 1
                        stats["max_datagram_bytes"] = max(stats["max_datagram_bytes"], len(raw))
                        if stream is front:
                            if address not in backends:
                                if len(backends) >= 128:
                                    raise RuntimeError("Proxy client flow limit exceeded")
                                backend = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                                backend.bind(("127.0.0.1", 0))
                                backend.setblocking(False)
                                backends[address] = backend
                                clients[backend] = address
                            target_stream, target = backends[address], ("127.0.0.1", server_port)
                        else:
                            target_stream, target = front, clients[stream]
                        if burst_started is not None and now - burst_started < burst_seconds:
                            stats["dropped_datagrams"] += 1
                            stats["burst_dropped_datagrams"] += 1
                            continue
                        if rng.random() < loss:
                            stats["dropped_datagrams"] += 1
                            continue
                        due = time.monotonic() + max(0, delay_ms + rng.uniform(-jitter_ms, jitter_ms)) / 1000
                        serial += 1
                        heapq.heappush(queue, (due, serial, target_stream, target, raw))
                        if rng.random() < duplicates:
                            serial += 1
                            heapq.heappush(queue, (due + rng.uniform(0, .04), serial, target_stream, target, raw))
                            stats["duplicated_datagrams"] += 1
                now = time.monotonic()
                while queue and queue[0][0] <= now:
                    _, packet_serial, target_stream, target, raw = heapq.heappop(queue)
                    target_stream.sendto(raw, target)
                    flow_key = (target_stream.fileno(), target)
                    if packet_serial < last_forwarded.get(flow_key, 0): stats["reordered_datagrams"] += 1
                    last_forwarded[flow_key] = max(packet_serial, last_forwarded.get(flow_key, 0))
                    stats["forwarded_datagrams"] += 1
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=8)
            for backend in clients:
                backend.close()
    if not report_path.is_file():
        raise RuntimeError("Native probe did not produce a report; inspect " + str(folder / (name + ".log")))
    report = json.loads(report_path.read_text("utf8"))
    report.update(case=name, impairment_seed=20261011 + index, injected_one_way_delay_ms=delay_ms, injected_jitter_ms=jitter_ms,
                  injected_datagram_loss_probability=loss, injected_duplicate_probability=duplicates, injected_burst_seconds=burst_seconds,
                  proxy=stats, process_exit_code=process.returncode)
    log_text = (folder / (name + ".log")).read_text("utf8", errors="replace")
    report["native_execution_errors"] = sum(any(marker in line.lower() for marker in ['script error', 'error:', 'mbedtls error:']) for line in log_text.splitlines())
    report["passed"] = report["passed"] and process.returncode == 0 and report["native_execution_errors"] == 0
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
