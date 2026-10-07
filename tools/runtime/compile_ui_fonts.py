"""Subset rounded fonts, preserving credits/OFL and supplying a full-CJK runtime fallback."""
from pathlib import Path
import hashlib
import json
import shutil
from fontTools.ttLib import TTFont
from fontTools import subset
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "game/assets/fonts"
CACHE = ROOT / ".local-tools/fonts"
REPORT = ROOT / "docs/incense-debt/reports/runtime/ui-refresh"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    characters = set(chr(x) for x in range(32, 127))
    characters.update(chr(x) for x in range(0x2000, 0x2070))
    characters.update(chr(x) for x in range(0x3000, 0x3040))
    characters.update(chr(x) for x in range(0xff00, 0xfff0))
    for a in range(0xa1, 0xf8):
        for b in range(0xa1, 0xff):
            try:
                characters.update(bytes([a, b]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    game_characters = set()
    for path in (ROOT / "game").rglob("*"):
        if ".godot" not in path.parts and path.suffix in [".gd", ".json", ".godot", ".tscn"]:
            game_characters.update(path.read_text("utf8"))
    characters.update(game_characters)
    rows = []
    for weight in ["Medium", "Bold"]:
        source = CACHE / "rounded-source" / f"ResourceHanRoundedCN-{weight}.ttf"
        target = FONTS / f"IncenseRounded-{weight}.ttf"
        font = TTFont(source, recalcTimestamp=False)
        options = subset.Options()
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        options.layout_features = ["*"]
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes={ord(c) for c in characters})
        subsetter.subset(font)
        # Subsets are derivatives: use a unique family while preserving upstream copyright.
        for record in font["name"].names:
            values = {1: "Incense Rounded", 2: weight, 3: "IncenseRounded-" + weight + "-0.990", 4: "Incense Rounded " + weight, 6: "IncenseRounded-" + weight, 16: "Incense Rounded", 17: weight}
            if record.nameID in values:
                record.string = values[record.nameID].encode(record.getEncoding())
        font.save(target)
        cmap = font.getBestCmap()
        missing = sorted(c for c in game_characters if ord(c) >= 32 and ord(c) not in cmap)
        fallback = TTFont(FONTS / "NotoSansSC.ttf").getBestCmap()
        unresolved = [c for c in missing if ord(c) not in fallback]
        rows.append({"file": str(target.relative_to(ROOT)).replace("\\", "/"), "family": "Incense Rounded", "upstream_family": "Resource Han Rounded CN", "weight": weight, "bytes": target.stat().st_size, "sha256": sha(target), "source_sha256": sha(source), "glyphs": len(cmap), "fallback_characters": missing, "unresolved_characters": unresolved, "subset": "GB2312 + game source/content + Latin/punctuation; arbitrary future wish names use Noto Sans SC fallback", "license": "SIL OFL 1.1; original credits retained; derivative family renamed"})
    source_title = next((CACHE / "smiley-source").rglob("SmileySans-Oblique.ttf"))
    target_title = FONTS / "SmileySans-Oblique.ttf"
    shutil.copyfile(source_title, target_title)
    rows.append({"file": str(target_title.relative_to(ROOT)).replace("\\", "/"), "family": "Smiley Sans Oblique", "version": "2.0.1", "bytes": target_title.stat().st_size, "sha256": sha(target_title), "source_sha256": sha(source_title), "modified": False, "license": "SIL OFL 1.1"})
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / "font-production.json").write_text(json.dumps({"fonts": rows, "fallback": "game/assets/fonts/NotoSansSC.ttf", "passed": all(not r.get("unresolved_characters") for r in rows)}, ensure_ascii=False, indent=2) + "\n", "utf8")
    image = Image.new("RGB", (1440, 540), "#171e20")
    draw = ImageDraw.Draw(image)
    for i, filename in enumerate(["NotoSansSC.ttf", "IncenseRounded-Medium.ttf", "SmileySans-Oblique.ttf"]):
        y = 30 + i * 166
        font = ImageFont.truetype(str(FONTS / filename), 36)
        small = ImageFont.truetype(str(FONTS / filename), 20)
        if filename == "NotoSansSC.ttf":
            font.set_variation_by_axes([500])
            small.set_variation_by_axes([500])
        draw.text((36, y), filename, font=small, fill="#a7b5af")
        draw.text((36, y + 36), "香火债  还愿人  纸童 / 铃师 / 灯客 / 傩面 / 伞灵 / 墨吏", font=font, fill="#edf2e7")
        draw.text((36, y + 96), "灯还燃着，账可以慢慢还。  06 / 12   100   Q / Space", font=small, fill="#ebaa75")
    image.save(REPORT / "font-comparison.png")
    print(json.dumps({"fonts": len(rows), "bytes": sum(r["bytes"] for r in rows), "glyph_fallback_verified": all(not r.get("unresolved_characters") for r in rows)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
