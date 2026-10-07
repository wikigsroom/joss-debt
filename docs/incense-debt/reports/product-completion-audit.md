# 《香火债》方向1完成审计

记录时间：2026-10-06T14:27:58.758103+00:00。总体状态：`software_verified_external_pending`。本审计不把自动测试、桌面截图或静态包检查写成真实设备与真人验收。

| 要求 | 状态 | 直接证据 | 当前边界 |
| --- | --- | --- | --- |
| 方向1设计、故事、交互与配套文档 | **verified_alpha** | `docs/incense-debt/README.md`；`docs/incense-debt/00-product-vision.md`；`docs/incense-debt/19-release-readiness.md`；`docs/incense-debt/20-direction1-system-bible.md`；`docs/incense-debt/21-external-acceptance-runbook.md`；`docs/incense-debt/22-menu-save-achievements.md`；`docs/incense-debt/reports/design-validation.json` | 设计审计通过仍不等于真人审美确认。 |
| 三章可玩循环、房间探索与物理门切换 | **verified_alpha** | `docs/incense-debt/reports/runtime/full-run-tests.json`；`docs/incense-debt/reports/runtime/route-navigation-tests.json`；`docs/incense-debt/reports/platforms/windows/door-navigation.png` | 完整真人整局手感仍需记录。 |
| 多角色、多路线、技能演化与局外成长 | **verified_alpha** | `docs/incense-debt/03-playable-characters.md`；`docs/incense-debt/05-progression-builds.md`；`docs/incense-debt/reports/runtime/route-matrix-tests.json`；`docs/incense-debt/reports/runtime/route-balance-baseline.json`；`docs/incense-debt/reports/runtime/campaign-rules-tests.json` | 六角色双路线真人平衡尚未完成。 |
| 局后平衡观测与本地样本记录 | **verified_alpha** | `docs/incense-debt/14-balance-telemetry.md`；`game/scripts/core/run_telemetry.gd`；`game/tests/run_telemetry.gd`；`docs/incense-debt/reports/runtime/run-telemetry-tests.json` | 本地结构化记录不替代真人平衡、设备性能和听测验收。 |
| 掉落、商店、特殊房间、债约与组合搭配 | **verified_alpha** | `docs/incense-debt/06-loot-economy-debt.md`；`docs/incense-debt/07-skills-synergies.md`；`docs/incense-debt/reports/runtime/shop-trial-tests.json`；`docs/incense-debt/reports/runtime/synergy-matrix-tests.json`；`docs/incense-debt/reports/runtime/daily-run-tests.json`；`docs/incense-debt/reports/runtime/loot-sampling-tests.json` | 掉落概率与组合收益仍需真人长期观察。 |
| 武器类型、打击、方向朝向与粒子反馈 | **verified_alpha** | `docs/incense-debt/04-combat-hit-feedback.md`；`docs/incense-debt/reports/runtime/weapon-special-room-tests.json`；`docs/incense-debt/reports/runtime/weapon-motion-tests.json`；`docs/incense-debt/reports/runtime/impact-resume-tests.json`；`docs/incense-debt/reports/platforms/windows/detonate.png` | 低端设备粒子舒适度与真人操作手感仍需设备/人工验收。 |
| 地图音乐、音效、素材来源与锁定美术风格 | **verified_alpha** | `docs/incense-debt/12-audio-narrative.md`；`docs/incense-debt/reports/runtime/adaptive-music-tests.json`；`docs/incense-debt/reports/platforms/windows/audio/native-audio.json`；`docs/incense-debt/reports/runtime/audio-design-verification.json`；`docs/incense-debt/reports/runtime/audio-source-research.json`；`docs/incense-debt/reports/runtime/asset-verification.json`；`output/imagegen/incense-debt/special-room-prop-board.png` | 手机扬声器、耳机及真人长局听测尚未完成。 |
| 现代圆角 UI、图标、字体、PC 键盘与触控适配 | **verified_alpha** | `docs/incense-debt/09-ui-ux-input.md`；`docs/incense-debt/22-menu-save-achievements.md`；`docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json`；`docs/incense-debt/reports/platforms/windows/ui-style.png`；`docs/incense-debt/reports/runtime/advanced-input-tests.json`；`docs/incense-debt/reports/runtime/choice-history-tests.json`；`docs/incense-debt/reports/runtime/achievement-tests.json` | 真实手机安全区、旋转和触控范围仍需设备验收。 |
| 以撒式菜单层级、返回边界与槽位审计 | **verified_alpha** | `docs/incense-debt/22-menu-save-achievements.md`；`docs/incense-debt/reports/runtime/menu-hierarchy-audit.json`；`docs/incense-debt/reports/runtime/menu-hierarchy-audit.md`；`docs/incense-debt/reports/platforms/windows/native-render.json` | 桌面键盘与 GUI 场景证据不能替代真人信息密度、系统文件对话框和移动端菜单体验。 |
| Sub2视觉参考、风格绑定与运行时画面对照 | **verified_alpha** | `docs/incense-debt/17-visual-contract.md`；`docs/incense-debt/data/asset-manifest.json`；`docs/incense-debt/assets/prompts/visual/menu-map-combat-board.txt`；`docs/incense-debt/reports/runtime/visual-contract-audit.json`；`docs/incense-debt/reports/runtime/visual-baseline.json` | 视觉概念板与原生截图不能替代真人审美、低端设备透明边和最终设备显示验收。 |
| 存档迁移、回滚、传递与成长账本 | **verified_alpha** | `docs/incense-debt/13-cross-platform-engineering.md`；`docs/incense-debt/22-menu-save-achievements.md`；`docs/incense-debt/reports/runtime/save-transfer-tests.json`；`docs/incense-debt/reports/runtime/achievement-tests.json`；`docs/incense-debt/reports/runtime/ui-refresh/save-roundtrip-regression.json` | 真实手机文件选择器、软键盘与剪贴板仍需设备验收。 |
| Windows 原生可运行交付 | **verified_alpha** | `build/windows/IncenseDebt.exe`；`docs/incense-debt/reports/platforms/windows/native-render.json`；`build/delivery-manifest.json` | 真人完整整局与低端机器性能仍需补充。 |
| Android 跨端包与共享内容 | **pending_device** | `build/android/IncenseDebt.apk`；`docs/incense-debt/reports/platforms/android-verification.json`；`docs/incense-debt/reports/platforms/platform-parity.json`；`docs/incense-debt/reports/external-acceptance.json` | 需要真实 Android 安装、触控、后台、文件/剪贴板、温度与 45 分钟长局记录。 |
| iOS 共享工程与原生交接 | **pending_device** | `build/ios-handoff/README.md`；`build/ios-handoff/IncenseDebt-shared-source.zip`；`docs/incense-debt/reports/platforms/ios-handoff-verification.json`；`docs/incense-debt/reports/external-acceptance.json` | 需要真实 macOS/Xcode 工程、签名 IPA、iPhone/iPad 运行与性能记录。 |
| 方向1稳定 ID 到运行钩子追踪 | **verified_alpha** | `docs/incense-debt/20-direction1-system-bible.md`；`docs/incense-debt/reports/runtime/direction1-system-audit.json`；`docs/incense-debt/reports/runtime/synergy-matrix-tests.json` | 逐条运行钩子通过仍不等于真人构筑平衡。 |
| 真人六角色双路线与正式发布签字 | **pending_human_and_device** | `docs/incense-debt/reports/human-balance-template.csv`；`docs/incense-debt/reports/external-acceptance.json`；`docs/incense-debt/reports/release-readiness.json`；`docs/incense-debt/reports/system-coverage.json` | 需要六角色×两路线的真人完整整局、难度/伤害/构筑理解记录，以及移动设备共同验收。 |

## 当前软件事实

设计数据：6 角色、6 路线、16 武器、18 技能、54 遗物、36 行愿、24 组合、3 区域、18 房间模板、4 类特殊房间。Windows 原生资源 725 项，截图 90 张；三章自动整局 12/12 胜利，路线矩阵 24/24 胜利。

## 不能在当前主机伪造的门槛

- Android 真机安装、触控、后台恢复、系统文件接口、热稳定与长局。
- 真实 macOS/Xcode 导出、签名 IPA、iPhone/iPad 运行。
- 六名角色各两条路线的真人整局与至少三次独立平衡记录。

重新生成：

```powershell
python tools/runtime/audit_product_completion.py
```
