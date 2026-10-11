# 香火债原生独立服务端 / Native dedicated server

**0.6.0 原生 UDP 正式联机发布**，提供 Linux x64 与 Windows x64。官方稳定服务为 `wss://xhz-server.sidcloud.cn/play` 加 UDP `xhz-server.sidcloud.cn:18779`；客户端进入共灯自动完成 WSS 身份交换，再用 ENet＋DTLS 承载战斗，不展示／编辑地址。默认双人合作十一层、共享 NPC／钱包／掉落、各自成长、救援与真实门口推进；可选对灯 PvP 使用隔离队列。

Official 0.6.0 clients bootstrap through the fixed public WSS service and carry battle traffic over encrypted native ENet/UDP. Co-Light is the default; optional Duel is isolated. Players do not need to run a server.

**2026-10-12 原生 UDP 已激活：** 0.6.0 使用 HTTPS／WSS 做身份与一次性 battle ticket，使用 UDP 18779 上的 Godot ENet＋DTLS 承载战斗。候选已完成隔离验收后切换到 `/play`，激活摘要、健康与 SHA 见[开发计划](../docs/incense-debt/46-network-development-plan.md)、[实现说明](../docs/incense-debt/47-native-udp-iteration.md)与本轮[验收证据](../docs/incense-debt/reports/network-udp-acceptance-2026-10-12.json)。

**Native UDP is active:** 0.6.0 uses HTTPS/WSS for identity and a one-use battle ticket, then Godot ENet/DTLS on UDP 18779 for battle. The isolated candidate passed its gates and was promoted to `/play`; see the [plan](../docs/incense-debt/46-network-development-plan.md), [implementation note](../docs/incense-debt/47-native-udp-iteration.md) and [acceptance evidence](../docs/incense-debt/reports/network-udp-acceptance-2026-10-12.json).

## 源码归档 / Source archival

[v0.6.0 独立源码归档](archives/v0.6.0/README.md)保存与正式服务端一致的共享脚本、12 份数据、可直接运行的 Godot 工程和公开部署文件；[归档清单](archives/v0.6.0/manifest.json)逐项绑定 SHA-256、原始 tag 与正式包摘要。0.5.0 归档继续保持不变；后续开发继续使用 `game/scripts/` 与 `game/data/`。运行 `python tools/runtime/verify_server_archive.py --version 0.6.0` 可只读核验。

The [standalone v0.6.0 source archive](archives/v0.6.0/README.md) preserves the exact accepted shared source bytes, portable project and public deployment files. Its manifest pins provenance and native server hashes. The immutable v0.5.0 archive remains available; future releases receive new archives. Verify from the repository root with `python tools/runtime/verify_server_archive.py --version 0.6.0`.

