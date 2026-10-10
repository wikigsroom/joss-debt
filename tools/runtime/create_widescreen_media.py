"""Produce documentation images from verified native pack captures; never synthesize gameplay."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/widescreen-2026-10-11"

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", default=str(REPORT.relative_to(ROOT)))
    parser.add_argument("--before-dir", help="Verified native capture directory to compare with the current pack.")
    parser.add_argument("--include-combat", action="store_true", help="Also save the current combat frame as a standalone preview.")
    args = parser.parse_args()
    report_root = Path(args.report_dir)
    if not report_root.is_absolute(): report_root = ROOT / report_root
    before_dir = Path(args.before_dir) if args.before_dir else report_root / "before/phone-20x9"
    if not before_dir.is_absolute(): before_dir = ROOT / before_dir
    sources = []
    def capture(mode, fixture, name):
        folder = before_dir if mode == "before" else report_root / mode / fixture
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
    before_version, after_version = sources[0]["version"], sources[1]["version"]
    font = ImageFont.truetype(str(ROOT / "game/assets/fonts/IncenseRounded-Medium.ttf"), 26)
    board = Image.new("RGB", (2560, 630), (27, 39, 42))
    draw = ImageDraw.Draw(board)
    draw.text((24, 14), before_version + " · 20:9 · 修复前 / BEFORE", font=font, fill=(236, 223, 200))
    draw.text((1304, 14), after_version + " · 20:9 · 修复后 / AFTER", font=font, fill=(157, 214, 191))
    board.paste(before.resize((1280, 576), Image.Resampling.LANCZOS), (0, 54))
    board.paste(after.resize((1280, 576), Image.Resampling.LANCZOS), (1280, 54))
    board.save(report_root / "before-after.jpg", quality=94)
    if args.include_combat:
        after.thumbnail((1920, 1080), Image.Resampling.LANCZOS)
        after.save(report_root / "combat.jpg", quality=94)
    for fixture, name, output in [("phone-20x9", "splash", "splash.jpg"),
                                 ("phone-20x9-left-cutout", "combat", "left-cutout.jpg"),
                                 ("phone-20x9-left-cutout", "rotated-combat", "rotated-cutout.jpg"),
                                 ("phone-20x9-punch-hole", "combat", "punch-hole.jpg")]:
        image = capture("windows", fixture, name)
        image.thumbnail((1920, 1080), Image.Resampling.LANCZOS)
        image.save(report_root / output, quality=94)
    matrix = json.loads((report_root / "windows-matrix.json").read_text("utf8"))
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
    board.save(report_root / "screen-matrix.jpg", quality=92)
    outputs = {p.name: digest(p) for p in report_root.glob("*.jpg")}
    (report_root / "media.json").write_text(json.dumps({"source": "Actual exported Windows packs, " + before_version + " before and " + after_version + " after",
        "physical_android_device_tested": False, "sources": sources, "outputs_sha256": outputs}, ensure_ascii=False, indent=2)+"\n", "utf8")
    print("Created", len(outputs), "source-bound native documentation images")

if __name__ == "__main__":
    main()
