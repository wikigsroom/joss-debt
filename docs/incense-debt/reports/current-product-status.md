# 《香火债》当前交付与验收记录

当前版本 **0.4.0**：默认双人合作闯十一层，保留离线单人和可选对灯切磋。双方共享真实敌人、场景、掉落与金币，各自成长、配装并救援队友；沿物理门和阶梯共同推进。发布页：[v0.4.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.4.0-alpha.1)。发布状态以文末回执为准。

| 平台 | 大小 | 实际 SHA-256 |
| --- | --- | --- |
| Windows 客户端 | 1057.5 MiB | `b606d2a6da40f97b0c89cdaa7fd005d789530bcc3485c3b45983bb85009c4368` |
| Android APK | 977.9 MiB | `4011656a48da8623a0253cee50f5b037a5d3ca655452d6a7b2c6f156dbecfe74` |
| Windows 独立服务端 | 105.7 MiB | `d7c794e31f8c23d10ccf59ed73fcb1e0d8fa6c358b28e272a1c7ca419ae5ae53` |

合作规则 **125** 项、真实传输 **32** 项、实际服务端重启／损坏恢复 **57** 项、写盘故障 **7** 项全部通过。实际新 EXE 合作键盘／触控流程 **27** 项、31 张捕获，包含真实清房、双人同门换房、数字选卡、双方成长历史和返回单人。可选 PvP 规则 271 项及实际 EXE 流程 30 项通过；离线核心 36 项、实际 EXE 键盘 107 项通过。

实际 Windows／Android 包体 **2171** 项核对通过，**90** 份编译脚本一致，3810 项运行资源打包；独立服务端与实际客户端的 37 个共享编译模块逐字节一致。Android **0.4.0／code 7**，arm64 调试签名与旧 APK 升级签名一致；INTERNET、VIBRATE、Expand、边到边与全部联机模块均从实际包体检查。未做实体手机安装验收。iOS 仍为 0.2.0 历史交接，无新版 IPA。

独立服务端默认两房、16 连接。实际最终 EXE 两房／四客户端、射线与散射 60 秒本机测试 **59.18 Hz**，step P95 **9.66 ms**、process P99 **33.63 ms**，无持久化错误。本轮是首房间短时网络负载，不能代表十一层长时容量或真实 WAN。暂停双方在线时没有断线期限；真正断线后重新计时 90 秒。两代注册表分别引用独立房间文件，损坏恢复经过实际二进制验证。

[合作交付与限制](../42-cooperative-delivery.md) · [架构](../41-cooperative-architecture.md) · [交付回执](cooperative-2026-10-11/delivery.json) · [实机 GIF](cooperative-2026-10-11/media/cooperative-native.gif) · [运维](../../../server/README.md) · [APK](cooperative-2026-10-11/android.json) · [跨包核对](cooperative-2026-10-11/package-parity.json)

旧 0.3.0 与此前移动／美术动作记录保留原版本身份，本轮重新核对编译纹理；旧标签及附件没有修改。离线 schema 2 三槽愿簿与联机身份／战绩分开，合作结算不会改写离线成就。

隐私政策 **1.5** 已公开到 [xhz.sidcloud.cn](https://xhz.sidcloud.cn/privacy-policy)，主体 **吴国黎**，邮箱 **carzyg@outlook.com**；合作共享场景、成长、救援及结果已同步。13 页现行 Word 全部逐页查看，现行与历史网页／下载共 **13** 项匿名 HTTPS 检查通过。

整个工作使用原生 Windows，无 Docker、WSL、虚拟机或模拟器，没有打开浏览器标签页。默认没有公网游戏主机；仍需实体 Android／手柄、真人十一层平衡、真实 WAN、目标主机长时容量和发行签名验收。

发布状态：最终包已验收，公开发布回执完成后附在此处。
