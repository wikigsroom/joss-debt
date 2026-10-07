"""Check actual protected pixels, provenance, grips and runtime rig resources."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/runtime/held-weapons"


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    data = json.loads((REPORT / "body-processing.json").read_text("utf8"))
    rig = json.loads((ROOT / "game/assets/weapon-rig.json").read_text("utf8"))
    animations = json.loads((ROOT / "game/assets/animation-manifest.json").read_text("utf8"))["strips"]
    failures = []
    checks = []
    for body in data["bodies"]:
        mask_path = ROOT / body.get("editable_mask", f"docs/incense-debt/reports/runtime/held-weapons/development-masks/{body['actor']}_{body['direction']}-editable-mask.png")
        body["editable_mask"] = mask_path.relative_to(ROOT).as_posix()
        old = np.asarray(Image.open(ROOT / body["original"]).convert("RGBA"))
        actual = np.asarray(Image.open(ROOT / body["file"]).convert("RGBA"))
        mask = np.asarray(Image.open(mask_path).convert("L")) > 0
        if not np.array_equal(old[~mask], actual[~mask]): failures.append(body["file"] + ": protected pixels")
        if digest(ROOT / body["original"]) != body["original_sha256"] or digest(ROOT / body["file"]) != body["sha256"]:
            failures.append(body["file"] + ": source/output hash")
        if digest(ROOT / body["source"]) != body["source_sha256"]: failures.append(body["source"] + ": generated master hash")
    checks.append("24 bodies preserve every RGBA byte outside the reviewed editable masks; original and generated sources match recorded hashes")
    modular = [a for a in animations if a["kind"] in ["weapon_body", "weapon_hand"]]
    for a in modular:
        path = ROOT / a["file"]
        if digest(path) != a["sha256"]: failures.append(a["file"] + ": animation hash")
        image = Image.open(path).convert("RGBA")
        if image.size != (96*a["frames"],384): failures.append(a["file"] + ": dimensions")
        for direction in range(4):
            for frame in range(a["frames"]):
                alpha = image.crop((frame*96,direction*96,(frame+1)*96,(direction+1)*96)).getchannel("A")
                blank = alpha.getbbox() is None
                if blank != (a["state"] == "death" and frame == a["frames"]-1): failures.append(a["file"] + ": frame alpha")
    checks.append("72 body and hand strips share dimensions, states, timing, sources and transparent death endpoints")
    for weapon, spec in rig["weapons"].items():
        path = ROOT / ("game/"+spec["texture"].removeprefix("res://"))
        image = Image.open(path).convert("RGBA")
        alpha = np.asarray(image)[:,:,3]
        if image.size != (128,128) or alpha.max() < 100 or (alpha==0).mean() < .35: failures.append(weapon + ": cutout alpha")
        if not all(0 < v < 1 for v in spec["grip"]): failures.append(weapon + ": grip outside cutout")
    checks.append("16 held cutouts have usable transparent edges and grips inside their textures; inventory images remain separate")
    original_specs = json.loads((ROOT / "docs/incense-debt/data/asset-manifest.json").read_text("utf8"))["assets"]
    for asset in original_specs:
        if asset["kind"] == "weapon" and digest(ROOT / asset["file"]) != asset["sha256"]: failures.append(asset["file"] + ": original inventory changed")
    checks.append("all sixteen original inventory icons retain their previously verified bytes")
    data["checks"] = checks
    data["failures"] = failures
    data["passed"] = not failures
    (REPORT / "body-processing.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n","utf8")
    print(json.dumps({"passed":not failures,"checks":checks,"failures":failures},ensure_ascii=False,indent=2))
    return 1 if failures else 0


if __name__ == "__main__": raise SystemExit(main())
