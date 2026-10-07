"""Record the locked references and real viewport captures without inventing a fidelity score."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont
from run_native_qa import CAPTURE_NAMES

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "docs/incense-debt/reports/runtime"
CAPTURE_ROOT = ROOT / "docs/incense-debt/reports/platforms/windows"
REFERENCES = ["output/imagegen/concepts/01-incense-debt.png",
              "output/imagegen/incense-debt/characters-roster.png",
              "output/imagegen/incense-debt/paper-lantern-asset-board.png",
              "output/imagegen/incense-debt/menu-map-combat-board.png"]
CAPTURES = CAPTURE_NAMES


def entry(relative):
    path = ROOT / relative
    im = Image.open(path)
    return {"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size": list(im.size)}


def main():
    native = json.loads((CAPTURE_ROOT / "native-render.json").read_text("utf-8"))
    ui = json.loads((REPORT / "ui-refresh/ui-refresh.json").read_text("utf8"))
    expansion = json.loads((CAPTURE_ROOT / "expansion/expansion-native.json").read_text("utf8"))
    production = json.loads((ROOT / "docs/incense-debt/assets/expansion-production.json").read_text("utf8"))
    processed = json.loads((ROOT / "docs/incense-debt/assets/expansion-processed.json").read_text("utf8"))
    strip_count = len(json.loads((ROOT / "game/assets/animation-manifest.json").read_text("utf8"))["strips"]) + len(processed["animations"])
    revision=json.loads((ROOT/"game/assets/fx/combat-revision/manifest.json").read_text("utf8"))
    if not all(item["saved"] and item.get("state_stable") for item in native["captures"]):
        raise RuntimeError("Viewport captures did not finish")
    if not ui["passed"] or ui["compiled_windows_sha256"] != native["artifact_sha256"]:
        raise RuntimeError("Rounded UI evidence does not belong to the compiled game")
    if not expansion["passed"] or expansion["artifact_sha256"] != native["artifact_sha256"]:
        raise RuntimeError("Expansion captures do not belong to the same compiled game")
    data = {"recorded_at": datetime.now(timezone.utc).isoformat(),
            "references": [entry(p) for p in REFERENCES],
            "additional_sources": [entry("output/imagegen/incense-debt/runtime/secret-entry.png"),
                                   entry("output/imagegen/incense-debt/held-weapons/neutral-grips-single-reference.png"),
                                   entry("output/imagegen/incense-debt/held-weapons/held-weapons-reference-edit.png")],
            "captures": [entry(f"docs/incense-debt/reports/platforms/windows/{name}.png") for name in CAPTURES],
            "expanded_sources": [entry(job["output"]) for job in production["jobs"]],
            "combat_revision_sources":[entry(path) for path in sorted({row["source"] for row in revision["records"]})],
            "combat_revision_generated_keyframes":revision["frames"],
            "combat_revision_inner_wall_review":"40 background-specific convex contours manually inspected; actual swept movement, projected entry gates and VFX wall clipping verified separately",
            "expanded_captures": [entry("docs/incense-debt/reports/platforms/windows/expansion/"+c["name"]+".png") for c in expansion["captures"]],
            "expanded_environment_review": "20 independent themes, both variants, actual panel boundaries, distinct palettes/materials/architecture and 20 matching mob/boss contact sheets manually reviewed",
            "engine": native["engine"], "renderer": native["driver"],
            "compiled_windows_sha256": native["artifact_sha256"],
            "capture_timing": "fixture clock frozen until two real viewport draws; screen/mode checked against named sheet expectations; fixture tick recorded",
            "generation": "Illustrative art: Sub2API / gpt-image-2.5 reference edits and original crops. The menu/map/combat board is a reviewed concept reference; rounded runtime UI remains native components and licensed Lucide vector symbols.",
            "ui_design_master": entry("docs/incense-debt/reports/platforms/windows/ui-style.png"),
            "ui_font": {"family": "Incense Rounded (Resource Han Rounded CN derivative)", "body_weight": 500, "hud_weight": 700, "title_family": "Smiley Sans Oblique 2.0.1",
                        "fallback": "Noto Sans SC; rare-name CJK checked by the native engine", "license": "SIL OFL 1.1", "production": ui["fonts"]},
            "ui_palette": ui["palette"], "ui_vector_icons": ui["vector_icons"], "ui_radius": ui["panel_radius"],
            "visual_review": {"method": "manual inspection of references, normalized alpha previews and real viewport images",
                              "retained": ["upper shrine alcoves", "torn vermilion drapes", "guardian carvings", "central low-contrast floor pattern",
                                           "original six character identities and costume material", "warm curled debt lines", "modern type hierarchy"],
                              "fixed": ["portrait overflow", "thin-font default weight", "flat obstacle placeholders", "reward icon gaps",
                                        "physical-entry actions overlapping the skill HUD", "discovery message overlapping clear actions",
                                        "previous-room death effects remaining after return", "async screenshot advancing to the next UI sheet",
                                        "mobile reward fixture accidentally returning to a visited room instead of an untaken offer",
                                        "old baked handheld equipment staying visible after weapon replacement",
                                        "HUD retaining a stale world after save import or backup restore",
                                        "dense boxed menu and HUD text", "text and button symbols overlapping",
                                        "small mobile toggles", "enlarged vector symbols looking soft",
                                        "focused primary buttons losing their dark text and clear fill",
                                        "TextureRect sizing before disabling intrinsic icon minimums",
                                        "locked character information depending on hover", "skill evolutions lacking an on-demand trial entry",
                                        "result screen losing the actual lethal attack identity after emitter removal",
                                        "reward notice covering result retry controls", "integer result counts showing decimal suffixes after disk reload",
                                        "shop cards lacking a visible weapon practice affordance", "shop practice tray obscuring the playfield or returning with changed wallet",
                                        "ranged impacts lacking short collision-aware displacement", "root state relying on flashing-only feedback",
                                        "elite death source validating against the wrong content table"],
                              "limitations": ["Fixture screenshots do not prove full playthrough or device performance",
                                              f"{strip_count} paper-puppet strips, including 72 modular body/grip strips from reviewed Sub2 local edits; not independently drawn AI frames",
                                              "These are fixture states; actual unboosted eleven-floor simulation is recorded separately in expanded-full-run.json"]}}
    (REPORT / "visual-baseline.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf-8")
    canvas = Image.new("RGB", (2560, 830), (29, 35, 29))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(ROOT / "game/assets/fonts/NotoSansSC.ttf"), 32)
    font.set_variation_by_axes([700])
    draw.text((28, 20), "设计来源 · 选定方向图", font=font, fill=(231, 216, 182))
    draw.text((1308, 20), "实际游戏 · Windows编译程序截图", font=font, fill=(231, 216, 182))
    for offset, path in [(0, ROOT / REFERENCES[0]), (1280, CAPTURE_ROOT / "chains.png")]:
        source = Image.open(path).convert("RGB")
        source.thumbnail((1264, 720), Image.Resampling.LANCZOS)
        canvas.paste(source, (offset + (1280 - source.width) // 2, 78 + (720 - source.height) // 2))
    canvas.save(REPORT / "design-vs-runtime.png")
    print(f"Recorded {len(REFERENCES)} binding references, {len(CAPTURES)} real viewport captures, and a side-by-side comparison.")


if __name__ == "__main__":
    main()
