"""Small shipping registry for loading real art and sound on the native renderer."""
from pathlib import Path
import json
import struct
import wave
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def prepare_music_scores():
    production = json.loads((ROOT / "game/assets/audio/manifest.json").read_text("utf8"))
    scores = production["scores"]
    for score in scores.values():
        for stem in score["stems"]:
            if not (ROOT / "game/assets/audio" / (stem + ".ogg")).is_file():
                raise ValueError("Missing runtime music stem: " + stem)
    (ROOT / "game/data/music_scores.json").write_text(
        json.dumps({"sample_rate": production["sample_rate"], "scores": scores}, ensure_ascii=False, indent=2) + "\n", "utf8")


def main():
    prepare_music_scores()
    records = []
    for path in sorted((ROOT / "game/assets").rglob("*.png")):
        image = Image.open(path)
        records.append({"file": "res://" + path.relative_to(ROOT / "game").as_posix(), "kind": "texture", "size": list(image.size)})
    for path in sorted((ROOT / "game/assets/ui/icons").glob("*.svg")):
        xml = ET.fromstring(path.read_text("utf8"))
        records.append({"file": "res://" + path.relative_to(ROOT / "game").as_posix(), "kind": "texture", "format": "svg", "size": [int(xml.attrib["width"]), int(xml.attrib["height"])]})
    for path in sorted((ROOT / "game/assets/fonts").glob("*.ttf")):
        records.append({"file": "res://" + path.relative_to(ROOT / "game").as_posix(), "kind": "font", "fallback": path.name == "NotoSansSC.ttf"})
    for path in sorted((ROOT / "game/assets/audio").glob("*.wav")):
        with wave.open(str(path), "rb") as file:
            records.append({"file": "res://" + path.relative_to(ROOT / "game").as_posix(), "kind": "audio", "format": "pcm_wav",
                            "sample_rate": file.getframerate(), "duration": file.getnframes() / file.getframerate()})
    for path in sorted((ROOT / "game/assets/audio").glob("*.ogg")):
        header = path.read_bytes()[:512]
        offset = header.find(b"\x01vorbis")
        if offset < 0: raise ValueError("Missing Vorbis identification packet: " + str(path))
        rate = struct.unpack_from("<I", header, offset + 12)[0]
        entry = next(a for a in json.loads((path.parent / "manifest.json").read_text("utf8"))["assets"] if a["file"] == path.relative_to(ROOT).as_posix())
        records.append({"file": "res://" + path.relative_to(ROOT / "game").as_posix(), "kind": "audio", "format": "ogg_vorbis",
                        "sample_rate": rate, "duration": entry["duration"]})
    playlist = json.loads((ROOT / "game/data/music_playlist.json").read_text("utf8"))
    for track in playlist["tracks"]:
        path = ROOT / "game" / track["path"].removeprefix("res://")
        header = path.read_bytes()[:512]
        offset = header.find(b"\x01vorbis")
        if offset < 0: raise ValueError("Invalid playlist Vorbis stream: " + str(path))
        records.append({"file": track["path"], "kind": "audio", "format": "ogg_vorbis", "sample_rate": struct.unpack_from("<I", header, offset + 12)[0], "duration": track["duration"], "source": "user_selected_yourset", "loop": False})
    (ROOT / "game/data/runtime_assets.json").write_text(json.dumps({"assets": records}, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Registered {len(records)} actual runtime assets.")


if __name__ == "__main__":
    main()
