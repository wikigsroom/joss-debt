# README 媒体说明 / README media notes

这里存放历史 0.2.0 展示媒体，包括 22 张静态图片和 6 段 GIF；首页另引用下表的 3 段 0.2.1 原生动作 GIF，以及 2 段 0.2.1 掉落物 GIF，共展示 11 段动效。相对路径在 GitHub 和本地 Markdown 阅读器中均可使用；历史图片来源、输出哈希与捕获构建见 [manifest.json](manifest.json)，新增掉落物见[来源记录](../incense-debt/reports/consumables-2026-10-11/media.json)。

This directory retains 22 still images and six GIFs from 0.2.0. The README also embeds three native 0.2.1 action GIFs and two 0.2.1 pickup GIFs, giving eleven motion examples. Relative paths work on GitHub and in local Markdown readers. [manifest.json](manifest.json) records the historical source paths, output hashes, and capture provenance; the pickup revision has its own [media record](../incense-debt/reports/consumables-2026-10-11/media.json).

## 0.2.1 动作对照 / 0.2.1 action comparisons

| GIF | 内容 / Content |
| --- | --- |
| [主角动作 / Hero actions](../incense-debt/reports/action-mobile-2026-10-09/native-actions.gif) | 六名角色、六状态的原生持械与事件特效对照；完整资产为四向 864 个姿势 / Six heroes and six states, with native held weapons and event effects; the full asset set contains 864 poses across four facings |
| [小怪四向 / Four-facing enemy actions](../incense-debt/reports/creature-actions-2026-10-10/enemy-four-directions.gif) | 四行朝向、攻击／受击两列 / Four facing rows, attack/hurt columns |
| [Boss 四向 / Four-facing boss actions](../incense-debt/reports/creature-actions-2026-10-10/boss-four-directions.gif) | 四行朝向、攻击 A／B／C 与受击四列 / Four facing rows, attack A/B/C and hurt columns |
| [掉落待机 / Pickup idle](../incense-debt/reports/consumables-2026-10-11/windows/idle.gif) | 六件生成消耗品在原生场景中的浮动与摆动 / Six generated collectibles bob and tilt in the native arena |
| [真实拾取 / Real collection](../incense-debt/reports/consumables-2026-10-11/windows/collect.gif) | 实际回血、吸附、纸钱与香灰数值变化 / Real healing, magnet attraction, coin and incense-energy changes |

新增 GIF 来自原生渲染帧；怪物对照逐帧绑定完整验收中的截图 SHA-256，按固定 140 毫秒比较，不代表实战时序。原始渲染帧保存在本地，发布 GIF 已纳入 Git。重建怪物 GIF 使用 `python tools/documentation/create_creature_action_showcase.py`；所需原生帧与验收步骤见 [全量怪物交付](../incense-debt/35-creature-action-completion.md)。主角来源见 [动作与移动修订](../incense-debt/33-action-mobile-update.md)。

The new GIFs use native render frames. Creature frames match the screenshot SHA-256 values in the complete verification record and use a fixed 140 ms comparison cadence, rather than combat timing. Raw captures stay local; published GIFs are tracked. Rebuild creature GIFs with `python tools/documentation/create_creature_action_showcase.py` after generating the native evidence described in the [complete creature delivery](../incense-debt/35-creature-action-completion.md). Hero provenance is documented in the [hero/mobile revision](../incense-debt/33-action-mobile-update.md).

## 实机来源 / Native provenance

本目录保留的 0.2.0 实机媒体来自 Windows 原生 Godot 应用，捕获构建 SHA-256：

The retained 0.2.0 runtime media in this directory comes from the native Windows Godot application, with capture-build SHA-256:

```text
51b896b4c3deb5a0bb197c44210f5bdd72e95cc216a4dd0961fedd4edee364d9
```

`menu-flow.png` 是基于实际菜单实现绘制的中英双语说明图，不是游戏截图。其他静态图保持原生视口布局，仅转为 WEBP；`themes.webp` 是原生环境捕获的总览拼图。

`menu-flow.png` is a bilingual documentation diagram of the implemented menu flow. Other stills retain their native viewport layout and are converted to WEBP; `themes.webp` is a contact sheet of native environment captures.

| 文件 / File | 内容与方法 / Content and method |
| --- | --- |
| `gameplay.gif` / `gameplay.webp` | 正常初始数值的纸童，行动机器人操作，真实敌人与物理门口；24 秒、120 帧、5 fps。/ Paper Child with unchanged initial stats, action-bot controls, real enemies and doorway movement; 24 seconds, 120 frames, 5 fps. |
| `equipment-inventory.webp` / `equipment-ground.webp` / `equipment-history.webp` | 主动槽、单槽饰品、E交换与完整历史。/ Active slot, one trinket, E exchange, and full history. |
| `equipment-timeline.webp` / `equipment-touch.webp` | 十一层路线与触控主动道具。/ Eleven-floor timeline and touch active control. |
| `equipment-five-beams.webp` / `equipment-combination.gif` | 真实组合命中与动态采样。/ Actual composed attacks and damage. |
| `equipment-storm.gif` | 只读雷霆家族的六阶段图。/ Read-only six-phase storm gallery. |
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

重建本目录的游玩媒体还需要先运行原生 GUI、键盘与扩展 QA，生成本地完整捕获目录，再执行 `python tools/documentation/prepare_readme_media.py`。普通捕获脚本单独执行只更新普通游玩媒体与记录；全量媒体脚本更新统一清单和菜单图。0.2.1 动作对照使用上方单独的动作捕获与生成流程。

To rebuild this directory's gameplay media, first run native GUI, keyboard, and expansion QA to populate the full local capture directories, then execute `python tools/documentation/prepare_readme_media.py`. The ordinary-capture helper updates its gameplay media and record; the full media helper refreshes the shared manifest and menu diagram. The 0.2.1 action comparisons use the separate capture/generation workflow above.
