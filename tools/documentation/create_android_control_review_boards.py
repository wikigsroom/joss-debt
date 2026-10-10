"""Arrange native QA screenshots for visual review, without generating game art."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/android-controls-current-2026-10-09"
FONT = ROOT / "game/assets/fonts/NotoSansSC.ttf"


def ui_font(size, weight=400):
    font = ImageFont.truetype(str(FONT), size)
    try:
        axes = font.get_variation_axes()
        font.set_variation_by_axes([weight if axis["name"] == b"Weight" else axis["default"] for axis in axes])
    except OSError:
        pass
    return font


def board(paths, target, columns=4, thumbnail=(320, 180)):
    font = ui_font(15)
    tw, th = thumbnail
    rows = (len(paths) + columns - 1) // columns
    image = Image.new("RGB", (columns * (tw + 12) + 12, rows * (th + 44) + 12), "#152020")
    drawing = ImageDraw.Draw(image)
    for index, path in enumerate(paths):
        x = 12 + (index % columns) * (tw + 12)
        y = 12 + (index // columns) * (th + 44)
        with Image.open(path) as source:
            thumb = ImageOps.contain(source.convert("RGB"), (tw, th))
            image.paste(thumb, (x + (tw - thumb.width) // 2, y + (th - thumb.height) // 2))
        drawing.text((x, y + th + 6), path.stem, font=font, fill="#e8eee7")
    image.save(target, quality=91)


def main():
    matrix = json.loads((REPORT / "matrix.json").read_text("utf8"))
    for entry in matrix:
        folder = REPORT / entry["fixture"]
        paths = sorted(folder.glob("*.png"))
        board(paths, REPORT / (entry["fixture"] + "-contact.jpg"))
    board(sorted((REPORT / "interaction-probes").glob("*.png")), REPORT / "interaction-contact.jpg")
    samples = [
        (REPORT / "interaction-probes/combat-with-enemies.png", "当前默认战斗布局"),
        (REPORT / "interaction-probes/floating-sticks-overlap.png", "有效自定义布局下，两杆浮动后重叠"),
        (REPORT / "compact-density-480/touch-layout.png", "高密度：控件重叠，保存按钮越界"),
        (REPORT / "interaction-probes/menu-files.png", "手机存档页仍提示 Enter / Esc"),
    ]
    result = Image.new("RGB", (1300, 850), "#152020")
    draw = ImageDraw.Draw(result)
    title_font = ui_font(26, 600)
    label_font = ui_font(20)
    draw.text((24, 14), "香火债 0.2.1 · 安卓操作复查 · 原生截图证据", font=title_font, fill="#e8eee7")
    for i, (path, label) in enumerate(samples):
        x, y = 20 + (i % 2) * 640, 70 + (i // 2) * 380
        with Image.open(path) as source:
            thumb = ImageOps.contain(source.convert("RGB"), (620, 349))
            result.paste(thumb, (x + (620 - thumb.width) // 2, y))
        draw.text((x, y + 350), label, font=label_font, fill="#efb48c")
    result.save(REPORT / "review-evidence.jpg", quality=94)
    print("Wrote 7 complete contact boards and review-evidence.jpg")


if __name__ == "__main__":
    main()
