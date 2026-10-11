"""Export native Windows/Linux servers from the exact shared combat sources."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil
import subprocess
import argparse
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
MODULES = ("protocol", "duel_actor", "duel_match", "cooperative_world", "cooperative_match", "server_runtime", "server_entry",
           "dtls_edge", "enet_battle", "state_stream", "input_frames")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["windows-x64", "linux-x64", "both"], default="windows-x64")
    args = parser.parse_args()
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    project = ROOT / "server/generated/project"
    if project.resolve().parent != (ROOT / "server/generated").resolve():
        raise RuntimeError("Unexpected generated server path")
    if project.is_dir():
        shutil.rmtree(project)
    project.mkdir(parents=True)
    hashes = {}
    files = list((ROOT / "game/scripts/core").glob("*.gd")) + list((ROOT / "game/scripts/combat").glob("*.gd"))
    files += [ROOT / "game/scripts/network" / (name + ".gd") for name in MODULES]
    files += list((ROOT / "game/data").glob("*.json"))
    for source in files:
        relative = source.relative_to(ROOT / "game")
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        hashes[relative.as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
    shutil.copyfile(ROOT / "server/server_boot.gd", project / "server_boot.gd")
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="IncenseDebt Dedicated Server"\nconfig/version="' + version + '"\nrun/main_scene="res://server.tscn"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="IncenseDebtServer"\nrun/flush_stdout_on_print=true\n[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', "utf8")
    (project / "server.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://server_boot.gd" id="1"]\n[node name="DedicatedServer" type="Node"]\nscript=ExtResource("1")\n', "utf8")
    templates = ROOT / ".local-tools/export-templates-4.7.2"
    platforms = ["windows-x64", "linux-x64"] if args.platform == "both" else [args.platform]
    if "linux-x64" in platforms:
        from fetch_export_templates import SIZE, SHA256
        archive = templates / "Godot_v4.7.2-stable_export_templates.tpz"
        with archive.open("rb") as stream:
            require_archive = archive.stat().st_size == SIZE and hashlib.file_digest(stream, "sha256").hexdigest() == SHA256
        if not require_archive: raise RuntimeError("Pinned native template archive mismatch")
        with zipfile.ZipFile(archive) as bundle:
            (templates / "linux_release.x86_64").write_bytes(bundle.read("templates/linux_release.x86_64"))
    presets = []
    for index, platform in enumerate(platforms):
        windows = platform == "windows-x64"
        template = templates / ("windows_release_x86_64.exe" if windows else "linux_release.x86_64")
        presets.append(f'[preset.{index}]\nname="{platform}"\nplatform="' + ("Windows Desktop" if windows else "Linux") + '"\nrunnable=true\ndedicated_server=true\ncustom_features="dedicated_server"\nexport_filter="all_resources"\ninclude_filter="data/*.json"\nexclude_filter=""\nscript_export_mode=2\n' + f'[preset.{index}.options]\ncustom_template/release="' + template.as_posix() + '"\ndebug/export_console_wrapper=0\nbinary_format/embed_pck=true\nbinary_format/architecture="x86_64"\napplication/modify_resources=false\n')
    (project / "export_presets.cfg").write_text("\n".join(presets), "utf8")
    logs = []
    def run(arguments, folder):
        completed = subprocess.run([str(ENGINE), *arguments], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        log = completed.stdout.decode("utf8", errors="replace")
        logs.append(log)
        if completed.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "export.log").write_text("\n".join(logs), "utf8")
            raise RuntimeError("Server export failed; see " + str(folder / "export.log"))
    run(["--headless", "--editor", "--path", str(project), "--import", "--quit"], ROOT / "build/server")
    for platform in platforms:
        windows = platform == "windows-x64"
        target = ROOT / ("build/server/IncenseDebtServer.exe" if windows else "build/server-linux/IncenseDebtServer.x86_64")
        target.parent.mkdir(parents=True, exist_ok=True)
        run(["--headless", "--path", str(project), "--export-release", platform, str(target)], target.parent)
        (target.parent / "export.log").write_text("\n".join(logs), "utf8")
        with target.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        report = {"version": version, "platform": platform, "headless": True, "virtualization": "none", "path": target.relative_to(ROOT).as_posix(), "bytes": target.stat().st_size, "sha256": digest, "shared_source_sha256": hashes, "built_at": datetime.now(timezone.utc).isoformat()}
        (target.parent / "server-build.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
        print(json.dumps({key: value for key, value in report.items() if key != "shared_source_sha256"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
