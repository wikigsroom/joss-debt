"""Export a small native Windows server from the exact shared combat sources."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
MODULES = ("protocol", "duel_actor", "duel_match", "server_runtime", "server_entry")


def main():
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
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="IncenseDebt Dedicated Server"\nconfig/version="0.3.0"\nrun/main_scene="res://server.tscn"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="IncenseDebtServer"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', "utf8")
    (project / "server.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://server_boot.gd" id="1"]\n[node name="DedicatedServer" type="Node"]\nscript=ExtResource("1")\n', "utf8")
    template = ROOT / ".local-tools/export-templates-4.7.2/windows_release_x86_64.exe"
    (project / "export_presets.cfg").write_text('[preset.0]\nname="Windows Server"\nplatform="Windows Desktop"\nrunnable=true\ndedicated_server=true\ncustom_features="dedicated_server"\nexport_filter="all_resources"\ninclude_filter="data/*.json"\nexclude_filter=""\nscript_export_mode=2\n[preset.0.options]\ncustom_template/release="' + template.as_posix() + '"\ndebug/export_console_wrapper=0\nbinary_format/embed_pck=true\nbinary_format/architecture="x86_64"\napplication/modify_resources=false\n', "utf8")
    target = ROOT / "build/server/IncenseDebtServer.exe"
    target.parent.mkdir(parents=True, exist_ok=True)
    logs = []
    for arguments in (["--headless", "--editor", "--path", str(project), "--import", "--quit"], ["--headless", "--path", str(project), "--export-release", "Windows Server", str(target)]):
        completed = subprocess.run([str(ENGINE), *arguments], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        log = completed.stdout.decode("utf8", errors="replace")
        logs.append(log)
        if completed.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            (target.parent / "export.log").write_text("\n".join(logs), "utf8")
            raise RuntimeError("Server export failed; see build/server/export.log")
    (target.parent / "export.log").write_text("\n".join(logs), "utf8")
    with target.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    report = {"version": "0.3.0", "platform": "windows-x64", "headless": True, "virtualization": "none", "path": str(target.relative_to(ROOT)).replace("\\", "/"), "bytes": target.stat().st_size, "sha256": digest, "shared_source_sha256": hashes, "built_at": datetime.now(timezone.utc).isoformat()}
    (target.parent / "server-build.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({key: value for key, value in report.items() if key != "shared_source_sha256"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
