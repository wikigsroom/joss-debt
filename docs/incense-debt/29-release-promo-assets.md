# 香火债 / Incense Debt · 发布 Banner、海报与交付索引

2026-10-08。对应已发布游戏版本 `v0.2.0-alpha.1`，沿用[第 28 篇已确认的原始纸偶](28-brand-publication.md)。本轮完成宣传美术文件，不改变已有安装包版本。

| 交付物 | 版本与规格 | 本地文件 |
| --- | --- | --- |
| Windows 可执行文件 | v0.2.0-alpha.1；Windows x64；560.1 MiB | [IncenseDebt.exe](../../build/windows/IncenseDebt.exe) |
| Android APK | v0.2.0-alpha.1；arm64；调试签名；482.6 MiB | [IncenseDebt.apk](../../build/android/IncenseDebt.apk) |
| 游戏图标 | 1024×1024 PNG；RGB，不透明背景，沿用纸偶 | [IncenseDebt-app-icon-1024.png](../../output/imagegen/incense-debt/release-promo-2026-10-08/IncenseDebt-app-icon-1024.png) |
| LOGO | 1024×1024 PNG；RGBA，透明背景，仅“香火债” | [IncenseDebt-logo-1024.png](../../output/imagegen/incense-debt/release-promo-2026-10-08/IncenseDebt-logo-1024.png) |
| Banner | 2560×1080 PNG；另附 JPG、WebP | [IncenseDebt-banner-2560x1080.png](../../output/imagegen/incense-debt/release-promo-2026-10-08/IncenseDebt-banner-2560x1080.png) |
| 海报 | 2160×3240 PNG；2:3；另附 JPG、WebP | [IncenseDebt-poster-2160x3240.png](../../output/imagegen/incense-debt/release-promo-2026-10-08/IncenseDebt-poster-2160x3240.png) |

Windows 与 Android 文件均已核对当前交付清单中的大小和 SHA-256。Android 文件为现有调试签名版本。既有公开安装包位于 [GitHub Release](https://github.com/wikigsroom/joss-debt/releases/tag/v0.2.0-alpha.1)，Windows 公开附件为 ZIP，其中包含可执行文件。

## 横版 Banner

![横版 Banner](../../output/imagegen/incense-debt/release-promo-2026-10-08/banner-preview.png)

适用于游戏发布页头图、官网首屏和宽幅宣传位。左侧仅游戏名“香火债”，右侧为完整纸偶；玉灰石阶、朱红债绳、空白愿纸与香火余烬连接画面。已移除英文、宣传语、玩法胶囊、平台及版本文字，裁切背景时排除了门楣上类似铭文的图案。

## 竖版海报

![竖版海报](../../output/imagegen/incense-debt/release-promo-2026-10-08/poster-preview.png)

适用于社交分享、竖版宣传和小幅印刷。两侧庙柱、纸灯与红幡包围纸偶，石阶形成探索纵深。顶部只保留游戏名“香火债”，其余画面没有宣传语、玩法、平台或版本文字。

PNG、JPG 标注 300dpi；海报按此密度对应约 18.3×27.4cm。文件为 RGB，交付像素尺寸不等于源图原生生成分辨率，原始背景与实际尺寸一并保留。

## 原始形象与美术一致性

纸偶直接复用 `game/assets/portraits/c_paper.png`。该肖像裁取 `(68,58,400,390)` 后缩放至 512px，与当前 `app-icon.png` 的像素完全一致。海报和 Banner 只提取透明轮廓并安排位置，保留原始纸脸、椭圆眼、红绳、衣装、铜香炉与木版纹理。正式 1024px 应用图标是当前 `ios-icon.png` 的逐字节副本；正式 LOGO 则为独立的透明纯文字 PNG，不能用纸偶图标替代。

新背景使用指定的 [sub2-image-gen](C:/Users/carzy/.codex/skills/sub2-image-gen/SKILL.md)，通过本地原生 CLI 请求 `gpt-image-2.5 / high`。场景依照游戏的纸、墨、火、线、铜主题生成；唯一的中文字标由已有授权的得意黑精确排版。颜色与字体细节见[素材说明](../../output/imagegen/incense-debt/release-promo-2026-10-08/README.md)。

## 配套文件

[纯发布图片包](../../output/publishing/incense-debt/store-kit-2026-10-08/IncenseDebt-publication-images-clean.zip)可直接用于上架，包含图标、透明字标、Banner、海报、横竖封面、五张宣传图和无字图。[宣传美术工程包](../../output/imagegen/incense-debt/release-promo-2026-10-08/IncenseDebt-publishing-artwork.zip)另外保留预览、两张原始背景、PNG 分层、实际提示词及来源清单，便于后续编辑。

[成品与来源清单](../../output/imagegen/incense-debt/release-promo-2026-10-08/media-manifest.json)记录尺寸、大小与哈希；[生成记录](../../output/imagegen/incense-debt/release-promo-2026-10-08/generation-report.json)记录实际背景尺寸；[交付索引](../../output/imagegen/incense-debt/release-promo-2026-10-08/release-delivery-index.json)提供可执行文件、APK、游戏图标、LOGO 和宣传图片的真实路径。

English: The artwork retains the approved paper spirit. The icon is opaque; the separate logo has a genuine transparent background and contains only 香火债. The 2560×1080 banner and 2160×3240 poster also contain only the Chinese game title. PNG, JPG, WebP, original backgrounds and layout layers are included. Installation files are the existing v0.2.0-alpha.1 artifacts.
