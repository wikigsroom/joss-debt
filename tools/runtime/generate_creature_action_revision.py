"""Resumable bounded concurrency through the user's configured Sub2 image CLI.

The configured skill script is executed, never read. Its credentials are never
copied to the plan, prompts, progress records or diagnostics.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/creature-action-revision"
CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
LOCK = threading.Lock()
STATUS = {}
PROGRESS_NAME = "generation-progress.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_status():
    temporary = OUT / (PROGRESS_NAME + ".tmp")
    temporary.write_text(json.dumps(dict(provider="sub2-image-gen", model="gpt-image-2.5",
        runner_pid=os.getpid(), updated_at=time.time(), jobs=STATUS), ensure_ascii=False, indent=2)+"\n", "utf8")
    # Windows readers can briefly hold the destination without delete sharing.
    # Keep the verified drawing and retry publication instead of marking its
    # generation as failed because the journal was temporarily locked.
    for attempt in range(8):
        try:
            temporary.replace(OUT / PROGRESS_NAME)
            break
        except PermissionError:
            if attempt == 7:
                raise
            time.sleep(min(.8, .05 * 2 ** attempt))


def update(identity, **changes):
    with LOCK:
        STATUS.setdefault(identity, {}).update(changes)
        save_status()


def inspect_png(path, job):
    with Image.open(path) as im:
        im.verify()
    with Image.open(path) as im:
        if im.mode != "RGBA" or im.getextrema()[3][0] != 0:
            raise ValueError("Drawing is missing a transparent RGBA background")
        width, height = im.size
        if abs(height / width - job["rows"] / job["columns"]) > .055:
            raise ValueError(f"Wrong drawing grid aspect ratio: {width}x{height}")
        if min(width / job["columns"], height / job["rows"]) < 120:
            raise ValueError("Raw pose cells are too small")
        return dict(size=list(im.size), sha256=digest(path))


def sanitized(value):
    value = re.sub(r"(?i)Bearer\s+[^\s\"']+", "Bearer [redacted]", value)
    return re.sub(r"\bsk-[A-Za-z0-9_-]{8,}\b", "[redacted]", value)


def generate(job):
    identity = job["id"]
    target = ROOT / job["output"]
    previous = STATUS.get(identity, {})
    fingerprint = dict(prompt_sha256=job["prompt_sha256"], reference_sha256=job["reference_sha256"],
                       source_sha256=job["source_sha256"], model=job["model"])
    for field, hash_field in [("prompt", "prompt_sha256"), ("reference", "reference_sha256"), ("source", "source_sha256")]:
        if digest(ROOT / job[field]) != fingerprint[hash_field]:
            raise RuntimeError("Generation plan no longer matches the actual input: " + identity + " / " + field)
    if target.is_file() and all(previous.get(key) == value for key, value in fingerprint.items()):
        result = inspect_png(target, job)
        update(identity, state="raw_verified", output=job["output"], **fingerprint, **result)
        return identity, True
    if target.is_file():
        raise RuntimeError("Existing drawing has unbound provenance; inspect before replacing: " + identity)
    print("Drawing complete creature page: " + identity, flush=True)
    command = [sys.executable, "-X", "utf8", str(ROOT / "tools/runtime/run_sub2_creature_cli.py"), "edit", "--image", str(ROOT / job["reference"]),
               "--prompt-file", str(ROOT / job["prompt"]), "--model", job["model"], "--quality", job["quality"],
               "--size", job["size"], "--background", "transparent", "--out", str(target)]
    update(identity, state="starting", started_at=time.time(), output=job["output"], **fingerprint)
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    update(identity, state="drawing", process_pid=process.pid)
    try:
        output, _ = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate()
        (OUT / "logs" / (identity + ".log")).write_text(sanitized(output.decode("utf8", errors="replace")), "utf8")
        update(identity, state="failed", process_pid=None, error="CLI terminated after its 600 second execution limit", finished_at=time.time())
        return identity, False
    (OUT / "logs" / (identity + ".log")).write_text(sanitized(output.decode("utf8", errors="replace")), "utf8")
    if process.returncode:
        diagnostic = output.decode("utf8", errors="replace")
        retryable = "gateway_concurrency_limit" in diagnostic or "timed out" in diagnostic.lower() or any(f"HTTP {code}" in diagnostic for code in [408, 429, 500, 502, 503, 504])
        update(identity, state="failed", process_pid=None, returncode=process.returncode, retryable=retryable,
               error="Configured Sub2 CLI failed; inspect local diagnostic", finished_at=time.time())
        return identity, False
    try:
        result = inspect_png(target, job)
    except Exception as error:
        update(identity, state="needs_review", process_pid=None, error=str(error), finished_at=time.time())
        return identity, False
    update(identity, state="raw_verified", process_pid=None, returncode=0, error=None, **result, finished_at=time.time())
    print("Verified transparent source page: " + identity, flush=True)
    return identity, True


def generate_with_retry(job):
    for attempt in range(1, 7):
        identity, passed = generate(job)
        if passed or not STATUS[identity].get("retryable", False) or attempt == 6: return identity, passed
        delay = min(60, 10 * 2 ** (attempt - 1))
        update(identity, state="gateway_backoff", retry_after_seconds=delay, attempt=attempt)
        print(f"Gateway busy for {identity}; bounded retry in {delay}s.", flush=True)
        time.sleep(delay)


def main():
    global PROGRESS_NAME
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--exclude", nargs="*")
    parser.add_argument("--progress-name", default="generation-progress.json", help="Separate journal for distinct corrective jobs while the main queue continues")
    parser.add_argument("--merge-journal", action="append", default=[], help="Consolidate a verified stopped queue into this journal before resuming")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    if Path(args.progress_name).name != args.progress_name or not args.progress_name.endswith(".json"):
        raise ValueError("Progress journal must be a JSON filename inside the drawing output directory")
    PROGRESS_NAME = args.progress_name
    plan = json.loads((OUT / "plan.json").read_text("utf8"))
    old = OUT / PROGRESS_NAME
    if old.is_file():
        previous = json.loads(old.read_text("utf8"))
        STATUS.update(previous.get("jobs", {}))
        previous_runner = previous.get("runner_pid")
        if previous_runner and int(previous_runner) != os.getpid():
            result = subprocess.run(["powershell", "-NoProfile", "-Command", f"Get-Process -Id {int(previous_runner)} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.stdout.strip(): raise RuntimeError("A verified live runner already owns the generation queue: " + str(previous_runner))
        # Never schedule a replacement solely because a previous observation
        # timed out. A concrete still-live CLI PID blocks this runner.
        live = []
        for identity, record in STATUS.items():
            pid = record.get("process_pid")
            if not pid:
                continue
            result = subprocess.run(["powershell", "-NoProfile", "-Command", f"Get-Process -Id {int(pid)} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.stdout.strip():
                live.append((identity, pid))
        if live:
            raise RuntimeError("Verified live drawing processes already own these jobs: " + str(live))
    merged = []
    for name in args.merge_journal:
        if Path(name).name != name or not name.endswith(".json") or name == PROGRESS_NAME:
            raise ValueError("Merge journal must be a different JSON filename inside the drawing output directory")
        path = OUT / name
        previous = json.loads(path.read_text("utf8"))
        pids = {int(previous.get("runner_pid") or 0)} | {int(r.get("process_pid") or 0) for r in previous.get("jobs", {}).values()}
        for pid in pids - {0}:
            result = subprocess.run(["powershell", "-NoProfile", "-Command", f"Get-Process -Id {pid} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.stdout.strip():
                raise RuntimeError("A verified live process still owns merge journal " + name + ": " + str(pid))
        STATUS.update(previous.get("jobs", {}))
        merged.append((name, path))
    if merged:
        history = OUT / "journal-history"
        history.mkdir(exist_ok=True)
        stamp = str(time.time_ns())
        if old.is_file(): shutil.copy2(old, history / (stamp + "-" + PROGRESS_NAME))
        for name, path in merged: shutil.copy2(path, history / (stamp + "-" + name))
        # Commit the combined records before clearing stale overlays. Nothing is
        # scheduled until both journals agree on their single new owner.
        save_status()
        for name, path in merged:
            temporary = path.with_suffix(".json.tmp")
            temporary.write_text(json.dumps(dict(consolidated_into=PROGRESS_NAME, consolidated_at=time.time(), jobs={}), indent=2)+"\n", "utf8")
            temporary.replace(path)
        print("Consolidated verified stopped drawing journals into one resumable queue.", flush=True)
    jobs = plan["jobs"]
    if args.only:
        jobs = [job for job in jobs if job["id"] in args.only or job["actor"] in args.only]
    if args.exclude:
        jobs = [job for job in jobs if job["id"] not in args.exclude and job["actor"] not in args.exclude]
    if args.limit:
        jobs = [job for job in jobs if STATUS.get(job["id"], {}).get("state") != "raw_verified"][:args.limit]
    failures = []
    with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 4))) as pool:
        futures = {pool.submit(generate_with_retry, job): job["id"] for job in jobs}
        for future in as_completed(futures):
            identity = futures[future]
            try:
                _, passed = future.result()
            except Exception as error:
                update(identity, state="failed", error=sanitized(str(error)), process_pid=None, finished_at=time.time())
                passed = False
            if not passed:
                failures.append(identity)
                print("Page requires inspection: " + identity, flush=True)
    print(f"Finished {len(jobs)} requested pages; {len(failures)} require inspection.", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
