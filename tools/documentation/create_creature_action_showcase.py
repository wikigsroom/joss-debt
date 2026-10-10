"""Assemble README GIFs from hash-bound native creature captures."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/creature-actions-2026-10-10"
CAPTURES = ROOT / ".local-tools/native-creature-frames"
DIRECTIONS = ("down", "left", "right", "up")


def main():
    evidence = json.loads((REPORT / "native-coverage.json").read_text("utf8"))
    current = hashlib.sha256((ROOT / "game/assets/creature-actions.json").read_bytes()).hexdigest()
    if not evidence["complete"] or evidence["manifest_sha256"] != current:
        raise RuntimeError("README media requires native evidence for the current complete creature assets")
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    for identity, filename, states in (
        ("e256", "enemy-four-directions.gif", ("attack", "hurt")),
        ("b28", "boss-four-directions.gif", ("attack_a", "attack_b", "attack_c", "hurt")),
    ):
        frames = []
        hashes = evidence["actors"][identity]["screenshots_sha256"]
        for index in range(6):
            board = Image.new("RGB", (256 * len(states), 282 * 4), "#24333a")
            draw = ImageDraw.Draw(board)
            for row, direction in enumerate(DIRECTIONS):
                for column, state in enumerate(states):
                    name = f"{identity}-{state}-{direction}-{index}.png"
                    source = CAPTURES / name
                    if hashlib.sha256(source.read_bytes()).hexdigest() != hashes[name]:
                        raise RuntimeError("Native capture differs from the reviewed evidence: " + name)
                    with Image.open(source) as capture:
                        board.paste(capture.convert("RGB"), (column * 256, row * 282 + 26))
                    draw.text((column * 256 + 8, row * 282 + 5),
                              f"{identity} / {state} / {direction} / {index + 1}",
                              font=font, fill="#efdfb7")
            frames.append(board)
        target = REPORT / filename
        frames[0].save(target, save_all=True, append_images=frames[1:],
                       duration=140, loop=0, optimize=True, disposal=2)
        frames[2].save(REPORT / filename.replace(".gif", "-preview.jpg"), quality=93, subsampling=0)
        with Image.open(target) as gif:
            if gif.n_frames != 6 or gif.info.get("loop") != 0:
                raise RuntimeError("Invalid six-frame looping README GIF: " + filename)
        print(f"{filename}: six native comparison frames, {target.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
