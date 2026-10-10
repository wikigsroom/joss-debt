"""Index, verify and package the complete publication media kit."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
import subprocess
import zipfile

from PIL import Image, ImageDraw
from create_logo_candidates import ROOT, font
from create_store_artwork import JOBS, write_artwork_manifest
from publication_brand import GAME_TITLE, wordmark

KIT = ROOT / "output/publishing/incense-debt/store-kit-2026-10-08"
ART = ROOT / "output/imagegen/incense-debt/store-campaign-2026-10-08"
BRAND = ROOT / "output/branding/incense-debt/current-paper-spirit"
PROMO = ROOT / "output/imagegen/incense-debt/release-promo-2026-10-08"
RAW = ROOT / ".local-tools/store-publishing-capture"
TAG = "v0.2.0-alpha.1"


def sha(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream,"sha256").hexdigest()


def probe(path):
    p=subprocess.run([shutil.which("ffprobe"),"-v","error","-show_format","-show_streams","-of","json",str(path)],capture_output=True,check=True,creationflags=subprocess.CREATE_NO_WINDOW)
    return json.loads(p.stdout)


def copy_sources():
    source=KIT/"sources"
    source.mkdir(exist_ok=True)
    (source/"backgrounds").mkdir(exist_ok=True)
    (source/"prompts").mkdir(exist_ok=True)
    generation=json.loads((ART/"generation-manifest.json").read_text("utf-8"))
    for record in generation["records"]:
        file=ROOT/record["file"]
        assert sha(file)==record["sha256"]
        shutil.copyfile(file,source/"backgrounds"/file.name)
    for job in JOBS:
        file=ART/"prompts"/job.get("prompt",job["id"]+".txt")
        shutil.copyfile(file,source/"prompts"/file.name)
    # Keep obsolete source art recoverable outside the current publication kit.
    for relative in ["sources/backgrounds/03-treasury-background.png","sources/prompts/03-treasury.txt"]:
        obsolete=KIT/relative
        if obsolete.exists():
            backup=ROOT/".local-tools/publication-assets-before-cleanup"/obsolete.relative_to(ROOT)
            backup.parent.mkdir(parents=True,exist_ok=True)
            if not backup.exists():shutil.copyfile(obsolete,backup)
            obsolete.unlink()
    shutil.copyfile(ART/"generation-manifest.json",source/"generation-manifest.json")
    shutil.copyfile(ROOT/"output/imagegen/incense-debt/release-promo-2026-10-08/layers/original-paper-spirit.png",source/"original-paper-spirit.png")
    shutil.copyfile(BRAND/"logo-title-only-1024.png",source/"approved-logo-1024.png")
    shutil.copyfile(BRAND/"app-icon-1024.png",source/"approved-app-icon-1024.png")
    (KIT/"branding").mkdir(exist_ok=True)
    for pattern in ["app-icon-*.png","android-app-icon-432.png","logo-*.png","windows-icon.ico"]:
        for file in BRAND.glob(pattern):shutil.copyfile(file,KIT/"branding"/file.name)
    for kind,dimensions in [("banner","2560x1080"),("poster","2160x3240")]:
        for extension in ["png","jpg","webp"]:
            shutil.copyfile(PROMO/f"IncenseDebt-{kind}-{dimensions}.{extension}",KIT/f"artwork/{kind}-{dimensions}.{extension}")
    write_artwork_manifest()
    (KIT/"licenses").mkdir(exist_ok=True)
    for name in ["SmileySans-OFL.txt","ResourceHanRounded-OFL.txt","OFL.txt"]:
        shutil.copyfile(ROOT/"game/assets/fonts"/name,KIT/"licenses"/name)
    for name in ["native-smoke.mp4"]:
        path=KIT/"videos"/name
        if path.exists():
            (RAW/"diagnostics").mkdir(exist_ok=True)
            path.replace(RAW/"diagnostics"/name)
    # The unedited five-shot source remains available for trailer revisions.
    path=KIT/"videos/native-showcase-40s.mp4"
    if path.exists():path.replace(source/"native-showcase-40s.mp4")
    capture_path=KIT/"videos/showcase-capture.json"
    capture=json.loads(capture_path.read_text("utf-8"))
    capture["final_video"]="sources/native-showcase-40s.mp4"
    capture_path.write_text(json.dumps(capture,ensure_ascii=False,indent=2)+"\n","utf-8")
    edit_path=KIT/"videos/trailer-edit.json"
    edit=json.loads(edit_path.read_text("utf-8"))
    edit["native_source"]="sources/native-showcase-40s.mp4"
    edit_path.write_text(json.dumps(edit,ensure_ascii=False,indent=2)+"\n","utf-8")


def screenshot_preview():
    report=json.loads((KIT/"screenshots/capture-report.json").read_text("utf-8"))
    canvas=Image.new("RGB",(1920,1140),"#171E20")
    d=ImageDraw.Draw(canvas)
    d.text((24,20),"香火债 · 十二张原生实机截图",font=font("NotoSansSC.ttf",30),fill="#F0DFC0",anchor="lt")
    for i,row in enumerate(report["screenshots"]):
        pic=Image.open(KIT/"screenshots"/row["filename"]).convert("RGB").resize((450,253),Image.Resampling.LANCZOS)
        x,y=24+(i%4)*474,84+(i//4)*340
        canvas.paste(pic,(x,y))
        d.text((x,y+265),f"{i+1:02d} / "+row["description"],font=font("NotoSansSC.ttf",18),fill="#F0DFC0",anchor="lt")
    canvas.save(KIT/"previews/twelve-screenshots-preview.jpg",quality=95)


def guides():
    rows=["# 十二张游戏截图\n\n1920×1080 原生 PNG，16:9。按实际 Windows 运行视口保存，保留原生 UI、敌人、弹体与效果。\n",
          "| 序号 | 内容 | PNG 文件 |\n| --- | --- | --- |"]
    capture=json.loads((KIT/"screenshots/capture-report.json").read_text("utf-8"))
    for i,entry in enumerate(capture["screenshots"]):rows.append(f"| {i+1:02d} | {entry['description']} | [{entry['filename']}]({entry['filename']}) |")
    rows.append("\n部分图片采用引擎内预置角色、器具、供物与进度的展示场景；截图保存实际原生绘制结果。来源、主题和捕获方法逐项记录在 capture-report.json。")
    (KIT/"screenshots/README.md").write_text("\n".join(rows)+"\n","utf-8")
    readme="""# 香火债 / Incense Debt · 产品发布素材包

