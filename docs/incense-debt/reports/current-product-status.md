# 当前产品与验证状态

0.5.0：十一层离线肉鸽、默认双人合作、可选对战，固定官方 WSS 自动连接。公网 Linux 原生服务已部署；GitHub 发布状态：prepared_stable。

Windows：`ad63f10b611d53641b483710c63d35539db28aeeec448c71b34b1df57a1e235c`。Android 正式签名包：`600ec0d5ef757fbc9f2d50e07fd453ddd668dec3c2fc270006dd5e55923b1d94`，arm64，Android 9+，version code 9。实际 APK 签名链通过 API 28/32/33/36 验证，旧测试签名具有 installed-data 继承能力；Android 真机安装仍待验。

实际 EXE 公网合作 29 项、对战 32 项、离线键盘 107 项；弱网故障 65 项。两个服务端分别与客户端 37 个共享模块一致；Windows/APK 2172 项内容核对、90 份编译脚本一致。页面布局使用独立离线展示夹具，不能代替实际联网流程证明。

实际主机重启恢复 10 项通过，四个实际 Session 客户端双房间持续 60 秒通过。短时测试不证明长时 SLA；共享主机存在调度和公网延迟，当前容量限制两个房间。

[本次详细交付](../44-public-online-release.md) · [原始验证证据](public-online-2026-10-11/) · [历史 0.4.1 基线](public-online-2026-10-11/baseline-0.4.1/)
