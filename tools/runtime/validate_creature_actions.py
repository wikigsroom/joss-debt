"""Catalog-derived shipping gate for every independently drawn creature action."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image
from prepare_creature_action_revision import roster

ROOT = Path(__file__).resolve().parents[2]
METHOD = "independently drawn Sub2 creature action frames"
DIRECTIONS = ["down", "left", "right", "up"]


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(root=ROOT, allow_incomplete=False):
    path = root / "game/assets/creature-actions.json"
    manifest = json.loads(path.read_text("utf8"))
    catalog_path = root / "game/data/catalog.json"
    expected = {actor["id"]: actor for actor in roster(json.loads(catalog_path.read_text("utf8")))}
    strips = json.loads((root / "game/assets/animation-manifest.json").read_text("utf8"))["strips"]
    records = {(r["actor"], r["state"]): r for r in strips if r.get("method") == METHOD}
    actors = manifest["actors"]
    missing = sorted(set(expected) - set(actors))
    extra = sorted(set(actors) - set(expected))
    if extra: raise ValueError("Unknown creature identities: " + str(extra))
    if manifest.get("catalog_sha256") != digest(catalog_path): raise ValueError("Creature action catalog fingerprint is stale")
    poses = 0
    for identity, entry in actors.items():
        actor = expected[identity]
        if entry.get("method") != METHOD or entry.get("source_sha256") != actor["source_sha256"] or entry.get("kind") != actor["kind"]:
            raise ValueError("Incorrect creature identity provenance: " + identity)
        if set(entry["states"]) != set(actor["states"]): raise ValueError("Missing or extra action states: " + identity)
        for state, animation in entry["states"].items():
            size = actor["frame_size"]
            atlas_path = root / "game" / animation["path"].removeprefix("res://")
            record = records.get((identity, state), {})
            if animation.get("frames") != 6 or animation.get("directions") != DIRECTIONS or animation.get("frame_size") != size:
                raise ValueError("Incorrect six-frame four-facing action layout: " + identity + "/" + state)
            if not atlas_path.is_file() or animation["sha256"] != digest(atlas_path) or record.get("sha256") != animation["sha256"]:
                raise ValueError("Missing or stale compiled creature atlas: " + str(atlas_path))
            if record.get("source") is None: raise ValueError("Creature atlas has no independent drawing provenance")
            for source in record["source"]:
                if source.get("model") != "gpt-image-2.5" or source.get("visual_review", {}).get("verdict") != "accepted":
                    raise ValueError("Unreviewed or wrong-provider drawing source: " + identity)
                if not (root / source["file"]).is_file() or source["sha256"] != digest(root / source["file"]):
                    raise ValueError("Drawing source changed after compilation: " + identity)
            with Image.open(atlas_path) as atlas:
                if atlas.mode != "RGBA" or atlas.size != (size * 6, size * 4) or atlas.getextrema()[3][0] != 0:
                    raise ValueError("Creature atlas dimensions/transparency failed: " + str(atlas_path))
                for row, direction in enumerate(DIRECTIONS):
                    hashes = []
                    for column in range(6):
                        frame = atlas.crop((column*size, row*size, (column+1)*size, (row+1)*size))
                        if frame.getbbox() is None: raise ValueError("Empty runtime pose: " + identity)
                        sha = hashlib.sha256(frame.tobytes()).hexdigest()
                        if sha != animation["frame_sha256"][direction][column]: raise ValueError("Runtime pose fingerprint differs from the accepted normalization")
                        hashes.append(sha)
                        poses += 1
                    if len(set(hashes)) < 5: raise ValueError("Insufficient independently drawn action poses: " + identity)
    complete = not missing and not extra
    if bool(manifest.get("complete")) != complete: raise ValueError("Creature manifest incorrectly claims full coverage")
    result = {"complete": complete, "compiled_identities": len(actors), "expected_identities": len(expected),
              "independent_action_poses": poses, "expected_action_poses": sum(len(a["states"])*24 for a in expected.values()), "missing_identities": missing}
    if not complete and not allow_incomplete:
        raise ValueError(f"Creature action revision is incomplete: {len(actors)}/{len(expected)} identities. Export is deferred until every enemy, boss, elite and sigil passes.")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()
    result = validate(allow_incomplete=args.allow_incomplete)
    print(json.dumps({key: value for key, value in result.items() if key != "missing_identities"}, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
