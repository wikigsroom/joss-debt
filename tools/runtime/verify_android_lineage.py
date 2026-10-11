"""Verify actual Android APK signing, not a sidecar claim."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]
JAVA = Path("C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot/bin")

def verify(apk):
    classes = ROOT / ".local-tools/android-signing/verifier"; classes.mkdir(exist_ok=True)
    jar = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/build-tools/36.0.0/lib/apksigner.jar"
    subprocess.run([str(JAVA / "javac.exe"), "-cp", str(jar), "-d", str(classes), str(ROOT / "tools/runtime/VerifyAndroidLineage.java")], check=True, capture_output=True)
    metadata = json.loads((ROOT / ".local-tools/android-signing/signer.json").read_text("utf8"))
    result = subprocess.run([str(JAVA / "java.exe"), "-cp", str(classes) + os.pathsep + str(jar), "VerifyAndroidLineage", str(apk), metadata["old_certificate_sha256"], metadata["release_certificate_sha256"]], check=True, capture_output=True, timeout=300)
    proof = json.loads(result.stdout)
    with apk.open("rb") as stream: proof["apk_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    return proof

if __name__ == "__main__":
    apk = ROOT / "build/android/IncenseDebt.apk"
    proof = verify(apk)
    (apk.parent / "android-lineage.json").write_text(json.dumps(proof, indent=2) + "\n", "utf8")
    print(json.dumps(proof))
