# 《香火债》发布图片规范与本轮复查

2026-10-08。纸偶形象继续使用已确认的原始肖像。以下规范同时适用于生成脚本、PNG/JPG/WebP 成稿、索引和打包文件。

| 用户要求 | 当前处理 | 正式文件 |
| --- | --- | --- |
| 2. 游戏图标不使用透明背景 | RGB 纸纹方图；多尺寸 PNG 及 Windows ICO 全部不透明 | [1024px 图标](../../output/publishing/incense-debt/store-kit-2026-10-08/branding/app-icon-1024.png) |
| 3. 游戏 LOGO 使用透明背景 | RGBA PNG 的背景 Alpha 为 0，实际字面非空 | [1024px 透明 LOGO](../../output/publishing/incense-debt/store-kit-2026-10-08/branding/logo-title-only-1024.png) |
| 4. LOGO 只包含游戏名文本 | 仅“香火债”，不包含纸偶、英文、副标题或标语 | [2400×840 横向字标](../../output/publishing/incense-debt/store-kit-2026-10-08/branding/logo-horizontal-for-dark-background.png) |
| 5. 封面与宣传图只含游戏标题 | 五张宣传图、横竖封面、Banner、海报均只含“香火债” | [图片选择说明](../../output/publishing/incense-debt/store-kit-2026-10-08/PUBLICATION-IMAGES.md) |

无 LOGO 宣传图与 5120×1654 游戏库壁纸继续完全无字。推荐语、简介、玩法和版本说明保留在发布页的独立文字栏。

[纯发布图片 ZIP](../../output/publishing/incense-debt/store-kit-2026-10-08/IncenseDebt-publication-images-clean.zip)包含可上传图标、透明字标与全部宣传成稿；[完整素材 ZIP](../../output/publishing/incense-debt/store-kit-2026-10-08/IncenseDebt-complete-store-kit.zip)包含实机截图、视频、文案和制作来源。旧版素材可在本地制作备份中恢复。

## 本轮修正

此前纸偶方图被同时标作 LOGO，现已明确区分用途。工程里的透明 Android 自适应前景与背景已合成不透明的发布图标。LOGO 由统一字标函数生成，字体采用已授权的得意黑；米白字用于深色底，墨色字用于浅色底，两者都是透明 PNG。

封面与宣传图已移除英文名、宣传语、玩法标签、平台及版本文字。背景也纳入查看：铜钱旧库使用指定 sub2-image-gen 重新生成没有铭文的钱币和空白愿纸；Banner 裁切排除了门楣上的类似文字图案。

## 验证入口

[validation.json](../../output/publishing/incense-debt/store-kit-2026-10-08/validation.json)检查图像解码、尺寸、全部图标／ICO 不透明、LOGO 透明通道与仅游戏名字标的像素一致性、原始纸偶 RGB、来源和文件哈希。[publication-visual-review.json](../../output/publishing/incense-debt/store-kit-2026-10-08/publication-visual-review.json)记录本轮逐张查看的发布图片及其 SHA-256，图片变化后须重新核对。视觉查看不是 OCR 自动识别结果。

[archive-manifest.json](../../output/publishing/incense-debt/store-kit-2026-10-08/archive-manifest.json)列出四个最新 ZIP 的大小和哈希；每个包完成完整 CRC 校验。当前包中的铜钱场景来源为重新生成的无字版本。
