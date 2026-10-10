"""Create Sub2 scene art and publish-ready banners/posters with the original hero.

Image generation uses the user's configured native Sub2 CLI. The retained
paper spirit is extracted from its existing portrait, which also supplies the
shipped app icon; typography is composed with the existing licensed fonts.
"""
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
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps
from scipy import ndimage

from create_logo_candidates import ROOT, font, text_center, spaced_text
from publication_brand import draw_title

OUT = ROOT / "output/imagegen/incense-debt/release-promo-2026-10-08"
SKILL = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
HERO = ROOT / "game/assets/portraits/c_paper.png"
ICON = ROOT / "game/assets/ui/app-icon.png"
TAG = "v0.2.0-alpha.1"
INK, PAPER, RED, GOLD, JADE = "#171E20", "#F0DFC0", "#BC3C2F", "#E9A34B", "#9DD6BF"

COMMON = """Create original high-quality release campaign BACKGROUND ART for the
Chinese folk-mystery indie 2D action roguelite Incense Debt / 香火债.
Its established visual language is hand-printed Chinese folk woodblock art,
layered paper-cut volumes, fibrous ivory paper edges, expressive coarse soot-black
contours and only two or three flat shading values. Rich but controlled materials:
muted jade grey stone, vermilion cloth, aged bronze gold, warm amber embers and
ivory torn wish papers. The ruined temple stores unpaid wishes; red debt cords
link wishes before they burn to ash. The atmosphere is mysterious, playful and
slightly uncanny, with a strong warm/cool contrast. Illustrate an inviting
fantasy GAME world, not a realistic architectural photograph or a grim movie.
Handmade paper textures and bold readable shapes; NO glossy 3D, photorealism,
anime, cyberpunk, neon, realistic humans or blood. Architectural perspective may
be cinematic for marketing, but retain the game's woodblock/paper aesthetic.
Build a layered foreground, middle-ground shrine, and softly receding temple.
Scenery only: the APPROVED ORIGINAL PAPER-SPIRIT HERO will be composited later.
ABSOLUTELY NO characters, creatures, faces on objects, humanoid statues, logo,
letters, fake Chinese writing, calligraphy, text, numbers, title, UI, caption,
watermark, frames, multiple panels, contact sheets, icons or mockups. Wish strips
and talismans are completely blank. One clean full-bleed background illustration.
"""

JOBS = [
    dict(id="banner", size="1536x1024", output="generated-banner-background.png", prompt="""
LANDSCAPE BANNER COMPOSITION. A sweeping nocturnal paper-lantern temple courtyard,
viewed slightly low at a three-quarter angle. The LEFT 48 percent is restrained
deep soot and grey-jade mist, with only faint layered roof silhouettes and soft
paper grain; leave this area quiet for a large title. The RIGHT third contains
an ornate but readable ruined temple doorway, a pair of vermilion fabric banners,
small aged-bronze lanterns and broad jade stone steps. Keep a clear empty landing
in front of the doorway for a large foreground hero to be placed later.
Amber firelight spills from the shrine, illuminating paper fibers and muted jade.
A few thick red cords sweep through the lower foreground like broken contracts,
with a small scatter of gold embers and ivory torn paper fragments. No wildfire
or huge blast hiding the scene. A compelling diagonal from lower left to upper
right leads toward the empty hero landing. Warm amber/ivory on the right, cooler
dark jade/soot on the left. Compose major architecture, lanterns and landing
inside the CENTRAL 60 percent of image height, so a wide panoramic middle crop
retains them; top and bottom have atmosphere and disposable edge scenery.
"""),
    dict(id="poster", size="1024x1536", output="generated-poster-background.png", prompt="""
PORTRAIT RELEASE POSTER COMPOSITION. A tall mysterious ruined paper temple gate
rises from a lantern-lit courtyard. Strong vertical depth: heavy dark roof and
grey jade silhouettes recede above, two broad ancient columns frame the sides,
warm bronze lanterns and torn vermilion banners frame the lower middle.
The TOP 30 percent is quiet deep charcoal-jade incense haze with sparse distant
roofs, intentionally clear for a large headline. A subdued warm arch occupies
the middle background; leave its central front unobstructed for the original
hero to be composited later. The lower half shows broad paper-edged stone steps,
low aged-bronze vessels at the sides, scattered gold coins and blank wish papers.
Two thick vermilion debt cords curl from the lower left/right toward the center;
one cord visibly breaks into a modest ember spray. The CENTRAL hero landing at
55 to 85 percent of image height is EMPTY and readable. The lowest 10 percent
is dark paper-textured stone to support a small typeset release footer.
An evocative amber rim glow around the central shrine, pale paper scraps floating
in smoky depth, and restrained warm fire motes. Keep the center darker than the
ivory hero that will be added. Beautiful narrative game key art, large shapes,
bold dry-ink contours, subtle print grain. No writing anywhere on architecture.
"""),
]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare():
    (OUT / "prompts").mkdir(parents=True, exist_ok=True)
    (OUT / "layers").mkdir(exist_ok=True)
    (OUT / "licenses").mkdir(exist_ok=True)
    for name in ["SmileySans-OFL.txt", "ResourceHanRounded-OFL.txt", "OFL.txt"]:
        shutil.copyfile(ROOT / "game/assets/fonts" / name, OUT / "licenses" / name)
    for job in JOBS:
        (OUT / "prompts" / (job["id"] + ".txt")).write_text(COMMON + job["prompt"], encoding="utf-8")


