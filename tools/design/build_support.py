"""Build prompt files and UX wireframes, adding missing planned asset specifications."""
from __future__ import annotations
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "incense-debt"
COMMON = """Original Incense Debt production art. Chinese folk woodblock and layered paper-cut style, chunky soot-black contours, ivory paper fiber edges, restrained flat 2-3-value shading. Fixed near-overhead game perspective with readable face, same upper-left light and short shadow. Vermilion #BC3C2F, soot #242725, ivory #E7D8B6, aged gold #C39A51, jade #53675C. Crisp readable silhouette at small game size. No text, no IDs, no numbers, no logo, no watermark, no scenic poster, no pixel art, no realistic 3D, no anime, no borrowed characters. IDs below identify the asset only and MUST NOT appear in the image."""
REGION_STYLE = {
    "paper_lane": "Desaturated jade stone and paper, torn vermilion curtains, folded offerings, broad low-contrast floor.",
    "coin_vault": "Dark gray copper plates, aged-gold pipes, square money racks and abacus structures, low-contrast floor.",
    "ownerless_temple": "Ivory broken ledger pages, soot-black shrine shapes, sparse vermilion seals, low-contrast floor.",
}


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def text(x, y, value, size=20, fill="#E7D8B6", anchor="start"):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" text-anchor="{anchor}">{html.escape(value)}</text>'


def rect(x, y, w, h, fill, stroke="#C39A51", radius=8, opacity=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}" opacity="{opacity}"/>'


def circle(x, y, radius, fill="none", stroke="#E7D8B6", opacity=1):
    return f'<circle cx="{x}" cy="{y}" r="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="3" opacity="{opacity}"/>'


def wireframe(mobile):
    width, height = (1560, 720) if mobile else (1280, 720)
    left = (width - 1152) / 2
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
             '<title>香火债移动端布局线框</title>' if mobile else '<title>香火债PC布局线框</title>',
             '<desc>静态交互布局说明，不是可玩游戏或实际运行截图。</desc>',
             '<g font-family="Microsoft YaHei, Noto Sans SC, sans-serif">',
             rect(0, 0, width, height, "#242725", "none", 0),
             rect(left, 72, 1152, 576, "#53675C", "#E7D8B6", 0),
             text(width/2, 345, "战场中心保持空白", 28, anchor="middle"),
             text(width/2, 382, "完整房间 / 统一规则 / 装饰低对比", 18, anchor="middle"),
             rect(28, 15, 330, 47, "#242725"), text(42, 46, "心火  ●●●    香火  40/100    纸钱 10", 17),
             rect(width-244, 15, 160, 47, "#242725"), text(width-230, 46, "地图   债约 0/2", 17),
             rect(width-74, 15, 54, 47, "#242725"), text(width-47, 46, "Ⅱ", 20, anchor="middle"),
             text(width/2, 703, "布局线框 · 实机触控尺寸与安全区需运行验收", 18, anchor="middle")]
    if mobile:
        parts += [rect(36, 83, width-72, 578, "none", "#C39A51", 18, .55),
                  text(52, 107, "运行时安全区边界", 16),
                  circle(142, 548, 84, "#242725", opacity=.75), circle(142, 548, 34), text(142, 555, "移动", 19, anchor="middle"),
                  circle(width-144, 548, 84, "#242725", opacity=.75), circle(width-144, 548, 34), text(width-144, 555, "瞄准", 19, anchor="middle"),
                  text(width-144, 645, "推动即射击", 17, anchor="middle"),
                  circle(width-291, 457, 44, "#BC3C2F"), text(width-291, 463, "焚债", 20, anchor="middle"),
                  circle(width-312, 564, 40, "#242725"), text(width-312, 570, "身法", 20, anchor="middle"),
                  rect(width/2-48, 568, 96, 55, "#242725"), text(width/2, 602, "交互", 19, anchor="middle"),
                  text(250, 626, "摇杆与按钮可拖动 / 镜像", 16)]
    else:
        parts += [rect(24, 657, 510, 33, "#242725", "none"), text(32, 679, "WASD 移动 · 左键射击 · 右键焚债 · Space 身法", 17),
                  rect(width-244, 657, 220, 33, "#242725", "none"), text(width-230, 679, "E 交互 · Esc 暂停", 17)]
    parts += ["</g>", "</svg>"]
    return "\n".join(parts) + "\n"


