# 46 · 原生低延迟联机开发计划与完成记录

本计划承接 [45 · 联机传输与同步重新选型](45-network-reselection.md)。目标是把《香火债》的双人合作从“WSS 承载全部战斗状态”迁移为 **WSS 身份引导 + 原生 UDP/DTLS/ENet 战斗**，同时保留可恢复存档、服务器权威和跨平台输入。开始基线为 `ed9d1ae`，当前正式版本为 `0.6.0`。

## 方案结论

Godot 的 ENet 已经提供 UDP 上的连接管理、确认、重传、顺序/无序通道和统计；DTLS 只负责机密性与身份验证。游戏层不再自行实现可靠 UDP，也不把 TCP/WSS 的队头阻塞带入高频状态。WSS 只做版本/内容指纹、匿名恢复身份和一次性 battle ticket，认证后的战斗数据走 ENet/DTLS。

选型比较、Godot/Liblast/netfox/官方 API 源码阅读、端口与失败模式见第 45 篇。Steam 专属 relay、WebRTC 数据通道和自定义 KCP 均不适合作为当前跨 Windows/Android 的默认依赖；未来需要中继时，可以在不改变权威协议的前提下替换 UDP 边缘层。

## 阶段与完成状态

| 阶段 | 实现与退出条件 | 当前状态 |
| --- | --- | --- |
| P0 可观测性 | 服务器 tick、阶段耗时、状态年龄、ENet RTT/丢包、DTLS 转发流和持久化故障均可从无凭据 health 端点读取 | 已完成 |
| P1 原生战斗链路 | ENet + DTLS、WSS 一次性票据、六通道、证书/主机名校验、旧票据拒绝、无 UDP 时明确失败 | 已完成 |
| P2 低延迟同步 | 60 Hz 权威模拟、30 Hz 输入及六帧冗余、动作 ID 去重、无序状态、baseline/definition 独立可靠通道、客户端预测与远端插值 | 已完成 |
| P3 弱网保护 | 输入保护与租约、状态黑洞冻结、旧 epoch/scene/link 拒绝、WSS 与 ENet 会话解耦、同身份 battle ticket 重绑、旧公网 tuple 隔离 | 已完成 |
| P4 交付验证 | 本地丢包/乱序/突发代理、4 客户端公网候选、服务端原生日志、Windows/Linux 构建哈希、服务端归档与 Release | 已完成；正式服务已激活 |
| P5 设备验收 | Android 正式签名、资源/脚本一致性和桌面触控夹具；摩托罗拉 X30 实机 | 软件检查完成；用户明确取消真机验证 |

## 不可退让的运行规则

1. 服务器唯一决定伤害、生命、钱包、掉落、成长、门切换和结算；客户端预测只负责视觉即时反馈。
2. 动态状态允许丢弃旧包；下一份绝对状态、实体序号和场景 revision 修复丢失。输入只保留最新移动，边沿动作使用独立 ID。
3. 成长、交易、暂停、恢复、离开和结果使用可靠、有序、幂等请求，并在对应检查点提交后确认。
4. 每次换房、换层、暂停恢复或重连都提升 input epoch，清空旧输入和旧场景确认；迟到包不能重新控制房间。
5. 普通丢包先冻结输入，不立即结束房间。WSS 身份和 ENet 战斗腿分离；战斗腿断开时保留身份并重发一次性 ticket。只有重连宽限期耗尽才进入终局。
6. DTLS 证书、主机名、票据和 link 全部验证；转发层只识别有界 DTLS record，不解密、不持有私钥、不凭未认证 Alert 关闭他人。
7. `server/archives/v0.5.0/` 保持不可变；正式 `0.6.0` 使用 transport revision 2，生产数据目录与旧版本切换前的私有备份分离。
8. 本轮全程原生 Windows/Linux 执行，不使用 Docker、WSL、虚拟机或模拟器；浏览器验收后关闭不用的标签页。

## 代码装配入口

| 组件 | 入口 | 责任 |
| --- | --- | --- |
| 协议与时钟 | `game/scripts/network/protocol.gd` | revision、tick、输入租约、状态/重连保护阈值 |
| ENet/DTLS | `game/scripts/network/enet_battle.gd` | Godot ENet host、六通道、DTLS setup、无序/可靠 flag、flush |
| 公网边缘 | `game/scripts/network/dtls_edge.gd` | loopback DTLS socket 与公网 tuple 转发、预算、公平轮询、旧流 quarantine |
| 客户端会话 | `game/scripts/network/online_session.gd` | WSS 引导、battle bind/rebind、预测输入、状态确认、重连退避 |
| 权威服务器 | `game/scripts/network/server_runtime.gd` | 房间、权威模拟、ticket 消费、输入保护、快照、存档与 health |
| 状态复制 | `game/scripts/network/state_stream.gd` | baseline/definition/实体绝对记录与 bounded assembly |
| 输入格式 | `game/scripts/network/input_frames.gd` | 固定 tick、动作边沿、六帧冗余、序号去重 |

## 验收门槛

正式候选必须同时满足：客户端没有 `SCRIPT ERROR`、`mbedtls error` 或未分类 TLS 错误；服务端 journal 无原生错误；四个真实 Windows headless Session/两房公网运行时 tick ≥58 Hz、状态年龄 P95 <150 ms、ping P95 <250 ms、p99 模拟步长 <16.7 ms、p999 <33.4 ms、战斗阻塞 >100 ms 为 0；所有输入/状态/经济/存档回归通过。Android 真机证据因用户决定不做而明确标记为未执行。

最新证据保存在 [network-udp-acceptance-2026-10-12.json](reports/network-udp-acceptance-2026-10-12.json)，其中绑定正式 server SHA、客户端源码树、候选与激活报告和 Android 限制。历史 WSS 报告仍保留为历史版本，不能用来宣称 0.6 的 UDP 质量。

## 后续维护顺序

先查看 health 的 `active_flows`、`active_quarantine`、`quarantined`、`output_backlog_max`、ENet RTT/variance/loss 和 `last_input_protections`，再判断是公网路径、客户端状态黑洞、服务端发送积压还是权威保护。不要通过降低安全阈值、关闭证书校验或改成可靠全量快照来掩盖丢包。任何协议字段变化都要同时更新客户端、Windows/Linux server、回归夹具、归档 manifest 和 Release 说明。
