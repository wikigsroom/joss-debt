"""Verify the frozen server archive against its release tag and published receipts."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.5.0")
    args = parser.parse_args()
    require(re.fullmatch(r"\d+\.\d+\.\d+", args.version), "Invalid archive version")
    archive = ROOT / "server/archives" / ("v" + args.version)
    manifest = json.loads((archive / "manifest.json").read_text("utf8"))
    tag = "v" + args.version
    require(manifest["version"] == args.version and manifest["release_tag"] == tag, "Version mismatch")
    require(git("rev-parse", tag + "^{commit}").decode().strip() == manifest["release_commit"], "Release tag moved or is unavailable; fetch tags")
    require(git("rev-parse", tag + ":game").decode().strip() == manifest["game_git_tree"], "Game tree mismatch")
    entries = manifest["files"]
    for relative, entry in entries.items():
        path = archive / relative
        require(not Path(relative).is_absolute() and path.resolve().is_relative_to(archive.resolve()), "Unsafe manifest path")
        require(not path.is_symlink() and path.is_file(), "Missing or linked archive file: " + relative)
        raw = path.read_bytes()
        require(len(raw) == entry["bytes"] and sha256(raw) == entry["sha256"], "Archive bytes changed: " + relative)
        if entry["origin"].startswith(tag + ":"):
            original = entry["origin"].split(";", 1)[0]
            require(raw == git("show", original), "Original release bytes differ: " + relative)
    actual = set()
    for path in archive.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(archive).as_posix()
        # Godot creates these local import files when opening a source project.
        if ".godot" in path.relative_to(archive).parts or relative.startswith("project/") and path.name.endswith(".gd.uid"):
            continue
        actual.add(relative)
    require(actual == set(entries) | {"README.md", "manifest.json"}, "Unexpected or missing file in archive")
    shared = manifest["shared_source_sha256"]
    require(sum(name.endswith(".gd") for name in shared) == manifest["shared_script_count"], "Script count mismatch")
    require(sum(name.endswith(".json") for name in shared) == manifest["shared_data_count"], "Data count mismatch")
    for relative, expected in shared.items():
        require(entries["project/" + relative]["sha256"] == expected, "Shared build fingerprint mismatch: " + relative)
    receipt = json.loads((ROOT / "docs/releases" / (tag + ".publication.json")).read_text("utf8"))
    published = {entry["name"]: entry for entry in receipt["assets"]}
    release = json.loads((ROOT / "docs/releases" / (tag + ".manifest.json")).read_text("utf8"))
    for artifact in manifest["published_server_archives"]:
        entry = published[artifact["name"]]
        require(entry["digest"] == "sha256:" + artifact["sha256"] and entry["bytes"] == artifact["bytes"] and entry["url"] == artifact["url"], "Published server receipt mismatch")
    for platform, artifact in manifest["native_artifacts"].items():
        require(artifact["sha256"] == release["native_server_sha256"][platform.removesuffix("-x64")], "Native server fingerprint mismatch")
    presets = (archive / "project/export_presets.cfg").read_text("utf8")
    require('custom_template/release=""' in presets and ":/" not in presets, "Machine-dependent export preset")
    config = json.loads((archive / "config.example.json").read_text("utf8"))
    require(config["bind"] == "127.0.0.1" and config["data_directory"].startswith("user://"), "Unsafe archive defaults")
    print(json.dumps({"passed": True, "archive": archive.relative_to(ROOT).as_posix(), "verified_files": len(entries), "shared_scripts": manifest["shared_script_count"], "shared_data": manifest["shared_data_count"], "release_commit": manifest["release_commit"], "published_server_archives": len(manifest["published_server_archives"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
