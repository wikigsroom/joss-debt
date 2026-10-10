"""Produce documentation images from verified native pack captures; never synthesize gameplay."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/widescreen-2026-10-11"

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    sources = []
    def capture(mode, fixture, name):
        folder = REPORT / mode / fixture
        report = json.loads((folder / "native.json").read_text("utf8"))
        record = next(row for row in report["captures"] if row["name"] == name)
        path = folder / (name + ".png")
        if not report["passed"] or not report["packaged"] or digest(path) != record["sha256"]:
            raise RuntimeError("Unverified native capture: " + str(path))
        sources.append({"path": path.relative_to(ROOT).as_posix(), "sha256": record["sha256"],
                        "version": report["version"], "artifact_sha256": report["artifact_sha256"]})
        return Image.open(path).convert("RGB")
    before = capture("before", "phone-20x9", "combat")
    after = capture("windows", "phone-20x9", "combat")
    font = ImageFont.truetype(str(ROOT / "game/assets/fonts/IncenseRounded-Medium.ttf"), 26)
    board = Image.new("RGB", (2560, 630), (27, 39, 42))
    draw = ImageDraw.Draw(board)
    draw.text((24, 14), "0.2.1 · 20:9 · 修复前 / BEFORE", font=font, fill=(236, 223, 200))
    draw.text((1304, 14), "0.2.2 · 20:9 · 修复后 / AFTER", font=font, fill=(157, 214, 191))
    board.paste(before.resize((1280, 576), Image.Resampling.LANCZOS), (0, 54))
    board.paste(after.resize((1280, 576), Image.Resampling.LANCZOS), (1280, 54))
    board.save(REPORT / "before-after.jpg", quality=94)
    for fixture, name, output in [("phone-20x9", "splash", "splash.jpg"),
                                 ("phone-20x9-left-cutout", "combat", "left-cutout.jpg"),
                                 ("phone-20x9-left-cutout", "rotated-combat", "rotated-cutout.jpg"),
                                 ("phone-20x9-punch-hole", "combat", "punch-hole.jpg")]:
        image = capture("windows", fixture, name)
        image.thumbnail((1920, 1080), Image.Resampling.LANCZOS)
        image.save(REPORT / output, quality=94)
    matrix = json.loads((REPORT / "windows-matrix.json").read_text("utf8"))
    board = Image.new("RGB", (2048, 1104), (27, 39, 42))
    draw = ImageDraw.Draw(board)
    small = ImageFont.truetype(str(ROOT / "game/assets/fonts/IncenseRounded-Medium.ttf"), 20)
    for i, fixture in enumerate(matrix["fixtures"]):
        image = capture("windows", fixture["fixture"], "combat")
        image.thumbnail((512, 480), Image.Resampling.LANCZOS)
        x, y = (i % 4) * 512, (i // 4) * 552
        draw.text((x+12, y+12), fixture["fixture"], font=small, fill=(157, 214, 191))
        draw.text((x+12, y+40), fixture["resolution"] + " · " + str(fixture["dpi"]) + " dpi", font=small, fill=(236, 223, 200))
        board.paste(image, (x+(512-image.width)//2, y+80+(472-image.height)//2))
    board.save(REPORT / "screen-matrix.jpg", quality=92)
    outputs = {p.name: digest(p) for p in REPORT.glob("*.jpg")}
    (REPORT / "media.json").write_text(json.dumps({"source": "Actual exported Windows packs, 0.2.1 before and 0.2.2 after",
        "physical_android_device_tested": False, "sources": sources, "outputs_sha256": outputs}, ensure_ascii=False, indent=2)+"\n", "utf8")
    print("Created", len(outputs), "source-bound native documentation images")

if __name__ == "__main__":
    main()
