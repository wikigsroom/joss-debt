"""Fetch a pinned, portable Windows Godot runtime without system installation."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.7.2"
FOLDER = ROOT / ".local-tools" / ("godot-" + VERSION)
FOLDER.mkdir(parents=True, exist_ok=True)
EXE = FOLDER / f"Godot_v{VERSION}-stable_win64_console.exe"
HEADERS = {"User-Agent": "IncenseDebt-local-build"}


def main():
    if EXE.exists():
        print(str(EXE), flush=True)
        return
    request = urllib.request.Request(f"https://api.github.com/repos/godotengine/godot/releases/tags/{VERSION}-stable", headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    name = f"Godot_v{VERSION}-stable_win64.exe.zip"
    asset = next(item for item in release["assets"] if item["name"] == name)
    archive = FOLDER / name
    downloaded = 0
    with urllib.request.urlopen(urllib.request.Request(asset["browser_download_url"], headers=HEADERS), timeout=30) as source, archive.open("wb") as target:
        while chunk := source.read(1024 * 1024):
            target.write(chunk)
            downloaded += len(chunk)
            if downloaded % (16 * 1024 * 1024) == 0:
                print(f"Godot download: {downloaded // (1024*1024)} MiB", flush=True)
    if downloaded != asset["size"]:
        raise RuntimeError("Godot download length differs from release metadata")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    expected = asset.get("digest")
    if expected and expected.startswith("sha256:") and digest != expected.split(":", 1)[1]:
        raise RuntimeError("Godot release digest mismatch")
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError("Godot archive CRC check failed")
        for item in bundle.infolist():
            if not (FOLDER / item.filename).resolve().is_relative_to(FOLDER.resolve()):
                raise RuntimeError("Unsafe archive entry")
        bundle.extractall(FOLDER)
    if not EXE.is_file():
        raise RuntimeError("Godot console executable was not extracted")
    record = {"version": VERSION, "source": asset["browser_download_url"], "bytes": downloaded, "sha256": digest,
              "exe": EXE.relative_to(ROOT).as_posix(), "mode": "portable-native-windows"}
    (ROOT / "tools" / "runtime" / "godot-lock.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"Godot {VERSION} ready: {EXE}", flush=True)


if __name__ == "__main__":
    main()
