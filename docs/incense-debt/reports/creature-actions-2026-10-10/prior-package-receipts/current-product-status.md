# 《香火债》当前交付与验收记录

更新：2026-10-08T21:25:50.362575+00:00。当前本机修订 **0.2.1**，十一层可玩 Alpha；公开 GitHub 发布仍为上一版 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 本轮已完成验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，575.9 MiB | 实际导出程序 107 项键盘闭环；内嵌导出资源检查、与 Android 72 份编译脚本一致 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，497.9 MiB | arm64 调试签名、版本、权限及 3789 项运行资源；未进行真机安装 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建，不作为 0.2.1 全树一致性或签名 IPA 证据 |

本轮实现六名主角的六状态、四朝向、六帧独立动作，共 864 个姿势；新增 24 个动作 FX 帧。移动触点按安全区布局，每杆／按钮独立保存大小与位置；修复跨半屏捕获、死区盲射、清房隐形键、战斗地图入口、满槽替换误触，增加四候选比较、软键盘避让和试操作。四首 Yourset 曲目随包随机轮播。隐私政策 v1.3 的主体为吴国黎，与用户最新指定的应用资料页主体一致，已部署并通过公开 HTTPS 核验。

[完整改动与原问题原因](../33-action-mobile-update.md) · [实际包体核对](action-mobile-2026-10-09/packaged-parity.json) · [移动矩阵](action-mobile-2026-10-09/mobile-matrix.json) · [Windows 键盘运行](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json) · [随机配乐](action-mobile-2026-10-09/playlist-tests.json) · [公开隐私政策](https://xhz.sidcloud.cn/privacy-policy)

四组原生窗口／密度配置合计 340 项检查、80 张画面；使用合成多指及真实应用事件分发，不是 Android 真机测试。配乐 19 项、持械 22 项、高级输入 54 项，以及相关攻击／恢复、组合装备、存档和房门回归通过。机器人终局检查不代表通关平衡。原生动作审查 GIF 使用固定比较节奏，不是完整游玩录屏。

Windows SHA-256：`a831f63db86899c7fe52f55e0390616296600585fcab05cb3bf1ed8eb18a5d12`。

Android SHA-256：`8e99ffebf6c5b5dbae175d26016d561ed55418e512148bd00f816f9dec838216`。

旧内容规模保持：二十套环境、四十张背景、二百九十六种小怪、九十九名首领、三十二件器具。正式遭遇按 60% 本土＋40% 单个高对比外来主题混编；前五层各两个独立单 Boss 房；保存继续兼容 schema 2。旧敌人动作没有在本轮全部重绘。

原始 0.2.0 状态另存 [历史说明](product-status-0.2.0.baseline.md) 与 [历史 JSON](product-status-0.2.0.baseline.json)。旧扩展／装备截图、原生性能数值和三平台全树报告只在它们各自的旧哈希范围内成立，不作为新包重新验收的结论。

Android 真机手感、软键盘／剪贴板／文件选择器、触觉、长局温控与真人平衡待验收；iOS 仍需真实 macOS/Xcode 和设备。本轮使用原生 Windows，无 Docker、WSL、模拟器或浏览器。
