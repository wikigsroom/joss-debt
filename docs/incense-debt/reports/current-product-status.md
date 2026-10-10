# 《香火债》当前交付与验收记录

更新：2026-10-10T18:36:58.530935+00:00。当前本机版本 **0.2.3**，十一层可玩 Alpha。默认触控改为左手只移动，右手负责瞄准／射击、身法位移、焚债技能和主动道具；包含此前长屏背景、安全区和边到边修复。公开 Release 仍为历史 `v0.2.0-alpha.1`。

| 平台 | 产物 | 实际验收 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，1057.3 MiB | 实际 EXE 107 项键盘流程；导出包原生屏幕／切口矩阵 282 项、51 张捕获 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，977.7 MiB | 0.2.3 / code 5、arm64 调试签名；签名与前一份 0.2.2 本地包一致，全屏、边到边与 Expand 通过实际包检查；未连接真机 |
| iOS | 0.2.0 历史源码交接 | 本轮未重建交接包或签名 IPA |

源码移动全流程通过 **368 项检查、80 张捕获**。旧手机／平板默认布局经 JSON 重载后自动升级；个别触点大小、透明度和已自定义位置保留。原布局尺寸过大、升级会重叠时保留已有合法设置，玩家可在设置 → 触控恢复新默认。两拇指切换和三指操作均检查了左手持续移动、右手位移、移动方向与瞄准方向分离，以及按钮单次触发。

源码和导出包各检查八组 16:9～21:9、4:3、左右切口和独立打孔；分别通过 282、282 项检查。真实导出包还通过 2157 项资源／逻辑核对，76 份编译脚本与 Android 一致，包含 3810 项运行资源。

[布局说明与原生对照](../38-right-hand-touch-layout.md) · [本轮交付](touch-right-2026-10-11/delivery.json) · [实际包布局矩阵](touch-right-2026-10-11/windows-matrix.json) · [移动回归](touch-right-2026-10-11/mobile-regression/mobile-matrix.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [APK 验收](platforms/android-verification.json)

Windows SHA-256：`71f27ca0c4a93bfa08935461adb84d665e06400c8f9e3ece63dc37d4f0b84c90`。

Android SHA-256：`bb2e3a32ddf849d50a4f655d1c1456ab013d1b71e5585c7d5e3e9eb6272b60eb`。

包名 `org.incensedebt.game`、本机调试签名和 schema 2 存档保持，可覆盖前一份同签名 APK 保留数据。0.2.2 长屏图像、0.2.1 消耗品与怪物 GIF 保留各自的历史来源；不是 Android 真机验收。隐私政策未更改，主体仍为 吴国黎，邮箱 carzyg@outlook.com。

当前未连接 X30。真机拇指舒适度、系统手势、触觉和长局温控，以及实际 iOS 构建仍待验收。本轮未使用 Docker、WSL、虚拟化或浏览器。
