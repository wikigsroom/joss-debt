"""Generate five Sub2 logo symbols and compose publication review assets.

Only the configured Sub2 CLI generates artwork. Pillow performs typography,
transparent layout, resizing, and contact-sheet composition. Native Windows
processes only; no browsers, virtual machines, containers, or runtime changes.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/incense-debt/logo-release-2026-10-08"
SKILL = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
REFERENCE = ROOT / "game/assets/ui/app-icon.png"
FONTS = ROOT / "game/assets/fonts"
COMMON = """Create ONE original professional brand logo SYMBOL for the released
indie action roguelite game Incense Debt (Chinese game title 香火债).
The EXISTING brand is a charming but uncanny Chinese folded-paper spirit: an
ivory origami face with one folded triangular forehead crest, two simple solid
black vertical oval eyes, vermilion ribbon tassels, a red robe, and an aged-gold
bronze incense burner. Its art is Chinese folk woodblock / layered paper cut,
bold soot-black contours, ivory paper, vermilion red, muted bronze gold, and
occasional grey jade. The soul is a mischievous paper spirit carrying unpaid
wishes through a ruined temple; gameplay links debts with red cord then burns
them in a burst of embers. Redesign that identity into the specific direction
below. Do not simply repaint or reproduce the old whole-body illustration.
This must be a distinctive compact game BRAND MARK, not a character-sheet
illustration, scenery, banner, stock esports crest, clip art, or UI screenshot.
Bold chunky smooth contours, carefully rounded corners, strong large shapes,
two or three flat shading values, sophisticated restrained paper-cut accents,
clean negative space, very sparse texture. One dominant silhouette readable
at 48 pixels. Limit to three or four coherent colors. Present ONE centered
isolated symbol occupying about 78 percent of the square, generous transparent
margin on every side. Actual transparent background, no background tile,
no backdrop, no shadow cast onto a background, no mockup, no multiple variants.
ABSOLUTELY NO letters, Chinese characters, text, numbers, labels, watermark,
wordmark, decorative frame, tiny ornaments, glossy 3D, photorealism, metallic
rendering, anime girl, cat, fox, or borrowed game characters. Typography will
be typeset separately, so ONLY the standalone artistic symbol is requested.
"""

CONCEPTS = [
    dict(id="01-paper-spirit", number="01", title="焚愿纸偶", tagline="纸偶主角 · 最接近现有品牌",
         rationale="把现有纸童收拢成大头标志，保留折纸脸、黑眼、红结与小香炉；亲近感和角色识别最强。",
         use="主品牌、应用图标、头像、开屏",
         background="#E7D8B6", foreground="#242725", accent="#BC3C2F", font="SmileySans-Oblique.ttf",
         palette=["#E7D8B6", "#BC3C2F", "#242725", "#C39A51"],
         prompt="""DIRECTION 01 — THE HERO PAPER SPIRIT. Design a charismatic,
almost frontal mascot HEAD with a tiny compact upper-body hint, not full body.
A broad soft ivory folded-paper face; one asymmetric folded triangular crest
on the top-left, two very large soot-black oval eye holes, no mouth. Two short
vermilion knotted ribbon tassels flank the face, sculpted as thick rounded
paper-cut ribbons rather than many thin strands. Beneath the chin, two simple
ivory hands cup ONE small bold bronze-gold incense bowl; one thick vermilion
S-shaped ember curls upward from it. A small dark collar, very little robe.
The ivory FACE occupies two thirds of the design. Friendly, mysterious, playful
and confident; preserve the old mascot's paper identity with stronger icon
clarity. Rounded heavy ink outline, minimal flat fold shading, no fine facial
decoration. This direction is mascot-led, NOT a seal, medallion or shield."""),
    dict(id="02-vermilion-seal", number="02", title="朱印焚债", tagline="朱砂印章 · 图标辨识优先",
         rationale="将纸脸与焚债火焰压成朱砂印记，粗轮廓和负形在小尺寸下更清楚，东方识别直接。",
         use="桌面与移动图标、小尺寸头像、角标",
         background="#EFE5CD", foreground="#BC3C2F", accent="#242725", font="IncenseRounded-Bold.ttf",
         palette=["#BC3C2F", "#EFE5CD", "#242725"],
         prompt="""DIRECTION 02 — VERMILION DEBT SEAL. Design a powerful iconic
