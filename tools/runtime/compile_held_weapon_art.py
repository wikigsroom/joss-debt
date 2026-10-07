"""Composite Sub2 local grip edits over approved poses; keep identity pixels exact.

This only processes generated rasters. The original pose and icon files are never
overwritten. The resulting neutral bodies must be visually reviewed before use.
"""
from pathlib import Path
import hashlib
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import map_coordinates
from scipy import ndimage

from compile_paper_animation import COUNTS, SPEED, deform
from prepare_held_weapon_art import ACTORS, DIRECTIONS, REGIONS, GRIPS, PROTECTED
from process_assets import split_atlas

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "output/imagegen/incense-debt/held-weapons"
ASSETS = ROOT / "game/assets"
REPORT = ROOT / "docs/incense-debt/reports/runtime/held-weapons"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transform(image, scale, dx, dy):
    """Fit the edit to an existing pose without moving any approved source pixel."""
    rgba = np.asarray(image, dtype=float) / 255
    rgba[:, :, :3] *= rgba[:, :, 3:4]
    y, x = np.mgrid[:96, :96].astype(float)
    u, v = (x - 48 - dx) / scale + 48, (y - 80.64 - dy) / scale + 80.64
    fitted = np.stack([map_coordinates(rgba[:, :, c], [v, u], order=1, mode="constant") for c in range(4)], axis=2)
    fitted[:, :, :3] /= np.maximum(fitted[:, :, 3:4], 1e-9)
    fitted[fitted[:, :, 3] < 1 / 255] = 0
    return Image.fromarray(np.clip(fitted * 255, 0, 255).astype(np.uint8))


def editable_mask(actor, row, original=None):
    mask = np.zeros((96, 96), dtype=bool)
    for x0, y0, x1, y1 in REGIONS[actor][row]:
        mask[y0:y1, x0:x1] = True
    for x0, y0, x1, y1 in PROTECTED.get(actor, [[], [], [], []])[row]:
        mask[y0:y1, x0:x1] = False
    if actor == "c_lantern" and original is not None:
        rgba = np.asarray(original)
        y, x = np.mgrid[:96, :96]
        orange = (rgba[:, :, 0] > 130) & (rgba[:, :, 1] > 45) & (rgba[:, :, 3] > 80) & (y < 53)
        labels, count = ndimage.label(orange)
        largest = 1 + np.argmax(np.bincount(labels.ravel())[1:])
        head = ndimage.binary_fill_holes(labels == largest)
        head = ndimage.binary_dilation(head, iterations=1)
        mask[head] = False
    return mask


def fit(original, candidate, mask):
    old = np.asarray(original, dtype=float) / 255
    # Both opaque identity pixels and their transparent silhouette boundary matter.
    weight = (~mask) * (1 + old[:, :, 3] * 4)
    old[:, :, :3] *= old[:, :, 3:4]
    best = (math.inf, None, None)
    # Coarse search, followed by a one-pixel refinement around its actual best fit.
    for scale in np.arange(.82, 1.121, .06):
        for dx in range(-8, 9, 4):
            for dy in range(-8, 9, 4):
                image = transform(candidate, scale, dx, dy)
                values = np.asarray(image, dtype=float) / 255
                values[:, :, :3] *= values[:, :, 3:4]
                error = np.sum(np.sum((values - old) ** 2, axis=2) * weight) / weight.sum()
                if error < best[0]: best = (error, image, (float(scale), dx, dy))
    center_scale, center_x, center_y = best[2]
    for scale in np.arange(center_scale - .03, center_scale + .031, .015):
        for dx in range(center_x - 2, center_x + 3):
            for dy in range(center_y - 2, center_y + 3):
                image = transform(candidate, scale, dx, dy)
                values = np.asarray(image, dtype=float) / 255
                values[:, :, :3] *= values[:, :, 3:4]
                error = np.sum(np.sum((values - old) ** 2, axis=2) * weight) / weight.sum()
                if error < best[0]: best = (error, image, (float(scale), dx, dy))
    return best