制作日期：2026-10-08。对应十一层 Alpha 内容线，发布版本标识 v0.2.0-alpha.1。沿用当前原始纸偶、游戏字体及纸墨民俗视觉。

| 交付项 | 数量 / 规格 | 入口 |
| --- | --- | --- |
| 游戏简介 | 一句话、短版、详细版及英文短版 | [游戏简介](copy/game-introduction.txt) |
| 开发者的话 | 可直接使用的长文 | [开发者的话](copy/developers-message.txt) |
| 首页推荐语 | 正式推荐语、短标题、卡片说明、极短标语 | [首页推荐语](copy/homepage-recommendation.txt) |
| 游戏截图 | 12 张，1920×1080 原生 PNG | [截图目录](screenshots/README.md) |
| 游戏实机录屏 | 120 秒，1920×1080，30fps，H.264/AAC | [120 秒录屏](videos/IncenseDebt-gameplay-120s.mp4) |
| 宣传片 | 45 秒，1920×1080，30fps，H.264/AAC | [45 秒宣传片](videos/IncenseDebt-trailer-45s.mp4) |
| 游戏图标 | 1024×1024，RGB，不透明纸偶方图；另有多尺寸与 ICO | [游戏图标](branding/app-icon-1024.png) |
| 游戏 LOGO | 1024×1024，RGBA，透明，仅“香火债”；另有横向字标 | [透明 LOGO](branding/logo-title-only-1024.png) |
| Banner | 2560×1080，仅游戏名文字，PNG/JPG/WebP | [Banner](artwork/banner-2560x1080.png) |
| 海报 | 2160×3240，仅游戏名文字，PNG/JPG/WebP | [海报](artwork/poster-2160x3240.png) |
| 宣传图 | 5 张，1920×1080，16:9，PNG/JPG/WebP | [五幅总览](previews/five-promos-preview.jpg) |
| 横版封面 | 1920×1080，PNG/JPG/WebP | [横版封面](artwork/cover-horizontal-1920x1080.png) |
| 竖版封面 | 1080×1920，PNG/JPG/WebP | [竖版封面](artwork/cover-vertical-1080x1920.png) |
| 游戏库背景壁纸 | 5120×1654，超宽横版，无 LOGO、无文字，PNG/JPG/WebP | [壁纸](artwork/library-wallpaper-no-logo-5120x1654.png) |
| 无 LOGO 宣传图 | 1920×1080，无字标、无文案、无 UI，PNG/JPG/WebP | [无字宣传图](artwork/promo-no-logo-1920x1080.png) |

