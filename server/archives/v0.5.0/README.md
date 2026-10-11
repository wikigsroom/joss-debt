# 0.5.0 服务端源码归档 / Server source archive

本目录固定对应正式版 `v0.5.0`（提交 `b3e2358196f9e7aa684cea59e642a80b1d86c05b`）。`project/` 是可独立导入和运行的 Godot 工程，包含 37 个共享 GDScript 模块、12 份游戏数据以及独立启动场景；无需客户端美术或音频。源码、数据的原始字节与当时 Linux／Windows 服务端构建清单逐项一致。

This snapshot is pinned to stable release **v0.5.0**. Its standalone `project/` contains the exact 37 shared modules and 12 data files used for the accepted servers, plus the native boot scene. Client art and audio are unnecessary. The active development source remains in `game/scripts/` and `game/data/`; keep this versioned snapshot fixed and create another directory for a future release.

| 路径 / Path | 内容 / Contents |
| --- | --- |
| `project/` | 独立原生服务端工程；相对路径导出预设 / Standalone native project and portable export presets |
| `deployment/` | 已核对的 systemd、回环配置、Nginx、停机、日志轮换、首页、证书续期脚本 / Public deployment files |
| `config.example.json` | 仅回环监听；使用独立归档测试存储 / Loopback-only example with separate private storage |
| `manifest.json` | 每个归档文件的大小、SHA-256、来源；正式二进制与 ZIP 摘要 / Source provenance and published artifact hashes |

## 核验 / Verify

在仓库根目录使用 Python 3.11 或更高版本。此操作只读，不连接正式服务器；需要本地存在原发布 tag。

From the repository root, use Python 3.11+; verification is read-only and requires the original release tag:

```sh
python tools/runtime/verify_server_archive.py --version 0.5.0
```

[原生归档验收](../../../docs/incense-debt/reports/server-archive-2026-10-11.json)记录独立工程导入、启动／健康状态、tick 推进、正常停机写盘与重启，以及 17 项私密文件忽略规则检查。它仅使用独立空存储；合作游玩与公网恢复记录见原正式版报告。

The [native archival check](../../../docs/incense-debt/reports/server-archive-2026-10-11.json) verifies standalone import, startup, health, tick progression, graceful persistence, restart and 17 ignore rules using isolated empty storage. Multiplayer gameplay and WAN recovery remain covered by the original release evidence.

## 原生启动 / Native startup

安装 **Godot 4.7.2 stable**。以下 Windows PowerShell 命令从仓库根目录运行，将自己的运行状态写入被 Git 忽略的目录；`godot` 应位于 PATH 中。

Install **Godot 4.7.2 stable**. From the repository root on Windows PowerShell:

```powershell
$serverProject = (Resolve-Path 'server/archives/v0.5.0/project').Path
$serverConfig = (Resolve-Path 'server/archives/v0.5.0/config.example.json').Path
$serverData = Join-Path (Get-Location).Path 'server/archives/v0.5.0/server-data'
godot --headless --editor --path $serverProject --import --quit
godot --headless --max-fps 60 --path $serverProject -- --config=$serverConfig --data-dir=$serverData
```

Linux／macOS 原生环境可在仓库根目录使用同一工程：

On a native Linux/macOS host, use the same project:

```sh
godot --headless --editor --path "$PWD/server/archives/v0.5.0/project" --import --quit
godot --headless --max-fps 60 --path "$PWD/server/archives/v0.5.0/project" -- \
  --config="$PWD/server/archives/v0.5.0/config.example.json" \
  --data-dir="$PWD/server/archives/v0.5.0/server-data"
curl --fail http://127.0.0.1:18778/health
```

在第二个终端写入 `<serverData>/stop` 文件正常停机，等待 `ONLINE_STOPPED checkpoints_flushed=true`；Linux 使用 `touch server/archives/v0.5.0/server-data/stop`，PowerShell 使用 `New-Item -ItemType File -Force 'server/archives/v0.5.0/server-data/stop'`。如端口已占用，显式传入 `--port=其他端口`，健康端口始终为游戏端口 +1。正式客户端固定连接官方 WSS，自建服务需要匹配地址的开发客户端。

