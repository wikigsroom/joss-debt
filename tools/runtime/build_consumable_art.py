"""Generate and normalize real Sub2 pickup drawings, without vector substitutes."""
from pathlib import Path
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import subprocess
import sys

from PIL import Image, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/consumables-2026-10-11"
DEST = ROOT / "game/assets/pickups"
SKILL = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
STYLE = """Create one production-ready collectible sprite for Incense Debt, a hand-painted Chinese folk-paper roguelike. Its world is made from ivory rice paper, vermilion folded paper, ink outlines, tarnished brass, red cord and warm lantern light. Match an illustrated paper puppet world: tactile paper fibres, deliberate chunky ink contour, hand-painted gouache shading, subtle layered folds, charming rounded object silhouette. Not a flat vector icon, not pixel art, not a photoreal product render, not glossy plastic, no modern electronic design.
Composition: ONE isolated object centered, three-quarter view from slightly above, front of object readable. Object occupies about 75 percent of a square canvas with generous clear margin. Big simple silhouette and broad colour blocks readable at 32-44 screen pixels; fine detail supports the silhouette. Warm upper-left light, deep ink-brown underside, cream edge highlights. No ground plane, no cast floor shadow, no surrounding scenery, no frame, no UI, no text, no letters, no numerals, no watermark, no logo. Fully transparent background; do not draw a checkerboard. Do not add floating sparkles, particles or a diffuse glow outside the object's silhouette.
Subject: """
SUBJECTS = {
    "heal": """A beautiful small heart-shaped paper lantern that restores life. The main body MUST be a clearly recognizable full vermilion-red heart with two rounded lobes and one pointed lower tip, NOT a diamond, not an anatomical organ. Layered ruby and scarlet rice paper, warm pale peach internal illumination, thick pale cream folded paper trim, dark ink outer rim, a few expressive diagonal paper creases. Tiny aged brass cap between the two lobes, a very short red cord knot and two small tassel ends beneath the tip. Keep the HEART BODY large, broad, rich red and overwhelmingly dominant; charms and cord must not elongate the sprite. Magical, handmade and inviting to pick up. No printed symbol or additional heart emblem on its surface.""",
    "coin": """One substantial round golden ancient Chinese cash coin, slightly tilted in three-quarter view, with a large open SQUARE hole cut through its middle, strongly readable warm gold face, thick tarnished brass rim, chunky embossed concentric ornaments without any lettering, cream-gold edge highlight, deep brown ink outline. A tiny short vermilion cord loop touches the coin's lower edge. Rich, collectible, pleasantly weighty, an appealing game treasure. Single coin only.""",
    "coin_pair": """A pair of exactly TWO round golden ancient Chinese cash coins, slightly overlapping in three-quarter view, both readable as round discs with open SQUARE center holes. Warm gold faces, thick tarnished brass rims, chunky embossed ornaments without any lettering, cream-gold highlights, deep brown ink outline. A tiny short vermilion cord loosely ties their lower edges together. Clearly a larger-value version of the same single cash coin collectible, compact wide silhouette, not a tall pile, no pouch.""",
    "ash": """A small open ivory folded rice-paper offering packet, shaped like a shallow cupped paper boat with chunky angular folded corners. Inside is a prominent little heap of dark slate incense ash with a large warm amber ember at its centre, surrounded by two smaller burnt-orange ember pieces. Ash clearly visible, cream paper perimeter contrasts against dark floor. One very short translucent white curl of incense smoke rises from the ember, thick readable brush-painted smoke, not wispy diffuse haze. A small red folded seam at the packet's front. Compact low wide silhouette, not a lantern, not a coin, not a flower, not a diamond jewel. This is energy returned from burnt offerings.""",
    "ash_bundle": """A larger open ivory folded rice-paper offering packet shaped like a low shallow cupped paper boat, with chunky angular folded corners and one red paper fold at the front. A rich heap of dark slate incense ash contains THREE clearly visible large glowing amber ember pieces, bright orange cores with burnt charcoal edges. Two short thick brush-painted ivory smoke curls rise only a little above the heap. Cream paper perimeter strongly readable, amber ash glowing inside. This is the richer elite/boss version of the small single-ember ash collectible: compact wide silhouette, no coin, no lantern, no crystal, no blossom.""",
    "battery": """A beautiful portable fire-core charm for recharging a magical active item, NOT a modern electrical battery or a lightning-bolt symbol. Short rounded aged-brass reliquary housing, compact rounded lantern capsule shape, squat ivory rice-paper side panels, a LARGE central window exposing a vivid orange-gold living flame. The flame takes half of the object, lit pale golden centre, deep orange outer edge; chunky brass lower cradle with tiny folded-paper scallops and one little vermilion cord knot. Small brass top cap, no tall handle. Strong gold/orange silhouette distinct from the red healing heart and flat coin, wonderfully handmade and collectible. No text, no heart symbol. CRITICAL COMPOSITION: make the object smaller within the canvas. The complete top brass cap and entire bottom cord must be visible. Every part fits inside the centre 70 percent of the canvas, leaving at least 15 percent EMPTY TRANSPARENT MARGIN above and below and on both sides. Squat round body; total object height only slightly greater than width. Never touch or crop at any canvas edge.""",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf8")


def prepare():
    (OUT / "prompts").mkdir(parents=True, exist_ok=True)
    jobs = []
    for key, subject in SUBJECTS.items():
        prompt = OUT / "prompts" / (key + ".txt")
        prompt.write_text(STYLE + subject + "\n", "utf8")
        jobs.append({"id": key, "prompt": str(prompt), "output": str(OUT / (key + "-source.png"))})
    write_json(OUT / "jobs.json", jobs)
    print(f"Prepared {len(jobs)} prompts for gpt-image-2.5, 1024x1024, high, transparent PNG.")


def generate_one(job):
    destination = Path(job["output"])
    if not destination.exists():
        command = [sys.executable, "-X", "utf8", str(SKILL), "generate", "--prompt-file", job["prompt"],
                   "--model", "gpt-image-2.5", "--size", "1024x1024", "--quality", "high",
                   "--background", "transparent", "--output-format", "png", "--out", str(destination)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=600,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        (OUT / (job["id"] + ".log")).write_bytes(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(job["id"] + ": Sub2 generation failed; diagnostic log saved locally")
    with Image.open(destination) as image:
        image.load()
        if min(image.size) < 1024 or image.width != image.height:
            raise ValueError(f"Unexpected generation dimensions: {image.size}")
        record = {"id": job["id"], "file": destination.relative_to(ROOT).as_posix(),
                  "sha256": sha(destination), "size": list(image.size), "requested_size": [1024, 1024], "mode": image.mode}
    print("Generated: " + job["id"], flush=True)
    return record


def generate(only):
    jobs = json.loads((OUT / "jobs.json").read_text("utf8"))
    if only:
        jobs = [job for job in jobs if job["id"] in only]
    records, failures = [], []
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks = {pool.submit(generate_one, job): job["id"] for job in jobs}
        for future in as_completed(tasks):
            try:
                records.append(future.result())
            except Exception as error:
                failures.append({"id": tasks[future], "error": str(error)})
                print(str(error), flush=True)
    write_json(OUT / "generation-report.json", {"provider": "sub2-image-gen", "model": "gpt-image-2.5",
               "passed": not failures, "sources": records, "failures": failures})
    return int(bool(failures))


def normalized(source):
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] == 255:
        raise ValueError("Source has no transparent background: " + str(source))
    # Remove barely visible alpha spill only. The object itself is generated art.
    alpha = alpha.point(lambda value: 0 if value < 8 else value)
    image.putalpha(alpha)
    bounds = alpha.point(lambda value: 255 if value >= 20 else 0).getbbox()
    if not bounds:
        raise ValueError("Empty generated drawing: " + str(source))
    if bounds[0] < 3 or bounds[1] < 3 or bounds[2] > image.width - 3 or bounds[3] > image.height - 3:
        raise ValueError("Source artwork touches canvas edge: " + str(source))
    art = image.crop(bounds)
    art.thumbnail((220, 216), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (256, 256))
    result.alpha_composite(art, ((256 - art.width) // 2, (256 - art.height) // 2))
    return result, bounds


def compile_art():
    DEST.mkdir(parents=True, exist_ok=True)
    records = []
    originals = {}
    for key in SUBJECTS:
        source = OUT / (key + "-source.png")
        image, bounds = normalized(source)
        originals[key] = image
        destination = DEST / (key + ".png")
        image.save(destination)
        records.append({"id": key, "file": "res://assets/pickups/" + destination.name,
                        "sha256": sha(destination), "source": source.relative_to(ROOT).as_posix(),
                        "source_sha256": sha(source), "source_bounds": list(bounds),
                        "source_size": list(Image.open(source).size), "requested_source_size": [1024, 1024], "size": [256, 256],
                        "method": "AI-drawn object; transparent crop, uniform scale, centered anchor only"})
        # A bitmap outline is a dilation of that exact generated silhouette, not redrawn geometry.
        outline = Image.new("RGBA", image.size, "#fff2cf")
        outline.putalpha(image.getchannel("A").filter(ImageFilter.MaxFilter(9)))
        outline.save(DEST / (key + "-outline.png"))
    for key, source_key in [("heart-solid", "heal"), ("heart", "heal"), ("coins", "coin"), ("ash-pickup", "ash"), ("battery-pickup", "battery")]:
        destination = DEST / (key + "-ui.png")
        icon = originals[source_key].resize((96, 96), Image.Resampling.LANCZOS)
        icon.save(destination)
        records.append({"id": key, "file": "res://assets/pickups/" + destination.name,
                        "sha256": sha(destination), "derived_from": source_key, "size": [96, 96],
                        "method": "same generated pickup resized for HUD / resource icons"})
    filled = originals["heal"].resize((96, 96), Image.Resampling.LANCZOS)
    empty = ImageOps.colorize(ImageOps.grayscale(filled), "#29383e", "#82979b").convert("RGBA")
    empty.putalpha(filled.getchannel("A"))
    empty.save(DEST / "heart-empty-ui.png")
    records.append({"id": "heart-empty", "file": "res://assets/pickups/heart-empty-ui.png",
                    "sha256": sha(DEST / "heart-empty-ui.png"), "derived_from": "heal", "size": [96, 96],
                    "method": "same generated heart, desaturated cool-grey empty health state"})
    # Floor shadow is also a transformed raster alpha, shared by all objects.
    mask = originals["coin"].getchannel("A").resize((224, 56), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", (256, 96))
    dark = Image.new("RGBA", mask.size, "#10161c")
    dark.putalpha(mask.point(lambda value: int(value * .38)).filter(ImageFilter.GaussianBlur(6)))
    shadow.alpha_composite(dark, (16, 20))
    shadow.save(DEST / "ground-shadow.png")
    for path in sorted(DEST.glob("*-outline.png")) + [DEST / "ground-shadow.png"]:
        records.append({"id": path.stem, "file": "res://assets/pickups/" + path.name,
                        "sha256": sha(path), "size": list(Image.open(path).size),
                        "method": "raster alpha silhouette derived from generated pickup; no vector object painting"})
    manifest = {"provider": "sub2-image-gen", "model": "gpt-image-2.5", "source_count": len(SUBJECTS),
                "objects": list(SUBJECTS), "records": records,
                "variants": {"coin_pair": "coin value >= 2", "ash_bundle": "ash value >= 16"},
                "gameplay": "presentation only; values, RNG, pickup radii, manual fire-core interaction and save schema unchanged"}
    write_json(DEST / "manifest.json", manifest)
    write_json(OUT / "asset-production.json", manifest)
    # Preview uses the actual normalized runtime bitmaps, not a fabricated mock-up.
    board = Image.new("RGBA", (1024, 640), "#1b282d")
    for index, key in enumerate(SUBJECTS):
        sprite = originals[key]
        board.alpha_composite(sprite, (88 + (index % 3) * 300, 28 + (index // 3) * 292))
    board.convert("RGB").save(OUT / "consumable-art-board.jpg", quality=95)
    print(json.dumps({"generated_objects": len(SUBJECTS), "runtime_bitmaps": len(records),
                      "manifest": str(DEST / "manifest.json")}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["prepare", "generate", "compile"])
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    if args.operation == "prepare":
        prepare()
    elif args.operation == "generate":
        return generate(args.only)
    else:
        compile_art()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