## 文案

首页正式推荐语：**纸偶提火，债绳连魂。走过十一重旧账，烧出自己的打法。**

宣传短语：**一愿未还，百债成灰。**

游戏简介围绕“余烬—连债—焚债—收灰”的战斗循环、器具与技能构筑、十一层走门探索、特殊房间、六名角色及本地存档展开。开发者的话说明创作意图、纸偶选择、AI 协作与 Alpha 打磨重点；采用开发者第一人称稿，可按发布者的口吻直接调整。所有文字为 UTF-8。

## 美术

五张宣传图分别使用灯市后巷、纸渡河埠、铜钱旧库、赤绫戏楼、万愿天穹五种环境身份，保留各自暖木、冷蓝、金黄、紫红和星纸色调。角色直接使用已确认的原始纸偶肖像透明轮廓，保留源图 RGB；新场景通过指定 Sub2API / gpt-image-2.5 / high 生成。

本轮发布图片统一采用以下规则：游戏图标为不透明背景；游戏 LOGO 为真正透明的纯中文字标，且仅含“香火债”；五张宣传图、横竖封面、Banner 和海报中的文字也仅含“香火债”。已移除英文名、宣传语、玩法、平台及版本文字。无 LOGO 宣传图与游戏库壁纸完全无字。铜钱旧库背景另行生成，钱币、愿纸、布幡均不带铭文。

中文字标使用得意黑，字体许可证随包提供。前述推荐语和宣传短语是发布页的独立文字栏稿件，不叠入这些图片。

游戏库壁纸单独重排为超宽无字画面，保留原始纸偶完整轮廓。无字背景与纸偶合成后，由本地 Real-ESRGAN 做四倍 AI 超分至 8000×2584，再降采样为 5120×1654；宽高均严格大于 3840×1240。壁纸没有片名、LOGO、文案、平台字样或水印，来源和模型哈希见 artwork/library-wallpaper-upscale.json。

## 实机与视频来源

12 张截图保存原生游戏视口；部分采用预置展示构筑与进度。120 秒录屏从正常初始纸童出发，由自动操作驱动 60Hz 真实战斗与物理门口移动，30fps 原生帧输出，并录入游戏配乐、攻击、命中与 UI 声音。剪掉启动及退出缓冲后，成片恰好 3600 帧。

45 秒宣传片包含动态纸偶美术开场/收尾及五段原生战斗镜头，共 1350 帧。相邻段落采用 0.3 秒转场；字幕避开战斗 HUD。预置展示构筑的五段未经剪辑源视频保留在 sources/；完整镜头表见 [宣传片脚本](copy/trailer-script.md)。

战斗、UI、音频和素材来自已发布 Windows EXE 的资源包，包 SHA-256 为 51b896b4c3deb5a0bb197c44210f5bdd72e95cc216a4dd0961fedd4edee364d9。捕获使用当前源码中的债链绘制修复：敌人死亡/移除后跳过失效链端，不改变战斗数值、掉落或随机序列。截图与视频的捕获记录保存资源包哈希、渲染源码路径与哈希。该修复已写入游戏源码，已发布安装包仍以原发布哈希识别。

临时原生采集工程使用 1280×720 逻辑坐标及 1920×1080 直接渲染输出；没有把截图从低分辨率放大。录屏由原生引擎自动操作采集，不代表真人游玩的帧率或设备性能测量。所有采集进程完成后退出，不使用 Docker、WSL、虚拟机或浏览器。

