"""Rebuild the store screenshots and videos against the current UI package.

The existing publication kit remains intact. This runner redirects the checked-in
capture/edit/package tools to a dated output directory, then binds every capture
report to the current Windows executable hash.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "output/publishing/incense-debt/store-kit-2026-10-14"
RAW = ROOT / ".local-tools/store-publishing-capture-2026-10-14"
WINDOWS = ROOT / "build/windows/IncenseDebt.exe"

# The publication helpers import each other by their script names.  Add their
# directory explicitly because this runner is launched from the repository
# root, then load the artwork module under the exact name expected by the
# trailer and packaging helpers.
DOCS = ROOT / "tools/documentation"
if str(DOCS) not in sys.path:
    sys.path.insert(0, str(DOCS))


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run_main(module, args):
    original = sys.argv[:]
    try:
        sys.argv = [str(module.__file__)] + args
        module.main()
    finally:
        sys.argv = original


def bind_hash(report_path: Path, artifact_sha256: str):
    if not report_path.is_file():
        return
    report = json.loads(report_path.read_text("utf-8"))
    report["artifact_sha256"] = artifact_sha256
    report["capture_package"] = "current Windows release package; no physical device"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")


def refresh_audio_quality():
    """Measure the newly encoded AAC streams before package verification."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required to measure publication audio")
    rows = []
    for name in ("IncenseDebt-gameplay-120s.mp4", "IncenseDebt-trailer-45s.mp4"):
        path = KIT / "videos" / name
        result = subprocess.run(
            [ffmpeg, "-hide_banner", "-nostats", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True,
            check=True,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        log = result.stderr.decode("utf-8", errors="replace")
        def last(pattern):
            matches = list(re.finditer(pattern, log))
            if not matches:
                raise RuntimeError(f"Unable to measure {name}: {pattern}")
            return matches[-1].group(1)
        rows.append({
            "file": f"videos/{name}",
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "mean_volume_db": float(last(r"mean_volume:\s*([+-]?[0-9.]+) dB")),
            "max_volume_db": float(last(r"max_volume:\s*([+-]?[0-9.]+) dB")),
            "decoded_samples": int(last(r"n_samples:\s*([0-9]+)")),
        })
    report = {
        "method": "FFmpeg volumedetect on the complete final AAC audio stream; measured 2026-10-14",
        "sample_rate": 48000,
        "channels": 2,
        "measurements": rows,
    }
    (KIT / "videos/audio-quality.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")


def main():
    KIT.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    artifact_sha256 = hashlib.sha256(WINDOWS.read_bytes()).hexdigest()

    if os.environ.get("REDO_STORE_MEDIA_SKIP_CAPTURE") != "1":
        record = load_module("record_store_media_2026_10_14", ROOT / "tools/documentation/record_store_media.py")
        record.OUT = KIT
        record.RAW = RAW
        run_main(record, ["--scenario", "all"])
        for scenario in ("screenshots", "gameplay", "showcase"):
            bind_hash(RAW / scenario / "capture-report.json", artifact_sha256)
            bind_hash(KIT / "screenshots/capture-report.json", artifact_sha256)
            bind_hash(KIT / "videos/gameplay-capture.json", artifact_sha256)
            bind_hash(KIT / "videos/showcase-capture.json", artifact_sha256)

    artwork = load_module("create_store_artwork", ROOT / "tools/documentation/create_store_artwork.py")
    artwork.KIT = KIT
    trailer = load_module("create_store_trailer_2026_10_14", ROOT / "tools/documentation/create_store_trailer.py")
    trailer.KIT = KIT
    trailer.WORK = ROOT / ".local-tools/store-trailer-edit-2026-10-14"
    run_main(trailer, [])
    refresh_audio_quality()

    package = load_module("package_store_kit_2026_10_14", ROOT / "tools/documentation/package_store_kit.py")
    package.KIT = KIT
    package.ART = ROOT / "output/imagegen/incense-debt/store-campaign-2026-10-08"
    package.BRAND = ROOT / "output/branding/incense-debt/current-paper-spirit"
    package.PROMO = ROOT / "output/imagegen/incense-debt/release-promo-2026-10-08"
    package.RAW = RAW
    package.TAG = "v0.6.1-ui-media-2026-10-14"
    artwork.KIT = KIT
    package.main()

    for path in [KIT / "screenshots/capture-report.json", KIT / "videos/gameplay-capture.json", KIT / "videos/showcase-capture.json", KIT / "videos/trailer-edit.json"]:
        bind_hash(path, artifact_sha256)
    manifest = KIT / "manifest.json"
    if manifest.is_file():
        data = json.loads(manifest.read_text("utf-8"))
        data["date"] = "2026-10-14"
        data["tag"] = package.TAG
        data.setdefault("provenance", {})["artifact_sha256"] = artifact_sha256
        manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(json.dumps({"kit": KIT.as_posix(), "raw": RAW.as_posix(), "artifact_sha256": artifact_sha256}, ensure_ascii=False))


if __name__ == "__main__":
    main()
