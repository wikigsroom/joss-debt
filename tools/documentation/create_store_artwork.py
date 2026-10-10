"""Generate five themed campaign backgrounds with Sub2 and retain the original hero."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from create_logo_candidates import ROOT, font, text_center, spaced_text
from publication_brand import draw_title

KIT = ROOT / "output/publishing/incense-debt/store-kit-2026-10-08"
SOURCE = ROOT / "output/imagegen/incense-debt/store-campaign-2026-10-08"
PREVIOUS = ROOT / "output/imagegen/incense-debt/release-promo-2026-10-08"
CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
INK, PAPER, RED, GOLD, JADE = "#171E20", "#F0DFC0", "#BC3C2F", "#E9A34B", "#9DD6BF"

JOBS = [
    {"id": "01-lantern", "biome": "m01", "theme": "灯市后巷", "color": "#E9A34B",
     "headline": ["一愿未还", "百债成灰"], "detail": "纸墨奇谭 · 房间动作肉鸽",
     "scene": "MIDNIGHT LANTERN MARKET. Glowing vermilion and saturated honey amber against dark aubergine shadows. Crowded timber storefronts, scalloped red awnings, zigzag strings of round paper lanterns, deep cherry-wood plank paths with worn pale seams. A lantern maker's old night street climbing toward an ancient shrine. Strong inviting amber light on the right, quiet soot/aubergine depth on the left. Red debt cords with a few embers wind along the planks; thick blank wish paper fragments drift. Distinct urban wood architecture, NO generic stone courtyard."},
    {"id": "02-river", "biome": "m02", "theme": "纸渡河埠", "color": "#86DFE8",
     "headline": ["每一扇门", "都是一笔旧账"], "detail": "十一层探索 · 二十套环境主题",
     "scene": "BLUE PAPER FERRY RIVER. Deep indigo water, sea-teal timber, luminous cold cyan reflections. Weathered blue-green wooden dock planks, mooring posts, taut dock ropes, folded ivory PAPER FERRY BOATS, floating piers and an old ferry pavilion at the far right. Water visible on every edge. Moonlit river and fog recede on the quiet left. One modest vermilion lantern casts an amber pool onto the empty hero landing on the right; red debt cord follows the pier. Cold BLUE identity, NO stone courtyard, NO ordinary warm temple."},
    {"id": "03-treasury", "biome": "m03", "theme": "铜钱旧库", "color": "#EAC270",
     "background": "03-treasury-no-text-background.png", "prompt": "03-treasury-no-text.txt",
     "headline": ["让每一发", "都有自己的打法"], "detail": "器具 × 技能 × 供物 · 自由组合",
     "scene": "GOLDEN COIN TREASURY. Ochre gold, dark chocolate wood and aged golden brass dominate. A forgotten wooden treasury with massive stacked brass cash coins, coin-bundles on shelves, bronze lock plates, patterned gilded floor tiles, a small furnace-like incense brazier at the far right. Gold floor dominant; dark chocolate shadow and stacked coin silhouettes on the quiet left. Red debt strings twist between old account boxes; blank torn ivory papers hover in amber incense. Bold GOLDEN-YELLOW identity, material weight without shiny photorealism. CRITICAL: all coins have COMPLETELY PLAIN smooth faces with only a square hole and a simple round rim. NO coin inscriptions, stamps, characters, glyphs, symbols resembling lettering or embossed writing. All hanging cloth, pillars, boxes, floor tiles and plaques are also completely blank; use only paper fibers, wood grain and plain geometric material shapes. No writing anywhere in the scene."},
    {"id": "04-opera", "biome": "m06", "theme": "赤绫戏楼", "color": "#E5A1CC",
     "headline": ["借来的火", "总要还"], "detail": "商店 · 献灯 · 判官 · 观音 · 债约",
     "scene": "PLUM PAPER OPERA THEATRE. Saturated magenta, mulberry purple, rose silk, dark charcoal stage wood. An abandoned traditional opera stage with sweeping plum-red cloth drapes, lacquered wooden balconies, hanging rose paper lanterns and an empty charcoal stage apron on the right. Faint balcony silhouettes and velvety purple haze on the quiet left. Red debt cords curl like stage rigging. Warm amber footlights along the right side, a few blank paper wishes floating. Clear MAGENTA/PURPLE theatrical identity, NO people or masks, NO face-shaped decorations."},
    {"id": "05-celestial", "biome": "m20", "theme": "万愿天穹", "color": "#CCB8F1",
     "headline": ["把名字", "从总账里带回来"], "detail": "六名还愿人 · 十一重旧账",
     "scene": "COSMIC LEDGER VOID. Midnight violet, starlight gold and pale lavender. Great torn ivory ledger leaves, all BLANK, float as broad paper islands in a layered celestial void. Tiny gold starlight and pale lavender cloud-ink show the vast depth. A broken circular golden ledger seal curves behind the empty hero landing on the right. Red debt cords lead between floating blank paper islands, some fraying into warm ember motes. Quiet violet space and distant paper silhouettes on the left. A readable flat dark-violet paper landing on the lower right. This is the final COSMIC theme, never an ordinary temple or astronomy photograph."},
]

COMMON = """Create one original, polished 16:9 landscape marketing BACKGROUND for the
Chinese folk-mystery 2D action roguelite Incense Debt / 香火债. Preserve the established
game art language: handmade Chinese woodblock printing, layered paper-cut planes,+fibrous ivory edges, coarse soot-black outlines, dry pigment and only two or three
flat shadow values. Ink, paper, aged bronze, red cords and amber incense fire.
Mystery and charm together, readable bold silhouettes, paper texture throughout.
Three-quarter cinematic scenery for game key art, not a gameplay screenshot.
One coherent scene, full bleed; NO UI or contact sheet.
COMPOSITION: left 42 percent remains restrained and quiet for typeset title and
only the Chinese game title later. The right third has the main landmark and a clear foreground
landing for the approved original paper spirit to be composited later. That hero
is already fixed; do not invent or draw it. Midground detail stays secondary.
NO characters, enemies, humans, faces, humanoid statues, portrait, mascot, writing,
letters, digits, calligraphy, logo, title, fake glyphs, interface or watermarks.
All wish papers, signs and ledger pages are completely blank. No photorealism,
glossy 3D, smooth anime, generic neon or blood. No Western cathedral.
""".replace("\\+", "")


def sha(path):
    with path.open("rb") as f: return hashlib.file_digest(f, "sha256").hexdigest()


def prepare():
    (SOURCE / "prompts").mkdir(parents=True, exist_ok=True)
    (KIT / "artwork").mkdir(parents=True, exist_ok=True)
    (KIT / "previews").mkdir(exist_ok=True)
    for job in JOBS:
        prompt = SOURCE / "prompts" / job.get("prompt", job["id"] + ".txt")
        if not prompt.exists():
            prompt.write_text(COMMON + "\n" + job["scene"], "utf-8")


def generate(job):
    path = SOURCE / job.get("background", job["id"] + "-background.png")
    if not path.exists():
        for attempt in range(1, 4):
            print(f"Sub2 {job['theme']}: gpt-image-2.5 / high, attempt {attempt}/3", flush=True)
            result = subprocess.run([sys.executable, "-X", "utf8", str(CLI), "generate", "--model", "gpt-image-2.5",
                "--quality", "high", "--size", "1536x1024", "--background", "opaque", "--output-format", "png",
                "--prompt-file", str(SOURCE / "prompts" / job.get("prompt", job["id"] + ".txt")), "--out", str(path)],
                cwd=ROOT, capture_output=True, timeout=600, creationflags=subprocess.CREATE_NO_WINDOW)
            text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
            text = re.sub(r"sk-[A-Za-z0-9_-]+", "[redacted]", text)
            text = re.sub(r"(?i)(authorization\s*:\s*bearer\s+)\S+", r"\1[redacted]", text)
            (SOURCE / f"{job['id']}-attempt-{attempt}.log").write_text(text, "utf-8")
            if result.returncode == 0: break
            print(text.strip(), flush=True)
            if attempt == 3 or not re.search(r"502|503|504|temporarily|timeout|timed out", text, re.I):
                raise RuntimeError("Sub2 generation failed: " + job["id"])
            time.sleep(attempt * 3)
    with Image.open(path) as im:
        im.load()
        assert im.width > im.height and min(im.size) >= 768 and im.width * im.height >= 1048576
        entry = dict(id=job["id"], biome=job["biome"], theme=job["theme"], requested_size="1536x1024",
                     dimensions=list(im.size), file=path.relative_to(ROOT).as_posix(), sha256=sha(path))
    print("Scene generated: " + job["theme"], flush=True)
    return entry


def hero():
    path = PREVIOUS / "layers/original-paper-spirit.png"
    im = Image.open(path).convert("RGBA")
    original = Image.open(ROOT / "game/assets/portraits/c_paper.png").convert("RGBA")
    assert np.array_equal(np.asarray(im)[:, :, :3], np.asarray(original)[:, :, :3])
    return im.crop(im.getchannel("A").getbbox())


def background(path, size):
    return ImageOps.fit(Image.open(path).convert("RGB"), size, Image.Resampling.LANCZOS).convert("RGBA")


def shade(im, strength=.72):
    w, h = im.size
    ramp = np.clip((.66 - np.linspace(0, 1, w)) / .4, 0, 1) * strength
    mask = Image.fromarray(np.broadcast_to((ramp * 255).astype(np.uint8), (h, w)).copy())
    overlay = Image.new("RGBA", im.size, INK)
    overlay.putalpha(mask)
    im.alpha_composite(overlay)


def add_hero(im, center=.785, height_ratio=.84, y_ratio=.095):
    actor = hero()
    height = round(im.height * height_ratio)
    actor = actor.resize((round(actor.width * height / actor.height), height), Image.Resampling.LANCZOS)
    x = round(im.width * center - actor.width / 2)
    y = round(im.height * y_ratio)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((x + actor.width * .15, y + height - 22, x + actor.width * .90, y + height + 38), fill=(4, 10, 9, 170))
    im.alpha_composite(layer.filter(ImageFilter.GaussianBlur(max(14, im.width // 110))))
    im.alpha_composite(actor, (x, y))


def brand(draw, x, y, size):
    face = font("SmileySans-Oblique.ttf", size)
    box = draw.textbbox((0, 0), "香火债", font=face)
    width = box[2] - box[0]
    draw_title(draw, x + width / 2, y, size)


def export(image, basename, folder="artwork"):
    path = KIT / folder / basename
    im = image.convert("RGB")
    im.save(path.with_suffix(".png"), dpi=(300, 300))
    im.save(path.with_suffix(".jpg"), quality=95, subsampling=0, dpi=(300, 300))
    im.save(path.with_suffix(".webp"), quality=94, method=6)
    return path.with_suffix(".png")


def promo(job, clean=False):
    im = background(SOURCE / job.get("background", job["id"] + "-background.png"), (1920, 1080))
    shade(im, .50)
    add_hero(im)
    if clean: return im
    d = ImageDraw.Draw(im)
    brand(d, 108, 380, 248)
    return im


def render():
    paths = []
    for job in JOBS:
        paths.append(export(promo(job), "promo-" + job["id"] + "-1920x1080"))
    paths.append(export(promo(JOBS[0], True), "promo-no-logo-1920x1080"))
    wide = background(SOURCE / "01-lantern-background.png", (1920, 1080))
    shade(wide, .58)
    add_hero(wide, center=.767)
    d = ImageDraw.Draw(wide)
    brand(d, 125, 348, 272)
    paths.append(export(wide, "cover-horizontal-1920x1080"))
    tall = background(PREVIOUS / "generated-poster-background.png", (1080, 1920))
    darkness = Image.new("RGBA", tall.size, (23, 30, 32, 90))
    tall.alpha_composite(darkness)
    add_hero(tall, center=.52, height_ratio=.51, y_ratio=.41)
    d = ImageDraw.Draw(tall)
    draw_title(d, 540, 295, 283)
    paths.append(export(tall, "cover-vertical-1080x1920"))
    from create_library_wallpaper import render_library_wallpaper
    paths.append(render_library_wallpaper())
    build_preview(paths)
    write_artwork_manifest()
    print(json.dumps(dict(artwork_items=len(paths), primary_files=[p.as_posix() for p in paths]), ensure_ascii=False), flush=True)


def write_artwork_manifest():
    manifest = []
    for path in sorted((KIT / "artwork").glob("*")):
        if path.suffix not in {".png", ".jpg", ".webp"}: continue
        with Image.open(path) as im:
            manifest.append(dict(file=path.relative_to(ROOT).as_posix(), dimensions=list(im.size), bytes=path.stat().st_size, sha256=sha(path)))
    (KIT / "artwork/artwork-manifest.json").write_text(json.dumps(dict(original_hero="game/assets/portraits/c_paper.png",
        original_hero_sha256=sha(ROOT / "game/assets/portraits/c_paper.png"), identity="Original portrait RGB retained",
        publication_rules=dict(allowed_visible_text=["香火债"], no_logo_images="no text"), files=manifest), ensure_ascii=False, indent=2) + "\n", "utf-8")


def build_preview(paths):
    canvas = Image.new("RGB", (1600, 1580), INK)
    d = ImageDraw.Draw(canvas)
    for i, path in enumerate(paths[:5]):
        x, y = 52 + (i % 2) * 770, 124 + (i // 2) * 470
        pic = Image.open(path).convert("RGB").resize((726, 409), Image.Resampling.LANCZOS)
        canvas.paste(pic, (x, y))
    canvas.save(KIT / "previews/five-promos-preview.jpg", quality=94)
    cover = Image.new("RGB", (1600, 1400), INK)
    d = ImageDraw.Draw(cover)
    for name, rect, caption in [
        ("cover-horizontal-1920x1080.png", (50, 114, 982, 638), "横版封面  ·  1920 × 1080"),
        ("library-wallpaper-no-logo-5120x1654.png", (50, 702, 982, 1003), "游戏库壁纸  ·  5120 × 1654  ·  无字"),
        ("promo-no-logo-1920x1080.png", (1064, 1040, 1542, 1309), "无 LOGO / 无文字宣传图"),
        ("cover-vertical-1080x1920.png", (1064, 114, 1542, 964), "竖版封面  ·  1080 × 1920")]:
        pic = Image.open(KIT / "artwork" / name).convert("RGB").resize((rect[2]-rect[0],rect[3]-rect[1]),Image.Resampling.LANCZOS)
        cover.paste(pic, (rect[0], rect[1]))
    cover.save(KIT / "previews/covers-wallpaper-preview.jpg",quality=94)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    prepare()
    if args.generate:
        records, errors = [], []
        with ThreadPoolExecutor(max_workers=2) as pool:
            jobs = {pool.submit(generate, j): j["id"] for j in JOBS}
            for future in as_completed(jobs):
                try: records.append(future.result())
                except Exception as error:
                    errors.append(dict(id=jobs[future], error=type(error).__name__ + ": " + str(error)))
                    print(errors[-1]["error"], flush=True)
        (SOURCE / "generation-manifest.json").write_text(json.dumps(dict(provider="sub2-image-gen", model="gpt-image-2.5", quality="high",
            records=records, failures=errors), ensure_ascii=False, indent=2) + "\n", "utf-8")
        if errors: raise SystemExit(1)
    render()


if __name__ == "__main__": main()
