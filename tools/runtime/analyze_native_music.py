"""Align native mixer PCM to decoded original stems and measure audible weights."""
from pathlib import Path
import json
import shutil
import subprocess
import wave
import numpy as np
from scipy.signal import correlate

ROOT = Path(__file__).resolve().parents[2]
RATE = 48000


def analyze(report):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg: raise RuntimeError("Native ffmpeg is required for reference decoding")
    stems = []
    # The fixture intentionally seeks near 30 seconds, with a short settle delay.
    start = 29.5
    for name in ["paper_lane_loop", "paper_lane_rhythm_loop", "paper_lane_tension_loop", "paper_lane_accent_loop", "paper_lane_texture_loop"]:
        result = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(ROOT / "game/assets/audio" / (name + ".ogg")),
                                 "-ss", str(start), "-t", "5", "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1"],
                                capture_output=True, check=True, timeout=20)
        stems.append(np.frombuffer(result.stdout, dtype="<f4").astype(np.float64))
    measurements = {}
    for clip in report["recordings"]:
        if clip["name"] not in ["exploration", "combat", "tension", "menu-pause"]: continue
        with wave.open(clip["file"], "rb") as source:
            if source.getframerate() != RATE: raise ValueError("Native mixer does not use the requested 48kHz rate")
            pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64) / 32768
            signal = pcm.reshape(-1, source.getnchannels()).mean(axis=1)
        # Drop record-effect startup samples, then normalize the correlation by
        # each candidate interval's energy; different notes must not bias offset.
        trim = round(.025 * RATE)
        signal = signal[trim:-trim]
        base = stems[0]
        cumulative = np.concatenate(([0.0], np.cumsum(base ** 2)))
        energy = cumulative[len(signal):] - cumulative[:-len(signal)]
        correlation = correlate(base, signal, mode="valid", method="fft")
        normalized = correlation / np.sqrt(np.maximum(1e-20, energy * np.dot(signal, signal)))
        offset = int(np.argmax(normalized))
        references = np.column_stack([stem[offset:offset + len(signal)] for stem in stems])
        weights, _, _, _ = np.linalg.lstsq(references, signal, rcond=None)
        residual = signal - references @ weights
        measurements[clip["name"]] = {
            "source_start_seconds": start + (offset - trim) / RATE,
            "weights": weights.tolist(), "relative_weights": (weights / max(1e-10, weights[0])).tolist(),
            "residual_rms_fraction": float(np.sqrt(np.mean(residual ** 2)) / max(1e-10, np.sqrt(np.mean(signal ** 2)))),
            "reference_condition": float(np.linalg.cond(references)),
            "method": "sample-aligned least-squares fit of four authored score stems plus filtered room-air texture to real native PCM"}
    return measurements


if __name__ == "__main__":
    path = ROOT / "docs/incense-debt/reports/runtime/audio/native-audio.json"
    print(json.dumps(analyze(json.loads(path.read_text("utf8"))), ensure_ascii=False, indent=2))
