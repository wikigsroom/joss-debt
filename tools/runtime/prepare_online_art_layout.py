"""Measure authored image bounds for consistent in-game online equipment thumbnails."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

def main():
    records = {}
    for group in ("heroes", "portraits", "weapons", "skills", "relics"):
        for source in sorted((ROOT / "game/assets" / group).glob("*.png")):
            with Image.open(source) as image:
                width, height = image.size
                bounds = image.convert("RGBA").getchannel("A").getbbox()
            if not bounds: raise RuntimeError("Empty menu artwork: " + str(source))
            x0, y0, x1, y1 = bounds
            pad = max(4, round(min(width, height) * .06))
            x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
            x1, y1 = min(width, x1 + pad), min(height, y1 + pad)
            records["res://" + source.relative_to(ROOT / "game").as_posix()] = {
                "region": [x0, y0, x1 - x0, y1 - y0],
                "source_size": [width, height], "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            }
    destination = ROOT / "game/assets/ui/online-art-layout.json"
    destination.write_text(json.dumps({"schema": 1, "artwork_unchanged": True, "records": records}, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Measured online artwork:", len(records), "original images; no source pixels modified")

if __name__ == "__main__": main()
