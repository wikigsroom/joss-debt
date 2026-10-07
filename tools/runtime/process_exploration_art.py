"""Normalize only the three generated entrance states and append source evidence."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
from process_assets import split_atlas, normalize, sha

ROOT = Path(__file__).resolve().parents[2]


def main():
    source = ROOT / "output/imagegen/incense-debt/runtime/secret-entry.png"
    _, crops = split_atlas(source, 3, 1)
    frame = 256
    scale = min((frame - 28) / max(image.width for image, _ in crops), frame * .75 / max(image.height for image, _ in crops))
    runtime_path = ROOT / "game/assets/runtime-manifest.json"
    manifest_path = ROOT / "docs/incense-debt/data/asset-manifest.json"
    runtime = json.loads(runtime_path.read_text("utf8"))
    manifest = json.loads(manifest_path.read_text("utf8"))
    ids = ["secret_clue", "secret_open", "secret_used"]
    runtime["entries"] = [entry for entry in runtime["entries"] if entry["id"] not in ids]
    manifest["assets"] = [entry for entry in manifest["assets"] if entry["id"] not in ["prop_" + name for name in ids]]
    preview = Image.new("RGB", (900, 328), (36, 39, 37))
    for index, (identifier, (crop, bounds)) in enumerate(zip(ids, crops)):
        image = normalize(crop, frame, scale)
        target = ROOT / "game/assets/props" / (identifier + ".png")
        target.parent.mkdir(exist_ok=True)
        image.save(target)
        entry = {"id": identifier, "kind": "props", "path": target.relative_to(ROOT / "game").as_posix(),
                 "frame": [frame, frame], "ground_anchor": [.5, .84], "source": source.relative_to(ROOT).as_posix(),
                 "source_sha256": sha(source), "sha256": sha(target), "source_bbox": bounds,
                 "shared_scale": scale, "animation": "three generated raster states; transition by native drawing"}
        runtime["entries"].append(entry)
        manifest["assets"].append({"id": "prop_" + identifier, "kind": "prop", "status": "normalized", "engine_ready": False,
                                   "file": target.relative_to(ROOT).as_posix(), "size": [frame, frame], "ground_anchor": [.5, .84],
                                   "provider": "sub2-image-gen", "model": "gpt-image-2.5", "sha256": sha(target),
                                   "source": entry["source"], "source_sha256": entry["source_sha256"],
                                   "prompt": "docs/incense-debt/assets/prompts/reference-locked-secret-entry.txt"})
        preview.paste(image, (22 + index * 300, 18), image)
        ImageDraw.Draw(preview).text((28 + index * 300, 294), identifier, fill=(231, 216, 182))
    preview.save(ROOT / "docs/incense-debt/reports/runtime/entrance-states.png")
    runtime_path.write_text(json.dumps(runtime, ensure_ascii=False, indent=2) + "\n", "utf8")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Three entrance states normalized to 256px with one shared scale and foot anchor.")


if __name__ == "__main__":
    main()
