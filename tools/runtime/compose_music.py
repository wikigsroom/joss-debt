"""Compose original 32-bar folk themes and synchronized combat stems locally.

The source PCM masters stay outside the game. Native Vorbis encoding controls
shipping size. Each combat theme has a base, rhythm, tension and accent
performance plus a quiet room-air bed; the accent is authored as a separate
voice so the adaptive mixer can make danger feel musical instead of merely
turning up a loop.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import wave
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/audio"
MASTERS = ROOT / "output/audio/score-masters"
RATE = 48000
BARS = 32
SCORES = [
    ("hub", "hub", 76, [57, 0, 60, 0, 64, 0, 60, 0], [45, 48, 45, 43]),
    ("region_1", "paper_lane", 88, [57, 0, 60, 64, 0, 67, 64, 0, 60, 0, 57, 55, 0, 60, 57, 0], [45, 43, 48, 45]),
    ("region_2", "coin_vault", 102, [55, 0, 62, 60, 0, 64, 0, 62], [43, 38, 43, 45]),
    ("region_3", "ownerless_temple", 66, [52, 0, 0, 59, 0, 62, 0, 0], [40, 38, 43, 40]),
    ("boss", "boss", 114, [57, 57, 0, 62, 60, 0, 64, 62], [45, 43, 40, 45]),
    ("ending", "ending", 72, [57, 0, 64, 0, 60, 0, 57, 0], [45, 48, 43, 45]),
    ("ending_burn", "ending_burn", 70, [57, 0, 55, 0, 60, 0, 57, 0], [45, 43, 40, 45]),
    ("ending_repay", "ending_repay", 80, [57, 0, 60, 64, 0, 67, 64, 0], [45, 48, 50, 45]),
    ("ending_rewrite", "ending_rewrite", 76, [60, 0, 64, 0, 67, 0, 72, 0], [48, 52, 50, 48]),
]

# CC0 references are used as low-volume air beds after local decoding,
# filtering and looping. The authored procedural stem remains the musical
# identity; these beds supply room-scale wind, dust and ember movement.
TEXTURE_SOURCES = {
    "region_1": "dungeon_ambient_1_0.ogg",
    "region_2": "dungeonfire_1.ogg",
    "region_3": "dungeonmystic_1.ogg",
    "boss": "whispers_in_the_fog.ogg",
}
TEXTURE_DIR = ROOT / "output/audio/references/oga-cc0"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frequency(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def struck(midi, duration, decay, material="string"):
    t = np.arange(round(duration * RATE)) / RATE
    f = frequency(midi)
    partials = [(1, 1), (2.01, .26), (3, .09)]
    if material == "copper": partials = [(1, 1), (2.41, .21), (3.76, .06)]
    if material == "wood": partials = [(1, 1), (1.47, .18), (2.68, .08)]
    if material == "jade": partials = [(1, 1), (2.01, .16), (4.03, .05)]
    if material == "paper": partials = [(1, 1), (1.98, .22), (3.99, .12)]
    signal = sum(weight * np.sin(2 * np.pi * f * multiple * t) * np.exp(-t * decay * (1 + .12 * index))
                 for index, (multiple, weight) in enumerate(partials))
    return signal * np.minimum(t / .008, 1)


def airy(midi, duration, rng):
    t = np.arange(round(duration * RATE)) / RATE
    f = frequency(midi)
    envelope = np.sin(np.pi * np.minimum(t / duration, 1)) ** 1.8
    air = sosfilt(butter(2, [900, 2600], fs=RATE, btype="bandpass", output="sos"), rng.normal(size=len(t)))
    return (np.sin(2 * np.pi * f * t + .008 * np.sin(2 * np.pi * 4.1 * t)) + .12 * air) * envelope


def pluck(midi, duration, decay, material="jade"):
    """A brighter, short transient for the authored accent voice."""
    t = np.arange(round(duration * RATE)) / RATE
    f = frequency(midi)
    if material == "copper":
        partials = [(1.0, 1.0), (2.41, .34), (3.76, .14), (5.11, .06)]
    elif material == "paper":
        partials = [(1.0, 1.0), (1.98, .28), (3.99, .15), (7.02, .05)]
    else:
        partials = [(1.0, 1.0), (2.01, .27), (4.03, .10), (6.05, .035)]
    signal = sum(weight * np.sin(2 * np.pi * f * multiple * t) for multiple, weight in partials)
    envelope = np.minimum(t / .004, 1.0) * np.exp(-t * decay)
    shimmer = .045 * np.sin(2 * np.pi * (f * 7.01) * t) * np.exp(-t * (decay * .65))
    return signal * envelope + shimmer


def add(track, note, beat_index, beat, level):
    start = round(beat_index * beat * RATE)
    # Carry the last note's natural tail over the seam at a matching sample offset.
    count = min(len(note), len(track) - start)
    track[start:start + count] += note[:count] * level
    if count < len(note): track[:len(note) - count] += note[count:] * level


def pcm(path, data):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes((np.clip(data, -.99, .99) * 32767).astype("<i2").tobytes())


def write_stem(ffmpeg, name, data, bpm, layer, source="project-original deterministic 32-bar composition", source_path=None):
    # A very short common seam, not a repeated fade every phrase.
    fade = round(.024 * RATE)
    data[:fade] *= np.linspace(0, 1, fade)
    data[-fade:] *= np.linspace(1, 0, fade)
    master = MASTERS / (name + ".wav")
    target = OUT / (name + ".ogg")
    pcm(master, data)
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(master),
                    "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "4", str(target)],
                   check=True, capture_output=True, timeout=60)
    # Inspect the actual encoded stream, including its complete sample count.
    decoded = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(target),
                              "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1"],
                             check=True, capture_output=True, timeout=30)
    samples = np.frombuffer(decoded.stdout, dtype="<f4")
    if abs(len(samples) - len(data)) > 256: raise ValueError("Encoded score length drift: " + name)
    if np.max(np.abs(samples)) >= .98: raise ValueError("Encoded score clips: " + name)
    entry = {"id": name, "file": target.relative_to(ROOT).as_posix(), "format": "ogg_vorbis",
            "sample_rate": RATE, "channels": 1, "duration": len(data) / RATE, "bpm": bpm,
            "bars": BARS, "layer": layer, "loop_start_frame": 0, "loop_end_frame": len(data),
            "peak": float(np.max(np.abs(samples))), "rms": float(np.sqrt(np.mean(samples ** 2))),
            "decoded_frames": len(samples), "boundary_jump": float(abs(samples[0] - samples[-1])),
            "sha256": sha(target), "source": source,
            "master": master.relative_to(ROOT).as_posix(), "master_sha256": sha(master)}
    if source_path is not None:
        entry["source_reference"] = source_path.relative_to(ROOT).as_posix()
        entry["source_reference_sha256"] = sha(source_path)
    return entry


def decode_texture(ffmpeg, source: Path, target_samples: int) -> np.ndarray:
    """Decode a CC0 reference to a quiet mono air bed at the score length."""
    decoded = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(source),
                              "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1"],
                             check=True, capture_output=True, timeout=60)
    raw = np.frombuffer(decoded.stdout, dtype="<f4").astype(np.float64)
    if len(raw) < RATE:
        raise ValueError("External texture is shorter than one second: " + str(source))
    raw -= float(np.mean(raw))
    if len(raw) < target_samples:
        raw = np.tile(raw, int(np.ceil(target_samples / len(raw))))
    start = int((len(raw) - target_samples) * .17) if len(raw) > target_samples else 0
    raw = raw[start:start + target_samples]
    # Remove subsonic rumble and brittle hiss while preserving the source's
    # room character. The low amplitude prevents it masking the paper melody.
    filtered = sosfilt(butter(2, [75, 4300], fs=RATE, btype="bandpass", output="sos"), raw)
    rms = float(np.sqrt(np.mean(filtered ** 2)))
    if rms > 1e-8:
        filtered *= .025 / rms
    t = np.arange(target_samples) / RATE
    filtered *= .68 + .22 * np.sin(2 * np.pi * t / max(target_samples / RATE, .1))
    fade = round(.45 * RATE)
    filtered[:fade] *= np.linspace(0, 1, fade)
    filtered[-fade:] *= np.linspace(1, 0, fade)
    return filtered


def compose(context, bpm, melody, roots):
    beat = 60 / bpm
    length = round(BARS * 4 * beat * RATE)
    tracks = {layer: np.zeros(length) for layer in ["base", "rhythm", "tension", "accent"]}
    rng = np.random.default_rng(9107 + sum(ord(c) for c in context))
    # Eight four-bar phrases: statement, answer, development, space, return.
    variations = [0, 0, 1, 2, 3, 1, 2, 0]
    for index in range(BARS * 4):
        phrase = index // 16
        variation = variations[phrase]
        note = melody[index % len(melody)]
        if note and not (variation == 2 and index % 4 in [1, 3]):
            note += 12 if variation == 3 and index % 4 == 2 else 0
            offset = .5 if variation == 1 and index % 4 == 1 else 0
            material = "copper" if context in ["region_2", "boss"] else "string"
            add(tracks["base"], struck(note, 1.7, 3.3, material), index + offset, beat, .07)
        if index % 4 == 0:
            root = roots[(index // 8) % len(roots)]
            add(tracks["base"], struck(root, 3.2, 1.6), index, beat, .075)
        if index % 16 in [10, 14] and context in ["hub", "region_1", "ending_repay", "ending_rewrite"]:
            add(tracks["base"], airy((note or 57) + 12, beat * 1.5, rng), index, beat, .035)
        if index % 16 == 8 and context == "region_3":
            add(tracks["base"], airy(59, beat * 3, rng), index, beat, .032)
        # Rhythm and tension are genuine separate same-length performances.
        add(tracks["rhythm"], struck(38 if index % 4 == 0 else 47, .26, 22, "wood"), index, beat,
            .12 if index % 4 == 0 else .042)
        if context in ["region_2", "boss"] or index % 4 == 2:
            add(tracks["rhythm"], struck(61, .17, 31, "wood"), index + .5, beat, .035)
        root = roots[(index // 8) % len(roots)]
        for subdivision in [0, .5]:
            pitch = root + (24 if subdivision == .5 else 19)
            add(tracks["tension"], struck(pitch, .42, 10, "copper" if context == "boss" else "string"),
                index + subdivision, beat, .055 if index % 4 == 0 else .038)
        if index % 8 == 6:
            add(tracks["tension"], struck((note or 64) + 12, .75, 8, "copper"), index, beat, .026)
        # The accent voice is deliberately sparse and phrase-aware. It is a
        # real second musical idea, not a duplicate of the base stem: jade
        # plucks answer the paper melody, while copper accents sharpen elite
        # and boss rooms. Keeping it independent lets the mixer add danger
        # without raising the whole theme's loudness.
        if index % 8 in [1, 5] or (context == "boss" and index % 4 == 3):
            accent_note = (note or roots[(index // 8) % len(roots)]) + (12 if index % 16 in [5, 13] else 0)
            accent_material = "copper" if context == "boss" or context == "region_2" else ("paper" if context == "region_1" else "jade")
            accent_offset = .25 if index % 16 == 5 else 0
            add(tracks["accent"], pluck(accent_note, beat * (.62 if context == "boss" else .78), 7.5, accent_material),
                index + accent_offset, beat, .038 if index % 4 else .052)
        if context == "region_3" and index % 16 == 15:
            add(tracks["accent"], airy((note or 59) + 19, beat * 1.4, rng), index + .5, beat, .018)
    mixture = tracks["base"] + .58 * tracks["rhythm"] + .45 * tracks["tension"] + .32 * tracks["accent"]
    scale = min(1.0, .55 / float(np.max(np.abs(mixture))))
    for layer in tracks: tracks[layer] *= scale
    return tracks


def main():
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg: raise RuntimeError("Native ffmpeg is required; no virtual environment fallback")
    MASTERS.mkdir(parents=True, exist_ok=True)
    existing = json.loads((OUT / "manifest.json").read_text("utf8"))
    assets = [item for item in existing["assets"] if not item["id"].endswith("_loop")]
    effects_before = {item["file"]: sha(ROOT / item["file"]) for item in assets}
    score_index = {}
    for context, name, bpm, melody, roots in SCORES:
        tracks = compose(context, bpm, melody, roots)
        layers = ["base", "rhythm", "tension", "accent"] if context in ["region_1", "region_2", "region_3", "boss"] else ["base"]
        entries = []
        for layer in layers:
            identifier = name + ("" if layer == "base" else "_" + layer) + "_loop"
            entry = write_stem(ffmpeg, identifier, tracks[layer], bpm, layer)
            assets.append(entry)
            entries.append(identifier)
        if context in TEXTURE_SOURCES:
            source = TEXTURE_DIR / TEXTURE_SOURCES[context]
            if not source.is_file():
                raise FileNotFoundError("Missing CC0 texture reference: " + str(source))
            texture_identifier = name + "_texture_loop"
            texture = decode_texture(ffmpeg, source, len(tracks["base"]))
            entry = write_stem(ffmpeg, texture_identifier, texture, bpm, "texture",
                               source="CC0 reference texture, locally filtered and looped",
                               source_path=source)
            assets.append(entry)
            entries.append(texture_identifier)
        score_index[context] = {"bpm": bpm, "beats_per_bar": 4, "bars": BARS,
                                "duration": assets[-1]["duration"], "stems": entries,
                                "phrases": ["statement", "answer", "development", "space", "lift", "answer", "reprise", "return"]}
        print(f"Composed {context}: {len(layers)} synchronized stems, {BARS} bars, {assets[-1]['duration']:.1f}s", flush=True)
    for file, digest in effects_before.items():
        if sha(ROOT / file) != digest: raise ValueError("Existing sound effect changed: " + file)
    # Preserve unused previous short PCM loops as recoverable production history.
    legacy = ROOT / "output/audio/legacy-short-loops"
    legacy.mkdir(parents=True, exist_ok=True)
    for _, name, _, _, _ in SCORES:
        old = OUT / (name + "_loop.wav")
        if old.is_file():
            destination = legacy / old.name
            if destination.exists() and sha(destination) != sha(old): raise ValueError("Conflicting legacy audio backup")
            shutil.move(str(old), str(destination))
            old.with_suffix(".wav.import").unlink(missing_ok=True)
    (OUT / "manifest.json").write_text(json.dumps({"sample_rate": RATE, "license": "project original",
        "assets": assets, "scores": score_index, "composition_tool": "tools/runtime/compose_music.py",
        "composition_revision": "adaptive-score-v3"}, ensure_ascii=False, indent=2) + "\n", "utf8")
    from prepare_asset_registry import prepare_music_scores
    prepare_music_scores()
    manifest_path = ROOT / "docs/incense-debt/data/asset-manifest.json"
    manifest = json.loads(manifest_path.read_text("utf8"))
    for item in assets:
        if not item["id"].endswith("_loop"): continue
        identifier = "music_" + item["id"].removesuffix("_loop")
        record = next((a for a in manifest["assets"] if a["id"] == identifier), None)
        if record is None:
            record = {"id": identifier, "kind": "music"}
            manifest["assets"].append(record)
        record.update({"file": item["file"], "status": "normalized", "engine_ready": False,
                       "sample_rate": RATE, "format": "ogg_vorbis", "source": item["source"],
                       "sha256": item["sha256"], "bpm": item["bpm"], "bars": BARS, "layer": item["layer"]})
        record.pop("engine_evidence", None)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", "utf8")
    report = {"scores": score_index, "audio_files": len(assets), "music_stems": sum(len(row["stems"]) for row in score_index.values()),
              "sound_effects_preserved": len(effects_before), "passed": True,
              "external_texture_sources": len(TEXTURE_SOURCES),
              "checks": ["decoded lengths within 256 samples", "encoded files do not clip", "independent accent stem is present in combat contexts", "SFX byte hashes preserved", "CC0 texture hashes recorded"],
              "composition_revision": "adaptive-score-v3",
              "scope": "local deterministic composition plus CC0 texture beds; not physical speaker or human listening acceptance"}
    (ROOT / "docs/incense-debt/reports/runtime/music-production.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")


if __name__ == "__main__":
    main()
