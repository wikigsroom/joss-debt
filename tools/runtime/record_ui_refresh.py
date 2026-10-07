"""Bind the reviewed native UI, licensed source files and current executable."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/incense-debt/reports/runtime/ui-refresh"
NATIVE = ROOT / "docs/incense-debt/reports/platforms/windows"


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def entry(relative):
    path = ROOT / relative
    return {"file": relative, "sha256": sha(path)}


def contrast(a, b):
    def luminance(color):
        values = [int(color[i:i+2], 16) / 255 for i in [0, 2, 4]]
        linear = [x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4 for x in values]
        return sum(v * w for v, w in zip(linear, [.2126, .7152, .0722]))
    lighter, darker = sorted([luminance(a), luminance(b)], reverse=True)
    return (lighter + .05) / (darker + .05)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    native = json.loads((NATIVE / "native-render.json").read_text("utf8"))
    build = json.loads((ROOT / "docs/incense-debt/reports/platforms/windows-build.json").read_text("utf8"))
    if native.get("artifact_sha256") != build["sha256"] or sha(ROOT / build["path"]) != build["sha256"]:
        raise ValueError("UI captures do not belong to the current compiled game")
    if not all(c["passed"] for c in native["interaction_checks"]):
        raise ValueError("Native UI interactions are unresolved")
    fonts = json.loads((OUT / "font-production.json").read_text("utf8"))
    licensed = json.loads((OUT / "licensed-sources.json").read_text("utf8"))
    if not fonts["passed"] or len(licensed["vector_icons"]) != 57:
        raise ValueError("Font or vector production is incomplete")
    for item in fonts["fonts"] + licensed["vector_icons"]:
        if sha(ROOT / item["file"]) != item["sha256"]:
            raise ValueError("Licensed UI resource changed: " + item["file"])
    theme = (ROOT / "game/scripts/ui/game_theme.gd").read_text("utf8")
    palette = dict(re.findall(r'const (\w+) = Color\("([a-f0-9]{6})"\)', theme))
    pairs = [("body", "TEXT", "SURFACE", 4.5), ("description", "MUTED", "SURFACE", 4.5),
             ("primary button", "BACKGROUND", "ACCENT", 4.5), ("resource icon", "JADE", "SURFACE", 3.0)]
    measurements = [{"usage": use, "foreground": "#"+palette[fg], "background": "#"+palette[bg],
                     "ratio": round(contrast(palette[fg], palette[bg]), 3), "minimum": minimum,
                     "passed": contrast(palette[fg], palette[bg]) >= minimum} for use, fg, bg, minimum in pairs]
    if not all(item["passed"] for item in measurements):
        raise ValueError("A primary UI palette contrast pair failed")
    prompts = ["docs/incense-debt/assets/prompts/ui-rounded-refresh.txt", "docs/incense-debt/assets/prompts/ui-rounded-skin.txt"]
    attempts = [{"operation": "edit", "model": "gpt-image-2.5", "quality": "high", "size": "1536x864", "prompt": entry(prompts[0]), "reference": entry("docs/incense-debt/reports/runtime/ui-refresh/before/menu.png"), "status": "failed", "http_status": 400, "output_created": False} for _ in range(2)]
    attempts.append({"operation": "generate", "model": "gpt-image-2.5", "quality": "high", "size": "1536x1024", "prompt": entry(prompts[1]), "status": "failed", "http_status": 400, "output_created": False})
    report = {"recorded_at": datetime.now(timezone.utc).isoformat(), "passed": True,
              "compiled_windows_sha256": build["sha256"], "native_interaction_checks": len(native["interaction_checks"]),
              "palette": {key: "#"+value for key, value in palette.items()}, "panel_radius": 24, "selected_card_radius": 22,
              "button_radius": "half of the smaller dimension; pills/circles", "logical_canvas": [1280, 720],
              "native_design_master": entry("docs/incense-debt/reports/platforms/windows/ui-style.png"),
              "fonts": fonts, "vector_icons": len(licensed["vector_icons"]), "licensed_sources": entry("docs/incense-debt/reports/runtime/ui-refresh/licensed-sources.json"),
              "contrast": measurements, "contrast_scope": "specified opaque primary palette pairs; not a claim about all effects, custom touch opacity or device calibration",
              "reviewed_views": ["menu", "chains", "choices", "debt", "route", "door-navigation", "inventory-detail", "inventory-synergy", "settings", "mobile-settings", "modern-menu-mobile", "achievements", "modern-pause", "modern-result", "utility-help", "hud-extended", "audio-mix", "character-details", "character-evolution", "character-training", "character-training-cast", "character-locked-mobile", "character-skills-mobile", "hurt-direction", "result-source", "result-build", "run-damage", "run-pages", "result-source-mobile", "run-damage-mobile", "run-pages-mobile", "impact-heavy-before", "impact-heavy-after", "root-bound", "root-release", "elite-source", "shop-trial", "shop-trial-live", "shop-trial-return"],
              "character_disclosure": {"default_menu": "one information icon; locked character selection opens the same detail", "skill_forms": 18, "preview": "real simulator in an isolated training run; does not commit rewards or change the suspended checkpoint", "mobile_scope": "native desktop injection of ScreenTouch events and enlarged controls; physical device still pending"},
              "run_disclosure": {"default_result": "actual lethal source, six statistic cards, original equipment/relic icons and two disclosure entries", "recent_hits": 12, "damage_review": "before/after HP, actual mitigation, revival and attack-specific advice", "earned_pages": "only committed per-run merit, bonus and newly completed personal pages; no retroactive attribution to legacy runs", "feedback": "incoming arrow or ground diamond remains visible with flashing and motion disabled", "retry": "same character; new seed and run ID; injury and death records cleared"},
              "physical_impact": {"simulation": "bounded 0.14-second decelerating displacement through room collision; saved mid-push", "root_cue": "existing warm-gold rope ring and knots, visible with flashing and motion disabled", "elite_identity": "actual elite_variants source retained after emitter removal and disk reload", "scope": "real native collision and checkpoint fixtures; not a human combat feel acceptance"},
              "generation_attempts": attempts, "generation_error": "Tool choice 'image_generation' not found in 'tools' parameter.",
              "generation_note": "No new AI UI reference was produced. Native rounded panels and utility vectors implement the explicit UI revision; original approved Sub2 character/map/item art is retained. No alternate image model or provider was used.",
              "limits": ["Physical phone touch, safe-area and thermal acceptance remains pending", "Native viewport fixtures are not a human full-run acceptance", "User approval of the revised visual direction remains separate"], "virtualization": "none"}
    (OUT / "ui-refresh.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", "utf8")
    canvas = Image.new("RGB", (2560, 816), "#171e20")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(ROOT / "game/assets/fonts/IncenseRounded-Bold.ttf"), 30)
    for x, title, path in [(0, "调整前 · 原生游戏", OUT / "before/menu.png"), (1280, "调整后 · 最新编译程序", NATIVE / "menu.png")]:
        draw.text((x+28, 20), title, font=font, fill="#edf2e7")
        canvas.paste(Image.open(path).convert("RGB"), (x, 76))
    canvas.save(OUT / "ui-before-after.png")
    print(json.dumps({"passed": True, "vector_icons": 57, "font_files": 4, "native_gui_checks": len(native["interaction_checks"]), "contrast": measurements, "new_ai_reference_generated": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
