"""Generate only through the named packaged Sub2 skill; resumable real output checks."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess
import json
import sys
import time
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")

def run(job):
    output = ROOT / job["output"]
    if output.is_file():
        with Image.open(output) as im: im.verify()
        return {"name": job["name"], "status": "existing"}
    command = [sys.executable, "-X", "utf8", str(CLI), "edit", "--model", "gpt-image-2.5", "--quality", "high",
               "--size", job["size"], "--background", job["background"], "--prompt-file", job["prompt"], "--out", job["output"]]
    for reference in job["references"]: command += ["--image", reference]
    print("Generating " + job["name"], flush=True)
    result = None
    for attempt in range(3):
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf8", errors="replace", timeout=480)
        except subprocess.TimeoutExpired:
            if attempt == 2:return {"name": job["name"], "status": "gateway_error", "message": "Image request timed out after three bounded attempts"}
            print("Retrying timed-out image "+job["name"],flush=True)
            continue
        if result.returncode == 0:break
        if attempt < 2:
            print("Retrying temporary image error "+job["name"],flush=True)
            time.sleep(10+attempt*5)
    if result.returncode:
        return {"name": job["name"], "status": "gateway_error", "message": (result.stdout + result.stderr)[-2000:]}
    with Image.open(output) as im: im.verify()
    return {"name": job["name"], "status": "generated", "output": job["output"]}

def main():
    jobs = json.loads((ROOT / "docs/incense-debt/assets/expansion-production.json").read_text("utf8"))["jobs"]
    results = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(run, jobs):
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)
            (ROOT / "docs/incense-debt/assets/expansion-generation-status.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), "utf8")
    if any(r["status"] == "gateway_error" for r in results): return 1
    return 0

if __name__ == "__main__": sys.exit(main())