def neutral_bodies():
    path = SOURCE / "neutral-grips-single-reference.png"
    source = Image.open(path).convert("RGBA")
    if source.size != (1536, 1024): raise ValueError("Unexpected edited pose layout")
    folder = ASSETS / "weapon-bodies/base"
    folder.mkdir(parents=True, exist_ok=True)
    board = Image.new("RGBA", (1152, 896), (36, 39, 37, 255))
    draw = ImageDraw.Draw(board)
    records = []
    for row, direction in enumerate(DIRECTIONS):
        for column, actor in enumerate(ACTORS):
            original_path = ASSETS / f"heroes/{actor}_{direction}.png"
            original = Image.open(original_path).convert("RGBA")
            candidate = source.crop((column * 256, row * 256, (column + 1) * 256, (row + 1) * 256)).resize((96, 96), Image.Resampling.LANCZOS)
            mask = editable_mask(actor, row, original)
            error, aligned, registration = fit(original, candidate, mask)
            old = np.asarray(original).copy()
            edited = np.asarray(aligned)
            result = old.copy()
            result[mask] = edited[mask]
            # RGBA outside the documented edit region must be byte-for-byte identical.
            if not np.array_equal(result[~mask], old[~mask]): raise ValueError("Identity drift")
            output = folder / f"{actor}_{direction}.png"
            image = Image.fromarray(result)
            image.save(output)
            REPORT.mkdir(parents=True, exist_ok=True)
            Image.fromarray(mask.astype(np.uint8) * 255).save(REPORT / f"{actor}_{direction}-editable-mask.png")
            preview = image.resize((160, 160), Image.Resampling.NEAREST)
            board.alpha_composite(preview, (column * 192 + 16, row * 224 + 32))
            draw.text((column * 192 + 12, row * 224 + 8), f"{actor} / {direction}", fill=(231, 216, 182))
            records.append({"actor": actor, "direction": direction, "file": output.relative_to(ROOT).as_posix(),
                            "sha256": digest(output), "original": original_path.relative_to(ROOT).as_posix(),
                            "original_sha256": digest(original_path), "source": path.relative_to(ROOT).as_posix(),
                            "source_sha256": digest(path), "editable_regions": REGIONS[actor][row],
                            "editable_mask": (REPORT / f"{actor}_{direction}-editable-mask.png").relative_to(ROOT).as_posix(),
                            "registration": list(registration), "fit_error": error,
                            "protected_rgba_unchanged": True, "grips": GRIPS[actor][row]})
    REPORT.mkdir(parents=True, exist_ok=True)
    board.convert("RGB").save(REPORT / "neutral-bodies-review.png")
    (REPORT / "body-processing.json").write_text(json.dumps({"status": "awaiting_visual_review", "bodies": records}, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Composited {len(records)} local edits; all protected RGBA pixels remain exact.")


def locate_hand(image, intended):
    a = np.asarray(image)
    y, x = np.mgrid[:96, :96]
    cream = (a[:, :, 0] > 150) & (a[:, :, 1] > 120) & (a[:, :, 2] > 75) & (a[:, :, 3] > 100)
    distance = (x - intended[0]) ** 2 + (y - intended[1]) ** 2
    available = cream & (distance < 12 ** 2) & (y > 49)
    labels, count = ndimage.label(available)
    best = (math.inf, intended)
    for label in range(1, count + 1):
        ys, xs = np.where(labels == label)
        if len(xs) < 3: continue
        center = [float(xs.mean()), float(ys.mean())]
        score = (center[0] - intended[0]) ** 2 + (center[1] - intended[1]) ** 2
        if score < best[0]: best = (score, center)
    return best[1]


def hand_layer(image, points):
    a = np.asarray(image).copy()
    y, x = np.mgrid[:96, :96]
    mask = np.zeros((96, 96), dtype=bool)
    for px, py in points:
        mask |= (x - px) ** 2 / 3.6 ** 2 + (y - py) ** 2 / 3.7 ** 2 < 1
    a[~mask] = 0
    return Image.fromarray(a)


def marker_centroid(point, state, frame, count):
    marker = Image.new("RGBA", (96, 96))
    ImageDraw.Draw(marker).ellipse((point[0] - 2, point[1] - 2, point[0] + 2, point[1] + 2), fill=(255, 255, 255, 255))
    alpha = np.asarray(deform(marker, state, frame, count))[:, :, 3].astype(float)
    if alpha.sum() == 0: return point
    y, x = np.mgrid[:96, :96]
    return [round(float((x * alpha).sum() / alpha.sum()), 4), round(float((y * alpha).sum() / alpha.sum()), 4)]


def finish():
    bodies = json.loads((REPORT / "body-processing.json").read_text("utf8"))
    new_animations = []
    runtime_entries = []
    rig = {"version": 1, "anchor": [.5, .84], "frame_size": 96, "actors": {}, "weapons": {}}
    by_actor = {(a["actor"], a["direction"]): a for a in bodies["bodies"]}
    grips_report = []
    for actor in ACTORS:
        sources, hands, points = [], [], []
        for row, direction in enumerate(DIRECTIONS):
            record = by_actor[actor, direction]
            path = ROOT / record["file"]
            if digest(path) != record["sha256"]: raise ValueError("Unreviewed body edit")
            image = Image.open(path).convert("RGBA")
            local_points = [locate_hand(image, p) for p in GRIPS[actor][row]]
            # The back umbrella view has no wrist in the original. Reuse the same
            # generated front-view paper fingers inside its approved editable region.
            if actor == "c_umbrella" and direction == "up" and not record.get("finger_reuse"):
                front = Image.open(ROOT / by_actor[actor, "down"]["file"]).convert("RGBA")
                front_point = locate_hand(front, GRIPS[actor][0][0])
                patch = front.crop((round(front_point[0])-3, round(front_point[1])-3, round(front_point[0])+4, round(front_point[1])+4))
                local_points = [[57, 65], [38, 65]]
                for p in local_points: image.alpha_composite(patch, (p[0]-3, p[1]-3))
                image.save(path)
                record["sha256"] = digest(path)
                record["finger_reuse"] = {"source": by_actor[actor, "down"]["file"], "reason": "same generated paper fingers on the back-view free wrists"}
            elif actor == "c_umbrella" and direction == "up": local_points = [[57, 65], [38, 65]]
            sources.append(image)
            # The fixed scroll/shield is never covered by a separate finger layer.
            overlay_points = local_points[:1] if actor in ["c_mask", "c_ink"] else local_points
            hands.append(hand_layer(image, overlay_points))
            points.append(local_points)
            grips_report.append({"actor": actor, "direction": direction, "points": local_points})
            runtime_entries.append({"id": actor + "_neutral_" + direction, "kind": "weapon_body", "path": path.relative_to(ROOT / "game").as_posix(),
                                    "source": record["source"], "source_sha256": record["source_sha256"], "sha256": digest(path),
                                    "original": record["original"], "original_sha256": record["original_sha256"], "ground_anchor": [.5, .84],
                                    "generation": "Sub2 reference edit, region-limited compositing over exact approved pose"})
        rig["actors"][actor] = {}
        for state, count in COUNTS["character"].items():
            rig["actors"][actor][state] = {}
            for kind, folder, inputs in [("weapon_body", "animation", sources), ("weapon_hand", "hands", hands)]:
                destination = ASSETS / "weapon-bodies" / folder / actor
                destination.mkdir(parents=True, exist_ok=True)
                atlas = Image.new("RGBA", (count * 96, 384))
                for row, source in enumerate(inputs):
                    for frame in range(count): atlas.alpha_composite(deform(source, state, frame, count), (frame * 96, row * 96))
                output = destination / f"{state}.png"
                atlas.save(output)
                new_animations.append({"actor": actor, "kind": kind, "state": state, "frames": count, "fps": SPEED[state],
                                       "directions": DIRECTIONS, "frame_size": 96, "anchor": [.5, .84], "file": output.relative_to(ROOT).as_posix(),
                                       "sha256": digest(output), "source": [{"file": by_actor[actor, d]["file"], "sha256": by_actor[actor, d]["sha256"]} for d in DIRECTIONS],
                                       "method": "shared approved paper-puppet warp; modular neutral body" if kind == "weapon_body" else "same generated grip pixels warped with the body"})
            for row, direction in enumerate(DIRECTIONS):
                rig["actors"][actor][state][direction] = [[marker_centroid(p, state, frame, count) for p in points[row]] for frame in range(count)]
    weapon_source = SOURCE / "held-weapons-reference-edit.png"
    _, crops = split_atlas(weapon_source, 4, 3)
    raw_grips = [[334,226], [573,87], [943,300], [1191,224], [93,518], [506,520], [904,580], [1231,525], [206,839], [552,947], [867,827], [1232,826]]
    sizes = [31,24,42,44,43,43,35,36,31,46,46,42]
    weapon_folder = ASSETS / "held-weapons"
    weapon_folder.mkdir(exist_ok=True)
    for index, (crop, bbox) in enumerate(crops):
        weapon = f"w{index+1:02d}"
        scale = min(108/crop.width,108/crop.height)
        resized = crop.resize((round(crop.width*scale), round(crop.height*scale)), Image.Resampling.LANCZOS)
        left, top = (128-resized.width)//2, (128-resized.height)//2
        image = Image.new("RGBA", (128,128))
        image.alpha_composite(resized,(left,top))
        output = weapon_folder / f"{weapon}.png"
        image.save(output)
        grip = [(left+(raw_grips[index][0]-bbox[0])*scale)/128, (top+(raw_grips[index][1]-bbox[1])*scale)/128]
        if not all(0 < v < 1 for v in grip): raise ValueError("Grip outside texture: " + weapon)
        rig["weapons"][weapon] = {"texture": "res://assets/held-weapons/"+weapon+".png", "grip": grip, "size": sizes[index],
                                   "aimed": weapon not in ["w01","w02","w03","w09","w10"], "mirror_outward": weapon == "w01"}
        runtime_entries.append({"id": weapon + "_held", "kind": "held_weapon", "path": output.relative_to(ROOT / "game").as_posix(),
                                "source": weapon_source.relative_to(ROOT).as_posix(), "source_sha256": digest(weapon_source),
                                "sha256": digest(output), "source_bbox": bbox, "grip": grip, "generation": "Sub2 single-reference local equipment edit; original inventory icon retained"})
    (ASSETS / "weapon-rig.json").write_text(json.dumps(rig, ensure_ascii=False, indent=2)+"\n", "utf8")
    animations_path = ASSETS / "animation-manifest.json"
    animations = json.loads(animations_path.read_text("utf8"))
    animations["strips"] = [a for a in animations["strips"] if a["kind"] not in ["weapon_body","weapon_hand"]] + new_animations
    animations_path.write_text(json.dumps(animations, ensure_ascii=False, indent=2)+"\n", "utf8")
    runtime_path = ASSETS / "runtime-manifest.json"
    runtime = json.loads(runtime_path.read_text("utf8"))
    runtime["entries"] = [a for a in runtime["entries"] if a.get("kind") not in ["weapon_body","held_weapon"]] + runtime_entries
    runtime_path.write_text(json.dumps(runtime, ensure_ascii=False, indent=2)+"\n", "utf8")
    bodies["status"] = "reviewed_local_edits"
    bodies["grips"] = grips_report
    bodies["modular_animation_strips"] = len(new_animations)
    bodies["held_weapon_cutouts"] = len(crops)
    (REPORT / "body-processing.json").write_text(json.dumps(bodies, ensure_ascii=False, indent=2)+"\n", "utf8")
    print(f"Compiled {len(new_animations)} matching body/hand strips and 12 held cutouts; original assets retained.")


if __name__ == "__main__":
    finish() if "--finish" in sys.argv else neutral_bodies()
