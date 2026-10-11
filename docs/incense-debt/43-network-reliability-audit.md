# 0.4.1 联机可靠性复查

本次复查针对共灯合作的匹配、控制指令、输入、地图快照、暂停恢复、身份接管和检查点；可选对灯也使用相同传输层。修复版为 **0.4.1 / Android code 8**，验收和本地包体摘要见 [本轮报告](reports/network-reliability-2026-10-11/audit.json)。公开 0.4.0 发布记录保留原有附件与版本身份。

## 丢包实际表现

游戏采用 WebSocket/TCP。TCP 重传和排序使网络丢包通常表现为延迟、队头阻塞、发送积压或断线；应用不能据此假定积压操作仍适合当前房间。

验证分两类：原生 WebSocket 测试主动拒绝发送、丢弃应用帧或确认消息；独立 TCP 中转保持字节顺序，制造分片写入、双向延迟和抖动、停滞及实际连接切断。应用帧故障不能称为真实 IP 丢包测试。全程使用 Windows 原生工具，没有 Docker、WSL、虚拟机、模拟器或浏览器。

## 发现与修复

| 问题 | 原行为与影响 | 修复 |
| --- | --- | --- |
| 发送失败后无补发 | 缓冲暂满时，选卡、暂停等操作一直留在 pending | 指令先保存，再进入顺序队列；750 ms 重试同一编号，确认前不会发送后续指令 |
| 确认缺失后永久等待 | 服务器已完成选择，客户端仍锁住后续操作 | 返回原请求的持久回执，避免再次扣款或成长；8 秒未完成则重连补发 |
| 心跳掩盖地图停滞 | ping/pong 正常但地图不更新，怪物仍攻击玩家 | 状态进度独立于心跳；超过 400 ms 禁止继续输入，2 秒无状态进展则重连与停战 |
| 快照积压、重复或迟到 | 展示旧战斗，倒退菜单，或重新打开已离开的房间 | 每连接最多 4 份未确认快照；合并积压状态并重传最后快照；校验连接、房间授权及快照序号 |
| 输入没有场景范围 | 积压移动、闪避、技能在换房或继续后执行 | 包含连接、房间、对局、暂停代数、场景及服务器时间；接收与每个模拟帧都校验 |
| 匹配回执与队列不一致 | 历史成功回执让已断线出队的客户端显示仍在匹配 | 回执附带当前服务状态，恢复后的队列与房间以服务器现状为准 |
| 新断线沿用旧继续确认 | 新一轮恢复可能沿用另一人的旧确认 | 每次新断线清空双方确认并更新输入代数 |
| 身份接管依赖关闭帧 | 旧客户端未收到 4001 时自动重连抢回身份 | 持久化身份代数阻止旧进程；接管提交两份注册表后再确认 |
| 旧进程覆盖凭据 | 两个进程共用联机存档时可能写回过期身份 | 保存前比对已提交身份代数，拒绝旧进程写入新持有者的凭据 |
| 首次 welcome 缺失 | 已连接却无法进入大厅，重试增加孤立身份 | 鉴权最多等待 6 秒；同一进程在恢复窗口内复用未领取、未操作的匿名身份，并换发凭据 |
| 忽略本地保存失败 | 恢复凭据没有成功保存，关机后可能找不回本局 | 初次身份或回执保存失败时停止连接并提示，修复写入后继续原身份 |
| 写盘恢复被误认为弱网 | 写盘故障停止快照，修复后可能立即触发状态超时 | 修复成功后清空旧快照窗口，重新开始状态进度计时 |
| 结算房间占用开局名额 | 两房服务器留下两个结果画面后，新玩家持续排队 | 开局容量只计等待／进行中的房间；超限时清理最早且无在线成员的旧结果 |
| 暂停失败后菜单等待 | pause_pending 仍等待未成立的暂停 | 请求失败时清除等待标记，按服务器最新阶段恢复界面 |

原始 0.4.0 三个确定性复现为：发送失败后未补发、回执缺失后未重试、状态停止但心跳继续时未停战。[前后基线](reports/network-reliability-2026-10-11/baseline.json)记录原故障；[故障回归](reports/network-reliability-2026-10-11/faults.json)包含更完整的网络与事务断言。

## 恢复规则

| 环节 | 当前规则 |
| --- | --- |
| 模拟与快照 | 服务器 60 Hz；最新状态最多 20 Hz，受确认窗口限制 |
| 高频输入 | 30 Hz；250 ms 没有有效输入后停止移动／持续射击 |
| 积压输入 | 超过 1 秒的服务器时间租约作废；已收到的输入不能跨越场景或暂停代数 |
| 重连退避 | 0.5、1、2、4、8 秒，附 0–200 ms 抖动；成功后重置 |
| 控制事务 | 一次只发送一个持久请求；同编号重试和最近 16 份服务端回执防重复 |
| 合作断线 | 默认 90 秒恢复窗口；双方重新确认才继续 |
| 合作菜单 | 双方在线的菜单暂停没有断线倒计时上限 |
| 恢复超时 | 共同结束本局并计一次合作失败，晚归不能重开已结算的对局 |
| 检查点 | 完整世界与双方成长由服务端保存，两代注册表各引用独立房间文件 |
| 终局容量 | 终局不占活跃名额；默认清理阈值 8 个，超限清理无在线成员的旧结果；在线结果继续保留，仍受连接上限限制 |

