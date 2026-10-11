# 《香火债》当前交付与验收记录

当前源码与本地修复包为 **0.4.1**。默认共灯合作闯十一层，保留离线单人与可选对灯。公开 [v0.4.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.4.0-alpha.1) 仍为旧版，附件和标签没有改动；0.4.1 尚未发布。

| 本地产物 | 大小 | 实际 SHA-256 |
| --- | --- | --- |
| Windows 客户端 | 1057.5 MiB | `b956487845f18859adcd90016f53cfaba24d185344d5bfb2cbd13368b4bf6e8e` |
| Android APK | 977.9 MiB | `baacb3414cb5e44eaf74510a9ed8ed43fad3f2617e648a8c46180ad9e68332b9` |
| Windows 独立服务端 | 105.7 MiB | `05fc609133a4b3bc647a7044a25226447049c2aa703549011fe06aefc854f2f0` |

联机应用故障 **65** 项、独立 TCP 中转 **18** 项、实际服务端崩溃／损坏恢复 **57** 项、持续写盘故障 **7** 项和原生 0.4.0 数据升级 **12** 项通过。应用消息丢弃与 TCP 字节停滞分开记录，没有宣称做过真实 IP 丢包或公网验收。

合作规则 **125** 项、真实传输 **32** 项、实际 EXE 合作流程 **27** 项／31 张捕获、可选对战规则 **271** 项／实际 EXE 流程 **30** 项通过。离线核心 **36** 项、实际 EXE 纯键盘流程 **107** 项通过。

Windows／Android 包体 **2171** 项、**90** 份编译脚本、**3810** 项运行资源通过核对；独立服务端与客户端 **37** 份共享编译模块一致。Android 为 **0.4.1／code 8**，arm64 调试签名，升级签名一致。没有实体手机安装或网络切换验收；iOS 保留 0.2.0 历史交接，无新版 IPA。

最终服务端两房／四客户端、射线与散射的 60 秒本机负载：**59.47 Hz**，step P95 **2.77 ms**，process P99 **8.88 ms**。这只是首房间短时验证，不能代表十一层长时容量或 WAN。

恢复默认 90 秒，双方重新确认后继续；双方在线的菜单暂停没有断线期限。客户端与服务器需一起更新到 transport revision 1。旧 0.4.0 检查点可以恢复，离线 schema 2 三槽保持独立。硬崩溃后可能回退到最近一次成功检查点；两代均损坏时保留原文件并拒绝覆盖。

[详细复查](../43-network-reliability-audit.md) · [结构化回执](network-reliability-2026-10-11/audit.json) · [实机 GIF](network-reliability-2026-10-11/media/cooperative-native.gif) · [媒体来源](network-reliability-2026-10-11/media-manifest.json) · [运维](../../../server/README.md) · [旧版发布回执](../../releases/v0.4.0-alpha.1.publication.json)

隐私政策沿用已发布的 **1.5**：[xhz.sidcloud.cn/privacy-policy](https://xhz.sidcloud.cn/privacy-policy)，主体 **吴国黎**，邮箱 **carzyg@outlook.com**。本轮没有新增隐私收集或网页部署。

全程原生 Windows，无 Docker、WSL、虚拟机、模拟器或浏览器。当前没有默认公网游戏服务器；实体 Android 网络切换／后台恢复、真实 WAN、长时合作平衡与目标主机容量仍待验证。