## 文件选择与验证

上架图片可直接取用 [纯发布图片包](IncenseDebt-publication-images-clean.zip)，文件选择见 [图片使用说明](PUBLICATION-IMAGES.md)。包内仅收录符合上述规则的图标、透明 LOGO、宣传图、封面、Banner、海报、无字图及验证记录。

截图上传优先使用 screenshots/ 内十二个编号 PNG。宣传图上传使用 artwork/promo-01 至 promo-05。需要重新写标题的版位使用 promo-no-logo；JPG 适合较小文件限制，PNG 适合保留图像细节，WebP 可用于官网。宣传图 PNG/JPG 有 300dpi 元数据且为 RGB，LOGO 单独使用 RGBA PNG 保留真实透明通道。

manifest.json 按类别列出 25 张主要图片、2 部视频和 3 份文案的尺寸、来源与 SHA-256；validation.json 保存解码、透明度、字标像素、原始纸偶、视频与文档检查。publication-visual-review.json 逐项绑定已检查的发布图片哈希。图片包、截图包、五张宣传图包及完整素材包均完成 ZIP CRC 检查。

## English

This kit includes publication copy, twelve native 1080p screenshots, a 120-second native gameplay recording, a 45-second edited trailer, five 16:9 promotional artworks, landscape and portrait covers, a library wallpaper and a text-free promotional image. Art retains the exact approved paper spirit. Gameplay is captured from native Godot rendering using automated actions; prepared builds are used for showcase shots. The current source renderer includes a stale debt-chain anchor fix. Original gameplay/UI/audio resources are bound to the published Windows artifact hash. No browser or virtualized environment is used.
"""
    (KIT/"README.md").write_text(readme,"utf-8")
    image_guide="""# 香火债 · 上架图片选择

| 用途 | 文件 | 背景与文字 |
| --- | --- | --- |
| 游戏图标 | [app-icon-1024.png](branding/app-icon-1024.png) | RGB，纸偶原图，不透明背景 |
| 游戏 LOGO | [logo-title-only-1024.png](branding/logo-title-only-1024.png) | RGBA 真透明，仅“香火债” |
| 深色背景横向 LOGO | [logo-horizontal-for-dark-background.png](branding/logo-horizontal-for-dark-background.png) | 2400×840，透明，米白字 |
| 浅色背景横向 LOGO | [logo-horizontal-for-light-background.png](branding/logo-horizontal-for-light-background.png) | 2400×840，透明，墨色字 |
| 横版封面 | [cover-horizontal-1920x1080.png](artwork/cover-horizontal-1920x1080.png) | 1920×1080，仅游戏名 |
| 竖版封面 | [cover-vertical-1080x1920.png](artwork/cover-vertical-1080x1920.png) | 1080×1920，仅游戏名 |
| Banner | [banner-2560x1080.png](artwork/banner-2560x1080.png) | 2560×1080，仅游戏名 |
| 海报 | [poster-2160x3240.png](artwork/poster-2160x3240.png) | 2160×3240，仅游戏名 |
| 无 LOGO 宣传图 | [promo-no-logo-1920x1080.png](artwork/promo-no-logo-1920x1080.png) | 无字 |
| 游戏库壁纸 | [library-wallpaper-no-logo-5120x1654.png](artwork/library-wallpaper-no-logo-5120x1654.png) | 5120×1654，无字 |

artwork/promo-01 至 promo-05 为五张 1920×1080 宣传图，均仅含“香火债”。所有成稿另附同名 JPG/WebP；透明 LOGO 仅提供 PNG。branding/ 另含多尺寸不透明 PNG 图标及 Windows ICO。请根据平台用途分别使用图标与字标。

