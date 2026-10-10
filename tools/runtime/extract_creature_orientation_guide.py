"""Crop one visually inspected pose only as a generation reference, never runtime animation."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image
from compile_creature_action_revision import sheet_poses

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/creature-action-revision"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    parser.add_argument("--row", type=int, required=True)
    parser.add_argument("--column", type=int, default=0)
    parser.add_argument("--direction", required=True, choices=["down", "left", "right", "up"])
    parser.add_argument("--note", required=True)
    args = parser.parse_args()
    plan = json.loads((OUT / "plan.json").read_text("utf8"))
    job = next(j for j in plan["jobs"] if j["id"] == args.job)
    raw = ROOT / job["output"]
    with Image.open(raw) as sheet:
        pose = sheet_poses(sheet.convert("RGBA"), job, required_cells={(args.row,args.column)})[args.row, args.column]
    pose.thumbnail((384, 384), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512,512))
    canvas.alpha_composite(pose, ((512-pose.width)//2, round(512*.84722)-pose.height))
    target = OUT / "references" / (job["actor"]+"-"+args.direction+"-inspected-pose.png")
    canvas.save(target)
    target.with_suffix(".json").write_text(json.dumps(dict(
        purpose="Visually inspected orientation reference; final six poses must be independently generated",
        source=job["output"], source_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(),
        row=args.row, column=args.column, declared_direction=args.direction,
        visual_finding=args.note, guide_sha256=hashlib.sha256(target.read_bytes()).hexdigest()), ensure_ascii=False, indent=2)+"\n", "utf8")
    print(target.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
