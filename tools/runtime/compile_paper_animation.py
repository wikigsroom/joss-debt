"""Animate the approved Sub2 sprites as paper puppets without redrawing their identity.

Shared ground pivots, small articulated folds and paper-strip dispersal produce real
transparent frame strips. This is deterministic animation processing, not image generation.
"""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "game/assets"
COUNTS = {"character": {"idle": 4, "run": 6, "cast": 4, "dash": 3, "hurt": 2, "death": 5},
          "enemy": {"idle": 3, "move": 4, "tell": 3, "attack": 3, "hurt": 2, "death": 5},
          "boss": {"idle": 3, "attack_a": 4, "attack_b": 4, "attack_c": 4, "phase": 3, "hurt": 2, "death": 6},
          "npc": {"idle": 3, "talk": 3}}
SPEED = {"idle": 5, "run": 12, "move": 10, "cast": 12, "dash": 15, "hurt": 16, "death": 10,
         "tell": 10, "attack": 12, "attack_a": 10, "attack_b": 12, "attack_c": 14, "phase": 8, "talk": 6}

def deform(source, state, frame, count):
    rgba = np.asarray(source.convert("RGBA"), dtype=np.float64) / 255
    n = source.width
    y, x = np.mgrid[:n, :n].astype(float)
    px, py = n * .5, n * .84
    phase = frame / count * math.tau
    t = frame / max(1, count - 1)
    dx = np.zeros_like(x)
    dy = np.zeros_like(y)
    u = x.copy()
    v = y.copy()
    alpha = np.ones_like(x)
    # Local masks articulate top folds, torso and left/right feet around one pivot.
    head = np.clip((py - y) / (n * .6), 0, 1)
    foot = np.clip((y - n * .63) / (n * .2), 0, 1)
    if state == "idle":
        dx = math.sin(phase) * n * .007 * head
        dy = math.cos(phase) * n * .003 * head
    elif state in ["run", "move"]:
        dx = math.sin(phase) * n * .012 * head
        dy = abs(math.sin(phase)) * n * .018 * head
        dy += math.sin(phase) * np.where(x < px, 1, -1) * n * .027 * foot
        dx += math.cos(phase) * n * .008 * foot
    elif state in ["cast", "attack", "attack_a", "attack_b", "attack_c", "tell", "talk", "phase"]:
        impulse = [0, .35, 1, .18][frame] if count == 4 else math.sin(t * math.pi)
        side = np.clip(abs(x - px) / (n * .3), 0, 1)
        dx = np.sign(x - px) * n * .014 * impulse * side * head
        dy = n * .025 * impulse * (1 - .6 * side) * head
        if state == "phase": dx += np.sin(y / n * math.tau) * n * .014 * impulse
        if state == "talk": dy *= .4
    elif state == "dash":
        squash = [.92, .80, .94][frame]
        v = py + (y - py) / squash
        dx = n * .013 * (1 if frame == 1 else -1) * head
    elif state == "hurt":
        angle = .055 if frame == 0 else -.023
        u = px + (x - px) * math.cos(angle) - (y - py) * math.sin(angle)
        v = py + (x - px) * math.sin(angle) + (y - py) * math.cos(angle)
    elif state == "death":
        # Three torn-paper sections separate; the last frame dissolves completely.
        section = np.floor(np.clip((x - n * .14) / (n * .24), 0, 2)) - 1
        dx = section * n * .10 * t
        dy = -n * .15 * t * (1 - .22 * section)
        alpha *= (1 - t) ** .9
    u -= dx
    v -= dy
    premultiplied = rgba.copy()
    premultiplied[:, :, :3] *= rgba[:, :, 3:4]
    warped = np.stack([map_coordinates(premultiplied[:, :, c], [v, u], order=1, mode="constant", cval=0) for c in range(4)], axis=2)
    warped[:, :, :3] /= np.maximum(warped[:, :, 3:4], 1e-9)
    warped[:, :, 3] *= alpha
    warped[warped[:, :, 3] < 1 / 255] = 0
    return Image.fromarray(np.clip(warped * 255, 0, 255).astype(np.uint8))

def main():
    rig_path = ASSETS / "weapon-rig.json"
    if rig_path.exists() and json.loads(rig_path.read_text("utf8")).get("animation_method") == "independently_drawn_six_frame_poses":
        raise RuntimeError("Independent action atlases are installed. Use compile_action_revision.py; legacy deformation cannot overwrite them.")
    catalog = json.loads((ROOT / "game/data/catalog.json").read_text("utf8"))
    records = []
    sample = []
    groups = [("character", "characters", "characters", 96), ("enemy", "enemies", "enemy-animation", 128),
              ("boss", "bosses", "boss-animation", 256), ("npc", "npcs", "npc-animation", 128),
              ("enemy", "elite_variants", "elite-animation", 128)]
    for kind, table, folder, frame_size in groups:
        for actor in catalog[table]:
            directions = ["down", "left", "right", "up"] if kind == "character" else ["down"]
            sources = [ASSETS / "heroes" / (actor["id"] + "_" + direction + ".png") for direction in directions] if kind == "character" else [ASSETS / ("elites" if table == "elite_variants" else table) / (actor["id"] + ".png")]
            if not all(p.exists() for p in sources): continue
            destination = ASSETS / folder / actor["id"]
            destination.mkdir(parents=True, exist_ok=True)
            for state, count in COUNTS[kind].items():
                atlas = Image.new("RGBA", (count * frame_size, len(directions) * frame_size))
                frames = []
                for row, path in enumerate(sources):
                    source = Image.open(path).convert("RGBA")
                    for column in range(count):
                        pose = deform(source, state, column, count)
                        atlas.alpha_composite(pose, (column * frame_size, row * frame_size))
                        if row == 0: frames.append(pose)
                output = destination / (state + ".png")
                atlas.save(output)
                records.append({"actor": actor["id"], "kind": kind, "state": state, "frames": count,
                                "directions": directions, "frame_size": frame_size, "fps": SPEED[state],
                                "anchor": [.5, .84], "file": output.relative_to(ROOT).as_posix(),
                                "source": [{"file": p.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources],
                                "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "method": "approved base-pose paper puppet deformation"})
                if kind == "character" and state == "run": sample.append((actor["id"], frames))
    report = ROOT / "docs/incense-debt/reports/runtime"
    report.mkdir(parents=True, exist_ok=True)
    (ASSETS / "animation-manifest.json").write_text(json.dumps({"strips": records, "method": "deterministic animation from reference-locked Sub2API source sprites; no redraw"}, ensure_ascii=False, indent=2) + "\n", "utf8")
    preview_frames = []
    for i in range(6):
        canvas = Image.new("RGBA", (768, 154), (36, 39, 37, 255))
        draw = ImageDraw.Draw(canvas)
        for j, (actor, frames) in enumerate(sample):
            canvas.alpha_composite(frames[i], (j * 128 + 16, 20))
            draw.text((j * 128 + 12, 127), actor, fill=(231, 216, 182))
        preview_frames.append(canvas.convert("RGB"))
    preview_frames[0].save(report / "paper-animation.gif", save_all=True, append_images=preview_frames[1:], duration=84, loop=0)
    print(f"Compiled {len(records)} transparent animation strips from approved source poses.")

if __name__ == "__main__":
    main()
