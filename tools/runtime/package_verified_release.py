"""Package exact-SHA verified Windows/Android builds without exporting again.

Run before committing release documentation, then publish the committed,
annotated tag with publish_release.py --tag. Only current installable builds
are packaged; older iOS handoffs retain their original release identity.
"""
import argparse
import hashlib
import re
import shutil
import subprocess
import zipfile

from record_widescreen_delivery import ROOT, REPORTS, read, write, digest, require, check_matrix


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf8").strip()


def verified_delivery(tag):
    status = read(REPORTS / "current-product-status.json")
    delivery = read(ROOT / "build/delivery-manifest.json")
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(re.fullmatch(r"v" + re.escape(version) + r"-alpha\.\d+", tag), "Tag differs from project version")
    require(version == status["version"] == delivery["version"], "Delivery versions differ")
    require(not git("status", "--porcelain", "--", "game"), "Commit gameplay before packaging")
    revision = ROOT / status["revision_reports"]
    receipt = read(revision / "delivery.json")
    require(receipt["passed"] and receipt["version"] == version, "Revision delivery not verified")
    windows, android = status["windows"], status["android"]
    for platform, artifact in [("windows", windows), ("android", android)]:
        path = ROOT / artifact["path"]
        require(artifact["bytes"] == path.stat().st_size and artifact["sha256"] == digest(path),
                "Canonical artifact differs from verified bytes: " + platform)
        require(receipt[platform + "_sha256"] == artifact["sha256"], "Stale revision artifact")
        require(any(row == {k: artifact[k] for k in ["path", "sha256", "bytes"]}
                    for row in delivery["files"]), "Delivery manifest differs")
    pack = read(ROOT / delivery["revision_report"])
    apk_path = REPORTS / "platforms/android-verification.json"
    keyboard_path = ROOT / windows["native_runtime_report"]
    apk, keys = read(apk_path), read(keyboard_path)
    require(all(row["passed"] and not row.get("failures") for row in [pack, apk, keys]), "Required verification failed")
    require(pack["windows_sha256"] == keys["artifact_sha256"] == windows["sha256"], "Windows proof is stale")
    require(pack["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Android proof is stale")
    require(all(apk["display_checks"].values()), "Android display flags not verified")
    require(apk["upgrade_signer_matches_previous"] and android["signature_verified"], "Android upgrade signature not verified")
    require(all(row["passed"] for row in keys["checks"]), "Keyboard flow incomplete")
    require(len(pack["checks"]) == receipt["package_checks"] and
            len(keys["checks"]) == receipt["keyboard_checks"], "Verification counts differ")
    source, source_checks, source_captures = check_matrix("native-matrix.json", version, revision=revision)
    native, native_checks, native_captures = check_matrix("windows-matrix.json", version, windows["sha256"], revision)
    require(source_checks == receipt["source_checks"] and native_checks == receipt["packaged_checks"], "Screen evidence differs")
    require(source_captures == receipt["source_captures"] and native_captures == receipt["packaged_captures"], "Screen captures differ")
    mobile = read(ROOT / status["mobile_regression_report"])
    require(not mobile["packaged"] and len(mobile["fixtures"]) == 4, "Mobile flow fixtures incomplete")
    for row in mobile["fixtures"]:
        report = read(revision / "mobile-regression" / row["fixture"] / "verification.json")
        require(row["passed"] and report["passed"] and not report["failures"] and
                len(report["checks"]) == row["checks"], "Mobile flow failed")
    require(sum(row["checks"] for row in mobile["fixtures"]) == receipt["mobile_regression_checks"], "Mobile counts differ")
    # A clean Git tree already binds every committed source/resource blob.
    # Avoid rescanning original art and ignored generation outputs: package
    # evidence binds the actual shipping bytes, while matrices bind the current
    # presentation/input scripts and their native captures.
    members = len(subprocess.check_output(["git", "ls-files", "-z", "game"], cwd=ROOT).split(b"\0")) - 1
    proof_paths = [revision / "delivery.json", ROOT / delivery["revision_report"], apk_path,
                   keyboard_path, revision / "native-matrix.json", revision / "windows-matrix.json",
                   ROOT / status["mobile_regression_report"]]
    return status, {
        "tag": tag, "version": version, "prerelease": True,
        "repository": "wikigsroom/joss-debt", "engine": "Godot 4.7.2",
        "built_from_commit": git("rev-parse", "HEAD"), "game_git_tree": git("rev-parse", "HEAD:game"),
        "game_member_count": members,
        "windows_verification": {"passed": True, "windows_exe_sha256": windows["sha256"],
                                 "keyboard_checks": len(keys["checks"]), "package_checks": len(pack["checks"]),
                                 "native_screen_checks": native_checks, "native_screen_captures": native_captures,
                                 "source_screen_checks": source_checks, "source_mobile_checks": receipt["mobile_regression_checks"],
                                 "runtime_resources": receipt["runtime_resources"],
                                 "matching_compiled_android_scripts": pack["matching_compiled_scripts"],
                                 "evidence_reuse": "exact verified canonical application; no new export"},
        "android": {"build": android["build"], "apk_sha256": android["sha256"],
                    "version_code": android["version_code"], "signature_verified": True,
                    "upgrade_signer_matches_previous": True,
                    "signer_certificate_sha256": apk["signer_certificate_sha256"],
                    "edge_to_edge": True, "physical_device_tested": False},
        "ios": {"included": False, "historical_handoff_version": status["ios"]["version"], "signed_ipa_created": False},
        "save_schema": status["save_schema"],
        "verification_reports": [{"path": path.relative_to(ROOT).as_posix(), "sha256": digest(path)} for path in proof_paths],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    print("Checking the existing applications and their exact-SHA verification records...", flush=True)
    status, manifest = verified_delivery(args.tag)
    directory = ROOT / "build/release" / args.tag
    payload = directory / "assets"
    payload.mkdir(parents=True, exist_ok=True)
    notices = {
        "NotoSansSC-OFL.txt": "game/assets/fonts/OFL.txt",
        "ResourceHanRounded-OFL.txt": "game/assets/fonts/ResourceHanRounded-OFL.txt",
        "SmileySans-OFL.txt": "game/assets/fonts/SmileySans-OFL.txt",
        "Lucide-LICENSE.txt": "game/assets/ui/icons/Lucide-LICENSE.txt",
        "Godot-THIRDPARTY.txt": "game/assets/licenses/Godot-THIRDPARTY.txt",
        "START-HERE.md": "docs/releases/START-HERE.md",
    }
    archive = payload / f"IncenseDebt-{args.tag}-windows-x64.zip"
    print("Compressing Windows with player instructions and license notices...", flush=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        bundle.write(ROOT / status["windows"]["path"], "IncenseDebt/IncenseDebt.exe")
        for name, source in notices.items():
            bundle.write(ROOT / source, "IncenseDebt/" + name)
    print("Checking ZIP integrity and the embedded executable checksum...", flush=True)
    with zipfile.ZipFile(archive) as bundle:
        require(bundle.testzip() is None, "Windows ZIP CRC check failed")
        with bundle.open("IncenseDebt/IncenseDebt.exe") as executable:
            require(hashlib.file_digest(executable, "sha256").hexdigest() == status["windows"]["sha256"], "ZIP executable differs")
        for name, source in notices.items():
            require(bundle.read("IncenseDebt/" + name) == (ROOT / source).read_bytes(), "ZIP notice differs")
    apk_name = f"IncenseDebt-{args.tag}-android-arm64-debug.apk"
    shutil.copyfile(ROOT / status["android"]["path"], payload / apk_name)
    require(digest(payload / apk_name) == status["android"]["sha256"], "Copied APK differs")
    shutil.copyfile(ROOT / notices["START-HERE.md"], payload / "START-HERE.md")
    names = [archive.name, apk_name, "START-HERE.md"]
    manifest["files"] = [{"name": name, "bytes": (payload / name).stat().st_size,
                           "sha256": digest(payload / name)} for name in names]
    write(payload / "release-manifest.json", manifest)
    write(ROOT / "docs/releases" / (args.tag + ".manifest.json"), manifest)
    (payload / "SHA256SUMS.txt").write_text("".join(digest(payload / name) + "  " + name + "\n"
                                                   for name in [*names, "release-manifest.json"]), "utf8")
    write(directory / "verification.json", manifest["windows_verification"])
    print(f"Prepared {args.tag}: verified Windows ZIP, exact Android APK, guide, manifest and checksums.", flush=True)
    for path in sorted(payload.iterdir()):
        if path.is_file():
            print(f"{path.name}: {path.stat().st_size / 1048576:.1f} MiB", flush=True)


if __name__ == "__main__":
    main()
