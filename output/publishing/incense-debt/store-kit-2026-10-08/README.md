# 香火债 / Incense Debt · 产品发布素材包

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
