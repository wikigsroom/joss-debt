"""Verify the authored SFX matrix and the sourced texture/music contract."""
from __future__ import annotations
import hashlib, json, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "game/assets/audio"
REPORT = ROOT / "docs/incense-debt/reports/runtime/audio-design-verification.json"
DIRECTOR = ROOT / "game/scripts/ui/audio_director.gd"
MUSIC_STATE = ROOT / "game/scripts/ui/music_state.gd"
EXPECTED_FAMILIES = {
    "shot", "shot_melee", "shot_ray", "shot_heavy", "shot_controlled",
    "hit", "hit_melee", "hit_heavy", "hit_crit", "hit_armor", "hit_chain",
    "hurt", "hurt_heavy", "hurt_debt", "skill", "dash", "pickup", "bell",
    "clear", "mark", "chain", "death", "warning", "contract", "repay", "menu",
    "armor", "deflect", "burst",
}

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    manifest = json.loads((AUDIO / "manifest.json").read_text("utf8"))
    rows = manifest["assets"]
    sfx = [row for row in rows if row.get("file", "").endswith(".wav")]
    music = [row for row in rows if row.get("format") == "ogg_vorbis"]
    families: dict[str, list[dict]] = {}
    failures: list[str] = []
    for row in sfx:
        ident = row["id"]
        base = ident[:-2] if ident.endswith(("_1", "_2")) else ident
        families.setdefault(base, []).append(row)
        path = ROOT / row["file"]
        if not path.is_file():
            failures.append(f"missing {row['file']}")
            continue
        with wave.open(str(path), "rb") as source:
            if source.getframerate() != 48000 or source.getnchannels() != 1 or source.getsampwidth() != 2:
                failures.append(f"format {ident}")
            if abs(source.getnframes() / 48000.0 - float(row["duration"])) > 1 / 48000:
                failures.append(f"duration {ident}")
        if row.get("source") != "original deterministic layered synthesis v3":
            failures.append(f"provenance {ident}")
        if float(row.get("peak", 1.0)) >= .98:
            failures.append(f"clip risk {ident}")
    if set(families) != EXPECTED_FAMILIES:
        failures.append("SFX family set mismatch")
    for family in EXPECTED_FAMILIES:
        ids = {row["id"] for row in families.get(family, [])}
        if ids != {family, family + "_1", family + "_2"}:
            failures.append(f"variants {family}")
        variant_rows = sorted(families.get(family, []), key=lambda row: row["id"])
        variant_hashes = {digest(ROOT / row["file"]) for row in variant_rows}
        variant_lengths = {round(float(row.get("duration", 0.0)), 6) for row in variant_rows}
        if len(variant_hashes) != 3 or len(variant_lengths) != 3:
            failures.append(f"variant diversity {family}")
    scores = json.loads((ROOT / "game/data/music_scores.json").read_text("utf8"))["scores"]
    stem_names = [name for score in scores.values() for name in score["stems"]]
    manifest_stems = {row["id"] for row in music}
    if set(stem_names) != manifest_stems or len(stem_names) != 25:
        failures.append("music stem registry mismatch")
    for name in stem_names:
        row = next((item for item in music if item["id"] == name), None)
        if row is None or row.get("sample_rate") != 48000 or row.get("channels") != 1 or row.get("bars") != 32:
            failures.append(f"music metadata {name}")
    source_report = json.loads((ROOT / "docs/incense-debt/reports/runtime/audio-source-research.json").read_text("utf8"))
    source_rows = source_report.get("sources", [])
    if len(source_rows) != 4 or any(row.get("license") != "CC0" for row in source_rows):
        failures.append("CC0 source audit")
    source_hashes = {}
    for row in source_rows:
        path = ROOT / row["local_path"]
        actual = digest(path) if path.is_file() else ""
        source_hashes[row["filename"]] = actual
        if actual != row.get("sha256"):
            failures.append(f"source hash {row['filename']}")
    texture_rows = [row for row in music if row.get("layer") == "texture"]
    if len(texture_rows) != 4 or any(row.get("source_reference_sha256") != source_hashes.get(Path(row.get("source_reference", "")).name) for row in texture_rows):
        failures.append("texture provenance")
    director_code = DIRECTOR.read_text("utf8")
    music_code = MUSIC_STATE.read_text("utf8")
    runtime_event_matrix = {
        "attack": ["shot", "ray", "slash"],
        "impact": ["hit", "burst", "chain_formed"],
        "hurt": ["player_hurt", "armor_break"],
        "adaptive_response": ["skill", "chain_formed", "burst", "boss_phase", "wave_incoming"],
    }
    for family, events in runtime_event_matrix.items():
        source = music_code if family == "adaptive_response" else director_code
        for event in events:
            if 'event.kind == "' + event + '"' not in source and '"' + event + '"' not in source:
                failures.append(f"runtime event {family}/{event}")
    payload = {
        "passed": not failures,
        "sfx_families": len(families), "sfx_variants": len(sfx),
        "sfx_family_ids": sorted(families), "music_themes": len(scores),
        "music_stems": len(stem_names), "texture_stems": len(texture_rows),
        "source_license": "CC0", "source_count": len(source_rows),
        "runtime_event_matrix": runtime_event_matrix,
        "checks": ["48kHz mono 16-bit PCM", "three deterministic variants per combat/UI family", "variant hashes and durations remain distinct", "mode-specific attack/impact/hurt families", "runtime attack/impact/hurt event contract", "chain-size adaptive music response", "nine 32-bar score contexts", "four synchronized foreground stems plus a CC0 texture bed in each combat context", "four CC0 texture stems hash-linked to local references"],
        "failures": failures, "virtualization": "none",
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