def main():
    catalog = json.loads((DOCS / "data" / "catalog.json").read_text(encoding="utf-8"))
    manifest_path = DOCS / "data" / "asset-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assets = manifest["assets"]
    known = {a["id"] for a in assets}
    for group, kind, folder, frame in [("skills", "skill_icon", "skills", [64, 64]),
                                       ("elite_variants", "elite_bundle", "elites", [128, 128]),
                                       ("npcs", "npc_bundle", "npcs", [128, 128])]:
        for entry in catalog[group]:
            aid = "asset_" + entry["id"]
            if aid not in known:
                assets.append({"id": aid, "kind": kind, "content_id": entry["id"], "frame_size": frame,
                               "alpha_required": True, "anchor": [.5, .84], "status": "planned",
                               "engine_ready": False, "file": f"game/assets/{folder}/{entry['id']}.png"})
                known.add(aid)
    for asset in assets:
        if asset["kind"] == "concept":
            asset["sha256"] = hashlib.sha256((ROOT / asset["file"]).read_bytes()).hexdigest()
        if asset["kind"] in {"enemy_bundle", "elite_bundle"}:
            asset.setdefault("required_states", ["idle", "move", "tell", "attack", "hurt", "death"])
        if asset["kind"] == "boss_bundle":
            asset.setdefault("required_states", ["idle", "attack_a", "attack_b", "attack_c", "phase", "hurt", "death"])
        if asset["kind"] == "npc_bundle":
            asset.setdefault("required_states", ["idle", "talk"])
    save_json(manifest_path, manifest)
    objects = {entry["id"]: entry for group in catalog.values() if isinstance(group, list) for entry in group}
    prompts = []
    folder = DOCS / "assets" / "prompts" / "production"
    folder.mkdir(parents=True, exist_ok=True)
    for asset in assets:
        if asset["kind"] == "concept" or not asset["file"].endswith(".png"):
            continue
        obj = objects.get(asset.get("content_id"), {})
        subject = obj.get("name", asset["id"])
        body = COMMON + "\n\nSubject: " + subject + ". "
        size = "1024x1024"
        if asset["kind"] == "character_strip":
            frames = asset["frames_per_direction"]
            cols = 6 if frames > 4 else 4
            size = "1536x1024" if cols == 6 else "1024x1024"
            body += obj["silhouette"] + ". Fixed costume and weapon proportions.\n"
            body += f"Animation state {asset['state']}. Four rows in order down, left, right, up. {frames} frames per row; {cols} equal 256px-wide columns, leave unused cells empty. Exactly one character per used cell, no overlap. Shared character scale and foot anchor at (0.5,0.84). Genuine transparent background. Preserve the same face, silhouette, palette and proportions in all cells.\n"
        elif asset["kind"] == "environment":
            body += REGION_STYLE[asset["region"]] + "\n"
            if asset["id"].endswith("_floor"):
                body += "Seamless top-view repeating floor tile, flat low contrast, all edges match, no props or characters. Opaque background.\n"
            elif asset["id"].endswith("_boss_room"):
                body += "Complete empty overhead boss-room environment, wide open arena, no characters, four clear exits, decoration only at perimeter. Opaque background.\n"
                size = "1536x1024"
            else:
                body += "One modular room object or small clearly separated matching object set, consistent 64-unit floor grid, true transparent background, no scene.\n"
        elif asset["kind"] in {"enemy_bundle", "elite_bundle", "boss_bundle", "npc_bundle"}:
            body += obj.get("silhouette", obj.get("pattern", obj.get("special_rule", ""))) + ".\n"
            body += "Neutral readable reference pose only, front-right game orientation, one full-body subject, true transparent background, generous clean padding. Later required action states are separate production jobs.\n"
        elif asset["kind"] == "weapon":
            body += "One hand-held weapon, neutral facing right, grip visible, paper and copper materials, true transparent background. No hand or character, no action scene.\n"
        elif asset["kind"] in {"relic_icon", "skill_icon"}:
            body += "One bold symbolic game pickup/icon, paper and copper objects, simple silhouette at 64px. True transparent background. Express the physical object named in the subject, no written symbols.\n"
            body += "Gameplay meaning for art direction only: " + obj.get("behavior", "") + "\n"
        elif asset["kind"] == "vfx":
            body += "A compact four-frame effect strip, four equal cells, fade from strong to weak, true transparent background. Friendly fire is rounded orange-gold; hostile telegraph uses jade pointed shape and black-white outlines; avoid mixing their meanings.\n"
        else:
            body += "One clearly isolated UI decorative shape or thematic icon, clean flat paper and bronze form, no lettering, true transparent background. Text and interaction will be rendered in code.\n"
        prompt_path = folder / (asset["id"] + ".txt")
        prompt_path.write_text(body, encoding="utf-8")
        prompts.append({"asset_id": asset["id"], "content_id": asset.get("content_id"),
                        "prompt": prompt_path.relative_to(ROOT).as_posix(), "model": "gpt-image-2.5",
                        "quality": "high", "source_size": size,
                        "background": "transparent" if asset.get("alpha_required", True) else "opaque",
                        "generation_status": "prompt_only",
                        "planned_output": "output/imagegen/incense-debt/production/" + asset["id"] + ".png"})
    save_json(DOCS / "assets" / "production-prompts.json", {"version": catalog["version"], "note": "Prompts only; no production sprites generated or verified by this tool.", "prompts": prompts})
    wireframes = DOCS / "assets" / "wireframes"
    wireframes.mkdir(parents=True, exist_ok=True)
    for name, mobile in [("pc", False), ("mobile", True)]:
        (wireframes / (name + ".svg")).write_text(wireframe(mobile), encoding="utf-8")
    print(json.dumps({"asset_entries": len(assets), "production_prompt_files": len(prompts), "wireframes": 2}))


if __name__ == "__main__":
    main()
