# 47 · 原生 UDP/DTLS 联机实现说明

本篇记录 `0.6.0` 的实际实现、测试与生产激活结果，和 [46 · 开发计划](46-network-development-plan.md) 配套。它描述的是当前源码与正式服务端，不把旧 `0.5.0` WSS 报告冒充成 UDP 交付。

## 链路结构

```text
客户端 WSS 443  ──版本/内容指纹/匿名身份/一次性 ticket──> ServerRuntime
客户端 UDP      ──DTLS record──> 公网 dtls_edge :18779
                                      │ 有界转发
                                      ▼
                               loopback ENet DTLS host
                                      │
                                      ▼
                               权威房间与存档
```

WSS 只负责引导和身份恢复；战斗期间可靠指令、输入、快照和 ping 通过已验证 ENet peer。ENet 的可靠/无序机制承担丢包恢复，DTLS 负责加密与证书校验，游戏层不再实现第二套 ACK 或自定义加密。

## 六通道契约

| 通道 | 内容 | 发送策略 |
| --- | --- | --- |
| 0 | 世界动态、实体绝对状态、表现事件 | 无序/不可靠；实体序号拒绝旧状态，下一份绝对记录修复丢包 |
| 1 | 移动、瞄准、射击、身法、技能、道具、交互 | 无序/不可靠；30 Hz 最新帧，最近六帧冗余；边沿动作按 ID 去重 |
| 2 | bind、成长、交易、暂停/恢复、离开、结果、ping | 可靠控制；请求序列和幂等回执；ping 使用无序控制包 |
| 3 | 场景 baseline、角色构筑、静态描述 | 可靠分块；revision 独立组装，不能因一块丢失污染下一版 |
| 4 | 弹丸/技能定义 | 独立可靠定义通道；运行轨迹仍走动态通道 |
| 5 | 状态/事件 ACK、scene/phase ready | 累积且可丢弃；新确认替代旧确认，不堵塞交易队列 |

服务器以 60 Hz 推进，客户端在固定输入 tick 预测自己的移动和攻击表现；服务器重新裁定碰撞、伤害、掉落、经济和成长。远端对象使用有界插值，网络断开时不会无限外推或穿越内墙。

## 丢包、乱序与重连

* 输入租约与 `INPUT_TIMEOUT` 只让角色停止移动；连续保护达到 `INPUT_PROTECT_SECONDS` 才冻结房间。输入的 epoch、scene、lease、link、room、match 和 sequence 全部校验，旧连接不能写入新房间。
* 动态状态不等待前一份 ACK；baseline/definition 丢失时以 revision 重发，状态年龄超过阈值时客户端停止提交输入并等待恢复。
* WSS 和 ENet 是两条生命周期不同的链路。ENet `EVENT_DISCONNECT` 只清理 battle peer，服务端保留 WSS 身份、房间和检查点，并向同一连接发出新的 `battle_grant`。客户端只重建 DTLS/ENet，不创建第二个身份；绑定失败才进入退避重连。
* 已验证的 close alert 或 peer 断开会让公网 `address/port` tuple 进入 30 秒 quarantine。迟到 DTLS record 不会在旧 socket 已销毁后被当成新的 ClientHello；正常重连绑定新源端口，不受影响。
* 房间冻结仍要求双方确认恢复；90 秒断线宽限期、在线菜单无超时、重复结算和检查点提交规则保持不变。超过宽限期才产生一次团队失败。

客户端每 2 秒发送 ENet ping，并在 WSS 仍开放时只发送 keepalive；WSS 不再发送重复 RTT 探针。服务端健康端点暴露活动流、隔离流、被丢弃的旧 tuple、输出积压峰值、ENet RTT/variance/loss、输入保护原因和存储状态。

## 服务器边缘保护

`dtls_edge.gd` 不解密记录，不参与证书认证。它只限制 record 长度与类型、限制每轮输入/输出预算、轮转多个 flow，避免一个大 baseline 阻塞另一个玩家的 handshake/ACK。只允许已记录的 ENet peer 触发 retire；未认证的公网 Alert 不能关闭他人 flow。握手流、已建立流和 retiring 流使用不同闲置期限，retiring flow 关闭后进入 tuple quarantine。

## 验收结果（2026-10-12）

机器可读总表：[network-udp-acceptance-2026-10-12.json](reports/network-udp-acceptance-2026-10-12.json)。关键结果：

* 本地真实 UDP 代理：loopback、50/100/175 ms 单向延迟、3/5/10% 丢包、重复/乱序、300 ms/1 s/3 s 突发丢包全部通过；可靠请求无重复，状态流持续。
* 应用故障回归：输入过期、旧 epoch/scene/link、状态黑洞、ACK 黑洞、双人恢复、身份接管、存档损坏、唯一结算和证书拒绝全部通过。
* 公网验收：4 个 Windows headless production Session、2 个合作房间、`wss://xhz-server.sidcloud.cn/candidate-play` + UDP `18779`，连续 62.665 秒；tick 59.146 Hz，状态年龄 P95 42 ms，ping P95 133 ms，p99 step 7.125 ms，p999 23.5 ms，战斗阻塞 >100 ms 为 0，客户端和服务端原生日志无错误。本次最终包验收未触发 rebind；此前同一实现的隔离公网重绑证据保留在历史报告中，重绑逻辑另由应用故障回归覆盖。
* 正式激活：候选停止后，`/opt/incense-debt/current` 已切换至 0.6.0，公网 `/play` 健康报告 `transport=2`、`battle_encrypted=true`、UDP `18779`，激活时无活跃连接或房间，旧 `v0.5.0` 数据已创建私有备份。
* 正式 Linux server SHA-256：`469d7d0a8e5eacb907a7e377b9fa016be11894693ca465216fa0bb44f92722ef`；Windows server 与包体清单另行绑定。

这组结果是当前候选的可复现实证，不是 SLA，也不代表所有网络运营商都有相同 RTT。长时容量、真人构筑平衡和 Android 真机运行均不由本轮报告宣称；用户已经明确取消 Android 真机验证。

## 发布与回滚

候选先写入 `/opt/incense-debt/candidates/v0.6.0` 与独立存储，健康、构建 SHA、客户端、原生日志和回归证据通过后切换 `/opt/incense-debt/current`。切换前备份旧 target、配置与已提交玩家状态；新服务启动失败时恢复旧 binary/config/state。`server/archives/v0.5.0` 不覆盖，`0.6.0` 使用新的归档目录和 Release tag；本轮激活记录位于 `reports/network-udp-acceptance-2026-10-12/activate.json`。
