"""Package the exact accepted 0.3.0 clients and standalone native server.

No exports or tests are fabricated here. Gameplay must already be committed;
all current receipts must agree with the canonical binary and source hashes.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile

from record_online_delivery import ROOT, TARGET, read, write, digest, require, passed


def git(*parts):
    return subprocess.check_output(["git", *parts], cwd=ROOT).decode("utf8").strip()


def verified(tag):
    status = read(ROOT / "docs/incense-debt/reports/current-product-status.json")
    receipt = read(TARGET / "delivery.json")
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(re.fullmatch(r"v" + re.escape(version) + r"-alpha\.\d+", tag), "Tag differs from source version")
    require(version == status["version"] == receipt["version"] == "0.3.0" and receipt["passed"], "Unaccepted delivery")
    require(not git("status", "--porcelain", "--", "game", "server"), "Commit gameplay and server sources before packaging")
    for relative, sha in receipt["source_sha256"].items():
        require(digest(ROOT / relative) == sha, "Gameplay changed after acceptance: " + relative)
    for proof in receipt["proofs"]:
        require(digest(ROOT / proof["path"]) == proof["sha256"], "Acceptance report changed: " + proof["path"])
    windows, android, server = [status[key] for key in ["windows", "android", "server"]]
    for key, artifact in [("windows", windows), ("android", android), ("server", server)]:
        path = ROOT / artifact["path"]
        require(digest(path) == artifact["sha256"] == receipt[key + "_sha256"] and path.stat().st_size == artifact["bytes"], "Artifact differs: " + key)
    for relative, sha in server["shared_source_sha256"].items():
        require(digest(ROOT / "game" / relative) == sha, "Shared server rule source differs")
    native, touch, parity, apk, keys, recovery, storage, load = [read(TARGET / name) for name in
        ["native.json", "native-touch.json", "package-parity.json", "android.json", "keyboard.json", "recovery.json", "storage.json", "load.json"]]
    require(all(passed(row) for row in [native, touch, parity, apk, keys, recovery, storage, load]), "Acceptance failed")
    require(native["packaged"] and native["artifact_sha256"] == parity["windows_sha256"] == keys["artifact_sha256"] == windows["sha256"], "Windows proofs are stale")
    require(touch["packaged_game_used"] and touch["artifact_sha256"] == windows["sha256"] and len(touch["checks"]) >= 33, "Compiled-pack touch proof is stale or incomplete")
    require(apk["apk_sha256"] == parity["android_sha256"] == android["sha256"], "Android proofs are stale")
    require(apk["internet_permission_matches_source"] and apk["internet_expected"] and all(apk["compiled_online_scripts_packaged"].values()), "Missing online APK components")
    require(all(row["server_sha256"] == server["sha256"] for row in [recovery, storage, load]), "Server proofs are stale")
    require(len(native["checks"]) >= 30 and len(keys["checks"]) >= 107 and len(recovery["scenarios"]) == 4 and len(storage["checks"]) == 7, "Incomplete flows")
    require(apk["signature_verified"] and apk["upgrade_signer_matches_previous"] and all(apk["display_checks"].values()), "Android acceptance incomplete")
    return status, {"tag": tag, "version": version, "prerelease": True, "repository": "wikigsroom/joss-debt",
        "engine": "Godot 4.7.2", "built_from_commit": git("rev-parse", "HEAD"), "game_git_tree": git("rev-parse", "HEAD:game"),
        "server_git_tree": git("rev-parse", "HEAD:server"),
        "windows_verification": {"passed": True, "windows_exe_sha256": windows["sha256"], "keyboard_checks": len(keys["checks"]),
            "online_checks": len(native["checks"]), "online_captures": len(native["captures"]), "online_touch_checks": len(touch["checks"]), "package_checks": len(parity["checks"]),
            "runtime_resources": receipt["runtime_resources"], "matching_compiled_android_scripts": parity["matching_compiled_scripts"]},
        "android": {"apk_sha256": android["sha256"], "build": "debug", "version_code": 6, "signature_verified": True,
            "signer_certificate_sha256": apk["signer_certificate_sha256"], "upgrade_signer_matches_previous": True,
            "internet_permission": True, "edge_to_edge": True, "physical_device_tested": False},
        "server": {"exe_sha256": server["sha256"], "platform": "windows-x64", "standalone": True,
            "default_rooms": 2, "default_connections": 16, "public_host_deployed": False, "recovery_checks": receipt["checks"]["recovery"],
            "storage_checks": 7, "load_report": (TARGET / "load.json").relative_to(ROOT).as_posix()},
        "ios": {"included": False, "historical_handoff_version": "0.2.0", "signed_ipa_created": False},
        "save_schema": 2, "protocol": 1, "ruleset": "duel-2", "privacy_policy_version": "1.4", "virtualization": "none",
        "verification_reports": receipt["proofs"] + [{"path": (TARGET / "delivery.json").relative_to(ROOT).as_posix(), "sha256": digest(TARGET / "delivery.json")}]}


def check_archive(path, member, sha):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "Archive CRC failure")
        with archive.open(member) as stream:
            require(hashlib.file_digest(stream, "sha256").hexdigest() == sha, "ZIP executable differs from accepted binary")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="v0.3.0-alpha.1")
    args = parser.parse_args()
    status, manifest = verified(args.tag)
    payload = ROOT / "build/release" / args.tag / "assets"
    payload.mkdir(parents=True, exist_ok=True)
    require(not any(payload.iterdir()), "Release assets folder is not empty; preserve it and review before replacing")
    notices = {"NotoSansSC-OFL.txt": "game/assets/fonts/OFL.txt", "ResourceHanRounded-OFL.txt": "game/assets/fonts/ResourceHanRounded-OFL.txt",
        "SmileySans-OFL.txt": "game/assets/fonts/SmileySans-OFL.txt", "Lucide-LICENSE.txt": "game/assets/ui/icons/Lucide-LICENSE.txt",
        "Godot-THIRDPARTY.txt": "game/assets/licenses/Godot-THIRDPARTY.txt", "START-HERE.md": "docs/releases/START-HERE.md"}
    windows_zip = payload / f"IncenseDebt-{args.tag}-windows-x64.zip"
    print("Compressing accepted Windows application...", flush=True)
    with zipfile.ZipFile(windows_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.write(ROOT / status["windows"]["path"], "IncenseDebt/IncenseDebt.exe")
        for name, source in notices.items(): archive.write(ROOT / source, "IncenseDebt/" + name)
    check_archive(windows_zip, "IncenseDebt/IncenseDebt.exe", status["windows"]["sha256"])
    server_zip = payload / f"IncenseDebt-{args.tag}-server-windows-x64.zip"
    print("Compressing accepted native server and launch configuration...", flush=True)
    prefix = "IncenseDebtServer/"
    with zipfile.ZipFile(server_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.write(ROOT / status["server"]["path"], prefix + "IncenseDebtServer.exe")
        for name in ["StartServer.cmd", "StopServer.ps1"]: archive.write(ROOT / "server" / name, prefix + name)
        archive.write(ROOT / "server/config.example.json", prefix + "config.json")
        archive.write(ROOT / "game/assets/licenses/Godot-THIRDPARTY.txt", prefix + "Godot-THIRDPARTY.txt")
        text = (ROOT / "server/README.md").read_text("utf8")
        text = text.replace("../docs/incense-debt/", f"https://github.com/wikigsroom/joss-debt/blob/{args.tag}/docs/incense-debt/")
        archive.writestr(prefix + "README.md", text)
    check_archive(server_zip, prefix + "IncenseDebtServer.exe", status["server"]["sha256"])
    with zipfile.ZipFile(server_zip) as archive:
        require(archive.read(prefix + "config.json") == (ROOT / "server/config.example.json").read_bytes(), "Server config differs")
        require(not any("data/" in name for name in archive.namelist()), "Persistent game data in server ZIP")
    apk_name = f"IncenseDebt-{args.tag}-android-arm64-debug.apk"
    shutil.copyfile(ROOT / status["android"]["path"], payload / apk_name)
    require(digest(payload / apk_name) == status["android"]["sha256"], "Copied APK differs")
    shutil.copyfile(ROOT / "docs/releases/START-HERE.md", payload / "START-HERE.md")
    names = [windows_zip.name, apk_name, server_zip.name, "START-HERE.md"]
    manifest["files"] = [{"name": name, "bytes": (payload / name).stat().st_size, "sha256": digest(payload / name)} for name in names]
    write(payload / "release-manifest.json", manifest)
    write(ROOT / "docs/releases" / (args.tag + ".manifest.json"), manifest)
    (payload / "SHA256SUMS.txt").write_text("".join(digest(payload / name) + "  " + name + "\n" for name in [*names, "release-manifest.json"]), "utf8")
    print(json.dumps({"tag": args.tag, "assets": [{"name": path.name, "bytes": path.stat().st_size} for path in sorted(payload.iterdir())]}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
