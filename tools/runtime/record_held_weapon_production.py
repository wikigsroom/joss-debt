"""Record actual image requests and review decisions, without gateway credentials."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]


def entry(path):
    p = ROOT / path
    return {"file": path, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}


def main():
    folder = "output/imagegen/incense-debt/held-weapons/"
    neutral_prompt = "docs/incense-debt/assets/prompts/reference-locked-neutral-grips.txt"
    held_prompt = "docs/incense-debt/assets/prompts/reference-locked-held-weapons.txt"
    attempts = [
        {"operation": "edit", "endpoint": "/images/edits", "references": [entry(folder+"approved-poses-edit-canvas.png"), entry(folder+"grip-edit-guide.png"), entry("output/imagegen/incense-debt/characters-roster.png")],
         "prompt": entry(neutral_prompt), "status": "failed", "http_status": 400,
         "error": "Tool choice 'image_generation' not found in 'tools' parameter.", "output_created": False},
        {"operation": "generate", "endpoint": "/images/generations", "references": [], "prompt": entry(held_prompt),
         "output": entry(folder+"held-weapons-generation-check.png"), "status": "generated_but_rejected_for_production",
         "review": "same gateway/model availability check succeeded; bell/censer/lamp details differ from the binding reference, so this image is not a game asset source"},
        {"operation": "edit", "endpoint": "/images/edits", "references": [entry(folder+"approved-poses-edit-canvas.png")], "prompt": entry(neutral_prompt),
         "output": entry(folder+"neutral-grips-single-reference.png"), "status": "accepted_local_grip_regions_only",
         "review": "generated full-body identity edits were discarded; all original RGBA outside the reviewed masks is retained byte-for-byte; no colored guide was supplied in this successful call"},
        {"operation": "edit", "endpoint": "/images/edits", "references": [entry("output/imagegen/incense-debt/runtime/weapons.png")], "prompt": entry(held_prompt),
         "output": entry(folder+"held-weapons-reference-edit.png"), "status": "accepted_held_cutouts",
         "review": "retains original coarse contours, paper, bronze, lamp face, bell holes and weapon identities; closed umbrella is a held variant; original icons remain unchanged"},
    ]
    report = {"recorded_at": datetime.now(timezone.utc).isoformat(), "provider": "sub2-image-gen", "model": "gpt-image-2.5",
              "quality": "high", "size": "1536x1024", "background": "transparent", "attempts": attempts,
              "recovery": "single-reference edits succeeded on the same configured gateway/model; the first failure's cause is not inferred from this result",
              "body_checks": "docs/incense-debt/reports/runtime/held-weapons/body-processing.json", "virtualization": "none"}
    target = ROOT / "docs/incense-debt/reports/runtime/held-weapons/image-production.json"
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    queue_path = ROOT / "docs/incense-debt/assets/runtime-production-queue.json"
    queue = json.loads(queue_path.read_text("utf8"))
    for job in queue["jobs"]:
        if job["name"] == "neutral-grips":
            job["references"] = [folder+"approved-poses-edit-canvas.png"]
            job["output"] = folder+"neutral-grips-single-reference.png"
        elif job["name"] == "held-weapons":
            job["references"] = ["output/imagegen/incense-debt/runtime/weapons.png"]
            job["output"] = folder+"held-weapons-reference-edit.png"
        else: continue
        job["production_report"] = target.relative_to(ROOT).as_posix()
    queue_path.write_text(json.dumps(queue,ensure_ascii=False,indent=2)+"\n","utf8")
    print("Recorded failed request, rejected generation probe and two accepted same-model reference edits.")


if __name__ == "__main__": main()
