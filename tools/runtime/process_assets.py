"""Slice Sub2API production atlases, normalize shared ground anchors, record provenance.

Connected components preserve parts crossing a nominal grid boundary without clipping.
No art is generated here: all raster source art comes from the user's Sub2API skill.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "output/imagegen/incense-debt/runtime"
DEST = ROOT / "game/assets"
REPORT = ROOT / "docs/incense-debt/reports/runtime/asset-processing.json"
MANIFEST = DEST / "runtime-manifest.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def split_atlas(path, columns, rows, used_cells=None):
    source = Image.open(path).convert("RGBA")
    rgba = np.asarray(source)
    alpha = rgba[:, :, 3]
    if np.count_nonzero(alpha == 0) < source.width * source.height // 4:
        raise ValueError(f"Atlas lacks usable transparency: {path.name}")
    # Use opaque cores to avoid a faint antialias bridge joining adjacent poses.
    labels, count = ndimage.label(alpha > 64)
    distance, indices = ndimage.distance_transform_edt(labels == 0, return_indices=True)
    recovered = labels[tuple(indices)]
    labels = np.where((alpha > 0) & (distance <= 3), recovered, 0)
    boxes = ndimage.find_objects(labels)
    assigned = [[] for _ in range(columns * rows)]
    w, h = source.width / columns, source.height / rows
    for label, box in enumerate(boxes, start=1):
        if box is None:
            continue
        ys, xs = box
        actual = (labels[box] == label) & (alpha[box] > 12)
        if np.count_nonzero(actual) < 24:
            continue
        cx, cy = (xs.start + xs.stop) / 2, (ys.start + ys.stop) / 2
        col = max(0, min(columns - 1, int(cx / w)))
        row = max(0, min(rows - 1, int(cy / h)))
        assigned[row * columns + col].append(label)
    result = []
    for index, parts in enumerate(assigned):
        if not parts:
            if used_cells is not None and index not in used_cells:
                result.append((Image.new("RGBA", (1, 1)), [0, 0, 0, 0]))
                continue
            raise ValueError(f"Empty atlas cell {index}: {path.name}")
        mask = np.isin(labels, parts)
        copied = rgba.copy()
        copied[:, :, 3] = np.where(mask, alpha, 0)
        image = Image.fromarray(copied)
        bbox = image.getbbox()
        result.append((image.crop(bbox), list(bbox)))
    return source, result


def normalize(image, frame, scale):
    resized = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (frame, frame))
    left = round(frame / 2 - resized.width / 2)
    top = round(frame * 0.84 - resized.height)
    if left < 6 or top < 4:
        raise ValueError("Normalized sprite has inadequate edge padding")
    canvas.alpha_composite(resized, (left, top))
    return canvas


def cut_paper_background(image):
    rgba = np.asarray(image.convert("RGBA")).copy()
    rgb = rgba[:, :, :3].astype(float)
    luma = rgb[:, :, 0] * .299 + rgb[:, :, 1] * .587 + rgb[:, :, 2] * .114
    cream = (luma > 112) & (rgb[:, :, 0] - rgb[:, :, 1] < 37) & (rgb[:, :, 1] - rgb[:, :, 2] < 60)
    seeds = np.zeros(cream.shape, dtype=bool)
    seeds[0] = cream[0]; seeds[-1] = cream[-1]
    seeds[:, 0] |= cream[:, 0]; seeds[:, -1] |= cream[:, -1]
    background = ndimage.binary_propagation(seeds, mask=cream)
    rgba[:, :, 3] = np.where(background, 0, 255)
    result = Image.fromarray(rgba)
    return result.crop(result.getbbox())


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    entries = []
    checks = []
    previews = []
    characters = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]
    directions = ["down", "left", "right", "up"]
    heroes_source = "heroes-poses-locked.png" if (SOURCES / "heroes-poses-locked.png").exists() else "heroes-poses.png"
    specs = [(heroes_source, 6, 4, 96, "heroes"), ("paper-enemies.png", 4, 2, 128, "enemies")]
    if (SOURCES / "bosses.png").exists():
        specs.append(("bosses.png", 3, 1, 256, "bosses"))
    relic_ids = ["r01", "r02", "r03", "r09", "r10", "r11", "r17", "r18", "r19", "r25", "r26", "r27", "r33", "r34", "r35", "r41", "r42", "r43"]
    if (SOURCES / "relics-initial.png").exists():
        specs.append(("relics-initial.png", 6, 3, 128, "relics"))
    if (SOURCES / "weapons.png").exists():
        specs.append(("weapons.png", 4, 3, 128, "weapons"))
    optional_specs = [("coin-enemies.png", 4, 2, 128, "enemies"), ("ownerless-enemies.png", 4, 2, 128, "enemies"),
                      ("relics-mid.png", 6, 3, 128, "relics"), ("relics-end.png", 6, 3, 128, "relics"),
                      ("optional-bosses.png", 2, 1, 256, "bosses"), ("npcs.png", 3, 2, 128, "npcs"),
                      ("skills.png", 6, 3, 128, "skills"), ("elites.png", 3, 2, 128, "elites")]
    specs.extend(spec for spec in optional_specs if (SOURCES / spec[0]).exists())
    extra_relics = {"relics-mid.png": ["r04", "r05", "r06", "r07", "r08", "r12", "r13", "r14", "r15", "r16", "r20", "r21", "r22", "r23", "r24", "r28", "r29", "r30"],
                    "relics-end.png": ["r31", "r32", "r36", "r37", "r38", "r39", "r40", "r44", "r45", "r46", "r47", "r48", "r49", "r50", "r51", "r52", "r53", "r54"]}
    for name, columns, rows, frame, kind in specs:
        source, crops = split_atlas(SOURCES / name, columns, rows)
        scales = {}
        if kind == "heroes":
            for col in range(columns):
                group = [crops[row * columns + col][0] for row in range(rows)]
                scales[col] = min((frame - 16) / max(im.width for im in group), (frame * .74) / max(im.height for im in group))
        output = DEST / kind
        output.mkdir(exist_ok=True)
        for index, (crop, bbox) in enumerate(crops):
            if kind == "heroes":
                identifier = f"{characters[index % columns]}_{directions[index // columns]}"
                scale = scales[index % columns]
            elif kind == "relics":
                identifier = extra_relics.get(name, relic_ids)[index]
                scale = min((frame - 20) / crop.width, (frame * .76) / crop.height)
            else:
                prefix = {"enemies": "e", "bosses": "b", "weapons": "w", "npcs": "n", "skills": "s", "elites": "x"}[kind]
                start = {"coin-enemies.png": 9, "ownerless-enemies.png": 17, "optional-bosses.png": 4}.get(name, 1)
                identifier = f"{prefix}{index + start:02d}"
                if kind == "npcs" and index == 5: identifier = "training_stand"
                scale = min((frame - 20) / crop.width, (frame * .76) / crop.height)
            image = normalize(crop, frame, scale)
            path = output / (identifier + ".png")
            image.save(path)
            entries.append({"id": identifier, "kind": kind, "path": path.relative_to(ROOT / "game").as_posix(),
                            "frame": [frame, frame], "ground_anchor": [.5, .84], "source": (SOURCES / name).relative_to(ROOT).as_posix(),
                            "source_sha256": sha(SOURCES / name), "sha256": sha(path), "source_bbox": bbox, "shared_scale": scale,
                            "animation": "procedural paper-puppet deformation from a locked base pose" if kind in ["heroes", "enemies", "bosses", "npcs"] else "static icon"})
            previews.append((identifier, image))
        checks.append({"atlas": name, "transparent_pixels": int(np.count_nonzero(np.asarray(source)[:, :, 3] == 0)),
                       "sprites": len(crops), "all_cells_nonempty": True, "source_sha256": sha(SOURCES / name)})
    board_path = ROOT / "output/imagegen/incense-debt/paper-lantern-asset-board.png"
    board = Image.open(board_path).convert("RGB")
    # A clean patch and wall strip from the approved Sub2 concept board. These are
    # explicitly provisional environment materials, not a final tileset claim.
    environment = DEST / "environment"
    environment.mkdir(exist_ok=True)
    board.crop((620, 215, 812, 407)).resize((192, 192)).save(environment / "floor-paper.png")
    board.crop((145, 14, 515, 113)).save(environment / "wall-paper.png")
    prop_dir = DEST / "props"
    prop_dir.mkdir(exist_ok=True)
    prop_crops = {"incense": (67, 804, 353, 1007), "paper_stack": (446, 803, 716, 1008),
                  "chest": (823, 817, 1113, 1007), "bell": (1197, 792, 1482, 1017)}
    for identifier, bounds in prop_crops.items():
        cropped = cut_paper_background(board.crop(bounds))
        scale = min(140 / cropped.width, 120 / cropped.height)
        normalize(cropped, 160, scale).save(prop_dir / (identifier + ".png"))
        entries.append({"id": "prop_" + identifier, "path": "assets/props/" + identifier + ".png", "source": board_path.relative_to(ROOT).as_posix(),
                        "source_sha256": sha(board_path), "source_bbox": list(bounds), "ground_anchor": [.5, .84], "generation": "approved-art crop with edge-connected paper background removed"})
    for name in ["paper-temple-arena", "coin-vault-arena", "ownerless-temple-arena", "hub-arena"]:
        arena = SOURCES / (name + ".png")
        if arena.exists():
            Image.open(arena).save(environment / (name + ".png"))
            entries.append({"id": name.replace("-", "_"), "source": arena.relative_to(ROOT).as_posix(), "source_sha256": sha(arena),
                            "path": "assets/environment/" + name + ".png", "generation": "Sub2API reference edit",
                            "reference": "output/imagegen/concepts/01-incense-debt.png" if name == "paper-temple-arena" else "output/imagegen/incense-debt/runtime/paper-temple-arena.png"})
    # The approved roster, without redrawing, remains the character-select master.
    portraits = DEST / "portraits"
    portraits.mkdir(exist_ok=True)
    roster_path = ROOT / "output/imagegen/incense-debt/characters-roster.png"
    roster = Image.open(roster_path)
    for i, identifier in enumerate(characters):
        x, y = (i % 3) * 512, (i // 3) * 512
        roster.crop((x + 8, y + 8, x + 504, y + 504)).save(portraits / (identifier + ".png"))
        entries.append({"id": identifier + "_portrait", "path": "assets/portraits/" + identifier + ".png",
                        "source": roster_path.relative_to(ROOT).as_posix(), "source_sha256": sha(roster_path), "generation": "direct approved-art crop"})
    entries.append({"id": "paper_lane_provisional_material", "source": board_path.relative_to(ROOT).as_posix(),
                    "source_sha256": sha(board_path), "status": "provisional concept crop", "paths": ["assets/environment/floor-paper.png", "assets/environment/wall-paper.png"]})
    MANIFEST.write_text(json.dumps({"generator": "Sub2API / gpt-image-2.5", "entries": entries}, ensure_ascii=False, indent=2) + "\n", "utf-8")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({"passed": True, "atlases": checks, "sprites": len(previews), "edge_padding_checked": True,
                                  "needs_visual_review": "normalized-sprites.png and native runtime screenshots"}, ensure_ascii=False, indent=2) + "\n", "utf-8")
    cols, cell = 8, 176
    montage = Image.new("RGB", (cols * cell, ((len(previews) + cols - 1) // cols) * cell), (42, 49, 45))
    draw = ImageDraw.Draw(montage)
    for index, (identifier, sprite) in enumerate(previews):
        x, y = (index % cols) * cell, (index // cols) * cell
        if sprite.width > 128:
            sprite = sprite.resize((128, 128), Image.Resampling.LANCZOS)
        montage.paste(sprite, (x + (cell - sprite.width) // 2, y + 16), sprite)
        draw.text((x + 8, y + cell - 18), identifier, fill=(231, 216, 182))
    montage.save(ROOT / "docs/incense-debt/reports/runtime/normalized-sprites.png")
    print(f"Processed {len(previews)} sprites with shared anchors; {len(checks)} transparent atlases.")


if __name__ == "__main__":
    main()