def generate(job):
    path = OUT / job["output"]
    if not path.exists():
        for attempt in range(1, 4):
            print(f"Sub2 {job['id']}: generation attempt {attempt}/3 with gpt-image-2.5 high", flush=True)
            result = subprocess.run([
                sys.executable, "-X", "utf8", str(SKILL), "generate", "--prompt-file",
                str(OUT / "prompts" / (job["id"] + ".txt")), "--model", "gpt-image-2.5",
                "--quality", "high", "--size", job["size"], "--background", "opaque",
                "--output-format", "png", "--out", str(path),
            ], cwd=ROOT, capture_output=True, timeout=600, creationflags=subprocess.CREATE_NO_WINDOW)
            output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
            safe = re.sub(r"sk-[A-Za-z0-9_-]+", "[redacted]", output)
            safe = re.sub(r"(?i)(authorization\s*:\s*bearer\s+)\S+", r"\1[redacted]", safe)
            (OUT / f"{job['id']}-attempt-{attempt}.log").write_text(safe, encoding="utf-8")
            if result.returncode == 0:
                break
            print(safe.strip(), flush=True)
            if attempt == 3 or not re.search(r"502|503|504|temporarily|timeout|timed out", safe, re.I):
                raise RuntimeError("The configured Sub2 generation failed: " + job["id"])
            time.sleep(attempt * 3)
    with Image.open(path) as im:
        im.load()
        # The gateway may return a fitted wide size, such as 1916x821.
        # Validate actual resolution and composition rather than its short edge alone.
        assert min(im.size) >= 768 and im.width * im.height >= 1024 * 1024, "Generated scene resolution is too low"
        if job["id"] == "banner":
            assert im.width > im.height
        else:
            assert im.height > im.width
        record = dict(id=job["id"], requested_size=job["size"], path=path.relative_to(ROOT).as_posix(),
                      size=list(im.size), mode=im.mode, sha256=sha(path))
    print("Generated and verified: " + job["id"], flush=True)
    return record


def original_hero():
    original = Image.open(HERO).convert("RGBA")
    app = Image.open(ICON).convert("RGBA")
    expected = original.crop((68, 58, 400, 390)).resize((512, 512), Image.Resampling.LANCZOS)
    assert np.array_equal(np.asarray(expected), np.asarray(app)), "Portrait is not the current icon source"
    rgb = np.asarray(original)[:, :, :3]
    light_paper = ((rgb.min(axis=2) > 110) & (rgb.max(axis=2) > 170) &
                   (rgb.max(axis=2).astype(int) - rgb.min(axis=2) < 100))
    # Close two-pixel breaks in dry-ink outlines before flooding the pale backdrop.
    # This retains the ivory cloak tail as well as the folded face.
    enclosed_ink = ndimage.binary_closing(~light_paper, iterations=2)
    labels, _ = ndimage.label(~enclosed_ink)
    boundary = np.unique(np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]]))
    boundary = boundary[boundary != 0]
    background = np.isin(labels, boundary)
    keep = ~background
    components, count = ndimage.label(keep)
    sizes = np.bincount(components.ravel())
    keep &= sizes[components] > 18
    # This closed face region must stay opaque; no identity pixels are painted.
    assert np.mean(keep[150:235, 190:300]) > .985, "Background extraction leaked into the original face"
    assert np.mean(keep[373:389, 133:144]) > .95, "Background extraction leaked into the ivory cloak tail"
    rgba = np.asarray(original).copy()
    rgba[:, :, 3] = keep.astype(np.uint8) * 255
    cutout = Image.fromarray(rgba)
    assert np.array_equal(np.asarray(cutout)[:, :, :3], rgb)
    cutout.save(OUT / "layers/original-paper-spirit.png")
    return cutout.crop(cutout.getchannel("A").getbbox())


