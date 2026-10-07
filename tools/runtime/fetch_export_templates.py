"""Fetch pinned official native export templates into this workspace only."""
from pathlib import Path
import hashlib
import json
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / ".local-tools/export-templates-4.7.2"
URL = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
SIZE = 1281349702
SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
WANTED = {"windows_release_x86_64.exe", "windows_debug_x86_64.exe", "android_debug.apk", "android_release.apk", "android_source.zip", "version.txt"}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    lock = DEST / "download-lock.json"
    if lock.exists() and all((DEST / name).exists() for name in WANTED):
        print("Pinned native export templates already ready.")
        return
    archive = DEST / "Godot_v4.7.2-stable_export_templates.tpz"
    if not archive.exists() or archive.stat().st_size != SIZE:
        request = urllib.request.Request(URL, headers={"User-Agent": "IncenseDebt-native-export"})
        with urllib.request.urlopen(request, timeout=120) as response, archive.open("wb") as output:
            total = 0
            reported = 0
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
                total += len(chunk)
                if total - reported >= 128 * 1024 * 1024:
                    print(f"Export templates: {total // (1024 * 1024)} MiB", flush=True)
                    reported = total
    digest = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
    if archive.stat().st_size != SIZE or digest != SHA256:
        raise ValueError("Official template archive size/checksum mismatch")
    records = []
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            name = Path(info.filename).name
            if name in WANTED:
                data = bundle.read(info)  # ZipFile validates the member CRC.
                (DEST / name).write_bytes(data)
                records.append({"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    if not all((DEST / name).exists() for name in WANTED):
        raise ValueError("Archive lacks required native platform templates")
    lock.write_text(json.dumps({"source": URL, "version": "4.7.2", "archive_sha256": digest, "files": records}, indent=2) + "\n", "utf8")
    print("Native Windows/Android export templates ready.")


if __name__ == "__main__":
    main()