Git 排除真实服务器配置、凭据、TLS 私钥、玩家 token／检查点、日志和缓存。运行包保留在 [正式 Release](https://github.com/wikigsroom/joss-debt/releases/tag/v0.6.0)；玩家状态需要正常停机后做独立的加密备份，源码归档不包含在线存档。

Private configuration, credentials, keys, player state, logs and caches are excluded from Git. Native packages are archived in the stable Release. Back up live state separately and privately after graceful shutdown.

[归档验收记录](../docs/incense-debt/reports/server-archive-2026-10-11.json)已验证独立工程原生导入、两次启动／健康与 tick 推进、正常停机写盘及重启，另检查 17 项私密运行文件排除规则；测试使用独立空存储，不操作线上玩家。

The [archive verification](../docs/incense-debt/reports/server-archive-2026-10-11.json) records native import, two isolated startup/health/tick/graceful-stop cycles, committed empty state and 17 private-file ignore checks. It does not exercise or modify live player sessions.

继承 [0.4.1 可靠性修复](../docs/incense-debt/43-network-reliability-audit.md)：顺序指令补发、状态停滞停战、旧输入与快照拒绝、持久身份接管。协议 2、transport revision 2；ENet channel 0 以可靠通道传送 baseline metadata，动态绝对状态使用无序包并由实体序号和下一份绝对状态修复丢包，输入使用 channel 1 的不可靠冗余帧，控制与重绑使用可靠控制通道；DTLS 证书轮换仅在服务空闲时应用。旧传输版本明确拒绝，WSS 断线与 UDP 断线相互解耦，20 秒 battle bind/silence deadline 防止假在线。

## 原生运行 / Native execution

Windows ZIP 完整解压后运行 `StartServer.cmd`，读取同目录 config.json、写入 server-data/，默认仅监听本机回环。Linux 解压后赋予可执行权限，系统应具备 Godot 4.7.2 headless 所需的原生库，无需桌面、Godot 安装或美术资源。

```powershell
.\IncenseDebtServer.exe --headless --max-fps 60 -- --config=config.json
Invoke-RestMethod http://127.0.0.1:18778/health
```

```sh
chmod +x IncenseDebtServer.x86_64
./IncenseDebtServer.x86_64 --headless --max-fps 60 -- --config=/absolute/path/config.json
curl --fail http://127.0.0.1:18778/health
```

All tools run natively; no Docker, WSL, VM or emulator. Official clients have a fixed service; self-hosting requires a development client configured for that server. QA URL overrides enter isolated test saves and are not a normal player setting.

## 配置 / Configuration

`config.example.json` 为源码示例；`linux/config.production.json` 为官方配置。CLI `--config=绝对路径` 加载配置，显式参数可覆盖。

| Key | 默认 / Default | 用途 / Meaning |
| --- | --- | --- |
| bind | 0.0.0.0（源码）；发布模板为 127.0.0.1 | 监听地址 / Bind |
| port | 18777 | 游戏；健康端口为 +1 / Game, health +1 |
| battle_bind | 127.0.0.1（源码）；官方为 0.0.0.0 | ENet＋DTLS battle bind |
| battle_port | 18779 | 加密 UDP battle port |
| battle_certificate / battle_private_key | 空（源码）；官方 TLS lineage | DTLS certificate and key paths |
| data_directory / --data-dir | user://online-server | 持久目录 / Persistent state |
| max_rooms | 2 | 活跃房间，不计结果页 / Active rooms |
| max_connections | 16 | 连接上限，不代表 16 人战斗 / Connection cap |
| grace | 90 s | 真正断线恢复窗口 / Disconnect grace |
| waiting | 300 s | 等待大厅期限 / Lobby timeout |
| checkpoint | 1 s | 检查点周期 / Checkpoint interval |

## 官方 Linux 部署 / Official Linux deployment

Ubuntu 24.04、新加坡共享主机。原生 ELF 位于 `/opt/incense-debt/releases/0.6.0/`，current 符号链接指向当前版本；配置 `/opt/incense-debt/config.json`，数据 `/var/lib/incense-debt` 由独立用户持有、权限 0700。

`linux/incense-debt.service` 使用独立用户与系统只读保护、内存软限制 192 MiB／硬限制 256 MiB、**仅本服务禁止 swap**、退出后 3 秒自动重启。`linux/stop.sh` 写入本服务的停止标记，等待最后检查点与正常退出。

```sh
sudo systemctl status incense-debt.service
sudo systemctl restart incense-debt.service
sudo systemctl stop incense-debt.service
sudo journalctl -u incense-debt.service --since '10 minutes ago'
```

当前主机已运行宝塔 Nginx。`linux/xhz-server.nginx.conf` 只配置本域名，使用实际 `/www/server/nginx/sbin/nginx`；不要安装／重启系统默认 Nginx、覆盖其他应用的全局配置。仅新增本游戏 vhost、测试并 reload 实际 Nginx。游戏／健康端口绑定回环，公开入口为 TLS 反代。

The scoped templates assume the existing BT Nginx installation. Adapt paths on another host; do not replace unrelated services. Only the game's service, vhost and data directory are managed here.

| 公开入口 / Entry | 用途 / Purpose |
| --- | --- |
| https://xhz-server.sidcloud.cn/ | 下载与政策 / Release and policy |
| https://xhz-server.sidcloud.cn/health | 不含玩家凭据的健康指标 / Credential-free health |
| wss://xhz-server.sidcloud.cn/play | TLS WebSocket |

证书 `/etc/letsencrypt/live/incense-debt-public/`，certbot.timer 已启用，续期 dry-run 成功；专属 deploy hook 仅针对本证书测试并 reload 实际 Nginx。访问日志关闭；专属错误日志按 `linux/logrotate.conf` 每日轮换、最多 14 天。不要发布 TLS 私钥、SSH 凭据、匿名 token 或检查点。

续期脚本已归档为 [linux/incense-debt-nginx-reload](linux/incense-debt-nginx-reload)，部署位置 `/etc/letsencrypt/renewal-hooks/deploy/incense-debt-nginx-reload`，需可执行权限。该文件不包含私钥，仅处理匹配的本服务证书；与线上脚本字节一致。

The tracked [certificate-renewal hook](linux/incense-debt-nginx-reload) matches the deployed public script. Install it as executable at the above deploy-hook path; it contains no private key and reloads only for the matching certificate lineage.

## 弱网与恢复 / Network and recovery

UDP 丢包由 ENet 的通道策略、输入冗余和绝对快照修复；可靠控制只承载需要确认的操作，避免把高频状态排成队头。事务同编号重试、服务端持久回执防止重复成长／扣款。250 ms 无有效输入停止移动射击，输入不能跨房间／暂停代数；状态过旧先停战，2 秒无进展再重连。普通断线自动退避重试，默认 90 秒内恢复，双方确认才能继续。

完整检查点保存地图、双方成长、钱包、救援、随机流与延迟攻击；两代注册表引用独立房间文件。正常退出后备份整个数据目录。硬崩溃可能丢失最近提交后的战斗尾部，不能承诺零回退。

Control requests use durable deduplication; stale input, snapshots and ownership generations are rejected. State stalls pause combat independently of ping. Recovery restores the latest committed world and requires both players to resume.

## 实测与容量 / Measurement and capacity

[0.5.0 报告](../docs/incense-debt/44-public-online-release.md)及[原生证据](../docs/incense-debt/reports/public-online-2026-10-11)：实际 Windows 包经官方 WSS 的合作 29 项、PvP 32 项；真实线上重启恢复 10 项；两房四个正式 Session 连续 60.399 秒、4542 快照、59.89 Hz、RTT p95 358 ms、状态年龄 p95 184 ms。实际 Linux／Windows 服务包分别有 37 份共享模块与客户端一致。

一分钟测量不是 SLA 或长时容量保证。共享主机／公网抖动仍存在；无恢复逻辑的原始 WebSocket 压测器曾发生连接关闭，原因未完全隔离。正式 Session 在记录的测量中无会话错误并通过恢复测试，不能据此宣称网络永不丢包。维持两间活跃房间，扩容前需长时负载和 Android 真机验收。

This is a bounded WAN test, not an availability guarantee. Raw clients without recovery have seen connection closure with an unresolved cause. Shipping sessions pass the recorded load/restart scenarios; sustained capacity and physical Android remain to be tested.