def scene(job, size):
    image = Image.open(OUT / job["output"]).convert("RGB")
    if job["id"] == "banner":
        # Exclude the generated lintel engraving instead of including pseudo-writing.
        image = image.crop((0, 180, image.width, image.height))
    return ImageOps.fit(image, size, Image.Resampling.LANCZOS,
                        centering=(.5, .54 if job["id"] == "banner" else .5)).convert("RGBA")


def scrim(size, kind):
    w, h = size
    if kind == "banner":
        x = np.linspace(0, 1, w)
        strength = np.clip((.70 - x) / .35, 0, 1) * .72
        values = np.broadcast_to(strength, (h, w))
    else:
        y = np.linspace(0, 1, h)
        top = np.clip((.38 - y) / .25, 0, 1) * .56
        values = np.broadcast_to(top[:, None], (h, w))
    layer = Image.new("RGBA", size, INK)
    layer.putalpha(Image.fromarray((values * 255).astype("uint8")))
    return layer


def hero_layer(size, hero, kind):
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    height = 935 if kind == "banner" else 1550
    subject = hero.resize((round(hero.width * height / hero.height), height), Image.Resampling.LANCZOS)
    x = round(w * (.773 if kind == "banner" else .535) - subject.width / 2)
    y = 95 if kind == "banner" else 1220
    ground = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    gd.ellipse((x + subject.width * .16, y + height - 30,
                x + subject.width * .9, y + height + 44), fill=(10, 13, 12, 180))
    layer.alpha_composite(ground.filter(ImageFilter.GaussianBlur(22)))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gx, gy = x + subject.width * .72, y + height * .60
    gd.ellipse((gx - 180, gy - 190, gx + 180, gy + 190), fill=(232, 152, 67, 72))
    layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(75)))
    layer.alpha_composite(subject, (x, y))
    return layer


def pill(draw, box, text, size, color):
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=(23, 36, 33, 230), outline=color, width=2)
    face = font("NotoSansSC.ttf", size)
    bounds = draw.textbbox((0, 0), text, font=face)
    y = (box[1] + box[3] - (bounds[3] - bounds[1])) / 2
    text_center(draw, (box[0] + box[2]) / 2, y, text, face, color)


def titles(size, kind):
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if kind == "banner":
        draw_title(d, 644, 346, 347)
    else:
        draw_title(d, w / 2, 443, 575)
    return layer


def render(hero):
    outputs = []
    for job, size in zip(JOBS, [(2560, 1080), (2160, 3240)]):
        kind = job["id"]
        bg = scene(job, size)
        overlay = scrim(size, kind)
        actor = hero_layer(size, hero, kind)
        lettering = titles(size, kind)
        for name, image in [("background", bg), ("shade", overlay), ("character", actor), ("typography", lettering)]:
            image.save(OUT / "layers" / f"{kind}-{name}.png")
        result = Image.alpha_composite(bg, overlay)
        result.alpha_composite(actor)
        result.alpha_composite(lettering)
        result = result.convert("RGB")
        base = f"IncenseDebt-{kind}-{size[0]}x{size[1]}"
        result.save(OUT / (base + ".png"), dpi=(300, 300))
        result.save(OUT / (base + ".jpg"), quality=95, subsampling=0, dpi=(300, 300))
        result.save(OUT / (base + ".webp"), quality=94, method=6)
        preview = result.copy()
        preview.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
        preview.save(OUT / (kind + "-preview.png"))
        outputs.append(dict(kind=kind, primary=(OUT / (base + ".png")).relative_to(ROOT).as_posix(), size=list(size)))
    brand = ROOT / "output/branding/incense-debt/current-paper-spirit"
    shutil.copyfile(brand / "logo-title-only-1024.png", OUT / "IncenseDebt-logo-1024.png")
    shutil.copyfile(brand / "app-icon-1024.png", OUT / "IncenseDebt-app-icon-1024.png")
    return outputs


