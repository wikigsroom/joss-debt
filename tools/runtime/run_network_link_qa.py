"""Native TCP faults; no packet-filter drivers, browser, WSL, or virtualization."""
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import random
import selectors
import socket
import subprocess
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
SERVER = ROOT / "build/server/IncenseDebtServer.exe"


class ByteProxy(threading.Thread):
    def __init__(self, folder):
        super().__init__(daemon=True)
        self.folder = folder
        self.stop_requested = threading.Event()
        self.started = threading.Event()
        self.failure = None
        self.control_id = -1
        self.mode = "normal"
        self.mode_until = 0
        self.selector = selectors.DefaultSelector()
        self.sides = {}
        self.random = random.Random(735281)
        self.metrics = {"accepted_connections": 0, "fragment_writes": 0, "bytes_forwarded": 0,
                        "maximum_buffered_bytes_per_direction": 0, "actual_cuts": 0, "mode_transitions": []}

    def close_pair(self, side):
        for sock in (side["socket"], side["other"]):
            self.sides.pop(sock, None)
            try:
                self.selector.unregister(sock)
            except (KeyError, ValueError):
                pass
            sock.close()

    def control(self):
        try:
            value = json.loads((self.folder / "proxy-mode.json").read_text("utf8"))
        except (OSError, ValueError):
            return
        if int(value["id"]) == self.control_id:
            return
        self.control_id = int(value["id"])
        self.mode = str(value["mode"])
        self.mode_until = time.monotonic() + float(value.get("seconds", 0))
        self.metrics["mode_transitions"].append({"id": self.control_id, "mode": self.mode, "at": time.monotonic(), "seconds": float(value.get("seconds", 0))})
        if self.mode == "cut":
            self.metrics["actual_cuts"] += 1
            for side in list(self.sides.values()):
                if side["socket"] in self.sides:
                    self.close_pair(side)
        status = self.folder / "proxy-status.json"
        temporary = status.with_suffix(".tmp")
        temporary.write_text(json.dumps({"id": self.control_id, "mode": self.mode}), "utf8")
        temporary.replace(status)

    def stalled(self, direction):
        return self.mode == "stall_both" or self.mode == "stall_downstream" and direction == "downstream"

    def run(self):
        listener = socket.socket()
        try:
            listener.bind(("127.0.0.1", 19181))
            listener.listen(8)
            listener.setblocking(False)
            self.selector.register(listener, selectors.EVENT_READ, None)
            self.started.set()
            while not self.stop_requested.is_set():
                self.control()
                now = time.monotonic()
                if self.mode in ("stall_both", "stall_downstream", "cut") and now >= self.mode_until:
                    self.mode = "normal"
                for side in list(self.sides.values()):
                    can_write = side["queue"] and side["queue"][0][0] <= now and not self.stalled(side["direction"])
                    self.selector.modify(side["socket"], selectors.EVENT_READ | (selectors.EVENT_WRITE if can_write else 0), side)
                for key, events in self.selector.select(.005):
                    side = key.data
                    if side is None:
                        downstream, _ = listener.accept()
                        upstream = socket.create_connection(("127.0.0.1", 19177), timeout=2)
                        self.metrics["accepted_connections"] += 1
                        for sock, other, direction in ((downstream, upstream, "downstream"), (upstream, downstream, "upstream")):
                            sock.setblocking(False)
                            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                            value = {"socket": sock, "other": other, "direction": direction, "queue": deque(), "bytes": 0, "last_due": 0}
                            self.sides[sock] = value
                            self.selector.register(sock, selectors.EVENT_READ, value)
                        continue
                    if side["socket"] not in self.sides:
                        continue
                    try:
                        if events & selectors.EVENT_READ:
                            data = side["socket"].recv(16384)
                            if not data:
                                self.close_pair(side)
                                continue
                            target = self.sides[side["other"]]
                            delay = .12 + self.random.uniform(-.035, .035) if self.mode == "delay" else 0
                            due = max(time.monotonic() + delay, target["last_due"])
                            target["last_due"] = due
                            target["queue"].append([due, data])
                            target["bytes"] += len(data)
                            self.metrics["maximum_buffered_bytes_per_direction"] = max(self.metrics["maximum_buffered_bytes_per_direction"], target["bytes"])
                            if target["bytes"] > 512 * 1024:
                                self.close_pair(side)
                                continue
                        if events & selectors.EVENT_WRITE and side["queue"]:
                            item = side["queue"][0]
                            sent = side["socket"].send(item[1][:97])
                            if sent:
                                self.metrics["fragment_writes"] += 1
                                self.metrics["bytes_forwarded"] += sent
                                side["bytes"] -= sent
                                item[1] = item[1][sent:]
                                if not item[1]:
                                    side["queue"].popleft()
                    except BlockingIOError:
                        pass
                    except (OSError, KeyError):
                        self.close_pair(side)
        except Exception as error:
            self.failure = repr(error)
            self.started.set()
        finally:
            for side in list(self.sides.values()):
                if side["socket"] in self.sides:
                    self.close_pair(side)
            self.selector.close()
            listener.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    folder = args.output.resolve()
    if not folder.is_relative_to(ROOT / ".local-tools") or folder.exists():
        raise RuntimeError("Use a fresh isolated .local-tools folder")
    folder.mkdir(parents=True)
    data = folder / "server"
    data.mkdir()
    proxy = ByteProxy(folder)
    server = None
    log = (folder / "server.log").open("wb")
    try:
        server = subprocess.Popen([str(SERVER), "--headless", "--max-fps", "60", "--", "--port=19177", "--bind=127.0.0.1", "--data-dir=" + str(data)],
                                  cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen("http://127.0.0.1:19178/health", timeout=1) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError("Native server did not become ready")
        proxy.start()
        if not proxy.started.wait(3) or proxy.failure:
            raise RuntimeError("TCP proxy failed: " + str(proxy.failure))
        result = subprocess.run([str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT / "game"), "--script", "res://tests/network_link.gd", "--", "--output=" + str(folder)],
                                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=160, creationflags=subprocess.CREATE_NO_WINDOW)
        output = result.stdout.decode("utf8", errors="replace")
        (folder / "client.log").write_text(output, "utf8")
        print(output)
        report = json.loads((folder / "network-link.json").read_text("utf8"))
        with SERVER.open("rb") as source:
            report["server_sha256"] = hashlib.file_digest(source, "sha256").hexdigest()
        report.update(packaged_server=True, proxy_metrics=proxy.metrics, proxy_failure=proxy.failure, recorded_at=datetime.now(timezone.utc).isoformat())
        report["passed"] = report["passed"] and result.returncode == 0 and not proxy.failure and "SCRIPT ERROR" not in output and "ERROR:" not in output
        (folder / "network-link.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
        print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "report": str(folder / "network-link.json")}, ensure_ascii=False))
        (data / "stop").touch()
        server.wait(timeout=10)
        return int(not report["passed"])
    finally:
        proxy.stop_requested.set()
        if proxy.ident is not None:
            proxy.join(3)
        if server is not None and server.poll() is None:
            server.kill()
            server.wait(timeout=8)
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
