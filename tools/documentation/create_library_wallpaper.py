"""Recompose the approved paper spirit without text, then run native 4x AI SR."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "output/publishing/incense-debt/store-kit-2026-10-08"
SOURCE = ROOT / "output/imagegen/incense-debt/release-promo-2026-10-08"
NATIVE = ROOT / ".local-tools/realesrgan-native/realesrgan-ncnn-vulkan-v0.2.0-windows"
MODELS = ROOT / ".local-tools/realesrgan-model-bundle/models"
WORK = ROOT / ".local-tools/library-wallpaper-upscale"
FINAL_SIZE = (5120, 1654)
NAME = "library-wallpaper-no-logo-5120x1654"
MODEL = "realesrgan-x4plus"


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def render_library_wallpaper():
    WORK.mkdir(parents=True, exist_ok=True)
    (KIT / "artwork").mkdir(parents=True, exist_ok=True)
    (KIT / "sources").mkdir(parents=True, exist_ok=True)
    (KIT / "previews").mkdir(parents=True, exist_ok=True)
    background_path = SOURCE / "generated-banner-background.png"
    hero_path = SOURCE / "layers/original-paper-spirit.png"
    executable = NATIVE / "realesrgan-ncnn-vulkan.exe"
    weights = MODELS / (MODEL + ".bin")
    config = MODELS / (MODEL + ".param")
    recipe = dict(background_sha256=sha(background_path), hero_sha256=sha(hero_path),
        model=MODEL, model_sha256=sha(weights), config_sha256=sha(config),
        executable_sha256=sha(executable), crop=[0, 180, 1916, 799],
        composition_size=[2000, 646], scale=4, final_dimensions=list(FINAL_SIZE),
        revision=1, text=False, logo=False, watermark=False)
    report_path = KIT / "artwork/library-wallpaper-upscale.json"
    final_path = KIT / "artwork" / (NAME + ".png")
    if report_path.exists() and final_path.exists():
        old = json.loads(report_path.read_text("utf-8"))
        if old.get("recipe") == recipe and old.get("final_sha256") == sha(final_path):
            print("Reusing the verified text-free AI wallpaper.", flush=True)
            return final_path

    # The crop excludes the decorative lintel panel. No letter/wordmark layer is loaded.
    with Image.open(background_path) as source:
        assert source.size == (1916, 821), source.size
        image = source.convert("RGB").crop(tuple(recipe["crop"])).resize(
            tuple(recipe["composition_size"]), Image.Resampling.LANCZOS).convert("RGBA")
    width, height = image.size
    ramp = np.clip((.60 - np.linspace(0, 1, width)) / .50, 0, 1) * .38
    shade = Image.new("RGBA", image.size, "#171E20")
    shade.putalpha(Image.fromarray(np.broadcast_to((ramp * 255).astype(np.uint8), (height, width)).copy()))
    image.alpha_composite(shade)
    with Image.open(hero_path) as source:
        actor = source.convert("RGBA")
        actor = actor.crop(actor.getchannel("A").getbbox())
    actor_height = round(height * .87)
    actor = actor.resize((round(actor.width * actor_height / actor.height), actor_height), Image.Resampling.LANCZOS)
    x = round(width * .815 - actor.width / 2)
    y = round(height * .06)
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((x + actor.width * .10, y + actor_height - 16,
        x + actor.width * .93, y + actor_height + 20), fill=(4, 10, 9, 160))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(17)))
    image.alpha_composite(actor, (x, y))
    base = KIT / "sources/library-wallpaper-no-text-base-2000x646.png"
    image.convert("RGB").save(base)
    raw_output = WORK / "wallpaper-ai-x4-8000x2584.png"
    # Use ASCII native paths because older Windows NCNN releases may use narrow argv.
    native_input = WORK / "input.png"
    shutil.copyfile(base, native_input)
    print("Native Real-ESRGAN 4x inference: 2000x646 -> 8000x2584", flush=True)
    command = [str(executable), "-i", "input.png", "-o", raw_output.name,
        "-m", str(MODELS), "-n", MODEL, "-s", "4", "-t", "256", "-g", "0", "-j", "1:1:1", "-f", "png"]
    result = subprocess.run(command, cwd=WORK, capture_output=True, timeout=900,
        creationflags=subprocess.CREATE_NO_WINDOW)
    log = WORK / "native-upscale.log"
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode != 0:
        raise RuntimeError("Native upscaler failed; diagnostics: " + str(log))
    with Image.open(raw_output) as upscaled:
        upscaled.load()
        assert upscaled.size == (8000, 2584), upscaled.size
        final = upscaled.convert("RGB").resize(FINAL_SIZE, Image.Resampling.LANCZOS)
    # Neural result is downsampled to upload size, never stretched to change the framing.
    final.save(final_path, dpi=(300, 300))
    final.save(final_path.with_suffix(".jpg"), quality=97, subsampling=0, dpi=(300, 300))
    final.save(final_path.with_suffix(".webp"), quality=96, method=6)
    final.resize((1920, 620), Image.Resampling.LANCZOS).save(
        KIT / "previews/library-wallpaper-no-logo-preview.jpg", quality=96)
    report = dict(recipe=recipe, method="Native Windows NCNN/Vulkan Real-ESRGAN 4x, followed by Lanczos downsampling",
        tool_source="https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/tag/v0.2.0",
        model_source="https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0",
        original_background=background_path.relative_to(ROOT).as_posix(),
        original_hero=hero_path.relative_to(ROOT).as_posix(),
        final_file=final_path.relative_to(KIT).as_posix(), final_sha256=sha(final_path),
        neural_output_dimensions=[8000, 2584], meets_minimum=FINAL_SIZE[0] > 3840 and FINAL_SIZE[1] > 1240,
        composited_layers=["original background crop", "quiet shadow", "original paper spirit", "ground shadow"],
        native_returncode=result.returncode)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    (KIT / "licenses").mkdir(exist_ok=True)
    shutil.copyfile(NATIVE / "LICENSE", KIT / "licenses/Real-ESRGAN-ncnn-vulkan-LICENSE.txt")
    # Preserve the earlier titled wallpaper outside the current upload kit.
    legacy = ROOT / "output/publishing/incense-debt/archived-wallpaper-before-upscale"
    for ext in [".png", ".jpg", ".webp"]:
        obsolete = KIT / "artwork" / ("library-wallpaper-2560x1440" + ext)
        if obsolete.exists():
            legacy.mkdir(parents=True, exist_ok=True)
            obsolete.replace(legacy / obsolete.name)
    print(json.dumps({"file": str(final_path), "size": list(FINAL_SIZE), "text": False, "logo": False}), flush=True)
    return final_path


if __name__ == "__main__":
    render_library_wallpaper()
