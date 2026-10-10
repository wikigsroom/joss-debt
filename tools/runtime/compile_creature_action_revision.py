"""Normalize accepted independent drawings; never manufacture poses from a base sprite.

Only crop, remove unrelated edge fragments, uniformly resize, and place each
already drawn pose. A single actor scale is shared by every state and facing.
The full shipping gate is catalog-derived, including elites and loan-note seals.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / ".local-tools/creature-python-deps"))
import numpy as np
from PIL import Image
from scipy import ndimage
from prepare_creature_action_revision import roster

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/creature-action-revision"
METHOD = "independently drawn Sub2 creature action frames"
DIRECTIONS = ["down", "left", "right", "up"]
FOLDERS = {"enemy": "enemy-animation", "boss": "boss-animation", "elite": "elite-animation", "summon": "sigil-animation"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")
    temporary.replace(path)


def sheet_poses(sheet, job, required_cells=None):
    # Generated art can overhang a nominal cell while remaining fully separated
    # by transparent space. Extract whole connected drawings, never sever feet
    # or permanent props at an arbitrary mathematical grid boundary.
    pixels = np.array(sheet.convert("RGBA"))
    labels, count = ndimage.label(pixels[:, :, 3] > 20)
    if count == 0:
        raise ValueError("Empty drawing: " + job["id"])
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    objects = ndimage.find_objects(labels)
    main = {}
    for index, bounds in enumerate(objects, 1):
        if bounds is None or areas[index] < 400: continue
        ys, xs = bounds
        row = min(job["rows"] - 1, int((ys.start + ys.stop) / 2 / (sheet.height / job["rows"])))
        column = min(5, int((xs.start + xs.stop) / 2 / (sheet.width / 6)))
        if (row, column) not in main or areas[index] > areas[main[row, column]]: main[row, column] = index
    required = required_cells if required_cells is not None else {
        (int(item.get("source_row", row)), column)
        for row, item in enumerate(job["row_order"]) for column in range(6)}
    missing = required - main.keys()
    if missing:
        raise ValueError("Missing or joined-together selected drawings in " + job["id"] + ": " + str(sorted(missing)))
    centers = {key: ((objects[index-1][1].start + objects[index-1][1].stop) / 2,
                     (objects[index-1][0].start + objects[index-1][0].stop) / 2) for key, index in main.items()}
    owners = {key: [index] for key, index in main.items()}
    for index, bounds in enumerate(objects, 1):
        if bounds is None or index in main.values() or areas[index] < 8: continue
        ys, xs = bounds
        cx, cy = (xs.start + xs.stop) / 2, (ys.start + ys.stop) / 2
        key = min(centers, key=lambda key: (cx - centers[key][0]) ** 2 + (cy - centers[key][1]) ** 2)
        if areas[index] >= max(8, areas[main[key]] * .004): owners[key].append(index)
    result = {}
    for key, components in owners.items():
        if key not in required: continue
        bounds = [objects[index - 1] for index in components]
        x0, y0 = min(b[1].start for b in bounds), min(b[0].start for b in bounds)
        x1, y1 = max(b[1].stop for b in bounds), max(b[0].stop for b in bounds)
        if x0 == 0 or y0 == 0 or x1 == sheet.width or y1 == sheet.height:
            raise ValueError("Drawing reaches the source image edge; redraw instead of cropping anatomy: " + job["id"] + " / " + str(key))
        x0, y0, x1, y1 = max(0, x0-2), max(0, y0-2), min(sheet.width, x1+2), min(sheet.height, y1+2)
        region = pixels[y0:y1, x0:x1].copy()
        keep = ndimage.binary_dilation(np.isin(labels[y0:y1, x0:x1], components), iterations=2)
        region[:, :, 3][~keep] = 0
        region[:, :, 3][region[:, :, 3] < 8] = 0
        pose = Image.fromarray(region)
        bbox = pose.getbbox()
        if bbox is None or min(bbox[2]-bbox[0], bbox[3]-bbox[1]) < 12:
            raise ValueError("Unusable pose silhouette: " + job["id"] + " / " + str(key))
        result[key] = pose.crop(bbox)
    return result


def inspect_actor(actor, jobs, progress, reviews):
    frames = {}
    sources = []
    for job in jobs:
        # A fully replaced page contributes no runtime poses. Do not approve
        # rejected originals just to satisfy a gate for unused source art.
        # The complete state/facing/pose check below still requires every pose
        # from the reviewed corrective pages.
        if not job["row_order"]:
            continue
        raw = ROOT / job["output"]
        record = progress.get(job["id"], {})
        review = reviews.get(job["id"], {})
        if not raw.is_file() or record.get("state") != "raw_verified":
            raise ValueError("Missing source drawing: " + job["id"])
        fingerprint = {field: job[field] for field in ["prompt_sha256", "reference_sha256", "source_sha256", "model"]}
        actual_hash = digest(raw)
        if any(record.get(field) != value for field, value in fingerprint.items()) or record.get("sha256") != actual_hash:
            raise ValueError("Drawing input provenance changed: " + job["id"])
        if review.get("verdict") != "accepted" or review.get("raw_sha256") != actual_hash:
            raise ValueError("A current visual review is required: " + job["id"])
        reviewed_rows = set(review.get("accepted_source_rows", range(job["rows"]) if review.get("reviewed_cells") == job["rows"] * 6 else []))
        if not {item.get("source_row", row) for row, item in enumerate(job["row_order"])}.issubset(reviewed_rows):
            raise ValueError("Selected source rows have not all passed visual review: " + job["id"])
        with Image.open(raw) as sheet:
            sheet = sheet.convert("RGBA")
            drawn = sheet_poses(sheet, job)
            page_scale = 256.0 / (sheet.width / job["columns"])
            for row, item in enumerate(job["row_order"]):
                row = int(item.get("source_row", row))
                for col in range(6):
                    key = (item["state"], item["direction"], col)
                    if key in frames: raise ValueError("Multiple drawings claim the same pose: " + str(key))
                    pose = drawn[row, col]
                    # Requests with fewer rows can return larger pixel cells.
                    # Convert the whole page to the same physical cell units
                    # before choosing one shared scale for this creature.
                    frames[key] = pose.resize((max(1, round(pose.width * page_scale)), max(1, round(pose.height * page_scale))), Image.Resampling.LANCZOS)
        sources.append({"file": job["output"], "sha256": actual_hash, "prompt_sha256": job["prompt_sha256"],
                        "reference_sha256": job["reference_sha256"], "model": job["model"], "visual_review": review,
                        "page_to_nominal_cell_scale": page_scale})
    expected = {(state, direction, col) for state in actor["states"] for direction in DIRECTIONS for col in range(6)}
    if frames.keys() != expected:
        raise ValueError("Incomplete state/facing/pose grid for " + actor["id"])
    with Image.open(ROOT / actor["source"]) as original:
        bbox = original.convert("RGBA").getbbox()
        desired_height = (bbox[3] - bbox[1]) / original.height * actor["frame_size"]
    median_height = float(np.median([frame.height for frame in frames.values()]))
    size = actor["frame_size"]
    scale = min(desired_height / median_height, size * .91 / max(p.width for p in frames.values()),
                size * .82 / max(p.height for p in frames.values()))
    normalized = {}
    for key, pose in frames.items():
        width, height = max(1, round(pose.width * scale)), max(1, round(pose.height * scale))
        pose = pose.resize((width, height), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (size, size))
        frame.alpha_composite(pose, ((size - width) // 2, round(size * .84722) - height))
        normalized[key] = frame
    # A duplicated frame is not proof of independently drawn animation.
    for state in actor["states"]:
        for direction in DIRECTIONS:
            hashes = [hashlib.sha256(normalized[state, direction, c].tobytes()).hexdigest() for c in range(6)]
            if len(set(hashes)) < 5:
                raise ValueError("Insufficient distinct drawings: " + actor["id"] + " / " + state + " / " + direction)
    return normalized, sources, scale


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="+")
    args = parser.parse_args()
    plan = json.loads((OUT / "plan.json").read_text("utf8"))
    current_roster = roster(json.loads((ROOT / "game/data/catalog.json").read_text("utf8")))
    if {a["id"]: a["source_sha256"] for a in current_roster} != {a["id"]: a["source_sha256"] for a in plan["actors"]}:
        raise ValueError("Current catalog/source roster differs from the drawing plan")
    progress = json.loads((OUT / "generation-progress.json").read_text("utf8"))["jobs"]
    priority = OUT / "generation-priority.json"
    if priority.is_file(): progress.update(json.loads(priority.read_text("utf8"))["jobs"])
    reviews = json.loads((OUT / "visual-reviews.json").read_text("utf8"))["jobs"]
    actors = [a for a in plan["actors"] if not args.only or a["id"] in args.only]
    if args.only and set(args.only) != {a["id"] for a in actors}: raise ValueError("Unknown creature identity")
    # Validate every selected drawing before modifying any runtime art.
    prepared = {a["id"]: inspect_actor(a, [j for j in plan["jobs"] if j["actor"] == a["id"] and j.get("purpose") != "reference_pose"], progress, reviews) for a in actors}
    manifest_path = ROOT / "game/assets/animation-manifest.json"
    manifest = json.loads(manifest_path.read_text("utf8"))
    runtime_path = ROOT / "game/assets/creature-actions.json"
    runtime = json.loads(runtime_path.read_text("utf8")) if runtime_path.is_file() else {"version": 1, "actors": {}}
    replacements = {(a["id"], s) for a in actors for s in a["states"]}
    manifest["strips"] = [r for r in manifest["strips"] if (r["actor"], r["state"]) not in replacements]
    for actor in actors:
        identity, size = actor["id"], actor["frame_size"]
        normalized, sources, scale = prepared[identity]
        folder = ROOT / "game/assets" / FOLDERS[actor["kind"]] / identity
        folder.mkdir(parents=True, exist_ok=True)
        entry = {"kind": actor["kind"], "frame_size": size, "method": METHOD, "states": {},
                 "source_sha256": actor["source_sha256"], "uniform_scale": scale}
        for state in actor["states"]:
            atlas = Image.new("RGBA", (size * 6, size * 4))
            for row, direction in enumerate(DIRECTIONS):
                for column in range(6): atlas.alpha_composite(normalized[state, direction, column], (column * size, row * size))
            target = folder / (state + ".png")
            backup = ROOT / ".local-tools/creature-actions-before" / identity / (state + ".png")
            if target.is_file() and not backup.is_file():
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
            atlas.save(target)
            fps = 18 if state == "hurt" else 1 / .065
            record = {"actor": identity, "kind": actor["kind"], "state": state, "frames": 6, "directions": DIRECTIONS,
                      "frame_size": size, "fps": fps, "anchor": [.5, .84722], "file": target.relative_to(ROOT).as_posix(),
                      "source": sources, "sha256": digest(target), "method": METHOD,
                      "frame_sha256": {d: [hashlib.sha256(normalized[state, d, c].tobytes()).hexdigest() for c in range(6)] for d in DIRECTIONS}}
            manifest["strips"].append(record)
            entry["states"][state] = {key: record[key] for key in ["frames", "directions", "frame_size", "fps", "sha256", "frame_sha256"]}
            entry["states"][state]["path"] = "res://" + target.relative_to(ROOT / "game").as_posix()
        runtime["actors"][identity] = entry
    wanted = {a["id"]: set(a["states"]) for a in current_roster}
    complete = runtime["actors"].keys() == wanted.keys() and all(set(runtime["actors"][i]["states"]) == s for i, s in wanted.items())
    runtime.update({"complete": complete, "expected_actors": len(wanted), "expected_action_poses": plan["expected_action_poses"],
                    "catalog_sha256": digest(ROOT / "game/data/catalog.json"), "directions": DIRECTIONS,
                    "compiled_actors": len(runtime["actors"]), "compiled_action_poses": sum(len(a["states"]) * 24 for a in runtime["actors"].values())})
    manifest["method"] = "Independently drawn hero/equipment and creature action atlases; legacy locomotion/death are separately identified per strip."
    write_json(manifest_path, manifest)
    write_json(runtime_path, runtime)
    print(f"Compiled {len(actors)} creatures; catalog coverage {runtime['compiled_actors']}/{runtime['expected_actors']}; complete={complete}.")


if __name__ == "__main__": main()
