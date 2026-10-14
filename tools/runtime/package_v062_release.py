"""Package the reviewed 0.6.2 client and native servers.

The script only copies already-built, already-verified artifacts. It never
builds an alternate client or includes private server state. Run it after the
source and server archive commits, before creating the v0.6.2 tag.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "0.6.2"
TAG = "v" + VERSION
REPO = "wikigsroom/joss-debt"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*parts: str) -> str:
    return subprocess.check_output(["git", *parts], cwd=ROOT).decode("utf8").strip()


def read_json(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text("utf8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")


def add_zip_file(archive: zipfile.ZipFile, source: Path, member: str) -> None:
    archive.write(source, member)


def check_zip_member(path: Path, member: str, expected: str) -> None:
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC failure: " + path.name)
        with archive.open(member) as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
                raise RuntimeError("ZIP member differs from source: " + member)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="replace an existing local assets folder")
    args = parser.parse_args()
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    if version != VERSION:
        raise RuntimeError(f"Expected project version {VERSION}, found {version}")
    if not args.clean and (ROOT / "build/release" / TAG / "assets").exists():
        raise RuntimeError("Release assets already exist; use --clean only after reviewing them")

    windows = ROOT / "build/windows/IncenseDebt.exe"
    android = ROOT / "build/android/IncenseDebt.apk"
    server_windows = ROOT / "build/server/IncenseDebtServer.exe"
    server_linux = ROOT / "build/server-linux/IncenseDebtServer.x86_64"
    for path in [windows, android, server_windows, server_linux]:
        if not path.is_file():
            raise RuntimeError("Missing build artifact: " + path.as_posix())

    windows_report = read_json("docs/incense-debt/reports/platforms/windows-0.6.2/native-render.json")
    keyboard_report = read_json("docs/incense-debt/reports/platforms/windows-0.6.2/keyboard/keyboard-flow.json")
    android_report = read_json("docs/incense-debt/reports/platforms/android-0.6.2-verification.json")
    windows_ok = not windows_report.get("asset_failures") and len(windows_report.get("captures", [])) == 90 and \
        len(windows_report.get("interaction_checks", [])) == 75 and \
        all(row.get("saved") and row.get("state_stable") for row in windows_report.get("captures", [])) and \
        all(row.get("passed") for row in windows_report.get("interaction_checks", []))
    if not windows_ok or not keyboard_report.get("passed"):
        raise RuntimeError("Windows packaged or keyboard verification did not pass")
    if not android_report.get("passed") or not android_report.get("signature_verified"):
        raise RuntimeError("Android static verification did not pass")

    payload = ROOT / "build/release" / TAG / "assets"
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir(parents=True)
    notices = {
        "NotoSansSC-OFL.txt": ROOT / "game/assets/fonts/OFL.txt",
        "ResourceHanRounded-OFL.txt": ROOT / "game/assets/fonts/ResourceHanRounded-OFL.txt",
        "SmileySans-OFL.txt": ROOT / "game/assets/fonts/SmileySans-OFL.txt",
        "Lucide-LICENSE.txt": ROOT / "game/assets/ui/icons/Lucide-LICENSE.txt",
        "Godot-THIRDPARTY.txt": ROOT / "game/assets/licenses/Godot-THIRDPARTY.txt",
    }

    windows_zip = payload / f"IncenseDebt-{TAG}-windows-x64.zip"
    with zipfile.ZipFile(windows_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        add_zip_file(archive, windows, "IncenseDebt/IncenseDebt.exe")
        for name, source in notices.items():
            add_zip_file(archive, source, "IncenseDebt/" + name)
        archive.writestr("IncenseDebt/README.txt", "Run IncenseDebt.exe on Windows x64 with OpenGL 3.3.\n")
    check_zip_member(windows_zip, "IncenseDebt/IncenseDebt.exe", digest(windows))

    def server_zip(path: Path, linux: bool) -> None:
        name = "linux-x64" if linux else "windows-x64"
        output = payload / f"IncenseDebt-{TAG}-server-{name}.zip"
        prefix = "IncenseDebtServer/"
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            add_zip_file(archive, path, prefix + ("IncenseDebtServer.x86_64" if linux else "IncenseDebtServer.exe"))
            if linux:
                add_zip_file(archive, ROOT / "server/linux/stop.sh", prefix + "stop.sh")
            else:
                add_zip_file(archive, ROOT / "server/StartServer.cmd", prefix + "StartServer.cmd")
                add_zip_file(archive, ROOT / "server/StopServer.ps1", prefix + "StopServer.ps1")
            add_zip_file(archive, ROOT / "server/config.example.json", prefix + "config.json")
            add_zip_file(archive, ROOT / "game/assets/licenses/Godot-THIRDPARTY.txt", prefix + "Godot-THIRDPARTY.txt")
            readme = (ROOT / "server/README.md").read_text("utf8")
            readme = readme.replace("../docs/incense-debt/", f"https://github.com/{REPO}/blob/{TAG}/docs/incense-debt/")
            archive.writestr(prefix + "README.md", readme)
        check_zip_member(output, prefix + ("IncenseDebtServer.x86_64" if linux else "IncenseDebtServer.exe"), digest(path))
        with zipfile.ZipFile(output) as archive:
            if any("data/" in member or "server-data/" in member for member in archive.namelist()):
                raise RuntimeError("Server package contains persistent data")
        return output

    linux_zip = server_zip(server_linux, True)
    windows_server_zip = server_zip(server_windows, False)
    apk_name = f"IncenseDebt-{TAG}-android-arm64.apk"
    apk_copy = payload / apk_name
    shutil.copyfile(android, apk_copy)
    if digest(apk_copy) != digest(android):
        raise RuntimeError("Copied APK differs")
    guide = ROOT / "docs/releases/START-HERE.md"
    shutil.copyfile(guide, payload / "START-HERE.md")

    files = [
        {"name": windows_zip.name, "bytes": windows_zip.stat().st_size, "sha256": digest(windows_zip)},
        {"name": apk_name, "bytes": apk_copy.stat().st_size, "sha256": digest(apk_copy)},
        {"name": linux_zip.name, "bytes": linux_zip.stat().st_size, "sha256": digest(linux_zip)},
        {"name": windows_server_zip.name, "bytes": windows_server_zip.stat().st_size, "sha256": digest(windows_server_zip)},
        {"name": "START-HERE.md", "bytes": (payload / "START-HERE.md").stat().st_size, "sha256": digest(payload / "START-HERE.md")},
    ]
    manifest = {
        "schema": 2,
        "tag": TAG,
        "version": VERSION,
        "repository": REPO,
        "prerelease": False,
        "engine": "Godot 4.7.2",
        "built_at": datetime.now(timezone.utc).isoformat(),
        "built_from_commit": git("rev-parse", "HEAD"),
        "game_git_tree": git("rev-parse", "HEAD:game"),
        "server_git_tree": git("rev-parse", "HEAD:server"),
        "native_server_sha256": {"windows": digest(server_windows), "linux": digest(server_linux)},
        "native_server_bytes": {"windows": server_windows.stat().st_size, "linux": server_linux.stat().st_size},
        "windows_verification": {
            "passed": True,
            "artifact_sha256": digest(windows),
            "artifact_bytes": windows.stat().st_size,
            "packaged_checks": len(windows_report.get("interaction_checks", [])),
            "native_captures": len(windows_report.get("captures", [])),
            "keyboard_checks": len(keyboard_report.get("checks", [])),
            "runtime_assets": windows_report.get("asset_loads", 0),
            "report": "docs/incense-debt/reports/platforms/windows-0.6.2/native-render.json",
        },
        "android_verification": {
            "passed": True,
            "apk_sha256": digest(android),
            "apk_bytes": android.stat().st_size,
            "signature_verified": True,
            "physical_device_tested": False,
            "report": "docs/incense-debt/reports/platforms/android-0.6.2-verification.json",
        },
        "native_wan_report": "docs/incense-debt/reports/latency-compensation-2026-10-13/public-wan-v0.6.1.json",
        "local_regression_report": "docs/incense-debt/reports/network-udp-acceptance-2026-10-12/application-regression.json",
        "ui_layout_report": "docs/incense-debt/53-ui-layout-audit-2026-10-14.md",
        "mobile_ui_report": "docs/incense-debt/reports/platforms/windows-0.6.2/mobile/mobile-matrix.json",
        "server_archive": "server/archives/v0.6.0/manifest.json",
        "server_archive_note": "The 0.6.2 server source is tracked in server/ and is bound by server_git_tree; v0.6.0 is the prior immutable archive.",
        "virtualization": "none",
        "physical_android_tested": False,
        "files": files,
    }
    write_json(payload / "release-manifest.json", manifest)
    write_json(ROOT / "docs/releases" / (TAG + ".manifest.json"), manifest)
    checksum_names = [row["name"] for row in files] + ["release-manifest.json"]
    (payload / "SHA256SUMS.txt").write_text("".join(digest(payload / name) + "  " + name + "\n" for name in checksum_names), "utf8")
    print(json.dumps({"tag": TAG, "files": files, "manifest": str(payload / "release-manifest.json")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
