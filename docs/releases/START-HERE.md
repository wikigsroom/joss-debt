# 香火债 0.5.0 / Incense Debt 0.5.0

十一层离线房间肉鸽、双人共灯合作和可选对灯切磋。游戏界面为简体中文。[Release 与校验文件](https://github.com/wikigsroom/joss-debt/releases/tag/v0.5.0)。

An eleven-floor offline roguelite with two-player Co-Light cooperation and optional Duel. The game currently uses Simplified Chinese.

## Windows

下载 `IncenseDebt-v0.5.0-windows-x64.zip`，完整解压后运行 `IncenseDebt.exe`。需要 Windows x64 和 OpenGL 3.3，不需安装 Godot。程序未做 Windows 发行者代码签名；同一 Release 提供 SHA256SUMS.txt。

Extract the Windows ZIP and run the EXE. Requires Windows x64 and OpenGL 3.3; no engine installation. No Windows publisher signature is provided. Check the release checksums.

## Android

安装 `IncenseDebt-v0.5.0-android-arm64.apk`：**Android 9 / API 28 以上、arm64**，版本 0.5.0 / code 9。正式私有签名、非调试构建；只请求 INTERNET、VIBRATE。离线游玩无需网络，实体手机验收尚未完成。

包内嵌入旧签名到正式签名的证书迁移链，官方校验器已验证 API 28、32、33、36 的签名与旧安装数据继承能力。优先直接覆盖安装，**不要先卸载**，卸载会删除私有愿簿。具体手机安装和触控仍需真机确认。

Install the release APK on Android 9+ arm64. The embedded legacy-to-release certificate lineage passes official verification on API 28, 32, 33 and 36, including installed-data inheritance. Install over the previous app when possible; uninstalling deletes private saves. Physical-device acceptance remains pending.

## 共灯 / Co-Light

主菜单展示联机处理告知和隐私入口。进入「共灯」自动连接官方服务，不需填写地址或手动连接。默认合作模式，快速匹配或双方填写相同六位房间码；保留前导零、先到者创建、后到者加入，双方准备后开始。大厅支持昵称、六角色、32 武器、18 技能配装，可切换独立 PvP。

Open Co-Light to connect automatically after reviewing the main-menu notice. Quick-match or share the same six-digit code. Both players ready up. Change nickname/loadout in the hub; optional Duel uses a separate queue.

普通断线自动退避重试，双方暂停；默认 90 秒内恢复身份与本局，双方确认才能继续。过期或已结算的局不会重开。官方共享主机暂限两间活跃房间；公网抖动可能短暂停战、重连或排队。

Ordinary disconnects retry automatically. The server pauses both players, normally retains the session for 90 seconds, and requires both to resume. Settled or expired matches cannot reopen. The shared official host currently allows two active rooms.

| 操作 / Action | Windows | 手机 / Touch |
| --- | --- | --- |
| 移动 / Move | WASD | 左侧仅移动摇杆 / Left movement stick |
| 射击 / Fire | 方向键；鼠标 / Arrows; mouse | 右侧瞄准摇杆 / Right aim stick |
| 身法与技能 / Dash, skill | 设置页中的绑定 / See settings | 右侧按钮 / Right-hand buttons |
| 选卡 / Growth | 1/2/3/4 或方向键 + Enter / Numbers or arrows + Enter | 点选 / Tap |
| 菜单 / Menus | 方向键、Tab、Enter、Esc | 点选 / Tap |
| 地图 / Map | Tab | 地图入口 / Map button |
| 暂停与历史 / Pause/builds | Esc；I | 暂停与成长入口 / Pause/build buttons |

## 存档与政策 / Saves and privacy

三槽离线愿簿不上传；匿名联机凭据与本次世界由服务端独立保存。请勿分享凭据文件。重要升级前可从主菜单导出愿簿。硬崩溃可能回退到最近提交的检查点，不承诺零回退。

Offline saves remain local. Keep anonymous online credentials private and export a save backup before major upgrades. A hard crash can lose the uncommitted checkpoint tail.

[隐私政策 / Privacy](https://xhz.sidcloud.cn/privacy-policy) · 运营主体 / Operator：吴国黎 · carzyg@outlook.com

一般玩家无需下载服务端。Windows / Linux 原生服务端供管理员使用，详见 [部署说明](https://github.com/wikigsroom/joss-debt/blob/main/server/README.md)。正式客户端固定官方服务，自托管需配置自己的开发客户端。本轮无 iOS IPA；历史源码交接包不能直接安装到 iPhone。

Players do not need a server download. Native Windows/Linux servers are for administrators; self-hosting requires a client configured for that host. No signed iOS IPA is provided.
