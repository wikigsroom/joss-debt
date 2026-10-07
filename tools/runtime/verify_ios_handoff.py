"""Verify the portable iOS handoff without pretending to build or sign iOS.

This check is deliberately limited to artifacts available on Windows. It
validates the shared source bundle, pinned Godot export template, platform
configuration, required runtime files, and sensitive-file exclusions. A real
Mac/Xcode build and device run remain separate acceptance gates.
"""

from pathlib import Path
import hashlib
import json
import zipfile


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/incense-debt/reports/platforms/ios-handoff-verification.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    handoff_path = ROOT / "build/ios-handoff/handoff.json"
    archive = ROOT / "build/ios-handoff/IncenseDebt-shared-source.zip"
    template = ROOT / ".local-tools/export-templates-4.7.2/ios.zip"
    handoff = json.loads(handoff_path.read_text("utf8"))
    failures = []
    required = [
        "game/project.godot",
        "game/data/catalog.json",
        "game/data/equipment.json",
        "game/data/fx_presets.json",
        "game/data/projectile_profiles.json",
        "game/scripts/combat/equipment.gd",
        "game/scripts/combat/attack_composer.gd",
        "game/scripts/ui/polished_fx.gd",
        "game/data/rules.json",
        "game/data/runtime_assets.json",
        "game/data/music_scores.json",
        "game/scripts/main.gd",
        "game/scripts/combat/world.gd",
        "game/scripts/ui/input_adapter.gd",
        "game/scripts/ui/orientation_guard.gd",
        "tools/runtime/export_ios_on_mac.py",
    ]
    forbidden_tokens = [".codex", "api_key", "keystore", "production-prompts", "sub2_image_gen"]
    members = []
    if not archive.is_file():
        failures.append("shared source ZIP is missing")
    else:
        if digest(archive) != handoff.get("source_sha256"):
            failures.append("shared source SHA-256 differs from handoff.json")
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                failures.append("shared source ZIP CRC check failed")
            members = bundle.namelist()
            member_set = set(members)
            for path in required:
                if path not in member_set:
                    failures.append("required handoff member missing: " + path)
            forbidden = [path for path in members if any(token in path.lower() for token in forbidden_tokens)]
            if forbidden:
                failures.append("sensitive or production-only members present: " + ", ".join(forbidden[:8]))
            source_project = bundle.read("game/project.godot").decode("utf8", errors="replace") if "game/project.godot" in member_set else ""
            source_rules = bundle.read("game/data/rules.json").decode("utf8", errors="replace") if "game/data/rules.json" in member_set else ""
            if 'renderer/rendering_method="gl_compatibility"' not in source_project:
                failures.append("handoff project is not pinned to Compatibility rendering")
            if 'window/handheld/orientation=0' not in source_project and 'window/size/viewport_width=1280' not in source_project:
                failures.append("handoff project does not expose the expected landscape viewport")
            if '"orientation": "landscape"' not in source_rules:
                failures.append("handoff rules do not declare landscape orientation")
            catalog = json.loads(bundle.read("game/data/catalog.json")) if "game/data/catalog.json" in member_set else {}
            if len(catalog.get("characters", [])) != 6 or len(catalog.get("skills", [])) != 18:
                failures.append("handoff catalog does not contain the six-character / eighteen-skill content baseline")
    template_sha = digest(template) if template.is_file() else ""
    if not template.is_file():
        failures.append("pinned iOS template is missing")
    elif template_sha != handoff.get("ios_template_sha256"):
        failures.append("pinned iOS template differs from handoff.json")
    if handoff.get("platform") != "ios" or handoff.get("virtualization") != "none":
        failures.append("handoff metadata has an invalid platform or virtualization declaration")
    if handoff.get("minimum_ios_version") != "15.0":
        failures.append("minimum iOS version is not 15.0")
    report = {
        "passed": not failures,
        "platform": "ios",
        "source_zip": handoff.get("source_zip", ""),
        "source_sha256": digest(archive) if archive.is_file() else "",
        "template": handoff.get("ios_template", ""),
        "template_sha256": template_sha,
        "required_members": required,
        "member_count": len(members),
        "forbidden_tokens_checked": forbidden_tokens,
        "failures": failures,
        "scope": "Windows-side handoff integrity only; no Xcode, signing, IPA or physical-device claim",
        "virtualization": "none",
    }
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "member_count": len(members), "source_sha256": report["source_sha256"], "template_sha256": template_sha, "failures": failures}, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