过期的闪避、技能短按会被放弃，避免在下一房间误释放。选卡、购买、离开等控制事务通过原编号确认。生命、伤害、掉落、金币和结算始终由服务器决定，客户端预测只负责移动展示。

## 原生验证

| 报告 | 覆盖 |
| --- | --- |
| [faults.json](reports/network-reliability-2026-10-11/faults.json) | 顺序补发、确认缺失、旧输入、状态中断、快照窗口、新身份接管、磁盘失败、重复成长与结算、开局容量 |
| [tcp.json](reports/network-reliability-2026-10-11/tcp.json) | 独立服务端和两个真实客户端；97 字节 TCP 写入、每方向 120 ms 加抖动、0.8 秒下行停滞、3.3 秒双向中断、实际断开连接 |
| [recovery.json](reports/network-reliability-2026-10-11/recovery.json) | 强制结束实际服务端、最新注册表损坏、最新房间及档案损坏、身份接管、恢复超时 |
| [storage.json](reports/network-reliability-2026-10-11/storage.json) | 实际服务器写盘受阻后额外持续 3 秒；停战、恢复和旧输入不重放 |
| [upgrade.json](reports/network-reliability-2026-10-11/upgrade.json) | 已发布 0.4.0 服务端及标签客户端准备保存，再用 0.4.1 在相同数据目录恢复 |
| [load.json](reports/network-reliability-2026-10-11/load.json) | 本机两房四客户端 60 秒的频率、处理时间、发送积压与持久化 |
| [native.json](reports/network-reliability-2026-10-11/native.json) | 实际 Windows 客户端的匹配、键盘、重连、触控、清房、走门、成长与历史 |
| [client-server-parity.json](reports/network-reliability-2026-10-11/client-server-parity.json) | 实际客户端／服务端 37 份共享编译模块一致 |
| [package-parity.json](reports/network-reliability-2026-10-11/package-parity.json) | 实际 EXE／APK 编译代码、数据与运行素材核对 |

故障回归中的无敌保护、清房夹具只用于隔离网络时序与选卡事务。TCP 中转、版本升级和实际 Windows 菜单测试没有注入生命、掉落或伪造客户端快照。各报告记录独立范围和对应产物摘要。

服务端恢复／过期测试通过启动参数把恢复期限缩短为 **10 秒**，用于实际等待过期；产品默认仍为 **90 秒**。原生负载使用最终服务端，60 秒平均 **59.47 Hz**，step P95 **2.77 ms**、process P99 **8.88 ms**，无发送积压或持久化错误。

## 复现方式

在仓库根目录使用原生 Python 与 Godot；先按照 `build/README.md` 构建 0.4.1 服务端。测试生成独立 `.local-tools` 数据目录，不使用正式服务端档案。

```powershell
python tools/runtime/run_network_link_qa.py --output .local-tools/network-recheck/tcp
python tools/runtime/run_online_recovery_qa.py --cooperative --packaged-server --output .local-tools/network-recheck/recovery
python tools/runtime/run_online_storage_qa.py --cooperative --hold-seconds 3 --output .local-tools/network-recheck/storage
python tools/runtime/run_online_load_qa.py --cooperative --rooms 2 --seconds 60 --weapons w14,w07 --output .local-tools/network-recheck/load
```

`game/tests/network_faults.gd` 由 Godot 原生执行，以 `--output=<新的独立目录>` 写入故障断言。`record_network_audit.py` 仅在本轮固定报告、实际产物摘要、编译代码和素材核验全部通过后生成验收回执；不执行发布或改写旧标签。

## 更新与边界

客户端与服务器必须一起更新到 **0.4.1**。战斗／检查点仍为 protocol 2／cooperative-1-duel-2；新增 **transport revision 1**，明确拒绝旧客户端或旧服务器。0.4.0 检查点通过原生升级验证，备份后可继续使用原数据目录；0.3.0 内容指纹不兼容。离线三槽保存独立。

实体 Android 的蜂窝／Wi-Fi 切换、后台冻结、省电模式，真实公网 WSS、运营商丢包及长时间跨平台通关仍需在对应设备和部署上测试。目前没有默认公网游戏服务器。

服务器硬崩溃会恢复到最近一次完整成功的检查点；之后尚未提交的移动和战斗尾部可能回退。已确认选卡等事务先成功保存。两代检查点均损坏时拒绝覆盖原数据，无法承诺任何损坏都无损恢复。

## English

0.4.1 adds FIFO command retries, current service state on replayed receipts, bounded acknowledged snapshots, connection/room/match/epoch/scene input fences, and independent state-progress timeouts. Scopes are checked again every simulation tick so an already received frame cannot keep moving a character after a room transition.

Repeated disconnects clear both resume confirmations. Persistent ownership generations prevent an old process reclaiming an identity after a lost close frame or overwriting its successor's credentials. Initial authentication has a finite deadline and reuses unclaimed enrollment. Local credential failures stop the connection; repaired server storage restarts state tracking. Finished rooms no longer consume active match capacity.

Evidence separates intentional application-frame faults from ordered TCP forwarding, packaged-server crash/corruption/storage recovery, immutable 0.4.0-to-0.4.1 data upgrade, local short load, packaged Windows UI, and compiled client/server/APK parity. These are not physical Android network-switching or public-WAN acceptance. Update clients and server together; hard crashes can roll back the uncommitted tail after the last successful checkpoint.