vermilion seal: one thick rounded-square Chinese folk-print silhouette, with
its interior carved into a VERY SIMPLE negative-space ivory paper-spirit
FACE. Two large black vertical oval eyes, a single broad folded crest on top,
and a stout three-pronged ember flame carved into the forehead. The rounded
lower cheek forms a tiny incense-bowl lip through one bold cutout. Vermilion
dominates, ivory negative shapes and black eyes only. Extremely geometric,
balanced, compact, contemporary game-brand icon. Smooth corners, thick bridges,
no detailed human body, no hanging tassel strands, no calligraphy or writing,
no real Chinese seal characters. A very slightly irregular paper-cut edge can
suggest a hand stamp, but no heavy distressed noise. The rounded square is
the actual SYMBOL itself, not a background icon tile. More emblematic and
radically simpler than the existing illustrated mascot."""),
    dict(id="03-bronze-burner", number="03", title="铜鼎回愿", tagline="铜鼎徽记 · 沉稳神秘",
         rationale="让铜香炉成为主形，把纸偶眼睛和纸焰融进炉身；适合深色启动页与发布封面。",
         use="深色开屏、发布封面、横向品牌锁定图",
         background="#202927", foreground="#E9C783", accent="#BC3C2F", font="IncenseRounded-Bold.ttf",
         palette=["#C39A51", "#E9C783", "#202927", "#BC3C2F"],
         prompt="""DIRECTION 03 — THE BRONZE WISH BURNER. Make ONE beautifully
balanced squat ancient Chinese bronze incense censer the entire brand mark.
It has a broad bowl, two large simple rounded loop handles and three short
sturdy feet. On the bowl, TWO wide soot-black oval openings subtly echo the
old paper-spirit eyes, without an actual human face or body. Above the broad
lid rise THREE thick curling ivory-and-aged-gold paper flames, with a folded
triangular paper crest embedded in the central flame and ONE small vermilion
ember dot. A strong rounded low horizontal silhouette with a proud upward
flame. Flat aged-gold and ivory shapes, strong charcoal ink outline and cutouts,
one vermilion accent. Premium Chinese folk-mystery identity, contemporary
bold game logo; engraved PAPER-CUT bronze feeling, NOT realistic polished
metal, NOT a thin-line luxury brand. No enclosing circle, crown, shield or
text. Sparse big forms so the gold burner remains readable on dark surfaces."""),
    dict(id="04-broken-cord", number="04", title="朱绳破契", tagline="断绳契印 · 强调动作爆发",
         rationale="以红绳连债、断契焚烧为记忆点，倾斜纸脸与断开的绳环让标志更有动作感。",
         use="动作宣传、视频片头、活动封面",
         background="#202927", foreground="#F0DFC0", accent="#D64B38", font="SmileySans-Oblique.ttf",
         palette=["#D64B38", "#F0DFC0", "#202927", "#E9A34B"],
         prompt="""DIRECTION 04 — BREAK THE RED DEBT CORD. Build an energetic,
diagonally tilted compact emblem of a simple folded ivory paper-spirit mask
with TWO big vertical black oval eyes and a single asymmetric origami crest.
ONE very thick vermilion cord loops around the mask in a bold imperfect circle,
with a readable chunky knot at upper left and a deliberately BROKEN section
at lower right. The two cut cord ends flare into two broad amber ember wedges,
showing an explosive break of a contract. The mask leans forward and the red
cord sweeps diagonally upward, giving action and freedom. Strong asymmetry,
large clean ivory / charcoal / vermilion shapes, amber only at the broken tips.
No full character, no incense bowl, no octagonal badge, no weapons, no many
thin strings, no letter marks. The big broken cord must be legible at icon size,
and its gap clearly visible. Crisp modern rounded woodblock silhouette."""),
    dict(id="05-jade-lantern", number="05", title="灰玉莲灯", tagline="莲灯纸灵 · 东方秘境气质",
         rationale="把纸脸、烟焰和莲灯融合成灰玉标志，保留朱砂火芯，强调世界观与安静的神秘感。",
         use="世界观主视觉、深色主题、品牌周边",
         background="#1C2827", foreground="#DAE6CA", accent="#91BCA4", font="IncenseRounded-Bold.ttf",
         palette=["#91BCA4", "#53675C", "#E7D8B6", "#BC3C2F"],
         prompt="""DIRECTION 05 — THE JADE PAPER SOUL LANTERN. Design a calm but
