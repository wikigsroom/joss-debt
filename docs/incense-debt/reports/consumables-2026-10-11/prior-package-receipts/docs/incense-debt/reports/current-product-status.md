# 《香火债》当前交付与验收记录

更新：2026-10-10T15:21:34.491649+00:00。当前本机修订 **0.2.1**，十一层可玩 Alpha；公开 GitHub 发布仍为上一版 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 本轮已完成验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，1056.8 MiB | 实际导出程序 107 项键盘闭环；载入全部 24,048 个怪物独立动作帧，与 Android 73 份编译脚本一致 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，977.3 MiB | arm64 调试签名、版本、权限及 3791 项运行资源；全部 1,002 张怪物动作图集与 Windows 一致；未进行真机安装 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建，不作为 0.2.1 全树一致性或签名 IPA 证据 |

本轮实现六名主角的六状态、四朝向、六帧独立动作，共 864 个姿势；新增 24 个动作 FX 帧。移动触点按安全区布局，每杆／按钮独立保存大小与位置；修复跨半屏捕获、死区盲射、清房隐形键、战斗地图入口、满槽替换误触，增加四候选比较、软键盘避让和试操作。四首 Yourset 曲目随包随机轮播。隐私政策 v1.3 的主体为 吴国黎，与应用资料页一致，已部署并通过公开 HTTPS 核验。

全部 296 种小怪、99 名 Boss、6 种精英变体及 1 种召唤符，合计 402 个身份，均已替换为独立绘制的攻击、受击动作。小怪／精英／召唤符每种 48 帧；Boss 的三类攻击及受击每种 96 帧；均为四朝向、每状态六帧。全部 24,048 帧通过来源、完整性、运行采样及原生截图哈希核验，17 项原生战斗检查通过。见[全量动作交付](../35-creature-action-completion.md)、[原生帧证据](creature-actions-2026-10-10/native-coverage.json)和[战斗状态检查](creature-actions-2026-10-10/native-suite.json)。

[完整改动与原问题原因](../33-action-mobile-update.md) · [实际包体核对](action-mobile-2026-10-09/packaged-parity.json) · [移动矩阵](action-mobile-2026-10-09/mobile-matrix.json) · [Windows 键盘运行](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json) · [随机配乐](action-mobile-2026-10-09/playlist-tests.json) · [公开隐私政策](https://xhz.sidcloud.cn/privacy-policy)

四组原生窗口／密度配置合计 340 项检查、80 张画面；使用合成多指及真实应用事件分发，不是 Android 真机测试。配乐 19 项、持械 22 项、高级输入 54 项，以及相关攻击／恢复、组合装备、存档和房门回归通过。机器人终局检查不代表通关平衡。原生动作审查 GIF 使用固定比较节奏，不是完整游玩录屏。

Windows SHA-256：`654e3e3c60f0e46c1faf7ae94ab8ed7834a699f11d23746ea076587505cacead`。

Android SHA-256：`bfc6280672c0e69069d674f59e7bc57d939f3bd226eae4bd34c5eef26a5ec50b`。

内容规模为二十套环境、四十张背景、二百九十六种小怪、九十九名首领、三十二件器具。正式遭遇按 60% 本土＋40% 单个高对比外来主题混编；前五层各两个独立单 Boss 房；保存继续兼容 schema 2。怪物的攻击、受击已全量重绘；待机、移动、死亡和阶段转换保留各自现有素材方法。

原始 0.2.0 状态另存 [历史说明](product-status-0.2.0.baseline.md) 与 [历史 JSON](product-status-0.2.0.baseline.json)。旧扩展／装备截图、原生性能数值和三平台全树报告只在它们各自的旧哈希范围内成立，不作为新包重新验收的结论。

Android 真机手感、软键盘／剪贴板／文件选择器、触觉、长局温控与真人平衡待验收；iOS 仍需真实 macOS/Xcode 和设备。本轮使用原生 Windows，无 Docker、WSL、模拟器或浏览器。
