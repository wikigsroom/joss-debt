"""Freeze the standalone native server source archive for a released tag."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf8").strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.6.0")
    parser.add_argument("--release-commit", required=True, help="release commit pinned by the annotated tag")
    args = parser.parse_args()
    tag = "v" + args.version
    archive = ROOT / "server/archives" / tag
    if archive.exists():
        raise RuntimeError("Archive already exists: " + str(archive))
    generated = ROOT / "server/generated/project"
    if not generated.is_dir():
        raise RuntimeError("Run build_online_server.py before freezing the archive")
    if git("rev-parse", tag + "^{commit}") != args.release_commit:
        raise RuntimeError("Release commit does not match the annotated tag")
    archive.mkdir(parents=True)
    project = archive / "project"
    deployment = archive / "deployment"
    shared: dict[str, str] = {}
    entries: dict[str, dict] = {}

    for source in sorted(generated.rglob("*")):
        if not source.is_file() or ".godot" in source.parts or source.name.endswith(".gd.uid"):
            continue
        relative = source.relative_to(generated).as_posix()
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if relative == "export_presets.cfg":
            # The generated project uses this machine's template paths. The
            # archive is a portable source snapshot, so preserve the preset
            # shape while removing host-specific absolute paths.
            text = source.read_text("utf8")
            text = __import__("re").sub(r'custom_template/release="[^"]*"', 'custom_template/release=""', text)
            target.write_text(text, "utf8")
        else:
            shutil.copyfile(source, target)
        origin = "generated:server/generated/project/" + relative
        if relative.endswith(".gd") or relative.endswith(".json"):
            if relative.startswith("scripts/") or relative.startswith("data/"):
                game_path = "game/" + relative
                origin = tag + ":" + game_path
                shared[relative] = sha(ROOT / game_path)
            elif relative == "server_boot.gd":
                origin = tag + ":server/server_boot.gd"
        entries["project/" + relative] = {"bytes": target.stat().st_size, "sha256": sha(target), "origin": origin}

    public_files = {
        "config.example.json": ROOT / "server/config.example.json",
        "deployment/config.production.json": ROOT / "server/linux/config.production.json",
        "deployment/incense-debt.service": ROOT / "server/linux/incense-debt.service",
        "deployment/incense-debt-certificate.service": ROOT / "server/linux/incense-debt-certificate.service",
        "deployment/incense-debt-certificate.timer": ROOT / "server/linux/incense-debt-certificate.timer",
        "deployment/certificate_refresh.py": ROOT / "server/linux/certificate_refresh.py",
        "deployment/incense-debt-nginx-reload": ROOT / "server/linux/incense-debt-nginx-reload",
        "deployment/index.html": ROOT / "server/linux/index.html",
        "deployment/logrotate.conf": ROOT / "server/linux/logrotate.conf",
        "deployment/stop.sh": ROOT / "server/linux/stop.sh",
        "deployment/xhz-server.nginx.conf": ROOT / "server/linux/xhz-server.nginx.conf",
    }
    for relative, source in public_files.items():
        target = archive / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        entries[relative] = {"bytes": target.stat().st_size, "sha256": sha(target), "origin": tag + ":" + source.relative_to(ROOT).as_posix()}

    readme = f"""# 香火债 {args.version} 服务端源码归档 / Incense Debt {args.version} server archive

本目录冻结 `v{args.version}` 正式版的共享权威逻辑、原生 Godot 服务工程和公开部署模板。正式 Release 只发布二进制 ZIP；本归档不包含 TLS 私钥、凭据、玩家 token、检查点、日志、缓存或 native binary。

This directory freezes the shared authoritative logic, portable native Godot server project and public deployment templates for release `v{args.version}`. The release publishes binary ZIPs separately; this archive contains no private keys, credentials, player tokens, checkpoints, logs, caches or native binaries.

从仓库根目录运行：

```powershell
python tools/runtime/verify_server_archive.py --version {args.version}
```

The manifest binds every file to SHA-256, the release tag and the native server build hashes. Rebuilds may differ in native bytes when import metadata changes; the published release remains authoritative.
"""
    (archive / "README.md").write_text(readme, "utf8")

    windows = ROOT / "build/server/IncenseDebtServer.exe"
    linux = ROOT / "build/server-linux/IncenseDebtServer.x86_64"
    native = {}
    for name, path in [("windows-x64", windows), ("linux-x64", linux)]:
        native[name] = {"bytes": path.stat().st_size, "sha256": sha(path), "name": path.name, "built_at": datetime.now(timezone.utc).isoformat()}
    manifest = {
        "schema": 1,
        "version": args.version,
        "release_tag": tag,
        "release_commit": args.release_commit,
        "game_git_tree": git("rev-parse", args.release_commit + ":game"),
        "archived_at": datetime.now(timezone.utc).isoformat(),
        "engine": "Godot 4.7.2.stable",
        "shared_script_count": sum(name.endswith(".gd") for name in shared),
        "shared_data_count": sum(name.endswith(".json") for name in shared),
        "shared_source_sha256": shared,
        "native_artifacts": native,
        "published_server_archives": [],
        "deployment_evidence": "docs/incense-debt/reports/network-udp-acceptance-2026-10-12/activate.json",
        "archive_scope": "Explicit shared source/data/public deployment allowlist; no live credentials, TLS keys, player state, logs, import caches or native binaries",
        "rebuild_scope": "Identical source/data bytes; native exports may differ due to engine/import metadata. Published hashes identify accepted binaries.",
        "files": entries,
    }
    (archive / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"archive": archive.relative_to(ROOT).as_posix(), "files": len(entries), "shared_scripts": manifest["shared_script_count"], "shared_data": manifest["shared_data_count"], "release_commit": args.release_commit}, ensure_ascii=False))


if __name__ == "__main__":
    main()
