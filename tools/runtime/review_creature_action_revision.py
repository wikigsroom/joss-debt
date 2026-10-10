"""Produce readable review boards; accept only explicit, hash-bound human inspection.

Rendering a board never approves it. Connected-component checks identify cut or
joined drawings before review, without manufacturing missing poses.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont
from compile_creature_action_revision import sheet_poses

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/creature-action-revision"
BOARDS = ROOT / ".local-tools/creature-review-boards"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", nargs="+")
    parser.add_argument("--limit", type=int, default=3)
    parser.add_argument("--accept-review", help="Explicit review records written after inspecting the displayed boards")
    args = parser.parse_args()
    plan = json.loads((OUT / "plan.json").read_text("utf8"))
    reviews_path = OUT / "visual-reviews.json"
    reviews = json.loads(reviews_path.read_text("utf8"))
    jobs = {j["id"]: j for j in plan["jobs"]}
    if args.accept_review:
        records = json.loads(Path(args.accept_review).read_text("utf8"))
        for identity, record in records.items():
            job = jobs[identity]
            raw = ROOT / job["output"]
            if record.get("raw_sha256") != digest(raw):
                raise ValueError("Reviewed drawing has changed: " + identity)
            rows = record.get("accepted_source_rows", [])
            if not rows or len(set(rows)) != len(rows) or any(r not in range(job["rows"]) for r in rows):
                raise ValueError("Specify the exact inspected rows: " + identity)
            if not record.get("review_note") or record.get("verdict") != "accepted":
                raise ValueError("An explicit visual finding is required: " + identity)
            with Image.open(raw) as source:
                sheet_poses(source.convert("RGBA"), job)
        for identity, record in records.items():
            reviews["jobs"][identity] = dict(record, reviewed_cells=len(record["accepted_source_rows"])*6,
                reviewed_at=datetime.now(timezone.utc).isoformat(),
                reviewer="Codex inspection of every selected pose on identity-referenced source boards")
        temporary = reviews_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(reviews, ensure_ascii=False, indent=2)+"\n", "utf8")
        temporary.replace(reviews_path)
        print("Recorded explicit visual findings for " + str(len(records)) + " source pages.")
        return
    progress = {}
    for filename in ["generation-progress.json", "generation-priority.json"]:
        path = OUT / filename
        if path.is_file():
            progress.update(json.loads(path.read_text("utf8")).get("jobs", {}))
    selected = [j for j in plan["jobs"] if j.get("purpose") != "reference_pose" and
        (j["id"] in args.jobs if args.jobs else progress.get(j["id"], {}).get("state") == "raw_verified" and
         reviews["jobs"].get(j["id"], {}).get("verdict") != "accepted")]
    if not args.jobs:
        selected = selected[:args.limit]
    if args.jobs and set(args.jobs) != {j["id"] for j in selected}:
        raise ValueError("Unknown review page")
    if not selected:
        print("No unreviewed complete source pages are currently available.")
        return
    BOARDS.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 20)
    boards = []
    for offset in range(0, len(selected), 3):
        batch = selected[offset:offset+3]
        board_height = 170 + max(round(960*j["rows"]/j["columns"]) for j in batch)
        board = Image.new("RGB", (len(batch)*992, board_height), "#58615e")
        draw = ImageDraw.Draw(board)
        metadata = {}
        for index, job in enumerate(batch):
            x = index*992
            raw = ROOT / job["output"]
            with Image.open(raw) as source:
                source = source.convert("RGBA")
                raw_hash = digest(raw)
                try:
                    inspected = sheet_poses(source, job)
                    structural = str(len(inspected)) + " complete separated selected poses"
                except ValueError as error:
                    structural = str(error)
                preview = source.copy()
                preview.thumbnail((960, 1280), Image.Resampling.LANCZOS)
                board.paste(preview, (x+16, 160), preview)
            with Image.open(ROOT / job["source"]) as seed:
                seed = seed.convert("RGBA")
                seed.thumbnail((128, 128), Image.Resampling.NEAREST)
                board.paste(seed, (x+832, 10), seed)
            draw.text((x+16, 12), job["id"], fill="#fff2d2", font=font)
            draw.text((x+16, 42), "Rows: front A/H; left A/H; right A/H; rear A/H" if job["rows"] == 8 else str(job["row_order"]), fill="#fff2d2", font=font)
            draw.text((x+16, 72), "SHA256 " + raw_hash[:24], fill="#d6dbd6", font=font)
            draw.text((x+16, 102), structural[:78], fill="#fff2d2", font=font)
            metadata[job["id"]] = dict(raw_sha256=raw_hash, structural=structural, rows=job["rows"], source=job["source"])
        target = BOARDS / ("__".join(j["id"] for j in batch)+".png")
        board.save(target)
        target.with_suffix(".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+"\n", "utf8")
        boards.append(str(target))
    print(json.dumps(dict(boards=boards), ensure_ascii=False))


if __name__ == "__main__":
    main()
