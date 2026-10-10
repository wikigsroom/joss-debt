# 香火债 · 对灯服务端

原生 Godot 专用服务器。架构与恢复规格见 [联机设计](../docs/incense-debt/39-online-architecture.md)。共用协议与双人战斗代码放在 `game/scripts/network/`，本目录维护服务入口、启动配置和运维说明。运行数据不进入 Git。

本机开发与验证直接使用 Windows 原生进程，不需要 Docker、WSL 或虚拟机。公网需要可持续运行的主机和有效 WSS 证书；本机地址不会自动变成公网服务。

0.3.0 提供快速匹配、同码开房／加入、四选一构筑、三局两胜、暂停、断线恢复、结算与再战。六名还愿人、32 件武器、18 种技能及 32 种适合对战的供物开放使用。

A native Windows x64 server for the playable 0.3.0 Duel mode: matchmaking, six-digit rooms, drafting, best-of-three combat, reconnect, results and rematches. No separate engine installation is needed for the exported server.

## 发布包运行 / Run the server package

解压服务端 ZIP 后双击 `StartServer.cmd`。脚本以 `--headless --max-fps 60` 启动同目录的 `IncenseDebtServer.exe`，读取 `config.json`，状态保存在旁边的 `data/`。不需要游戏素材、Godot 或 Python。看到 `ONLINE_READY` 表示成功启动。

Extract the server ZIP and run `StartServer.cmd`. It loads `config.json`, stores state in `data/`, and prints `ONLINE_READY` when ready.

```powershell
# 服务端目录中 / In the extracted server folder
.\IncenseDebtServer.exe --headless --max-fps 60 -- --config="C:/Games/Duel/config.json" --data-dir="C:/Games/Duel/data"
Invoke-RestMethod http://127.0.0.1:18778/health
# 优雅停机 / Graceful shutdown
powershell -NoProfile -ExecutionPolicy Bypass -File .\StopServer.ps1
```

两份同电脑客户端填写 `ws://127.0.0.1:18777`。局域网两台设备连接同一 Wi-Fi，在两个客户端的「对灯 → 服务器」填主机 IPv4，例如 `ws://192.168.1.10:18777`。手机的 `127.0.0.1` 指手机自身。Windows 防火墙需允许服务器在所选网络接收 **TCP 18777**；不使用 UDP。健康端口 **18778** 应限制在可信网络。

Two clients on one PC use `ws://127.0.0.1:18777`. LAN clients use the server PC's IPv4 address, e.g. `ws://192.168.1.10:18777`. On a phone, localhost refers to the phone. Allow inbound TCP 18777; restrict health port 18778 to trusted operators.

双方连接同一服务器、使用同一版本。在六位房间页输入相同数字，先到者创建、后到者加入；保留前导零，每房两人，第三人被拒。房间码用于寻找开放房间，不是身份密码。快速对战使用独立 FIFO 队列。

Enter the same six-digit code on both clients: the first creates and the second joins. Leading zeroes are preserved. Rooms admit two players. Codes locate open rooms; they are not authentication secrets. Quick play uses a FIFO queue.

## 源码运行与导出 / Source and build

```powershell
# 仓库根目录 / Repository root
powershell -NoProfile -ExecutionPolicy Bypass -File server/run-server.ps1
# 强制源码模式 / Force source runtime
powershell -NoProfile -ExecutionPolicy Bypass -File server/run-server.ps1 -Source
python tools/runtime/build_online_server.py
```

启动器优先使用已构建 EXE，源码模式调用 `.local-tools/godot-4.7.2/` 原生 Godot。构建工具创建隔离的小型工程，复制战斗、数据和服务模块，导出 `build/server/IncenseDebtServer.exe`，并记录共享源码 SHA-256。客户端美术、音频、用户存档和凭据不打入服务端。

The launcher prefers the built EXE. Source mode uses the repository's native Godot. The exporter includes shared combat and data with source hashes, excluding client art, audio, user saves and credentials.

## 配置 / Configuration

复制 `config.example.json` 为 `config.json`。`--config=绝对路径` 加载配置，命令行参数覆盖配置。

| 键 / Key | 默认 / Default | 用途 / Purpose |
| --- | --- | --- |
| `bind` | `0.0.0.0` | 监听地址；仅本机使用 `127.0.0.1` / Listen address |
| `port` | `18777` | TCP WebSocket；健康检查用此值 + 1 / TCP game, health +1 |
| `data_directory` / `--data-dir` | `user://online-server` | 发布启动器覆盖为旁边 `data/` / Persistent path |
| `max_connections` | `16` | 连接与握手上限，含排队者 / Connection cap |
| `max_rooms` | `2` | 等待和对局共用上限 / Waiting and active room cap |
| `grace` | `90` 秒 | 断线／暂停恢复窗口 / Reconnect grace |
| `waiting` | `300` 秒 | 未开战房间 TTL / Lobby TTL |
| `checkpoint` | `1` 秒 | 后台检查点捕获间隔 / Capture interval |

