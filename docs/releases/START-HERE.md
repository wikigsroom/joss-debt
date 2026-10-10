# 香火债 / Incense Debt · v0.3.0-alpha.1

十一层离线肉鸽 + 独立双人对灯 Alpha。游戏界面为简体中文，本说明为中英双语。

An eleven-floor offline roguelite with a separate online two-player Duel mode. The game UI is Simplified Chinese; these instructions are bilingual.

## Windows

下载 `IncenseDebt-v0.3.0-alpha.1-windows-x64.zip`，完整解压，再打开其中 `IncenseDebt/IncenseDebt.exe`。无需安装 Godot。保留同文件夹的字体、图标与 Godot 授权文本。程序为原生 x64、Compatibility / OpenGL 渲染，未做发行者代码签名。

Download `IncenseDebt-v0.3.0-alpha.1-windows-x64.zip`, extract it completely, then launch `IncenseDebt/IncenseDebt.exe`. Godot is not required. Retain the font, icon, and engine notices beside the application. This is a native x64 Compatibility/OpenGL export without publisher code signing.

## Android

下载 `IncenseDebt-v0.3.0-alpha.1-android-arm64-debug.apk`，传到真实 arm64 手机，使用系统安装器安装。版本 0.3.0 / versionCode 6，最低 Android 7 / API 24；APK 为调试签名试玩包，通过结构、权限、签名及资源检查，尚未完成真实手机运行验收。启用 VIBRATE 与可选联机需要的 INTERNET；离线游玩不要求连接服务器。

Download `IncenseDebt-v0.3.0-alpha.1-android-arm64-debug.apk` (version 0.3.0 / versionCode 6) and install it with the system installer on a real arm64 phone, Android 7 / API 24 or later. This is a debug-signed playtest package with structural, permission, signature, and asset checks; physical-phone acceptance is pending. VIBRATE and INTERNET for optional multiplayer are enabled; offline play requires no server.

## 双人联机与服务端 / Duel and dedicated server

下载 `IncenseDebt-v0.3.0-alpha.1-server-windows-x64.zip`，完整解压后运行 `IncenseDebtServer/StartServer.cmd`，读取旁边的 `config.json`，状态写入 `data/`。无需安装 Godot 或 Python。默认两间房、16 条连接；WebSocket 使用 TCP 18777，健康检查使用同一监听地址的 18778，主机防火墙应将健康端口限制到可信网络。

Download and extract the server ZIP, then run `IncenseDebtServer/StartServer.cmd`. The native standalone server loads `config.json` and writes `data/`. Godot/Python are not required. Defaults: two rooms, 16 connections; TCP game port 18777 and health port 18778 on the same configured listen address. Restrict health access to trusted networks.

1. 进入客户端「对灯 → 服务器」，填写同一服务地址和各自昵称；首次连接先阅读告知。 / Open Duel → Server, enter the same address and your nickname, then review the connection notice.
2. 同一电脑用 `ws://127.0.0.1:18777`；局域网手机／另一电脑填主机 IPv4，如 `ws://192.168.1.10:18777`。手机的 127.0.0.1 是手机本身。 / Same-PC clients use localhost; LAN clients use the host PC's IPv4. Localhost on a phone means that phone.
3. Windows 防火墙允许服务主机接收 TCP 18777，双方使用同一版本。 / Permit inbound TCP 18777 on the host and use the same game version.
4. 「快速对战」自动配对；或双方输入同一六位数字，如 `003719`，先到开房、后到加入。 / Quick play pairs players, or enter the same six digits: first creates, second joins.
5. 双方准备，每轮数字 1–4 选供物，倒数后开战；先赢两轮获胜。 / Both ready, draft with keys 1–4, then fight. First to two round wins takes the match.

角色、武器和技能对战全部开放，32 种供物可组合；没有离线解锁优势。Esc 暂停会停下双方；I 查看双方历史构筑，Tab 看战术图。断线自动重连，90 秒内恢复原血量、比分、构筑与冷却，双方准备后继续；旧按键会清空。超时或离开由服务器唯一结算。对战不修改或上传单人愿簿。

All heroes/weapons/skills are available, with 32 composable PvP relics and no offline-unlock advantages. Esc pauses both; I shows both build histories and Tab shows the arena. Automatic reconnection retains match state within 90 seconds; both confirm to resume and stale controls clear. The server settles timeout/forfeit results once. Solo save slots are not changed or uploaded.

