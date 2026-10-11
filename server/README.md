# 香火债原生独立服务端 / Native dedicated server

**0.5.0 正式联机发布**，提供 Linux x64 与 Windows x64。官方服务已部署为 `wss://xhz-server.sidcloud.cn/play`；客户端进入共灯自动连接，不展示／编辑地址。默认双人合作十一层、共享 NPC／钱包／掉落、各自成长、救援与真实门口推进；可选对灯 PvP 使用隔离队列。

Official 0.5.0 clients auto-connect to the fixed public WSS service. Co-Light is the default; optional Duel is isolated. Players do not need to run a server.

继承 [0.4.1 可靠性修复](../docs/incense-debt/43-network-reliability-audit.md)：顺序指令补发、状态停滞停战、旧输入与快照拒绝、持久身份接管。协议 2、transport revision 1；旧传输版本明确拒绝。历史 0.4.0 检查点升级已有原生验证，旧 Release 保留原样。

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
| data_directory / --data-dir | user://online-server | 持久目录 / Persistent state |
| max_rooms | 2 | 活跃房间，不计结果页 / Active rooms |
| max_connections | 16 | 连接上限，不代表 16 人战斗 / Connection cap |
| grace | 90 s | 真正断线恢复窗口 / Disconnect grace |
| waiting | 300 s | 等待大厅期限 / Lobby timeout |
| checkpoint | 1 s | 检查点周期 / Checkpoint interval |

## 官方 Linux 部署 / Official Linux deployment

Ubuntu 24.04、新加坡共享主机。原生 ELF 位于 `/opt/incense-debt/releases/0.5.0/`，current 符号链接指向当前版本；配置 `/opt/incense-debt/config.json`，数据 `/var/lib/incense-debt` 由独立用户持有、权限 0700。

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

## 弱网与恢复 / Network and recovery

TCP 丢包主要表现为重传延迟、阻塞、积压或断线。事务同编号重试、服务端持久回执防止重复成长／扣款。250 ms 无有效输入停止移动射击，输入不能跨房间／暂停代数；状态过旧先停战，2 秒无进展再重连。普通断线自动退避重试，默认 90 秒内恢复，双方确认才能继续。

完整检查点保存地图、双方成长、钱包、救援、随机流与延迟攻击；两代注册表引用独立房间文件。正常退出后备份整个数据目录。硬崩溃可能丢失最近提交后的战斗尾部，不能承诺零回退。

Control requests use durable deduplication; stale input, snapshots and ownership generations are rejected. State stalls pause combat independently of ping. Recovery restores the latest committed world and requires both players to resume.

## 实测与容量 / Measurement and capacity

[0.5.0 报告](../docs/incense-debt/44-public-online-release.md)及[原生证据](../docs/incense-debt/reports/public-online-2026-10-11)：实际 Windows 包经官方 WSS 的合作 29 项、PvP 32 项；真实线上重启恢复 10 项；两房四个正式 Session 连续 60.399 秒、4542 快照、59.89 Hz、RTT p95 358 ms、状态年龄 p95 184 ms。实际 Linux／Windows 服务包分别有 37 份共享模块与客户端一致。

一分钟测量不是 SLA 或长时容量保证。共享主机／公网抖动仍存在；无恢复逻辑的原始 WebSocket 压测器曾发生连接关闭，原因未完全隔离。正式 Session 在记录的测量中无会话错误并通过恢复测试，不能据此宣称网络永不丢包。维持两间活跃房间，扩容前需长时负载和 Android 真机验收。

This is a bounded WAN test, not an availability guarantee. Raw clients without recovery have seen connection closure with an unresolved cause. Shipping sessions pass the recorded load/restart scenarios; sustained capacity and physical Android remain to be tested.
