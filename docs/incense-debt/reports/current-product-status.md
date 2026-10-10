# 《香火债》当前交付与验收记录

更新：2026-10-10T18:11:02.513989+00:00。本机修订 **0.2.2**，十一层可玩 Alpha；本轮修复手机长屏两侧黑边，完善前摄、安全区和横屏翻转。公开 GitHub Release 仍为历史 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 当前包体验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，1057.3 MiB | 实际 EXE 107 项键盘流程；同一导出包在原生 Godot 中通过八组屏幕／切口的 274 项检查、51 张捕获 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，977.7 MiB | 0.2.2 / versionCode 4、arm64 调试签名；APK 内确含全屏、边到边与移动 Expand，签名与旧包一致；未连接真机 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建交接包或创建签名 IPA |

两套屏幕矩阵均覆盖 16:9、19.5:9、20:9、21:9、4:3、左右前摄与独立打孔。背景延伸至整张视口，完整战斗房间仍按原比例绘制；碰撞、四向出口、HUD、双摇杆和瞄准坐标通过复查。遮罩覆盖全屏，系统安全区域变化时重排并释放旧触点。源码移动全流程另通过 **340 项检查、80 张捕获**。

当前包通过 **2157 项资源与逻辑核对**；Windows / Android 的 76 份编译脚本、19 张消耗品位图、1,002 张怪物图集及 3810 项运行资源与源码对应。此前 0.2.1 的消耗品 GIF、105 项拾取检查、91 张捕获和怪物逐帧证据保留原始版本／哈希，相关素材未改变。

[黑边修复、实际对照与重现](../37-mobile-widescreen-adaptation.md) · [本轮交付](widescreen-2026-10-11/delivery.json) · [实际包屏幕矩阵](widescreen-2026-10-11/windows-matrix.json) · [移动全流程](widescreen-2026-10-11/mobile-regression/mobile-matrix.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [键盘流程](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json)

Windows SHA-256：`c1bcd02a86ea9e0d3d629d8fbe84418c24dbfa1da1a9f76cacf6692228729995`。

Android SHA-256：`41ecdb45185f24a110b6546646b1c3cd64cfd32f7ae028b5dad12188995e3b8b`。

新版包名仍为 `org.incensedebt.game`，与上一份本地 APK 使用同一签名，存档 schema 2 不变，可覆盖升级保留应用数据。旧包收据已原样归档到 [previous receipts](widescreen-2026-10-11/prior-package-receipts/docs/incense-debt/reports/current-product-status.json)。隐私主体仍为 吴国黎、邮箱 carzyg@outlook.com；本轮没有更改或重新部署隐私政策。

当前没有连接摩托罗拉 X30，原生窗口中模拟的前摄／密度／触摸不能代替设备上的系统全屏与手势验收。Android 真机操作、触觉、长局温控、真人平衡及实际 iOS 构建仍待验收。本轮未调用 Docker、WSL、虚拟化或浏览器。
