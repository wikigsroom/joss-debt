"""Package the selected, existing paper-spirit identity for publication."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

from PIL import Image, ImageDraw

from create_logo_candidates import ROOT, font, text_center, spaced_text
from publication_brand import wordmark

OUT = ROOT / "output/branding/incense-debt/current-paper-spirit"
SOURCES = {
    "paper-spirit-original-512.png": "game/assets/ui/app-icon.png",
    "app-icon-1024.png": "game/assets/ui/ios-icon.png",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lockup(dark):
    return wordmark((2400, 840), light=dark)


def preview():
    board = Image.new("RGB", (1800, 1160), "#171E20")
    d = ImageDraw.Draw(board)
    d.rounded_rectangle((50, 50, 1750, 765), 38, fill="#242F32")
    source = Image.open(OUT / "app-icon-1024.png").convert("RGB")
    board.paste(source.resize((560, 560), Image.Resampling.LANCZOS), (120, 124))
    image = lockup(True).resize((1015, 356), Image.Resampling.LANCZOS)
    board.paste(image, (710, 226), image)
    x = 110
    for size in (192, 128, 64, 48, 32):
        icon = source.resize((size, size), Image.Resampling.LANCZOS)
        board.paste(icon, (x, 855 + (192 - size) // 2))
        x += size + 60
    board.save(OUT / "current-brand-preview.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = []
    for target, source in SOURCES.items():
        shutil.copyfile(ROOT / source, OUT / target)
        assert digest(ROOT / source) == digest(OUT / target)
        sources.append(dict(source=source, output=target, sha256=digest(ROOT / source)))
    im = Image.open(OUT / "paper-spirit-original-512.png").convert("RGB")
    im.save(OUT / "paper-spirit-original-512.png")
    im.save(OUT / "windows-icon.ico", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
    for size in (512, 256, 128, 64, 48, 32, 16):
        im.resize((size, size), Image.Resampling.LANCZOS).save(OUT / f"app-icon-{size}.png")
    android = Image.open(ROOT / "game/assets/ui/adaptive-background.png").convert("RGBA")
    foreground = Image.open(ROOT / "game/assets/ui/adaptive-foreground.png").convert("RGBA")
    android.alpha_composite(foreground)
    android.convert("RGB").save(OUT / "android-app-icon-432.png")
    # Adaptive layers are engine inputs, not standalone store-upload icons.
    for old in ("android-adaptive-foreground.png", "android-adaptive-background.png"):
        (OUT / old).unlink(missing_ok=True)
    lockup(False).save(OUT / "logo-horizontal-for-light-background.png")
    lockup(True).save(OUT / "logo-horizontal-for-dark-background.png")
    wordmark((1024, 1024), light=True).save(OUT / "logo-title-only-1024.png")
    preview()
    guide = """# 香火债 / Incense Debt · 当前纸偶发布素材

选型记录：2026-10-08，用户决定继续使用当前游戏内的纸偶形象。

游戏图标沿用原始纸偶：折纸脸、椭圆黑眼、朱红绳结、红衣与铜香炉。正式上传图标全部导出为 RGB，不含透明背景。LOGO 独立导出为透明 PNG，仅包含“香火债”三个字；没有纸偶、英文副标题或其他文字。

![发布品牌](current-brand-preview.png)

| 文件 | 用途 |
| --- | --- |
| paper-spirit-original-512.png / app-icon-512.png | 同源纸偶的完整不透明方形图标，RGB |
| app-icon-1024.png | 当前 iOS 图标原文件；完整方形、无透明通道 |
| android-app-icon-432.png | Android 前景和背景合成后的完整不透明图标，RGB |
| windows-icon.ico | 同一纸偶的 16 / 32 / 48 / 64 / 128 / 256px Windows 图标 |
| app-icon-尺寸.png | 同一原图的缩小版本 |
| logo-title-only-1024.png | 1024×1024px，透明背景，仅“香火债”字标 |
| logo-horizontal-for-light-background.png | 2400×840px，透明背景，浅色底使用的深色“香火债”字标 |
| logo-horizontal-for-dark-background.png | 2400×840px，透明背景，深色底使用的纸米色“香火债”字标 |

应用图标保留原有纸纹底色，外围和四角全部不透明，不预先裁出透明圆角。Windows ICO 的所有内嵌尺寸也均不透明。Android 自适应的透明前景是引擎输入层，不作为独立上传图标随本包交付。

LOGO 使用已有授权字体得意黑，朱红字影也属于同一游戏名的文字轮廓。透明区域是真实 Alpha 通道；没有底板、纸纹背景、装饰文字或棋盘格。预览图也仅显示游戏名。

当前公开 Release 已经使用该纸偶形象。manifest.json 保存来源、原图哈希和输出规格。

## English

Application icons retain the approved paper spirit and paper-texture backdrop, with fully opaque RGB canvases. Android foreground and background are composited into a standalone opaque icon. Logos are separate RGBA PNG wordmarks containing only the exact Chinese title 香火债, with genuine transparent backgrounds. No subtitle, slogan, mascot or platform label appears inside the logos.
"""
    (OUT / "README.md").write_text(guide, encoding="utf-8")
    outputs = []
    for p in sorted(OUT.iterdir()):
        if p.suffix not in {".png", ".ico"}: continue
        with Image.open(p) as picture:
            picture.load()
            outputs.append(dict(path=p.name, dimensions=list(picture.size), mode=picture.mode,
                                alpha_extrema=list(picture.getchannel("A").getextrema()) if "A" in picture.getbands() else None,
                                bytes=p.stat().st_size, sha256=digest(p)))
    report = dict(selection="existing_paper_spirit", selected_on="2026-10-08",
                  source_release="v0.2.0-alpha.1", source_files=sources, outputs=outputs,
                  artwork_method="Opaque source-identity icons and transparent title-only typesetting",
                  publication_rules=dict(icon_background="opaque", logo_background="transparent", logo_text="香火债"))
    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    archive = OUT / "IncenseDebt-current-paper-spirit-brand-kit.zip"
    members = [p for p in sorted(OUT.iterdir()) if p.suffix in {".png", ".ico", ".md", ".json"}]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for p in members:
            bundle.write(p, "IncenseDebt-current-paper-spirit/" + p.name)
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        for item in members:
            assert bundle.read("IncenseDebt-current-paper-spirit/" + item.name) == item.read_bytes()
    print(json.dumps(dict(selected=report["selection"], copied_originals=len(sources),
                          image_outputs=len(outputs), archive=str(archive), bytes=archive.stat().st_size), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
