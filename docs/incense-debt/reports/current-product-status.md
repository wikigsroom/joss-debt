# 《香火债》当前交付与验收记录

更新：2026-10-10T17:15:33.676315+00:00。本机修订 **0.2.1**，十一层可玩 Alpha；本轮更新掉落消耗品、相关资源 UI 和安装包。公开 GitHub Release 仍为 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 当前包体验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，1057.3 MiB | 实际导出程序 105 项掉落检查、91 张捕获，以及 107 项完整键盘流程；全部 19 张新位图通过原生载入和纹理核对 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，977.7 MiB | arm64 调试签名、版本、权限和 3810 项运行资源；75 份编译脚本、19 张消耗品位图和 1,002 张怪物动作图集与 Windows / 源码一致；未进行真机安装 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建或创建签名 IPA |

掉落物为 sub2-image-gen / gpt-image-2.5 独立生成的红心纸灯、单枚铜钱、双枚红绳铜钱、普通香灰包、高额香灰包和充能火芯。六张原画生成 19 张透明运行位图，统一地面、血条、金币栏、回血商品和火芯拾取提示。40 张背景均检查实际尺寸辨识度。轻微浮动、摆动与同源资源拾取淡出遵从减少动态选项，表现层不改变 RNG 或模拟。

实际检查覆盖资源数值、吸附边界、键盘 E、满充能保留、九个地面物品及完整模拟的存档恢复。存档 schema 2 与原有掉落数值规则保持。源图、SHA-256、前后对照、原生 GIF 与复现入口见[掉落消耗品修订](../36-consumable-art-update.md)。

[当前 Windows 掉落验证](consumables-2026-10-11/windows/native.json) · [美术检查](consumables-2026-10-11/art-validation.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [键盘流程](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json)

既有六角色四向 864 个独立动作姿势、24 个角色 FX 帧、四首随机 BGM、可单独调整的移动触控继续随包交付。全部 402 个怪物身份、1,002 张独立攻击 / 受击图集和 24,048 个姿势保留完整素材；当前包再次核对和载入这些资源。之前的逐帧截图及 17 项战斗状态证据仍绑定其原始哈希，素材未变化，本轮没有重新录制全体怪物。见[全量动作范围](../35-creature-action-completion.md)。

Windows SHA-256：`79848dfe4835ff67aa12479b633a79db55d42e2fce220e9dcbf7371286b42e19`。

Android SHA-256：`2c58c1ba1e8b95a6901870074a23b3899722777511c2400abdada016b4bbe88b`。

[上轮 0.2.1 安装包与报告](consumables-2026-10-11/prior-package-receipts/docs/incense-debt/reports/current-product-status.json)已经保存；历史 0.2.0 普通游玩及宣传媒体保持各自来源记录。它们不代替当前包验收。当前隐私政策记录仍为 v1.3、主体 吴国黎、邮箱 carzyg@outlook.com，公开核验时间保留在 JSON 中，本轮没有更改政策或重新部署。

Android 真机触屏、触觉、文件选择器与长局温控、真人难度平衡仍待验收；移动 HUD 截图是 Windows 原生移动布局。iOS 仍需要实际 macOS / Xcode 与设备。本轮没有使用 Docker、WSL、虚拟机、模拟器或浏览器。