当前没有默认公共游戏服务器。公网需要持续运行的主机和有效证书的 WSS 反向代理；`xhz.sidcloud.cn` 仅是隐私网站。更多配置、容量、恢复与备份见服务端 ZIP 内 README 和[源码运维说明](https://github.com/wikigsroom/joss-debt/blob/v0.3.0-alpha.1/server/README.md)。

No default public game server is deployed. Public play requires an always-running host and valid WSS reverse proxy. `xhz.sidcloud.cn` hosts privacy only. See the bundled server README and [operations guide](https://github.com/wikigsroom/joss-debt/blob/v0.3.0-alpha.1/server/README.md).

优雅停机：在服务端目录执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\StopServer.ps1`，等进程结束后备份整个 `data/`。强制结束可能损失最近尚未提交的战斗尾部；内容／规则升级前完成旧比赛并备份，升级后采用新的数据目录。

Graceful stop: run `powershell -NoProfile -ExecutionPolicy Bypass -File .\StopServer.ps1` in the server folder, wait for exit, then back up all of `data/`. Hard termination may lose the uncommitted battle tail. Finish/back up old matches before a rules/content upgrade and use a new data folder afterward.

## iOS

本次不附 iOS 包。[历史 v0.2.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.2.0-alpha.1) 的 `IncenseDebt-v0.2.0-alpha.1-ios-shared-source.zip` 是旧版共享源码，不能直接安装在 iPhone；当前没有已签名 IPA。

No iOS package is attached to this release. The shared-source ZIP in [historical v0.2.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.2.0-alpha.1) retains its old version and is not an iPhone installation package. No signed IPA is supplied.

## 第一次游玩 / First run

标题 → 选择一个愿簿槽 → 新局 → 纸童 → 确认 / 教学。其余角色通过游戏进度解锁。未完成局被新局替换前需要确认，取消保留原局。

Title → Choose a save slot → New run → Paper Child → Confirm/tutorial. Other characters unlock through play. Replacing an unfinished run requires confirmation; canceling preserves it.

| 操作 / Action | PC |
| --- | --- |
| 移动 / Move | WASD |
| 瞄准攻击 / Aim and fire | 鼠标 + 左键，或方向键 / Mouse + left button, or held arrow keys |
| 焚债 / Burn Debt | Q / 鼠标右键 / right mouse |
| 主动道具 / Active item | F（手柄 X / gamepad X） |
| 身法 / Dodge | Space |
| 交互 / Interact | E；清房后走入对应门口切房 / E; walk through doors after clearing |
| 成长选择 / Growth choices | 1 / 2 / 3 / 4；或方向键 + Enter / or arrows + Enter |
| 行路图 / Map | Tab |
| 构筑 / Build | I |
| 暂停 / 返回 / Pause / back | Esc |
| 菜单确认 / Menu confirm | Enter |
| 全屏 / Fullscreen | F11 |

主攻击挂余烬，邻近标记形成债链，Q / 右键焚债集中爆发，击杀后收灰恢复香火。暂停页成长入口可查看本局完整历史选择。F 使用满充能主动道具；E 拾取/交换装备，饰品最多一件。手机默认左侧只有移动摇杆；右侧为瞄准／射击、身法位移、焚债／爆炸技能与装备后出现的道具按钮。设置 → 触控可调整位置、独立大小、透明度及固定／浮动摇杆，也可恢复默认并保存。

Primary attacks mark enemies; nearby marked enemies form chains. Q/right mouse detonates them, and collected ash replenishes Incense. The growth page in pause shows full selection history. F uses the charged active item; E exchanges equipment, with exactly one trinket slot. The default mobile layout reserves the left for movement; aim/fire, dash, Burn Debt/explosion and the equipped active item sit on the right. Settings → Touch adjusts positions, individual sizes, opacity and fixed/floating sticks, or resets and saves the default preset.

## 存档与校验 / Saves and verification

Windows 存档在 `%APPDATA%\IncenseDebt\`，有三个独立愿簿槽。菜单保存退出；恢复后先暂停，确认继续。设置 → 愿簿传递可导出文件或压缩文字，导入有预览及导入前备份。升级前关闭游戏并备份整个存档目录。APK 包名为 `org.incensedebt.game`，已验证与前一份本地 0.2.3 APK 同签名，支持覆盖该包保留数据；手机卸载通常删除私有数据，升级前可先导出愿簿。

Windows saves live in `%APPDATA%\IncenseDebt\`, with three independent slots. Save-and-quit through menus; resumed runs start paused. Settings → Save transfer exports files or compressed text, with import preview and a pre-import backup. Close the game before backing up the directory. Package ID `org.incensedebt.game` and the signing certificate match the previous local 0.2.3 APK, allowing an in-place upgrade from that package. Export saves before updating; mobile uninstall normally removes private data.

旧手机／平板的完整默认位置会自动切到右手战斗布局；自定义位置、大小与透明度保留。旧尺寸过大导致新位置重叠时保留原合法布局，可在设置中手动恢复默认。存档格式仍为 2。

Exact old phone/tablet defaults migrate to right-hand combat. Custom positions, sizes and opacity remain intact. If oversized old controls would overlap after migration, their valid layout is retained; reset defaults in settings to switch explicitly. Save schema remains 2.

下载后可对照同一 Release 中的 `SHA256SUMS.txt` 校验。PowerShell 示例：

Compare downloads with `SHA256SUMS.txt` from the same release. PowerShell example:

```powershell
Get-FileHash .\IncenseDebt-v0.3.0-alpha.1-windows-x64.zip -Algorithm SHA256
```

完整说明、实机截图、GIF、角色、武器、地图与构建：[项目 README](https://github.com/wikigsroom/joss-debt/blob/v0.3.0-alpha.1/README.md)。当前版本仍需真人手感 / 平衡与移动设备验收。

Full guide, screenshots, GIFs, characters, weapons, maps, and build instructions: [project README](https://github.com/wikigsroom/joss-debt/blob/v0.3.0-alpha.1/README.md). Human feel/balance and mobile-device acceptance remain pending.

## 隐私 / Privacy

政策 1.4，2026-10-11 生效，运营主体 **吴国黎**，邮箱 **carzyg@outlook.com**。联网采用匿名恢复身份，处理昵称、配装、操作、房间和结果；不上传离线愿簿。[可直接访问的 HTTPS 条款](https://xhz.sidcloud.cn/privacy-policy)。

Policy 1.4 is effective 2026-10-11, operator **吴国黎**, contact **carzyg@outlook.com**. Optional online play uses anonymous recovery identities and processes names/loadouts/inputs/rooms/results; offline save slots are not uploaded. [Public HTTPS policy](https://xhz.sidcloud.cn/privacy-policy).
