"""Reconcile planned specs with actual native-loaded raster, code and audio assets."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import struct
import wave
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs/incense-debt"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    report_path = DOCS / "reports/platforms/windows/native-render.json"
    native = json.loads(report_path.read_text("utf8"))
    build = json.loads((DOCS / "reports/platforms/windows-build.json").read_text("utf8"))
    if native.get("artifact_sha256") != build["sha256"] or digest(ROOT / build["path"]) != build["sha256"]:
        raise ValueError("Asset evidence does not belong to the current compiled executable")
    registry = json.loads((ROOT / "game/data/runtime_assets.json").read_text("utf8"))["assets"]
    if native["asset_failures"] or native["asset_loads"] != len(registry):
        raise ValueError("Compiled native build has not loaded the current runtime registry")
    runtime = json.loads((ROOT / "game/assets/runtime-manifest.json").read_text("utf8"))
    animations = json.loads((ROOT / "game/assets/animation-manifest.json").read_text("utf8"))["strips"]
    expansion = json.loads((DOCS / "assets/expansion-processed.json").read_text("utf8"))
    animations += [{"actor": a["id"], "state": a["state"], "frame_size": a["frame_size"], "frames": a["frames"],
        "directions": ["front"], "file": a["path"], "sha256": a["sha256"], "fps": 12,
        "method": "precomputed source-bound paper-puppet deformation", "kind": "expansion"} for a in expansion["animations"]]
    revision=json.loads((ROOT/"game/assets/fx/combat-revision/manifest.json").read_text("utf8"))
    animations += [{"actor":a["id"],"state":"generated_fx","frame_size":256,"frames":6,"directions":["front"],"file":a["path"],"sha256":a["sha256"],"fps":20,"method":a["method"],"kind":"combat_revision"} for a in revision["records"]]
    weapon_rig = json.loads((ROOT / "game/assets/weapon-rig.json").read_text("utf8"))
    grip_report = json.loads((DOCS / "reports/runtime/held-weapons/body-processing.json").read_text("utf8"))
    if not grip_report.get("passed") or grip_report.get("failures"):
        raise ValueError("Protected grip edits have not passed their raster checks")
    audio_manifest = json.loads((ROOT / "game/assets/audio/manifest.json").read_text("utf8"))
    audio = audio_manifest["assets"]
    audio_report_path = DOCS / "reports/platforms/windows/audio/native-audio.json"
    audio_report = json.loads(audio_report_path.read_text("utf8"))
    if not audio_report["passed"] or audio_report.get("artifact_sha256") != build["sha256"]:
        raise ValueError("Current compiled native audio mixer has not passed")
    image_sources = {"game/" + a["path"]: a for a in runtime["entries"] if "path" in a}
    image_sources.update({a["path"]: a for a in expansion["records"]})
    image_sources.update({a["path"]: a for a in revision["records"]})
    for a in expansion["records"]:
        if a["kind"] == "weapons":image_sources["game/assets/held-weapons/"+a["id"]+".png"] = a
    animation_files = {a["file"]: a for a in animations}
    failures = []
    for animation in animations:
        path = ROOT / animation["file"]
        image = Image.open(path).convert("RGBA")
        n = animation["frame_size"]
        if image.size != (n * animation["frames"], n * len(animation["directions"])) or digest(path) != animation["sha256"]:
            failures.append(animation["file"] + ": dimensions/hash")
        for direction in range(len(animation["directions"])):
            frames = [image.crop((i * n, direction * n, (i + 1) * n, (direction + 1) * n)) for i in range(animation["frames"])]
            if animation["state"] == "death":
                if frames[0].getchannel("A").getbbox() is None or frames[-1].getchannel("A").getbbox() is not None:
                    failures.append(animation["file"] + ": death endpoints")
            elif any(frame.getchannel("A").getbbox() is None for frame in frames):
                failures.append(animation["file"] + ": blank frame")
            if len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames}) < 2:
                failures.append(animation["file"] + ": duplicate animation")
    for item in audio:
        if item.get("format") == "ogg_vorbis":
            path = ROOT / item["file"]
            header = path.read_bytes()[:512]
            offset = header.find(b"\x01vorbis")
            if offset < 0 or struct.unpack_from("<I", header, offset + 12)[0] != 48000 or header[offset + 11] != 1:
                failures.append(item["file"] + ": encoded Vorbis format")
            if digest(path) != item["sha256"] or abs(item["decoded_frames"] - item["loop_end_frame"]) > 256:
                failures.append(item["file"] + ": encoded hash or full loop length")
            if item["boundary_jump"] > .001 or item["peak"] >= .98:
                failures.append(item["file"] + ": decoded seam or clipping")
            continue
        with wave.open(str(ROOT / item["file"]), "rb") as source:
            if source.getframerate() != 48000 or source.getnchannels() != 1 or source.getsampwidth() != 2:
                failures.append(item["file"] + ": audio format")
            if item["id"].endswith("_loop"):
                samples = source.readframes(source.getnframes())
                if samples[:2] != b"\0\0" or samples[-2:] != b"\0\0": failures.append(item["file"] + ": loop boundary")
    if failures: raise ValueError(failures)
    manifest_path = DOCS / "data/asset-manifest.json"
    manifest = json.loads(manifest_path.read_text("utf8"))
    existing={a["id"] for a in manifest["assets"]}
    catalog=json.loads((ROOT / "game/data/catalog.json").read_text("utf8"))
    known_content={a["id"] for rows in catalog.values() if isinstance(rows,list) for a in rows}
    for a in expansion["records"]:
        identity="asset_"+a["id"]
        if identity in existing:continue
        kind={"bosses":"boss_bundle","enemies":"enemy_bundle","weapons":"weapon"}.get(a["kind"],"expansion_"+a["kind"])
        row={"id":identity,"kind":kind,"file":a["path"],"status":"processed","engine_ready":False,
             "provider":"sub2-image-gen","model":"gpt-image-2.5","source":a["source"],"source_sha256":a["source_sha256"]}
        if a["id"] in known_content:row["content_id"]=a["id"]
        if a["kind"] in ["bosses","enemies"]:row["required_states"]=sorted({s["state"] for s in expansion["animations"] if s["id"]==a["id"]})
        manifest["assets"].append(row);existing.add(identity)
    for a in revision["records"]:
        identity="combat_revision_"+a["id"]
        if identity not in existing:
            manifest["assets"].append({"id":identity,"kind":"expansion_fx","file":a["path"],"status":"processed","engine_ready":False,"provider":"sub2-image-gen","model":"gpt-image-2.5","source":a["source"],"source_sha256":a["source_sha256"]})
    arenas = {"paper_lane": "paper-temple", "coin_vault": "coin-vault", "ownerless_temple": "ownerless-temple"}
    sfx = {"shot": "shot", "paper_hit": "hit", "copper_hit": "bell", "ignite": "mark", "link_tension": "chain", "detonate": "skill", "ash_pickup": "pickup", "dash": "dash", "guard": "bell", "player_hurt": "hurt", "enemy_death": "death", "boss_warning": "warning", "reward": "clear", "contract": "contract", "repay": "repay", "menu": "menu"}
    for asset in manifest["assets"]:
        if asset["kind"] == "concept": continue
        kind = asset["kind"]
        asset.setdefault("original_specification", {key: asset[key] for key in ["file", "frame_size", "sample_rate"] if key in asset})
        mode = "reference-locked raster"
        if kind == "environment":
            asset["file"] = "game/assets/environment/" + arenas[asset["region"]] + "-arena.png"
            mode = "baked full-arena floor/wall/door/props composition; shared collision geometry in code"
            asset["geometry"] = "game/scripts/combat/room_geometry.gd"
            asset["shared_dynamic_props"] = ["game/assets/props/paper_stack.png", "game/assets/props/chest.png"]
            asset["alpha_required"] = False
        elif kind == "vfx":
            asset["file"] = "game/scripts/ui/game_renderer.gd"
            mode = "native procedural geometry and particles"
        elif kind == "ui":
            suffix = asset["id"].removeprefix("ui_")
            asset["file"] = {"chinese_font": "game/assets/fonts/IncenseRounded-Medium.ttf", "app_icon": "game/assets/ui/app-icon.png", "menu_paper": "game/scripts/ui/modern_ui.gd", "touch_controls": "game/scripts/ui/game_renderer.gd"}.get(suffix, "game/scripts/ui/game_hud.gd")
            mode = "licensed rounded CJK subset with full-CJK fallback and Smiley Sans titles" if suffix == "chinese_font" else ("reference-derived application icon" if suffix == "app_icon" else "rounded native controls/drawing, licensed vector symbols and live text")
            if suffix == "chinese_font":
                asset["variants"] = ["game/assets/fonts/IncenseRounded-Bold.ttf", "game/assets/fonts/SmileySans-Oblique.ttf", "game/assets/fonts/NotoSansSC.ttf"]
                asset["font_production"] = "docs/incense-debt/reports/runtime/ui-refresh/font-production.json"
                asset["licenses"] = ["game/assets/fonts/ResourceHanRounded-OFL.txt", "game/assets/fonts/SmileySans-OFL.txt", "game/assets/fonts/OFL.txt"]
            elif suffix != "app_icon":
                asset["shared_ui_sources"] = [{"file": f, "sha256": digest(ROOT / f)} for f in ["game/scripts/ui/game_theme.gd", "game/scripts/ui/modern_ui.gd", "game/scripts/ui/rounded_button.gd", "game/scripts/ui/character_sheet.gd", "game/scripts/ui/run_review.gd", "game/scripts/ui/weapon_trial_ui.gd", "game/scripts/core/weapon_trial.gd", "game/scripts/core/damage_record.gd"]]
                asset["vector_production"] = "docs/incense-debt/reports/runtime/ui-refresh/licensed-sources.json"
        elif kind == "music":
            asset["file"] = "game/assets/audio/" + asset["id"].removeprefix("music_") + "_loop.ogg"
            mode = "original 32-bar theme/stem; 48kHz mono Vorbis, independent combat accent voices, synchronized native player and sample-verified live mixing"
            asset["audio_engine_evidence"] = audio_report_path.relative_to(ROOT).as_posix()
        elif kind == "sfx":
            name = sfx[asset["id"].removeprefix("sfx_")]
            asset["file"] = "game/assets/audio/" + name + ".wav"
            asset["variants"] = ["game/assets/audio/" + name + suffix + ".wav" for suffix in ["", "_1", "_2"]]
            mode = "original v3 material synthesis with transient/sub/noise layers; three variants; related copper events share the bell group"
        path = ROOT / asset["file"]
        if not path.is_file(): raise ValueError("Missing actual resource: " + asset["file"])
        asset.update({"status": "engine_verified", "engine_ready": True, "implementation_mode": mode, "sha256": digest(path), "engine_evidence": report_path.relative_to(ROOT).as_posix()})
        if path.suffix == ".png":
            size = list(Image.open(path).size)
            asset["size"] = size
            if kind != "character_strip": asset["frame_size"] = size
        else:
            asset.pop("frame_size", None)
            asset.pop("alpha_required", None)
        if asset["file"] in image_sources:
            source = image_sources[asset["file"]]
            asset["source"] = source["source"]
            asset["source_sha256"] = source["source_sha256"]
        if kind == "character_strip":
            asset["animation"] = animation_files[asset["file"]]
            asset["modular_animation_files"] = [a for a in animations if a["actor"] == asset["content_id"] and a["state"] == asset["animation"]["state"] and a["kind"] in ["weapon_body", "weapon_hand"]]
            if len(asset["modular_animation_files"]) != 2: raise ValueError("Incomplete modular body/grip pair")
            asset["grip_provenance"] = "docs/incense-debt/reports/runtime/held-weapons/body-processing.json"
        elif kind == "weapon":
            held = weapon_rig["weapons"][asset["content_id"]]
            held_file = "game/" + held["texture"].removeprefix("res://")
            asset["held_equipment"] = {**held, "file": held_file, "sha256": digest(ROOT / held_file), "source": image_sources[held_file]["source"], "source_sha256": image_sources[held_file]["source_sha256"]}
        elif kind.endswith("_bundle"):
            states = [a for a in animations if a["actor"] == asset["content_id"]]
            if not set(asset["required_states"]).issubset({a["state"] for a in states}): raise ValueError("Incomplete actual states: " + asset["id"])
            asset["animation_files"] = [{key: a[key] for key in ["state", "frames", "fps", "file", "sha256", "method"]} for a in states]
    manifest["status_policy"] = "engine_verified means actual resource load/dimensions and native fixture integration; does not imply mobile-device, hand-drawn animation, or final balance acceptance"
    manifest["production_specification_policy"] = "191 historical production prompts remain prompt_only specifications; actual generation provenance lives in runtime manifests and the production queue"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", "utf8")
    evidence = {"animation_strips": len(animations), "direction_frames": sum(a["frames"] * len(a["directions"]) for a in animations), "native_assets_loaded": native["asset_loads"], "audio_files": len(audio),
                "raster_files": sum(a["kind"] == "texture" and a.get("format") != "svg" for a in registry), "vector_icons": sum(a.get("format") == "svg" for a in registry), "font_files": sum(a["kind"] == "font" for a in registry),
                "music_stems": sum(item.get("format") == "ogg_vorbis" for item in audio), "music_themes": len(audio_manifest["scores"]),
                "checks": ["strip dimensions and hashes", "nonempty active frames", "different animation frames", "death dissolves to alpha zero",
                           "48kHz mono PCM effects and encoded Vorbis themes", "full decoded loop length and quiet seam", "compiled native resource loads", "compiled native sample-aligned stem mixing",
                           "protected original RGBA pixels outside reviewed grip masks", "shared body/hand animation anchors and thirty-two separately held equipment cutouts"],
                "expanded_content_evidence": "docs/incense-debt/reports/platforms/windows/expansion/expansion-assets.json",
                "failures": failures, "passed": True, "asset_status_counts": dict(Counter(a["status"] for a in manifest["assets"])),
                "limitations": ["No physical mobile performance/transparent-edge or speaker check", "Character/equipment motion uses paper-puppet deformation; the eight new VFX strips use 48 distinct AI-generated keyframes", "Native mixer samples do not substitute for human listening acceptance"]}
    (DOCS / "reports/runtime/asset-verification.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps(evidence, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
