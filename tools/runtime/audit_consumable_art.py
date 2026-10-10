"""Check source-bound pickup bitmaps and assemble native screenshots for review."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports/consumables-2026-10-11"
ART = ROOT / "game/assets/pickups"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((ART / "manifest.json").read_text("utf8"))
    checks = []
    for row in manifest["records"]:
        path = ROOT / "game" / row["file"].removeprefix("res://")
        image = Image.open(path).convert("RGBA")
        alpha = image.getchannel("A")
        corners = [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)]
        valid = digest(path) == row["sha256"] and list(image.size) == row["size"]
        if row["id"] == "ground-shadow":
            valid = valid and alpha.getextrema()[0] == 0 and alpha.getextrema()[1] > 0
        else:
            valid = valid and alpha.getextrema() == (0, 255)
        valid = valid and all(alpha.getpixel(point) == 0 for point in corners)
        if "source" in row:
            source = ROOT / row["source"]
            valid = valid and digest(source) == row["source_sha256"]
            bounds = row["source_bounds"]
            valid = valid and bounds[0] >= 3 and bounds[1] >= 3 and bounds[2] <= row["source_size"][0] - 3 and bounds[3] <= row["source_size"][1] - 3
        checks.append({"id": row["id"], "passed": bool(valid), "file": row["file"]})
    sources = [row["source_sha256"] for row in manifest["records"] if "source_sha256" in row]
    checks.append({"id": "six_distinct_generated_source_drawings", "passed": len(sources) == 6 and len(set(sources)) == 6})
    report = {"passed": all(row["passed"] for row in checks), "checks": checks,
              "recorded_at": datetime.now(timezone.utc).isoformat(), "provider": manifest["provider"],
              "model": manifest["model"], "generated_objects": 6, "runtime_bitmaps": len(manifest["records"]),
              "manifest_sha256": digest(ART / "manifest.json"),
              "method": "generated raster objects, alpha cleanup, uniform scaling, bitmap-derived keylines/shadow; no vector pickup drawing"}
    (REPORTS / "art-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    folder = REPORTS / ("windows" if (REPORTS / "windows/native.json").is_file() else "native")
    for variant in ["a", "b"]:
        contact = Image.new("RGB", (4 * 500, 5 * 224), "#1b282d")
        labels = ImageDraw.Draw(contact)
        for index in range(20):
            source = folder / (f"theme-{index + 1:02d}-{variant}.png")
            image = Image.open(source).convert("RGB").crop((390, 275, 890, 455))
            x, y = index % 4 * 500, index // 4 * 224
            contact.paste(image, (x, y + 28))
            labels.text((x + 12, y + 9), f"m{index + 1:02d} / {variant} / native 1:1 crop", fill="#f7dfbb")
        contact.save(REPORTS / ("twenty-themes-" + variant + ".jpg"), quality=96)
    for index, name in [(0, "warm-room"), (6, "bright-room"), (13, "dark-room")]:
        Image.open(folder / f"theme-{index + 1:02d}-a.png").convert("RGB").save(REPORTS / (name + ".jpg"), quality=96)
    Image.open(folder / "healing-shop.png").convert("RGB").save(REPORTS / "healing-shop.jpg", quality=96)
    Image.open(folder / "fire-core-keyboard-hint.png").convert("RGB").save(REPORTS / "fire-core-keyboard-hint.jpg", quality=96)
    Image.open(folder / "mobile-hud.png").convert("RGB").save(REPORTS / "mobile-hud.jpg", quality=96)
    before = Image.open(REPORTS / "before/theme-01-a.png").convert("RGB")
    after = Image.open(folder / "theme-01-a.png").convert("RGB")
    comparison = Image.new("RGB", (2560, 760), "#1b282d")
    comparison.paste(before, (0, 40)); comparison.paste(after, (1280, 40))
    labels = ImageDraw.Draw(comparison)
    labels.text((24, 14), "BEFORE / native renderer", fill="#f7dfbb")
    labels.text((1304, 14), "AFTER / generated pickup bitmaps in the native renderer", fill="#f7dfbb")
    comparison.save(REPORTS / "native-before-after.jpg", quality=96)
    media = []
    for path in sorted(REPORTS.glob("*.jpg")) + sorted(folder.glob("*.gif")):
        with Image.open(path) as image:
            media.append({"file": path.relative_to(ROOT).as_posix(), "sha256": digest(path),
                          "size": list(image.size), "frames": getattr(image, "n_frames", 1)})
    (REPORTS / "media.json").write_text(json.dumps({"source": folder.relative_to(ROOT).as_posix(), "files": media}, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "media": len(media)}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
