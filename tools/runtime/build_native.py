"""Native portable Godot exports. No Docker, WSL, emulator, or user-wide settings."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
from PIL import Image
from prepare_asset_registry import main as prepare_registry

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / ".local-tools/godot-4.7.2"
ENGINE = TOOLS / "Godot_v4.7.2-stable_win64_console.exe"
REPORTS = ROOT / "docs/incense-debt/reports/platforms"


def configure():
    # This portable copy receives its own editor profile; existing user's profile is untouched.
    (TOOLS / "._sc_").touch()
    profile = TOOLS / "editor_data"
    profile.mkdir(exist_ok=True)
    sdk = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk"
    java = Path("C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot")
    text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    text += f'export/android/android_sdk_path="{sdk.as_posix()}"\n'
    text += f'export/android/java_sdk_path="{java.as_posix()}"\n'
    (profile / "editor_settings-4.7.tres").write_text(text, "utf-8")
    icon_dir = ROOT / "game/assets/ui"
    icon_dir.mkdir(exist_ok=True)
    portrait = Image.open(ROOT / "game/assets/portraits/c_paper.png").convert("RGBA")
    icon_path = icon_dir / "app-icon.png"
    if not icon_path.exists():
        icon_bg = Image.new("RGBA", (512,512), (36,39,37,255))
        icon_bg.alpha_composite(portrait.crop((68,58,400,390)).resize((512,512),Image.Resampling.LANCZOS))
        icon_bg.convert("RGB").save(icon_path)
    elif Image.open(icon_path).convert("RGBA").getextrema()[3][0] != 255:
        icon_bg = Image.new("RGBA", (512,512), (36,39,37,255))
        icon_bg.alpha_composite(Image.open(icon_path).convert("RGBA").resize((512,512)))
        icon_bg.convert("RGB").save(icon_path)
    portrait.crop((68, 58, 400, 390)).convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS).save(icon_dir / "ios-icon.png")
    foreground = Image.new("RGBA", (432, 432))
    hero = Image.open(ROOT / "game/assets/heroes/c_paper_down.png").convert("RGBA")
    hero = hero.crop(hero.getbbox())
    hero.thumbnail((246, 254), Image.Resampling.LANCZOS)
    # thumbnail does not enlarge a source pose; resize from the same source if needed.
    scale = min(246 / hero.width, 254 / hero.height)
    hero = hero.resize((round(hero.width * scale), round(hero.height * scale)), Image.Resampling.LANCZOS)
    foreground.alpha_composite(hero, ((432 - hero.width) // 2, (432 - hero.height) // 2))
    foreground.save(icon_dir / "adaptive-foreground.png")
    Image.new("RGB", (432, 432), (36, 39, 37)).save(icon_dir / "adaptive-background.png")
    prepare_registry()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=["windows", "android"])
    parser.add_argument("--export-timeout", type=int, default=900,
                        help="Bounded export timeout in seconds; large native packs need more than three minutes.")
    parser.add_argument(
        "--android-build",
        choices=["debug", "release"],
        default="debug",
        help="Android export variant. The default keeps the local debug APK path unchanged.",
    )
    parser.add_argument(
        "--android-output",
        help="Optional Android APK output path. Relative paths are resolved from the workspace root.",
    )
    args = parser.parse_args()
    if args.export_timeout < 60:
        parser.error("--export-timeout must be at least 60 seconds")
    if args.platform != "android" and (args.android_build != "debug" or args.android_output):
        parser.error("--android-build and --android-output are only valid for the android platform")
    if (ROOT / "game/assets/creature-actions.json").is_file():
        from validate_creature_actions import validate
        validation = validate()
        validation.update(
            verified_at=datetime.now(timezone.utc).isoformat(),
            manifest_sha256=hashlib.sha256((ROOT / "game/assets/creature-actions.json").read_bytes()).hexdigest(),
            catalog_sha256=hashlib.sha256((ROOT / "game/data/catalog.json").read_bytes()).hexdigest(),
            export_platform=args.platform,
            source="Full catalog-derived source, provenance, alpha, atlas and individual pose shipping gate",
        )
        validation_path = ROOT / "docs/incense-debt/reports/creature-actions-2026-10-10/source-validation.json"
        validation_path.parent.mkdir(parents=True, exist_ok=True)
        validation_path.write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", "utf8")
    configure()
    output_dir = ROOT / "build" / args.platform
    output_dir.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["JAVA_HOME"] = "C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
    if args.platform == "android":
        output = Path(args.android_output) if args.android_output else output_dir / (
            "IncenseDebt.apk" if args.android_build == "debug" else "IncenseDebt-release.apk"
        )
        if not output.is_absolute():
            output = ROOT / output
        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        export_flag = "--export-release" if args.android_build == "release" else "--export-debug"
        build_variant = args.android_build
        report_name = "android-build.json" if build_variant == "debug" else "android-release-build.json"
        log_name = "android-export.log" if build_variant == "debug" else "android-release-export.log"
    else:
        output = output_dir / "IncenseDebt.exe"
        export_flag = "--export-release"
        build_variant = "release"
        report_name = "windows-build.json"
        log_name = "windows-export.log"
    # Export to a fresh file: an existing Android APK can retain old ZIP data
    # even when the native exporter exits successfully. Preserve one previous
    # generated package for recovery; verification still checks the new output.
    if output.exists():
        output.replace(output.with_name(output.stem + "-previous" + output.suffix))
    commands = [[str(ENGINE), "--headless", "--editor", "--path", str(ROOT / "game"), "--import", "--quit"],
                [str(ENGINE), "--headless", "--path", str(ROOT / "game"),
                 export_flag, "Windows Desktop" if args.platform == "windows" else "Android", str(output)]]
    logs = []
    for step, cmd in enumerate(commands):
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=ROOT, env=env,
                                    timeout=180 if step == 0 else args.export_timeout)
        except subprocess.TimeoutExpired as error:
            logs.append((error.stdout or b"").decode("utf-8", errors="replace"))
            (REPORTS / log_name).write_text("\n".join(logs), "utf-8")
            if step == 1 and output.exists():
                output.replace(output.with_name(output.stem + "-incomplete" + output.suffix))
            print(logs[-1][-4000:])
            raise RuntimeError(f"{args.platform} exporter timed out; inspect saved platform log") from error
        logs.append(result.stdout.decode("utf-8", errors="replace"))
        (REPORTS / log_name).write_text("\n".join(logs), "utf-8")
        if result.returncode or "SCRIPT ERROR" in logs[-1] or "ERROR:" in logs[-1]:
            # Godot may leave an unsigned or partially assembled APK after a
            # release-signing failure. Never leave that file looking like a
            # deliverable beside the verified debug package.
            if args.platform == "android" and args.android_build == "release":
                output.unlink(missing_ok=True)
            print(logs[-1])
            lowered = logs[-1].lower()
            if "keystore" in lowered or "发布密钥" in logs[-1] or "release key" in lowered:
                raise RuntimeError(
                    "Android release export requires the owner's release keystore; "
                    "the incomplete APK was removed. See the saved export log."
                )
            raise RuntimeError(f"{args.platform} export failed; inspect platform log")
    if not output.exists():
        raise RuntimeError("Exporter did not create the expected file")
    try:
        relative_output = output.relative_to(ROOT).as_posix()
    except ValueError:
        relative_output = output.as_posix()
    report = {"platform": args.platform, "path": relative_output, "bytes": output.stat().st_size,
              "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "engine": "4.7.2",
              "build": build_variant,
              "version": "0.3.0",
              "playable_scope": "eleven-floor offline alpha plus authoritative two-player Duel: quick pairing, six-digit open rooms, 32 weapons, 18 skills, 32 PvP relics, reconnect and isolated online records",
              "source_status": "Build output; current rule, playthrough and native-render evidence recorded separately in reports/current-product-status.json",
              "device_tested": False, "virtualization": "none"}
    (REPORTS / report_name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    # Distribute the exact font license beside desktop builds as well as inside the pack.
    if args.platform == "windows":
        (output_dir / "NotoSansSC-OFL.txt").write_bytes((ROOT / "game/assets/fonts/OFL.txt").read_bytes())
        (output_dir / "Godot-THIRDPARTY.txt").write_bytes((ROOT / "game/assets/licenses/Godot-THIRDPARTY.txt").read_bytes())
        for name in ["ResourceHanRounded-OFL.txt", "SmileySans-OFL.txt"]:
            (output_dir / name).write_bytes((ROOT / "game/assets/fonts" / name).read_bytes())
        (output_dir / "Lucide-LICENSE.txt").write_bytes((ROOT / "game/assets/ui/icons/Lucide-LICENSE.txt").read_bytes())


if __name__ == "__main__":
    main()
