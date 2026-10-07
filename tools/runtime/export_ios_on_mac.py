"""Export the shared project on a real Mac, without a simulator or virtual machine.

Only creates an Xcode project. Opening, signing and deploying it remain separate
native actions with the owner's real Apple development team and iPhone/iPad.
"""
from pathlib import Path
import argparse
import json
import platform
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, help="Godot 4.7.2 macOS executable")
    parser.add_argument("--team-id", required=True, help="Your actual 10-character Apple development team ID")
    parser.add_argument("--bundle-id", default="org.incensedebt.game")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("This handoff runs only on a real macOS host with Xcode.")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Use your actual 10-character Apple team ID.")
    if not re.fullmatch(r"[a-zA-Z][\w-]*(?:\.[a-zA-Z][\w-]*)+", args.bundle_id):
        parser.error("Bundle ID must be a valid reverse-domain identifier.")
    if not shutil.which("xcodebuild"):
        parser.error("Install and select native Xcode before exporting.")
    root = Path(__file__).resolve().parents[2]
    project = root / "game"
    template = root / ".local-tools/export-templates-4.7.2/ios.zip"
    if not template.is_file():
        parser.error("Place the supplied ios.zip template at .local-tools/export-templates-4.7.2/ios.zip.")
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith("4.7.2.stable"):
        parser.error("This handoff is locked to Godot 4.7.2 stable.")
    preset_file = project / "export_presets.cfg"
    preset = preset_file.read_text("utf8")
    preset = preset.replace('application/app_store_team_id=""', 'application/app_store_team_id="' + args.team_id + '"')
    preset = preset.replace('application/bundle_identifier="org.incensedebt.game"', 'application/bundle_identifier="' + args.bundle_id + '"')
    # A local signing field stays with the Mac project; no team or key is committed here.
    preset_file.write_text(preset, "utf8")
    destination = root / "build/ios"
    destination.mkdir(parents=True, exist_ok=True)
    commands = [[args.godot, "--headless", "--editor", "--path", str(project), "--import", "--quit"],
                [args.godot, "--headless", "--path", str(project), "--export-debug", "iOS", str(destination / "IncenseDebt.zip")]]
    for index, command in enumerate(commands):
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
        (destination / ("import.log" if index == 0 else "export.log")).write_text(result.stdout, "utf8")
        if result.returncode or "SCRIPT ERROR" in result.stdout or "ERROR:" in result.stdout:
            raise RuntimeError("Native iOS export failed; inspect its saved log.")
    projects = list(destination.glob("*.xcodeproj"))
    if not projects:
        raise RuntimeError("Godot returned without creating an Xcode project.")
    report = {"platform": "ios", "engine": version, "native_host": "macOS", "xcode_project": str(projects[0]),
              "signed_ipa_created": False, "physical_device_tested": False, "virtualization": "none"}
    (destination / "ios-export.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Xcode project created. Open it in native Xcode to sign and run on your iPhone/iPad.")


if __name__ == "__main__":
    main()
