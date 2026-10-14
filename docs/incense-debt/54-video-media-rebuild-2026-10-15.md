# 《香火债》视频媒体重制记录 · 2026-10-15

本次重新构建了当前 `v0.6.2` 水墨朱砂符 UI 的两部视频：120 秒原生实机录屏和 45 秒宣传片。录制使用已验证的 Windows 包 `build/windows/IncenseDebt.exe`，通过 Godot 原生 MovieWriter 以 1920×1080、30fps 输出；宣传片再使用五段这次采集的战斗镜头进行剪辑。

| 交付项 | 文件 | 时长 | 视频规格 | SHA-256 |
| --- | --- | ---: | --- | --- |
| 游戏实机录屏 | `output/publishing/incense-debt/store-kit-2026-10-08/videos/IncenseDebt-gameplay-120s.mp4` | 120.000 秒 | H.264 / AAC，1920×1080，30fps，3600 帧 | `0100632c4e6cf67c7e145c339a126d7c68de75f6f3ff6655c76c6ef43387eba6` |
| 宣传片 | `output/publishing/incense-debt/store-kit-2026-10-08/videos/IncenseDebt-trailer-45s.mp4` | 45.000 秒 | H.264 / AAC，1920×1080，30fps，1350 帧 | `5f687de1afe72dc3677ccf516fcd0c25afecc97e9fb04ccc62ea6a705b2a834b` |

宣传片源视频保存在 `output/publishing/incense-debt/store-kit-2026-10-08/sources/native-showcase-40s.mp4`，片内包含动态纸偶开场、五段战斗镜头、0.3 秒转场和品牌收尾。片尾版本号已更新为 `v0.6.2 · 双人合作 · Windows / Android`。

## 验证

- 120 秒录屏：3600 帧，平均音量 -28.3dB，峰值 -1.8dB。
- 45 秒宣传片：1350 帧，平均音量 -28.2dB，峰值 -4.3dB。
- 两部视频均通过 FFmpeg 完整解码；115 项素材包验证全部通过。
- 关键帧预览：[trailer-contact-sheet.jpg](../../output/publishing/incense-debt/store-kit-2026-10-08/previews/trailer-contact-sheet.jpg)。
- 详细捕获与剪辑记录：[gameplay-capture.json](../../output/publishing/incense-debt/store-kit-2026-10-08/videos/gameplay-capture.json)、[trailer-edit.json](../../output/publishing/incense-debt/store-kit-2026-10-08/videos/trailer-edit.json)、[validation.json](../../output/publishing/incense-debt/store-kit-2026-10-08/validation.json)。

## English

The v0.6.2 Ink Cinnabar UI media was rebuilt on 2026-10-15. The native gameplay recording is exactly 120 seconds at 1920×1080, 30fps, H.264/AAC; the edited trailer is exactly 45 seconds with 1350 frames. Both videos were captured from the verified Windows package and passed full FFmpeg decode plus the 115-check publication-kit validation.