def record(outputs):
    files = []
    for path in sorted(OUT.rglob("*")):
        if path.suffix not in {".png", ".jpg", ".webp"}: continue
        if "review" in path.relative_to(OUT).parts: continue
        with Image.open(path) as im:
            im.load()
            files.append(dict(path=path.relative_to(ROOT).as_posix(), dimensions=list(im.size),
                              mode=im.mode, bytes=path.stat().st_size, sha256=sha(path)))
    report = dict(tag=TAG, original_hero=HERO.relative_to(ROOT).as_posix(), original_hero_sha256=sha(HERO),
                  original_icon=ICON.relative_to(ROOT).as_posix(), original_icon_sha256=sha(ICON),
                  title_logo="IncenseDebt-logo-1024.png", title_logo_sha256=sha(OUT / "IncenseDebt-logo-1024.png"),
                  identity="Original portrait RGB retained for the icon and campaign hero; logos contain title text only",
                  publication_rules=dict(icon_background="opaque", logo_background="transparent", allowed_visible_text=["香火债"]),
                  outputs=outputs, files=files, typography=["Smiley Sans"])
    (OUT / "media-manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    guide = """# 香火债 / Incense Debt · 发布 Banner 与海报

2026-10-08。当前发布版本：v0.2.0-alpha.1。

主角直接取自当前游戏的纸偶肖像，保留原图脸、椭圆眼、红绳、红衣、铜香炉与木版纹理。图标为不透明的纸偶方图；LOGO 为透明的纯“香火债”中文字标。场景背景由指定 Sub2API / gpt-image-2.5 / high 生成，中文字标采用已有授权字体精确排版。

## 横版 Banner

2560×1080px，适合发布页头图、官网首屏和宽幅宣传。左侧仅“香火债”标题，右侧同源纸偶；玉灰庙宇、朱绳、纸灯和香火余烬连接两侧。背景裁切排除了门楣上类似铭文的图案。

![横版 Banner](banner-preview.png)

## 竖版海报

2160×3240px，2:3 构图，300dpi 元数据。顶部仅“香火债”标题，完整纸偶居中，庙门与灯火形成纵向舞台；没有标语、玩法、平台、版本或英文副标题。按 300dpi 对应约 18.3×27.4cm；文件为 RGB。

![竖版海报](poster-preview.png)

两种主图均提供 PNG、JPG、WebP；layers/ 保存背景、遮罩、纸偶、标题分层 PNG 与原始纸偶抠图，prompts/ 保存实际背景请求。仅标题文字层参与成稿；游戏 LOGO 和应用图标分开交付。

## 文件与排版规格

| 内容 | 主文件 | 配套文件 |
| --- | --- | --- |
| 应用图标 | IncenseDebt-app-icon-1024.png | 1024×1024，RGB，不透明背景 |
| 正式 LOGO | IncenseDebt-logo-1024.png | 1024×1024，RGBA，透明背景，仅“香火债” |
| 横版 Banner | IncenseDebt-banner-2560x1080.png | 同名 JPG、WebP；banner-preview.png |
| 竖版海报 | IncenseDebt-poster-2160x3240.png | 同名 JPG、WebP；poster-preview.png |
| 可编辑分层 | layers/banner-*.png、layers/poster-*.png | 背景、阅读遮罩、角色、文字四层；另有原始纸偶透明抠图 |

Banner 以左侧标题、右侧完整纸偶安排构图；海报以顶部标题、中段完整角色与灯火纵深安排构图。画面中的唯一文字是游戏名“香火债”。预览图与所有 PNG/JPG/WebP 成稿采用同一规则。

字标使用得意黑 Smiley Sans；字体沿用工程中已有的授权文件，许可证保存在 licenses/。配色为煤墨 #171E20、纸米 #F0DFC0、朱红 #BC3C2F、香火金 #E9A34B、灰玉 #9DD6BF；庙宇、红绳、空白愿纸和余烬来自既有世界设定。

背景源图的实际尺寸分别为 1916×821 和 1024×1536；输出图在最终排版时统一缩放到交付尺寸。纸偶保留原始肖像 RGB，仅提取透明轮廓，并保留折纸披片。中文文字由字体排版，背景生成不承担文字绘制。生成请求、源图尺寸和哈希记录在 generation-report.json；成品与来源记录在 media-manifest.json。

发布图片不含宣传语、玩法短语、英文名、平台字样、版本标识或水印。版本与玩法说明保留在发布页的文字栏，不叠入图片。

IncenseDebt-publishing-artwork.zip 收录上述素材、原始背景、分层、提示词与清单；安装包单独交付，完整交付索引见 release-delivery-index.json 与 docs/incense-debt/29-release-promo-assets.md。

## English

The 2560×1080 banner and 2160×3240 poster retain the approved paper spirit. Their only lettering is 香火债. The separate logo is a genuine transparent title-only PNG; the application icon is fully opaque. PNG, JPG, WebP and editable layers are included.
"""
    (OUT / "README.md").write_text(guide, encoding="utf-8")


def delivery_index():
    manifest = json.loads((ROOT / "build/delivery-manifest.json").read_text("utf-8"))
    files = []
    for entry in manifest["files"]:
        if Path(entry["path"]).suffix not in {".exe", ".apk"}: continue
        path = ROOT / entry["path"]
        assert path.is_file() and path.stat().st_size == entry["bytes"]
        files.append(dict(kind="Windows executable" if path.suffix == ".exe" else "Android APK",
                          absolute_path=path.as_posix(), relative_path=entry["path"], bytes=entry["bytes"],
                          sha256=entry["sha256"], specification="Windows x64" if path.suffix == ".exe" else "Android arm64 / debug signed"))
    for kind, name in [("game icon", "IncenseDebt-app-icon-1024.png"),
                       ("LOGO", "IncenseDebt-logo-1024.png"),
                       ("banner", "IncenseDebt-banner-2560x1080.png"),
                       ("poster", "IncenseDebt-poster-2160x3240.png")]:
        path = OUT / name
        with Image.open(path) as im:
            im.load()
            files.append(dict(kind=kind, absolute_path=path.as_posix(), relative_path=path.relative_to(ROOT).as_posix(),
                              bytes=path.stat().st_size, sha256=sha(path), dimensions=list(im.size), format="PNG / " + im.mode))
    report = dict(tag=TAG, release_url="https://github.com/wikigsroom/joss-debt/releases/tag/" + TAG,
                  binary_sha256_source="build/delivery-manifest.json", files=files)
    (OUT / "release-delivery-index.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    return report


def package_artwork():
    archive = OUT / "IncenseDebt-publishing-artwork.zip"
    members = [path for path in OUT.rglob("*") if path.is_file()
               and path.suffix in {".png", ".jpg", ".webp", ".json", ".md", ".txt"}
               and "review" not in path.relative_to(OUT).parts]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(members):
            bundle.write(path, "IncenseDebt-publishing-artwork/" + path.relative_to(OUT).as_posix())
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None, "Artwork archive failed CRC verification"
    return dict(path=str(archive), bytes=archive.stat().st_size, sha256=sha(archive), entries=len(members))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    prepare()
    if args.generate:
        records, failures = [], []
        with ThreadPoolExecutor(max_workers=2) as pool:
            jobs = {pool.submit(generate, job): job["id"] for job in JOBS}
            for task in as_completed(jobs):
                try:
                    records.append(task.result())
                except Exception as error:
                    failures.append(dict(id=jobs[task], error=type(error).__name__ + ": " + str(error)))
                    print(type(error).__name__ + ": " + str(error), flush=True)
        (OUT / "generation-report.json").write_text(json.dumps(dict(provider="sub2-image-gen", model="gpt-image-2.5",
            quality="high", records=records, failures=failures), ensure_ascii=False, indent=2) + "\n", "utf-8")
        if failures: raise SystemExit(1)
    hero = original_hero()
    outputs = render(hero)
    record(outputs)
    delivery_index()
    archive = package_artwork()
    print(json.dumps(dict(output_directory=str(OUT), generated_backgrounds=2, products=outputs, archive=archive), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
