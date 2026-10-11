"""Create a private release signer and rotate the legacy test certificate.

Private keys/passwords remain under ignored .local-tools. Windows DPAPI binds
the password to this user. Subprocess passwords use environment variables.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import shutil
import zipfile
from android_manifest import minimum_sdk

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / ".local-tools/android-signing"
JAVA = Path("C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot/bin")
KEYSTORE = PRIVATE / "incense-debt-release.jks"
LINEAGE = PRIVATE / "incense-debt-signing-lineage.bin"
LEGACY = ROOT / ".local-tools/godot-4.7.2/editor_data/keystores/debug.keystore"
EXPECTED_LEGACY = "66e1cfbcef2c0251d6d74144e6ac845ad713ec0496a266934645f06ca454708c"


def protect(raw, decrypt=False):
    class Blob(ctypes.Structure):
        _fields_ = [("length", ctypes.c_uint32), ("data", ctypes.POINTER(ctypes.c_ubyte))]
    buffer = ctypes.create_string_buffer(raw)
    source = Blob(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    out = Blob()
    if decrypt:
        ok = ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 0, ctypes.byref(out))
    else:
        ok = ctypes.windll.crypt32.CryptProtectData(ctypes.byref(source), "IncenseDebt release signing", None, None, None, 0, ctypes.byref(out))
    if not ok: raise RuntimeError("Signing password protection failed")
    result = ctypes.string_at(out.data, out.length)
    ctypes.windll.kernel32.LocalFree(out.data)
    return result


def prepare():
    PRIVATE.mkdir(parents=True, exist_ok=True)
    password_file = PRIVATE / "release-password.dpapi"
    if not password_file.exists():
        if KEYSTORE.exists(): raise RuntimeError("A signer exists without its protected password; refusing replacement")
        password_file.write_bytes(protect(secrets.token_urlsafe(32).encode()))
    password = protect(password_file.read_bytes(), True).decode()
    env = os.environ.copy()
    env["INCENSE_ANDROID_RELEASE_PASS"] = password
    env["INCENSE_ANDROID_LEGACY_PASS"] = "android"
    sdk = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/build-tools"
    jar = sorted(sdk.glob("*/lib/apksigner.jar"))[-1]

    def run(command):
        result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, timeout=120)
        if result.returncode:
            message = (result.stdout + result.stderr).decode("utf8", errors="replace").replace(password, "[redacted]")
            raise RuntimeError(message)
        return result.stdout

    if not KEYSTORE.exists():
        run([str(JAVA / "keytool.exe"), "-genkeypair", "-keystore", str(KEYSTORE), "-storetype", "JKS",
             "-alias", "incense-release", "-keyalg", "RSA", "-keysize", "3072", "-validity", "10000",
             "-dname", "CN=Incense Debt, OU=Game Release, O=Wu Guoli",
             "-storepass:env", "INCENSE_ANDROID_RELEASE_PASS", "-keypass:env", "INCENSE_ANDROID_RELEASE_PASS", "-noprompt"])
    for store, alias, variable, name in [(LEGACY, "androiddebugkey", "INCENSE_ANDROID_LEGACY_PASS", "legacy.cer"),
                                        (KEYSTORE, "incense-release", "INCENSE_ANDROID_RELEASE_PASS", "release.cer")]:
        run([str(JAVA / "keytool.exe"), "-exportcert", "-keystore", str(store), "-alias", alias,
             "-storepass:env", variable, "-file", str(PRIVATE / name)])
    old = hashlib.sha256((PRIVATE / "legacy.cer").read_bytes()).hexdigest()
    new = hashlib.sha256((PRIVATE / "release.cer").read_bytes()).hexdigest()
    if old != EXPECTED_LEGACY or new == old: raise RuntimeError("Unexpected release/legacy certificate")
    signer = [str(JAVA / "java.exe"), "-jar", str(jar)]
    if not LINEAGE.exists():
        run([*signer, "rotate", "--out", str(LINEAGE), "--old-signer", "--ks", str(LEGACY),
             "--ks-key-alias", "androiddebugkey", "--ks-pass", "env:INCENSE_ANDROID_LEGACY_PASS",
             "--set-installed-data", "true", "--set-shared-uid", "false", "--set-permission", "false",
             "--set-rollback", "false", "--set-auth", "false", "--new-signer", "--ks", str(KEYSTORE),
             "--ks-key-alias", "incense-release", "--ks-pass", "env:INCENSE_ANDROID_RELEASE_PASS"])
    receipt = {"old_certificate_sha256": old, "release_certificate_sha256": new,
               "lineage_sha256": hashlib.sha256(LINEAGE.read_bytes()).hexdigest(),
               "private_key_committed": False, "password_protection": "Windows user-bound DPAPI",
               "installed_data_capability": True, "rollback_capability": False, "minimum_android_api": 28}
    (PRIVATE / "signer.json").write_text(json.dumps(receipt, indent=2) + "\n", "utf8")
    return env, signer, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--export", action="store_true")
    parser.add_argument("--apk", type=Path, default=ROOT / "build/android/IncenseDebt.apk")
    args = parser.parse_args()
    env, signer, receipt = prepare()
    if args.prepare_only:
        print(json.dumps(receipt)); return
    if args.export:
        env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(KEYSTORE), GODOT_ANDROID_KEYSTORE_RELEASE_USER="incense-release",
                   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=env["INCENSE_ANDROID_RELEASE_PASS"])
        result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "tools/runtime/build_native.py"), "android",
                                 "--android-build", "release", "--android-output", str(args.apk), "--export-timeout", "1800"], cwd=ROOT, env=env)
        if result.returncode: raise RuntimeError("Native Android release export failed")
    target = args.apk.resolve()
    # Native templates fix minSdk at 24. Restrict the formal rotated-key APK to
    # Android 9+ by editing this one manifest value, then align and sign again.
    unaligned = target.with_name(target.stem + "-unaligned.apk")
    aligned = target.with_name(target.stem + "-aligned.apk")
    with zipfile.ZipFile(target) as source, zipfile.ZipFile(unaligned, "w") as output:
        for info in source.infolist():
            name = info.filename.upper()
            if name.startswith("META-INF/") and (name.endswith((".SF", ".RSA", ".DSA", ".EC")) or name == "META-INF/MANIFEST.MF"): continue
            if info.filename == "AndroidManifest.xml": output.writestr(info, minimum_sdk(source.read(info), 28))
            else:
                with source.open(info) as reader, output.open(info, "w", force_zip64=info.file_size >= 2**31) as writer: shutil.copyfileobj(reader, writer, 1024 * 1024)
    aligner = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/build-tools/36.0.0/zipalign.exe"
    subprocess.run([str(aligner), "-f", "-P", "16", "4", str(unaligned.relative_to(ROOT)), str(aligned.relative_to(ROOT))], check=True, cwd=ROOT, capture_output=True, timeout=300)
    temporary = target.with_name(target.stem + "-rotation.apk")
    result = subprocess.run([*signer, "sign", "--ks", str(LEGACY), "--ks-key-alias", "androiddebugkey",
                             "--ks-pass", "env:INCENSE_ANDROID_LEGACY_PASS", "--next-signer", "--ks", str(KEYSTORE),
                             "--ks-key-alias", "incense-release", "--ks-pass", "env:INCENSE_ANDROID_RELEASE_PASS",
                             "--lineage", str(LINEAGE), "--rotation-min-sdk-version", "28", "--v1-signing-enabled", "false",
                             "--v4-signing-enabled", "false", "--out", str(temporary), str(aligned)], cwd=ROOT, env=env,
                            capture_output=True, timeout=300)
    if result.returncode: raise RuntimeError(result.stderr.decode("utf8", errors="replace"))
    temporary.replace(target)
    unaligned.unlink(); aligned.unlink()
    with target.open("rb") as stream: sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt.update(apk_sha256=sha, apk_bytes=target.stat().st_size, build="release", artifact=target.relative_to(ROOT).as_posix())
    (target.parent / "android-signing.json").write_text(json.dumps(receipt, indent=2) + "\n", "utf8")
    source = ROOT / "docs/incense-debt/reports/platforms/android-release-build.json"
    if args.export:
        metadata = json.loads(source.read_text("utf8")); metadata.update(sha256=sha, bytes=target.stat().st_size, signing="release_with_legacy_rotation")
        source.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", "utf8")
        (source.parent / "android-build.json").write_text(source.read_text("utf8"), "utf8")
    print(json.dumps(receipt))


if __name__ == "__main__": main()
