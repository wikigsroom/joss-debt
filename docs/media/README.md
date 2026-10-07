# README 媒体说明 / README media notes

这里存放项目首页的 16 张静态图片和 4 段 GIF。相对路径在 GitHub 和本地 Markdown 阅读器中均可使用；图片来源、输出哈希与捕获构建见 [manifest.json](manifest.json)。

This directory contains the 16 still images and 4 GIFs used by the repository README. Relative paths work on GitHub and in local Markdown readers. [manifest.json](manifest.json) records source paths, output hashes, and the captured build.

## 实机来源 / Native provenance

所有实机媒体来自当前 Windows 原生 Godot 应用，已验证构建 SHA-256：

All runtime media comes from the verified native Windows Godot application, with build SHA-256:

```text
7bed5e7ffc5620dc009493a5c91b7007d2e67091291e829b8650bdfd7958fd85
```

`menu-flow.png` 是基于实际菜单实现绘制的中英双语说明图，不是游戏截图。其他静态图保持原生视口布局，仅转为 WEBP；`themes.webp` 是原生环境捕获的总览拼图。

`menu-flow.png` is a bilingual documentation diagram of the implemented menu flow. Other stills retain their native viewport layout and are converted to WEBP; `themes.webp` is a contact sheet of native environment captures.

| 文件 / File | 内容与方法 / Content and method |
| --- | --- |
| `gameplay.gif` / `gameplay.webp` | 正常初始数值的纸童，行动机器人操作，真实敌人与物理门口；24 秒、120 帧、5 fps。/ Paper Child with unchanged initial stats, action-bot controls, real enemies and doorway movement; 24 seconds, 120 frames, 5 fps. |
| `combat-fx.gif` | 原生脚本场景展示射线和范围攻击阶段。/ Native scripted demonstration of beam and area-attack phases. |
| `scenery.gif` | 原生脚本场景展示地图环境动态。/ Native scripted demonstration of scenery motion. |
| `boss-motion.gif` | 后段双首领原生脚本演示；不表示前五层把两个 Boss 放在同一房。/ Later-floor paired-boss demonstration; early-floor bosses occupy separate chambers. |
| `main-menu.webp` / `save-slots.webp` | 主菜单、三个独立愿簿。/ Main menu and three independent save slots. |
| `characters.webp` / `character-details.webp` | 选角与角色详情。/ Character selection and details. |
| `pause.webp` / `build-map.webp` | 暂停与完整构筑。/ Pause and complete-build view. |
| `shop.webp` | 灯摊购买与试射入口。/ Shop and weapon-trial entry. |
| `mixed-encounter.webp` | 本土与外来主题混编。/ Local/guest-theme mixing. |
| `ray.webp` | 照骨镜射线。/ Native beam weapon. |
| `early-boss-map.webp` / `boss.webp` / `boss-alternative.webp` | 前期独立 Boss 房地图及各房画面。/ Early-floor separate-boss map and chamber views. |
| `themes.webp` / `final-floor.webp` | 二十环境总览与最终主题。/ Twenty-theme overview and final environment. |

GIF 使用统一调色板和透明差分压缩，每一帧解码合成后与原采样的量化结果逐帧比对；尺寸为 768 × 432。降低展示采样率与 GIF 色彩精度不改变游戏画面结构；GIF 不包含音频，也不表示游戏帧率。普通游玩统计与初始角色状态见 [gameplay-capture.json](gameplay-capture.json)。

GIFs use a shared palette and transparent deltas. Every decoded composite frame is checked against its quantized captured frame. Output is 768 × 432. Sampling and GIF palette limits do not change scene layout. GIFs carry no audio and do not establish runtime frame rate. [gameplay-capture.json](gameplay-capture.json) records ordinary capture stats and initial character state.

## 重新捕获 / Reproduction

Windows 导出后，在项目根目录运行：

After exporting Windows, run from the repository root:

```powershell
python -m pip install -r requirements.txt
python tools/documentation/capture_readme_gameplay.py
```

录制脚本使用已导出的 EXE 中的实际世界、渲染器、HUD 和素材，载入本地行动机器人，不读取或写入玩家存档；临时原生窗口退出时关闭。原始采样放在被忽略的 `.local-tools/readme-capture/`。

The capture script uses the actual world, renderer, HUD, and assets embedded in the exported EXE, with the local action bot. It does not read or write player saves and closes its temporary native window on exit. Raw frames go to the ignored `.local-tools/readme-capture/` directory.

生成全部媒体还需要先运行原生 GUI、键盘与扩展 QA，生成本地完整捕获目录，再执行 `python tools/documentation/prepare_readme_media.py`。普通捕获脚本单独执行只更新普通游玩媒体与记录；全量媒体脚本更新统一清单和菜单图。

To rebuild all media, first run native GUI, keyboard, and expansion QA to populate the full local capture directories, then execute `python tools/documentation/prepare_readme_media.py`. The ordinary-capture helper updates its gameplay media and record; the full media helper refreshes the shared manifest and menu diagram.