默认两房依据真实短时压测设置；四房压力测试也留有记录，但峰值停顿更高。八房及以上探索未通过稳定性标准。提高容量前在目标机器重测，不能把本机结果当成任意主机的承载承诺。详见 [交付证据](../docs/incense-debt/40-online-delivery.md)。

The conservative two-room default follows a native local benchmark. Four-room tests show higher peak pauses; exploratory loads of eight or more did not meet stability criteria. Re-test on the intended host before increasing capacity.

## 公网 / Public WSS

客户端不预设公共运营服务器。公网需持续运行的主机与有效证书的 TLS 反向代理，将 `wss://您的域名` 转到 `127.0.0.1:18777`，保留 WebSocket Upgrade，连接超时需容纳心跳和恢复窗口。原生 Caddy 的配置示例：

```caddyfile
duel.example.com {
    reverse_proxy 127.0.0.1:18777
}
```

此例不代表已经申请主机、证书或完成公网部署。18777／18778 可保持私有。`xhz.sidcloud.cn` 的 Vercel 站点仅托管隐私政策，独立于持续运行的游戏服务器。客户端保留正常证书验证；公网使用 WSS，明文 WS 只适合可信本机／局域网。

Public play requires an always-running host and a TLS reverse proxy with a valid certificate. This example does not provision either. Keep raw game/health ports private. The Vercel privacy website is separate from the persistent server. Use WSS publicly; certificate verification remains enabled.

## 存盘与恢复 / Persistence and recovery

`data/registry/checkpoint_0.json`、`checkpoint_1.json` 保存两代注册表，明确引用 `data/rooms/<随机房间>/revision_*.json` 的完整一致代。周期捕获从主线程分离完整状态，后台单一写入线程先房间、后注册表，每次最多一个任务。准备、选择、离开与结果的确认在可靠提交之后发送。

Two registry generations reference exact immutable room generations. A single bounded background writer commits detached snapshots, rooms first and registry last. Control and result acknowledgments follow durable commits.

备份先停机，再复制整个 `data/`，不要只拷最新 JSON。创建 `data/stop` 后，进程完成写入并打印 `ONLINE_STOPPED checkpoints_flushed=true`。强制结束可能丢失尚未提交的战斗尾部：一秒是捕获间隔，实际恢复点还受写入耗时影响。

Back up all of `data/` after graceful shutdown. A hard kill may lose the uncommitted battle tail: one second is the capture interval, not a strict loss bound.

未完成对局重启后停在恢复等待，清空旧按键。原身份重新连接，恢复血量、位置、子弹、冷却、构筑、随机流和比分；两人确认后继续。新连接接管旧连接，旧端停止重试。超时结果只提交一次，不能复活旧比赛。最新注册表或房间损坏时回退到上一组一致代；均损坏则保留原件并拒绝启动。

Unfinished matches restart suspended with old input cleared. Original identities recover combat and RNG state; both players confirm before resuming. Takeover stops the old client's retries. Expired results settle once. Corruption falls back consistently; unrecoverable data is preserved and startup refused.

`storage_fault=true` 停止战斗与新控制事务，客户端显示停战，后台尝试恢复写入。检查磁盘和目录权限。不要公开服务端 `data/`、客户端 `online-client/` 或恢复密钥。默认 14 天后清理离线无房间身份、过期结算账册及不再被恢复代引用的已释放房间文件；活动与恢复数据受保护。外部备份和代理日志由运营者管理。

Storage faults suspend combat and new transactions while writes are retried. Protect data and recovery credentials. Default retention clears inactive roomless identities and expired unreferenced data after 14 days; operators manage external backups and proxy logs.

内容／规则指纹变化拒绝加载旧对战检查点。升级前完成旧比赛并备份，更新后使用新数据目录。离线三槽存档兼容规则独立。

A content/rules mismatch rejects old online checkpoints. Finish and back up matches before upgrading, then use a new data directory. Offline save compatibility is separate.

## 验收 / Verification

健康接口显示连接、房间、排队、Tick、物理及网络处理 P95／P99／最大耗时、积压字节、后台写入与持久化错误，不含昵称、房间码或恢复密钥。

```powershell
python tools/runtime/run_online_recovery_qa.py --packaged-server
python tools/runtime/run_online_load_qa.py --rooms 2 4 --seconds 60
python tools/runtime/run_online_native_qa.py --packaged
```

恢复测试对隔离目录中的实际 EXE 执行崩溃、重启、双类损坏、身份接管和超时；负载测试另起原生进程发送真实射击与技能。客户端原生输入与宽屏触控测试使用真实连接；APK 权限、签名和模块检查不等于手机真机联机验收。测试凭据只保存在 `.local-tools/`。

Tests use actual native processes and real traffic, with corruption restricted to isolated data. APK inspection is not physical-device multiplayer validation. Test identities remain private under `.local-tools/`.