以下文件是验证依据：[图片视觉复查](publication-visual-review.json)、[整体校验](validation.json)。所有文字文案由发布页独立承载。
"""
    (KIT/"PUBLICATION-IMAGES.md").write_text(image_guide,"utf-8")


def index():
    groups={
        "game_introduction":["copy/game-introduction.txt"],
        "developers_message":["copy/developers-message.txt"],
        "homepage_recommendation":["copy/homepage-recommendation.txt"],
        "screenshots":[p.relative_to(KIT).as_posix() for p in sorted((KIT/"screenshots").glob("[0-9][0-9]-*.png"))],
        "gameplay_recording":["videos/IncenseDebt-gameplay-120s.mp4"],
        "trailer":["videos/IncenseDebt-trailer-45s.mp4"],
        "game_icon":["branding/app-icon-1024.png"],
        "game_logo":["branding/logo-title-only-1024.png"],
        "banner":["artwork/banner-2560x1080.png"],
        "poster":["artwork/poster-2160x3240.png"],
        "promotional_16_9":[p.relative_to(KIT).as_posix() for p in sorted((KIT/"artwork").glob("promo-0[1-5]-*-1920x1080.png"))],
        "cover_horizontal":["artwork/cover-horizontal-1920x1080.png"],
        "cover_vertical":["artwork/cover-vertical-1080x1920.png"],
        "library_wallpaper":["artwork/library-wallpaper-no-logo-5120x1654.png"],
        "promotion_no_logo":["artwork/promo-no-logo-1920x1080.png"],
    }
    files=[]
    for category,paths in groups.items():
        for relative in paths:
            path=KIT/relative
            assert path.is_file(),path
            entry=dict(category=category,file=relative,absolute_path=path.as_posix(),bytes=path.stat().st_size,sha256=sha(path))
            if path.suffix==".png":
                with Image.open(path) as im:entry.update(dimensions=list(im.size),mode=im.mode)
            if path.suffix==".mp4":
                info=probe(path)
                vs=next(s for s in info["streams"] if s["codec_type"]=="video")
                audio=next(s for s in info["streams"] if s["codec_type"]=="audio")
                entry.update(dimensions=[vs["width"],vs["height"]],duration=float(info["format"]["duration"]),
                    fps=vs["avg_frame_rate"],video_frames=int(vs["nb_frames"]),video_codec=vs["codec_name"],audio_codec=audio["codec_name"])
            files.append(entry)
    manifest=dict(version=TAG,date="2026-10-08",groups=groups,files=files,primary_image_count=25,
        publication_rules=dict(icon_background="opaque",logo_background="transparent",logo_text=GAME_TITLE,
            cover_and_promotional_allowed_text=[GAME_TITLE],no_logo_images="no text"),
        provenance=dict(original_hero="game/assets/portraits/c_paper.png",original_hero_sha256=sha(ROOT/"game/assets/portraits/c_paper.png"),
            renderer_source="game/scripts/ui/game_renderer.gd",renderer_sha256=sha(ROOT/"game/scripts/ui/game_renderer.gd"),
            generation="sources/generation-manifest.json",screenshots="screenshots/capture-report.json",gameplay="videos/gameplay-capture.json",trailer="videos/trailer-edit.json"))
    (KIT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n","utf-8")
    with (KIT/"asset-index.csv").open("w",encoding="utf-8-sig",newline="") as stream:
        writer=csv.writer(stream)
        writer.writerow(["分类","文件","宽度","高度","时长（秒）","字节","SHA-256"])
        for entry in files:writer.writerow([entry["category"],entry["file"],*entry.get("dimensions",["",""]),entry.get("duration",""),entry["bytes"],entry["sha256"]])
    return manifest


def verify(manifest,previous_manifest,previous_validation):
    checks=[]
    def check(name,passed,detail=""):
        checks.append(dict(name=name,passed=bool(passed),detail=detail))
    check("twelve screenshots",len(manifest["groups"]["screenshots"])==12)
    check("five 16:9 promotional images",len(manifest["groups"]["promotional_16_9"])==5)
    check("25 primary raster images",sum(1 for e in manifest["files"] if e["file"].endswith(".png"))==25)
    wallpaper=next(e for e in manifest["files"] if e["category"]=="library_wallpaper")
    check("wallpaper strictly larger than 3840x1240",wallpaper["dimensions"][0]>3840 and wallpaper["dimensions"][1]>1240,wallpaper["dimensions"])
    upscaling=json.loads((KIT/"artwork/library-wallpaper-upscale.json").read_text("utf-8"))
    check("wallpaper neural 4x output",upscaling["recipe"]["scale"]==4 and upscaling["neural_output_dimensions"]==[8000,2584])
    check("wallpaper no typography or logo layer",upscaling["recipe"]["text"] is False and upscaling["recipe"]["logo"] is False)
    check("wallpaper upscale proof hash",upscaling["final_sha256"]==wallpaper["sha256"])
    for e in manifest["files"]:
        path=KIT/e["file"]
        check("file hash / "+e["file"],sha(path)==e["sha256"])
        if path.suffix==".png":
            with Image.open(path) as im:im.verify()
            check("decoded PNG / "+e["file"],True)
        if path.suffix==".mp4":
            duration=120 if e["category"]=="gameplay_recording" else 45
            check("duration / "+e["file"],abs(e["duration"]-duration)<.04,e["duration"])
            check("1080p 30fps / "+e["file"],e["dimensions"]==[1920,1080] and e["fps"]=="30/1")
            check("frame count / "+e["file"],e["video_frames"]==duration*30,e["video_frames"])
            check("H264 + AAC / "+e["file"],e["video_codec"]=="h264" and e["audio_codec"]=="aac")
            old_file=next((row for row in previous_manifest.get("files",[]) if row["file"]==e["file"]),{})
            old_check=next((row for row in previous_validation.get("checks",[]) if row["name"]=="complete AV decode / "+e["file"]),{})
            if old_file.get("sha256")==e["sha256"] and old_check.get("passed"):
                check("complete AV decode / "+e["file"],True,dict(verification="Reused successful decode for identical file SHA-256",sha256=e["sha256"]))
            else:
                decoded=subprocess.run([shutil.which("ffmpeg"),"-v","error","-i",str(path),"-f","null","-"],capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
                check("complete AV decode / "+e["file"],decoded.returncode==0 and not decoded.stderr,decoded.stderr.decode("utf-8",errors="replace")[:500])
    import numpy as np
    with Image.open(KIT/"sources/original-paper-spirit.png") as retained,Image.open(ROOT/"game/assets/portraits/c_paper.png") as original:
        check("original paper-spirit RGB unchanged",np.array_equal(np.asarray(retained.convert("RGB")),np.asarray(original.convert("RGB"))))
    check("approved icon copy",sha(KIT/"sources/approved-app-icon-1024.png")==sha(BRAND/"app-icon-1024.png"))
    check("approved title logo copy",sha(KIT/"sources/approved-logo-1024.png")==sha(BRAND/"logo-title-only-1024.png"))
    for path in sorted((KIT/"branding").glob("*.png")):
        with Image.open(path) as im:
            alpha=im.convert("RGBA").getchannel("A")
            if path.name.startswith("logo-"):
                corners=[alpha.getpixel(point) for point in [(0,0),(im.width-1,0),(0,im.height-1),(im.width-1,im.height-1)]]
                check("genuine transparent logo / "+path.name,im.mode=="RGBA" and alpha.getextrema()==(0,255) and corners==[0]*4,
                    dict(mode=im.mode,alpha_extrema=alpha.getextrema(),corner_alpha=corners))
                expected=wordmark(im.size,light="light-background" not in path.name)
                check("logo contains only title glyphs / "+path.name,np.array_equal(np.asarray(im),np.asarray(expected)),GAME_TITLE)
            else:
                check("opaque game icon / "+path.name,im.mode=="RGB" and alpha.getextrema()==(255,255),dict(mode=im.mode,alpha_extrema=alpha.getextrema()))
    with Image.open(KIT/"branding/windows-icon.ico") as ico:
        frames=[dict(dimensions=list(size),alpha_extrema=list(ico.ico.getimage(size).convert("RGBA").getchannel("A").getextrema())) for size in sorted(ico.ico.sizes())]
    check("all ICO frames opaque",all(row["alpha_extrema"]==[255,255] for row in frames),frames)
    review=json.loads((KIT/"publication-visual-review.json").read_text("utf-8"))
    reviewed={row["file"]:row for row in review["images"]}
    publication_files=[entry for entry in manifest["files"] if entry["file"].startswith(("artwork/","branding/"))]
    for entry in publication_files:
        row=reviewed.get(entry["file"],{})
        expected_text=[] if entry["category"] in {"game_icon","library_wallpaper","promotion_no_logo"} else [GAME_TITLE]
        check("visual review bound to image / "+entry["file"],row.get("sha256")==entry["sha256"] and row.get("allowed_text")==expected_text and row.get("passed") is True)
    check("obsolete inscribed treasury absent from current source kit",not (KIT/"sources/backgrounds/03-treasury-background.png").exists())
    for phase in ["screenshots","gameplay","showcase"]:
        log=(RAW/phase/"native.log").read_text("utf-8",errors="replace")
        check("native capture no errors / "+phase,"SCRIPT ERROR" not in log and "ERROR:" not in log)
    audio_quality=json.loads((KIT/"videos/audio-quality.json").read_text("utf-8"))
    for row in audio_quality["measurements"]:
        check("audio file hash / "+row["file"],sha(KIT/row["file"])==row["sha256"])
        check("audible soundtrack with peak headroom / "+row["file"],-80<row["mean_volume_db"]<0 and row["max_volume_db"]<-.1,
            dict(mean_db=row["mean_volume_db"],max_db=row["max_volume_db"]))
    for doc in [KIT/"README.md",KIT/"screenshots/README.md",KIT/"PUBLICATION-IMAGES.md"]:
        missing=[]
        for target in re.findall(r"\]\(([^)]+)\)",doc.read_text("utf-8")):
            if target.startswith(("https://","http://","#")):continue
            if target.endswith(".zip"):continue  # Archives are created after verification.
            if not (doc.parent/target).exists():missing.append(target)
        check("document links / "+doc.name,not missing,missing)
    report=dict(passed=all(e["passed"] for e in checks),checks=checks)
    (KIT/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf-8")
    assert report["passed"],json.dumps([e for e in checks if not e["passed"]],ensure_ascii=False)
    return report


def archive(path,members):
    print("Packaging "+path.name,flush=True)
    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for item in sorted(members):z.write(item,item.relative_to(KIT).as_posix())
    with zipfile.ZipFile(path) as z:assert z.testzip() is None
    return dict(file=path.name,bytes=path.stat().st_size,sha256=sha(path))


def main():
    def prior(path):
        return json.loads(path.read_text("utf-8")) if path.exists() else {}
    previous_manifest=prior(KIT/"manifest.json")
    previous_validation=prior(KIT/"validation.json")
    copy_sources()
    screenshot_preview()
    guides()
    manifest=index()
    verification=verify(manifest,previous_manifest,previous_validation)
    archives=[]
    archives.append(archive(KIT/"IncenseDebt-screenshots-12.zip",[KIT/p for p in manifest["groups"]["screenshots"]]+[KIT/"screenshots/README.md",KIT/"screenshots/capture-report.json"]))
    promos=[p for p in (KIT/"artwork").glob("promo-0[1-5]-*") if p.suffix in {".png",".jpg",".webp"}]
    archives.append(archive(KIT/"IncenseDebt-promotional-images-5.zip",promos))
    clean_members=[p for folder in ["branding","artwork"] for p in (KIT/folder).glob("*") if p.suffix in {".png",".jpg",".webp",".ico"}]
    clean_members += [KIT/"PUBLICATION-IMAGES.md",KIT/"publication-visual-review.json",KIT/"validation.json"]
    archives.append(archive(KIT/"IncenseDebt-publication-images-clean.zip",clean_members))
    members=[p for p in KIT.rglob("*") if p.is_file() and p.suffix not in {".zip",".log"} and p.name!="archive-manifest.json"]
    archives.append(archive(KIT/"IncenseDebt-complete-store-kit.zip",members))
    (KIT/"archive-manifest.json").write_text(json.dumps(dict(archives=archives),ensure_ascii=False,indent=2)+"\n","utf-8")
    print(json.dumps(dict(passed=verification["passed"],checks=len(verification["checks"]),primary_files=len(manifest["files"]),archives=archives,root=str(KIT)),ensure_ascii=False,indent=2),flush=True)


if __name__=="__main__":main()