Create a `stop` file in the selected data directory from another terminal and wait for `ONLINE_STOPPED checkpoints_flushed=true`. Use `--port=...` if necessary; health listens on game port +1. Shipping clients connect to the official WSS endpoint; self-hosted play requires a development client configured for that service.

## 重新导出 / Rebuild exports

安装匹配的 **4.7.2 stable 原生导出模板**后，在仓库根目录执行以下命令。`manifest.json` 固定官方模板包的下载地址、大小及 SHA-256。预设使用安装后的标准模板，避免包含任何本机绝对路径。Windows 可通过本机 Godot 交叉导出 Linux ELF，全程使用原生进程。

Install the matching **4.7.2 stable export templates**. The manifest pins the official template archive URL, size and SHA-256. Then run from the repository root using native Godot; Windows can also cross-export the Linux ELF:

```sh
python tools/runtime/verify_server_archive.py
mkdir -p build/server-archive-v0.5.0
godot --headless --editor --path server/archives/v0.5.0/project --import --quit
godot --headless --path server/archives/v0.5.0/project --export-release windows-x64 "$PWD/build/server-archive-v0.5.0/IncenseDebtServer.exe"
godot --headless --path server/archives/v0.5.0/project --export-release linux-x64 "$PWD/build/server-archive-v0.5.0/IncenseDebtServer.x86_64"
```

导出目标使用**绝对路径**：Godot 的相对输出路径基于项目目录解析。上述为 sh 命令；PowerShell 创建目录使用 `New-Item -ItemType Directory -Force 'build/server-archive-v0.5.0'`，导出目标分别使用 `(Join-Path (Get-Location).Path 'build/server-archive-v0.5.0/IncenseDebtServer.exe')` 与相应 Linux 文件路径。重新导出可能因导入 UID／引擎元数据不同而产生不同的二进制摘要；本归档证明源文件逐字节一致，正式包仍以清单绑定的已验收附件为准。

**Use absolute output paths**: relative outputs resolve against the project directory. The example uses sh; in PowerShell create the folder with `New-Item -ItemType Directory -Force 'build/server-archive-v0.5.0'` and use `(Join-Path (Get-Location).Path 'build/server-archive-v0.5.0/IncenseDebtServer.exe')` as the output argument, likewise for Linux. Import IDs and engine metadata can change rebuilt binary hashes; identical archived source bytes do not imply a reproducible binary hash. Accepted binaries remain available in [Release v0.5.0](https://github.com/wikigsroom/joss-debt/releases/tag/v0.5.0).

## 部署与备份 / Deployment and backups

`deployment/` 保存经过实际线上摘要核对的公开配置；证书续期 hook 同样从线上只读核对。宝塔 Nginx 路径及域名为当前部署环境专用，换主机时需调整。将续期脚本安装至 `/etc/letsencrypt/renewal-hooks/deploy/incense-debt-nginx-reload` 并设为可执行。它仅在本服务的 `RENEWED_LINEAGE` 匹配时检查并 reload 实际 Nginx。其余安装说明见 [服务端说明](../../README.md)。

The public deployment templates were matched to installed hashes. Adapt host-specific BT Nginx paths and the domain when moving hosts. Install the executable certificate hook under `/etc/letsencrypt/renewal-hooks/deploy/`; it reloads the existing Nginx only for this certificate lineage. See the [server guide](../../README.md) for operations.

Git 保存源代码、公开模板与核验信息。SSH／DPAPI 凭据、TLS 私钥、真实玩家 token、检查点、日志、Godot 缓存与 EXE／ZIP 均排除。玩家状态应在正常停机后对 `/var/lib/incense-debt` 单独做加密备份，并验证恢复，不应放入公开仓库。部署模板中的证书路径是公开文件位置，私钥内容不在本归档中。

Git archives source, public templates and provenance. Credentials, TLS private keys, player tokens/checkpoints, logs, caches and binaries are excluded. Back up the complete `/var/lib/incense-debt` privately after graceful shutdown, encrypt the backup and test recovery. Public Git archival is separate from live player-state backup. Existing project and third-party licensing terms still apply.
