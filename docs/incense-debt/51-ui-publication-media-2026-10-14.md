# 《香火债》新 UI 发布媒体重制记录

制作日期：2026-10-14。对应当前 `v0.6.1` Windows 发行包和已确认的「水墨朱砂符」UI。此篇是商店截图、实机录屏和宣传片的最新入口；旧版 2026-10-08 媒体保留在原目录作为历史归档。

## 当前交付

| 交付项 | 规格 | 当前文件 |
| --- | --- | --- |
| 游戏截图 | 12 张，1920×1080，原生 PNG | [截图目录](../../output/publishing/incense-debt/store-kit-2026-10-14/screenshots/README.md) · [截图 ZIP](../../output/publishing/incense-debt/store-kit-2026-10-14/IncenseDebt-screenshots-12.zip) |
| 游戏实机录屏 | 120.000 秒，1920×1080，30fps，H.264/AAC | [IncenseDebt-gameplay-120s.mp4](../../output/publishing/incense-debt/store-kit-2026-10-14/videos/IncenseDebt-gameplay-120s.mp4) |
| 宣传片 | 45.000 秒，1920×1080，30fps，H.264/AAC | [IncenseDebt-trailer-45s.mp4](../../output/publishing/incense-debt/store-kit-2026-10-14/videos/IncenseDebt-trailer-45s.mp4) |
| 全量发布媒体包 | 截图、视频、图片、文案、源素材、验证记录 | [完整 ZIP](../../output/publishing/incense-debt/store-kit-2026-10-14/IncenseDebt-complete-store-kit.zip) |
| 当前包清单 | 30 个主要索引文件；含 SHA-256 | [manifest.json](../../output/publishing/incense-debt/store-kit-2026-10-14/manifest.json) |
| 校验结果 | 115 项全部通过 | [validation.json](../../output/publishing/incense-debt/store-kit-2026-10-14/validation.json) |

### 视觉预览

![十二张新 UI 原生截图总览](../../output/publishing/incense-debt/store-kit-2026-10-14/previews/twelve-screenshots-preview.jpg)

![45 秒宣传片关键帧](../../output/publishing/incense-debt/store-kit-2026-10-14/previews/trailer-contact-sheet.jpg)

## 新 UI 对齐内容

本轮媒体全部从当前 Windows 发行包重新采集，画面采用已确认的宣纸、深墨圆角牌、朱砂选择态、玉青可用态和金色奖励态。截图 02 直接展示新角色选择页：生成的纸张背景、墨刷角色卡、圆形图标导航、朱砂主操作按钮和新版字体均来自当前运行时。截图 09、10 展示灯摊和供物选择页，截图 12 展示新的行路图与紧凑侧栏；战斗截图则保留当前 HUD 的红心、铜钱、器具、暂停和地图图标。

宣传片开场与收尾使用同一套纸偶和墨色场景，战斗段落取自当前运行包的灯市、戏楼、铜钱库、河埠和判殿画面。片尾已同步为 `v0.6.1 · 双人合作 · Windows / Android`，不再显示过期的旧版本和“离线单人”信息。字幕仅用于视频叙事，不改变商店图片的“仅游戏名”文字规则。

## 十二张截图内容

| 编号 | 画面 | 对应文件 |
| --- | --- | --- |
| 01 | 纸童 · 灯市后巷实战 | `01-paper-child-combat.png` |
| 02 | 六名还愿人 · 水墨朱砂符角色选择 | `02-character-selection.png` |
| 03 | 纸渡河埠 · 回旋纸伞 | `03-river-returning-umbrella.png` |
| 04 | 铜钱旧库 · 散射射线构筑 | `04-treasury-composed-beams.png` |
| 05 | 赤绫戏楼 · 流火战斗 | `05-opera-flame-lantern.png` |
| 06 | 雷鼓山门 · 雷霆器具 | `06-thunder-gate-lightning.png` |
| 07 | 竹影契林 · 近战灰骨刃 | `07-bamboo-melee.png` |
| 08 | 守名判殿 · 首领战 | `08-magistrate-boss.png` |
| 09 | 灯摊 · 器具与供物 | `09-lantern-shop.png` |
| 10 | 供物选择 · 构筑分歧 | `10-relic-choice.png` |
| 11 | 万愿天穹 · 裂空铜镜 | `11-celestial-prism.png` |
| 12 | 十一重旧账 · 完整行路图 | `12-eleven-floor-map.png` |

完整逐项方法、主题、角色和截图尺寸见 [screenshots/capture-report.json](../../output/publishing/incense-debt/store-kit-2026-10-14/screenshots/capture-report.json)。每张图均为 1920×1080，未经低分辨率截图放大。

## 录制方法与音频

120 秒实机视频使用当前发布 EXE 的原生 Godot MovieWriter，60Hz 游戏模拟由动作脚本驱动，输出固定 30fps、3600 帧；内容包含真实房间移动、走门换层、技能选择、掉落、商店和多种攻击效果。最终 AAC 编码保留 -1.5 dB 峰值余量，避免命中音效在 0 dBFS 处削波。它是可重复的原生展示录制，不冒充真人设备性能测试。

45 秒宣传片由 3.6 秒动态开场、五段各 7.2 秒原生战斗镜头和 7.2 秒动态收尾组成，段落使用 0.3 秒转场，最终 1350 帧。游戏 BGM、攻击音效、命中音效和 UI 声音均保留；最终 AAC 音轨使用 FFmpeg `volumedetect` 复查，报告见 [audio-quality.json](../../output/publishing/incense-debt/store-kit-2026-10-14/videos/audio-quality.json)。

## 证据与边界

- 媒体采集所用 Windows 发行包 SHA-256：`42cbd99e7d8f2905fa1a85264dab3b52f98bcaa1c9b014b91ee92cf3891c7e65`。
- 截图、120 秒录屏和宣传片的 capture/edit 报告均绑定该 SHA，见 [视频报告目录](../../output/publishing/incense-debt/store-kit-2026-10-14/videos/) 和 [截图报告](../../output/publishing/incense-debt/store-kit-2026-10-14/screenshots/capture-report.json)。
- 当前 Windows 包在媒体采集后加入了移动端菜单触摸滚动修复，最新 SHA-256 为 `d1a42e0de0fe08722aeb4a8ac8b20ba1faf73e80b9e5234004164032ca357e81`；滚动修复的独立原生回归证据见 [第52篇](52-mobile-menu-scroll-compatibility-2026-10-14.md)。媒体画面未因该输入层修复改变。
- 当前只完成 Windows 原生桌面/离屏视口采集；没有连接 Android 真机，因此媒体不能作为 Motorola X30 的全屏、帧率或触控验收证据。
- 媒体生成使用本地 Godot、FFmpeg 和项目现有素材，不使用浏览器、Docker、WSL、虚拟机或云端运行环境。

## English

This is the current publication media kit rebuilt for the approved Ink Cinnabar Talisman UI. It contains twelve native 1920×1080 screenshots, a 120-second native gameplay recording, and a 45-second H.264/AAC trailer. The capture reports are bound to the current Windows executable SHA-256 and the final validation has 115 passing checks. The package was captured on a native Windows desktop viewport; no Android physical-device claim is made.
