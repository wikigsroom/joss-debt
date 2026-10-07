"""Run the user's packaged Sub2API CLI sequentially, preserving references and provider."""
from pathlib import Path
import json
import subprocess
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")


def main():
    manifest = json.loads((ROOT / "docs/incense-debt/assets/runtime-production-queue.json").read_text("utf-8"))
    for index, job in enumerate(manifest["jobs"]):
        output = ROOT / job["output"]
        if output.exists():
            with Image.open(output) as image:
                image.verify()
            print("Already generated: " + job["name"], flush=True)
            continue
        print(f"Generating {index + 1}/{len(manifest['jobs'])}: {job['name']}", flush=True)
        command = [sys.executable, "-X", "utf8", str(CLI), "edit", "--model", manifest["model"], "--quality", manifest["quality"],
                   "--size", "1536x1024", "--background", job["background"], "--prompt-file", job["prompt"], "--out", job["output"]]
        for reference in job["references"]:
            command += ["--image", reference]
        result = subprocess.run(command, cwd=ROOT, timeout=240)
        if result.returncode:
            raise RuntimeError("Production stopped on gateway failure; rerun after resolving the same-provider error: " + job["name"])
        with Image.open(output) as image:
            image.verify()
        print("Ready for visual review: " + str(output), flush=True)


if __name__ == "__main__":
    main()