mysterious brand emblem: a large ivory folded-paper spirit FACE, with two
charcoal vertical oval eyes and one folded crest, suspended as the flame of
a stylized jade LOTUS LAMP. Under the face are exactly three large broad rounded
jade paper-cut lotus petals cupping it; a thick grey-jade smoke curl embraces
one side and finishes in a single tiny vermilion ember. The complete silhouette
is a compact round-topped teardrop lantern, softly asymmetric, combining paper
soul, incense smoke and jade shrine. Muted grey jade plus pale jade highlights,
ivory face, charcoal eyes, ONE red ember accent. Airy negative space, thick
curves, near-flat paper layering, modern rounded game branding. No actual
religious figure, many-petalled mandala, fine ornamental filigree, gold burner,
red ribbons or mascot body. Elegant uncanny folk-myth atmosphere; different
from a generic wellness or spa lotus logo because the big paper-spirit face
is the central recognizable identity."""),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    (OUT / "prompts").mkdir(parents=True, exist_ok=True)
    for option in CONCEPTS:
        (OUT / "prompts" / (option["id"] + ".txt")).write_text(
            COMMON + "\n" + option["prompt"] + "\n", encoding="utf-8")
    (OUT / "directions.json").write_text(json.dumps(CONCEPTS, ensure_ascii=False, indent=2) + "\n", "utf-8")


def generate(option):
    target = OUT / (option["id"] + "-generated.png")
    if not target.exists():
        result = subprocess.run([
            sys.executable, "-X", "utf8", str(SKILL), "generate",
            "--prompt-file", str(OUT / "prompts" / (option["id"] + ".txt")),
            "--model", "gpt-image-2.5", "--quality", "high", "--size", "1024x1024",
            "--background", "transparent", "--output-format", "png", "--out", str(target),
        ], cwd=ROOT, capture_output=True, timeout=600,
            creationflags=subprocess.CREATE_NO_WINDOW)
        (OUT / (option["id"] + ".log")).write_bytes(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"Sub2 generation failed for {option['id']}; inspect its log")
    with Image.open(target) as im:
        im.load()
        alpha = im.convert("RGBA").getchannel("A")
        if alpha.getextrema()[0] == 255:
            raise RuntimeError(f"{option['id']}: image has no transparent background")
        if min(im.size) < 1024:
            raise RuntimeError(f"{option['id']}: unexpectedly small source {im.size}")
        info = dict(id=option["id"], path=target.relative_to(ROOT).as_posix(),
                    dimensions=list(im.size), mode=im.mode, sha256=sha(target),
                    alpha_extrema=list(alpha.getextrema()))
    print("Generated and verified: " + option["id"], flush=True)
    return info


def font(name, size):
    f = ImageFont.truetype(str(FONTS / name), size)
    if name == "NotoSansSC.ttf":
        f.set_variation_by_axes([650])
    return f


def text_center(draw, x, y, text, face, fill, stroke_width=0, stroke_fill=None):
    box = draw.textbbox((0, 0), text, font=face, stroke_width=stroke_width)
    draw.text((x - (box[2] - box[0]) / 2 - box[0], y - box[1]), text,
              font=face, fill=fill, stroke_width=stroke_width, stroke_fill=stroke_fill)
    return box[3] - box[1]


def spaced_text(draw, center, y, text, face, fill, spacing=4):
    widths = [draw.textlength(ch, font=face) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = center - total / 2
    for ch, width in zip(text, widths):
        draw.text((x, y), ch, font=face, fill=fill, anchor="lt")
        x += width + spacing


def symbol(option, size=1024):
    im = Image.open(OUT / (option["id"] + "-generated.png")).convert("RGBA")
    box = im.getchannel("A").getbbox()
    im = im.crop(box)
    im.thumbnail((int(size * .82), int(size * .82)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas


def app_icon(option, size=1024, rounded=False):
    canvas = Image.new("RGBA", (size, size), option["background"])
    canvas.alpha_composite(symbol(option, size))
    if rounded:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * .22), fill=255)
        canvas.putalpha(mask)
    return canvas


def compose_option(option):
    symbol(option).save(OUT / (option["id"] + "-symbol.png"))
    icon = app_icon(option)
    icon.convert("RGB").save(OUT / (option["id"] + "-app-icon-1024.png"))
    for size in (256, 128, 64, 48, 32):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(OUT / (option["id"] + f"-app-icon-{size}.png"))

    lockup = Image.new("RGBA", (2400, 840), (0, 0, 0, 0))
    lockup.alpha_composite(symbol(option, 840), (12, 0))
    draw = ImageDraw.Draw(lockup)
    face = font(option["font"], 338)
    center = 1555
    if option["number"] in {"01", "04"}:
        text_center(draw, center + 6, 203 + 10, "香火债", face, option["accent"], stroke_width=4, stroke_fill=option["accent"])
    text_center(draw, center, 203, "香火债", face, option["foreground"])
    spaced_text(draw, center, 604, "INCENSE DEBT", font("IncenseRounded-Bold.ttf", 77), option["foreground"], 12)
    lockup.save(OUT / (option["id"] + "-lockup.png"))

    board = Image.new("RGB", (1800, 1280), "#121B1C")
    d = ImageDraw.Draw(board)
    d.text((66, 46), option["number"] + "  " + option["title"], font=font("NotoSansSC.ttf", 49), fill="#F0DFC0")
    d.text((66, 119), option["tagline"], font=font("NotoSansSC.ttf", 27), fill="#A4B5AB")
    d.rounded_rectangle((60, 193, 1740, 860), 42, fill=option["background"])
    display = lockup.resize((1600, 560), Image.Resampling.LANCZOS)
    board.paste(display, (100, 247), display)
    d.text((76, 924), "应用图标 / App icon", font=font("NotoSansSC.ttf", 29), fill="#F0DFC0")
    x = 78
    for size in (192, 128, 64, 48, 32):
        preview = app_icon(option, 1024, rounded=True).resize((size, size), Image.Resampling.LANCZOS)
        board.paste(preview, (x, 996 + (192 - size) // 2), preview)
        text_center(d, x + size / 2, 1210, f"{size}px", font("IncenseRounded-Medium.ttf", 20), "#A4B5AB")
        x += size + 68
    d.text((1215, 954), "品牌色 / Palette", font=font("NotoSansSC.ttf", 27), fill="#F0DFC0")
    for i, color in enumerate(option["palette"]):
        px = 1215 + (i % 2) * 223
        py = 1012 + (i // 2) * 94
        d.rounded_rectangle((px, py, px + 55, py + 55), 17, fill=color, outline="#45534D", width=2)
        d.text((px + 73, py + 15), color.upper(), font=font("IncenseRounded-Medium.ttf", 20), fill="#A4B5AB")
    board.save(OUT / (option["id"] + "-brand-board.png"))


def comparison():
    canvas = Image.new("RGB", (2400, 1810), "#121B1C")
    d = ImageDraw.Draw(canvas)
    d.text((66, 42), "香火债", font=font("SmileySans-Oblique.ttf", 97), fill="#F0DFC0")
    d.text((394, 72), "INCENSE DEBT  /  5 LOGO DIRECTIONS", font=font("IncenseRounded-Bold.ttf", 33), fill="#91BCA4")
    d.text((67, 163), "发布 Logo 选型    折纸 / 朱砂 / 铜器 / 绳结 / 灰玉", font=font("NotoSansSC.ttf", 31), fill="#A4B5AB")
    for i, option in enumerate(CONCEPTS):
        x = 60 + (i % 3) * 770
        y = 245 + (i // 3) * 754
        d.rounded_rectangle((x, y, x + 740, y + 720), 38, fill="#202B2D")
        d.text((x + 29, y + 22), option["number"], font=font("IncenseRounded-Bold.ttf", 41), fill="#D64B38" if i in (0, 1) else "#91BCA4")
        d.text((x + 112, y + 25), option["title"], font=font("NotoSansSC.ttf", 36), fill="#F0DFC0")
        preview = app_icon(option, 1024, rounded=True).resize((378, 378), Image.Resampling.LANCZOS)
        canvas.paste(preview, (x + 181, y + 103), preview)
        face = font(option["font"], 112)
        if option["number"] in {"01", "04"}:
            text_center(d, x + 374, y + 510, "香火债", face, option["accent"])
        text_center(d, x + 370, y + 505, "香火债", face, "#F0DFC0" if i != 2 else "#E9C783")
        spaced_text(d, x + 370, y + 637, "INCENSE DEBT", font("IncenseRounded-Bold.ttf", 21), "#A4B5AB", 4)
        for k, color in enumerate(option["palette"]):
            cx = x + 660 + (k % 2) * 28
            cy = y + 640 + (k // 2) * 28
            d.ellipse((cx, cy, cx + 18, cy + 18), fill=color)
    x, y = 1600, 999
    d.rounded_rectangle((x, y, x + 740, y + 720), 38, fill="#192324", outline="#35433E", width=3)
    d.text((x + 31, y + 27), "当前 Logo · 对照", font=font("NotoSansSC.ttf", 36), fill="#A4B5AB")
    old = Image.open(REFERENCE).convert("RGB").resize((378, 378), Image.Resampling.LANCZOS)
    mask = Image.new("L", old.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 377, 377), 82, fill=255)
    canvas.paste(old, (x + 181, y + 103), mask)
    text_center(d, x + 370, y + 518, "保留纸偶身份", font("NotoSansSC.ttf", 38), "#A4B5AB")
    text_center(d, x + 370, y + 590, "加强轮廓与小尺寸辨识", font("NotoSansSC.ttf", 27), "#A4B5AB")
    d.text((66, 1751), "每案另附透明图形、透明中英组合、1024px 应用图标与缩小预览。", font=font("NotoSansSC.ttf", 24), fill="#A4B5AB")
    canvas.save(OUT / "five-logo-comparison.png")


def document():
    text = "# 香火债 / Incense Debt · 发布 Logo 五案\n\n"
    text += "日期：2026-10-08。以当前折纸脸、椭圆黑眼、红绳和铜香炉为来源，保留中式纸扎 / 木版气质，针对发布图标与品牌锁定图重新构建。\n\n"
    text += "![五案与现有 Logo 对照](five-logo-comparison.png)\n\n"
    text += "| 编号 | 方向 | 特征 | 优先用途 |\n| --- | --- | --- | --- |\n"
    for c in CONCEPTS:
        text += f"| {c['number']} | {c['title']} | {c['rationale']} | {c['use']} |\n"
    text += "\n选型建议：01 最贴近当前角色，适合主品牌；02 轮廓最简洁，适合小图标；03 偏铜器秘境；04 突出连债 / 焚债动作；05 偏灰玉庙宇氛围。\n\n"
    text += "每案的 `*-generated.png` 是 Sub2API / gpt-image-2.5 / high 实际生成原图；`*-symbol.png` 是统一留白后的 1024px 透明图形；`*-lockup.png` 是 2400×840px 透明中英组合；`*-app-icon-1024.png` 是无预切圆角的应用底图。另有 256/128/64/48/32px 预览。圆角在评审图中模拟，应用交付原图保留完整方形，避免系统裁切造成重复圆角。\n\n"
    text += "游戏名固定为 `香火债` / `INCENSE DEBT`。文字使用本游戏已有得意黑与 Incense Rounded 精确排版；说明使用 Noto Sans SC。栅格设计，没有宣称为矢量文件。当前为选型候选素材。\n\n"
    for c in CONCEPTS:
        text += f"## {c['number']} · {c['title']}\n\n{c['rationale']}\n\n![品牌组合与小尺寸预览]({c['id']}-brand-board.png)\n\n"
    text += "## English\n\nFive release-brand directions derived from the existing paper spirit, oval eyes, red knots and bronze incense burner. Real Sub2-generated artwork is composed with accurately typeset Chinese/English titles. Each option includes a transparent symbol, transparent bilingual lockup, a full-square 1024px app icon, and several reduced-size previews. Review boards simulate system corner masks; shipped app-icon source images remain square. These are raster candidates for selection.\n"
    (OUT / "README.md").write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    prepare()
    selected = [c for c in CONCEPTS if not args.only or c["id"] in args.only]
    if args.generate:
        records, failures = [], []
        with ThreadPoolExecutor(max_workers=3) as pool:
            jobs = {pool.submit(generate, c): c["id"] for c in selected}
            for job in as_completed(jobs):
                try:
                    records.append(job.result())
                except Exception as error:
                    failures.append({"id": jobs[job], "error": str(error)})
                    print(str(error), flush=True)
        report = dict(provider="sub2-image-gen", model="gpt-image-2.5", quality="high",
                      created_at=datetime.now(timezone.utc).isoformat(),
                      reference_path=REFERENCE.relative_to(ROOT).as_posix(), reference_sha256=sha(REFERENCE),
                      reference_method="Visual inspection and written identity description; configured generations CLI has no reference-image parameter",
                      records=sorted(records, key=lambda x: x["id"]), failures=failures)
        (OUT / "generation-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
        if failures:
            raise SystemExit(1)
    for c in CONCEPTS:
        if not (OUT / (c["id"] + "-generated.png")).exists():
            raise RuntimeError("Generate all five symbols before composing the comparison")
        compose_option(c)
    comparison()
    document()
    records = []
    for p in sorted(OUT.glob("*.png")):
        with Image.open(p) as im:
            records.append(dict(path=p.name, dimensions=list(im.size), mode=im.mode, bytes=p.stat().st_size, sha256=sha(p)))
    (OUT / "asset-manifest.json").write_text(json.dumps(dict(outputs=records), indent=2) + "\n", "utf-8")
    print(json.dumps(dict(comparison=str(OUT / "five-logo-comparison.png"), options=5,
                          image_outputs=len(records), guide=str(OUT / "README.md")), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
