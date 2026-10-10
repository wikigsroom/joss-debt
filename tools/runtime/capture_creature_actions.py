"""Capture only installed action atlases through native Godot; close our process on completion."""
from pathlib import Path
import argparse
import json
import subprocess
import hashlib
from datetime import datetime, timezone
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="+")
    args = parser.parse_args()
    manifest_path = ROOT / "game/assets/creature-actions.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    actors = args.only or list(manifest["actors"])
    if any(identity not in manifest["actors"] for identity in actors): raise ValueError("Cannot capture uninstalled action art")
    frames = ROOT / ".local-tools/native-creature-frames"
    frames.mkdir(exist_ok=True)
    imported = subprocess.run([str(ENGINE), "--headless", "--editor", "--path", str(ROOT / "game"), "--import", "--quit"], capture_output=True, timeout=180)
    import_log = imported.stdout.decode("utf8", errors="replace") + imported.stderr.decode("utf8", errors="replace")
    (frames / "import.log").write_text(import_log, "utf8")
    if imported.returncode or "ERROR:" in import_log: raise RuntimeError(import_log[-4000:])
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    command = [str(ENGINE), "--path", str(ROOT / "game"), "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
               "--audio-driver", "Dummy", "--resolution", "1280x720", "--position", "-16000,-16000", "--script", str(ROOT / "tools/runtime/capture_creature_actions.gd"),
               "--", "--qa-capture", "--qa-output=" + str(frames / "saves"), "--creature-output=" + str(frames), "--creature-ids=" + ",".join(actors)]
    result = subprocess.run(command, cwd=ROOT / "game", capture_output=True, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=max(180, len(actors)*35))
    log = result.stdout.decode("utf8", errors="replace") + result.stderr.decode("utf8", errors="replace")
    (frames / "native.log").write_text(log, "utf8")
    if result.returncode or "ERROR:" in log or "SCRIPT ERROR" in log: raise RuntimeError(log[-6000:])
    for identity in actors:
        states = list(manifest["actors"][identity]["states"])
        for direction in ["down", "left", "right", "up"]:
            animation = []
            for column in range(6):
                board = Image.new("RGB", (len(states)*256, 278), "#24333a")
                draw = ImageDraw.Draw(board)
                for index, state in enumerate(states):
                    frame = Image.open(frames / f"{identity}-{state}-{direction}-{column}.png").convert("RGB")
                    board.paste(frame.resize((256,256), Image.Resampling.LANCZOS), (index*256, 22))
                    draw.text((index*256+8, 5), f"{identity} / {state} / {direction} / {column+1}", fill="#ebdfc8")
                animation.append(board)
            animation[2].save(frames / f"{identity}-{direction}-preview.png")
            animation[0].save(frames / f"{identity}-{direction}-preview.gif", save_all=True, append_images=animation[1:], duration=140, loop=0)
    # Keep each successful run's exact scope and asset bindings; the latest
    # capture.json alone cannot prove a previous larger batch was checked.
    if manifest_path.read_bytes() != manifest_bytes:
        raise RuntimeError("Creature manifest changed during native capture; rerun against a stable asset set")
    evidence = {}
    for identity in actors:
        screenshots = {}
        for state in manifest["actors"][identity]["states"]:
            for direction in ["down", "left", "right", "up"]:
                for column in range(6):
                    name = f"{identity}-{state}-{direction}-{column}.png"
                    screenshots[name] = hashlib.sha256((frames / name).read_bytes()).hexdigest()
        evidence[identity] = {"asset_binding": manifest["actors"][identity], "screenshots_sha256": screenshots}
    run = frames / "runs" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run.mkdir(parents=True)
    (run / "capture.json").write_bytes((frames / "capture.json").read_bytes())
    (run / "native.log").write_text(log, "utf8")
    (run / "import.log").write_text(import_log, "utf8")
    (run / "asset-bindings.json").write_text(json.dumps({"manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(), "actors": evidence}, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(f"Actual native preview boards/GIFs written for {len(actors)} installed creature identities.")
    print("Immutable native run evidence: " + str(run))


if __name__ == "__main__": main()
