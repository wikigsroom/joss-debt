# 香火债 / Incense Debt · v0.2.3-alpha.1

十一层单人离线 Alpha。游戏界面为简体中文，本说明为中英双语。

An offline, single-player eleven-floor Alpha. The game UI is Simplified Chinese; these instructions are bilingual.

## Windows

下载 `IncenseDebt-v0.2.3-alpha.1-windows-x64.zip`，完整解压，再打开其中 `IncenseDebt/IncenseDebt.exe`。无需安装 Godot。保留同文件夹的字体、图标与 Godot 授权文本。程序为原生 x64、Compatibility / OpenGL 渲染，未做发行者代码签名。

Download `IncenseDebt-v0.2.3-alpha.1-windows-x64.zip`, extract it completely, then launch `IncenseDebt/IncenseDebt.exe`. Godot is not required. Retain the font, icon, and engine notices beside the application. This is a native x64 Compatibility/OpenGL export without publisher code signing.

## Android

下载 `IncenseDebt-v0.2.3-alpha.1-android-arm64-debug.apk`，传到真实 arm64 手机，使用系统安装器安装。版本 0.2.3 / versionCode 5，最低 Android 7 / API 24；APK 为调试签名试玩包，通过结构、权限、签名及资源检查，尚未完成真实手机运行验收。只启用 VIBRATE，不请求网络权限。

Download `IncenseDebt-v0.2.3-alpha.1-android-arm64-debug.apk` (version 0.2.3 / versionCode 5) and install it with the system installer on a real arm64 phone, Android 7 / API 24 or later. This is a debug-signed playtest package with structural, permission, signature, and asset checks; physical-phone acceptance is pending. Only VIBRATE is enabled, with no network permission.

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

Windows 存档在 `%APPDATA%\IncenseDebt\`，有三个独立愿簿槽。菜单保存退出；恢复后先暂停，确认继续。设置 → 愿簿传递可导出文件或压缩文字，导入有预览及导入前备份。升级前关闭游戏并备份整个存档目录。APK 包名为 `org.incensedebt.game`，已验证与前一份本地 0.2.2 APK 同签名，支持覆盖该包保留数据；手机卸载通常删除私有数据，升级前可先导出愿簿。

Windows saves live in `%APPDATA%\IncenseDebt\`, with three independent slots. Save-and-quit through menus; resumed runs start paused. Settings → Save transfer exports files or compressed text, with import preview and a pre-import backup. Close the game before backing up the directory. Package ID `org.incensedebt.game` and the signing certificate match the previous local 0.2.2 APK, allowing an in-place upgrade from that package. Export saves before updating; mobile uninstall normally removes private data.

旧手机／平板的完整默认位置会自动切到右手战斗布局；自定义位置、大小与透明度保留。旧尺寸过大导致新位置重叠时保留原合法布局，可在设置中手动恢复默认。存档格式仍为 2。

Exact old phone/tablet defaults migrate to right-hand combat. Custom positions, sizes and opacity remain intact. If oversized old controls would overlap after migration, their valid layout is retained; reset defaults in settings to switch explicitly. Save schema remains 2.

下载后可对照同一 Release 中的 `SHA256SUMS.txt` 校验。PowerShell 示例：

Compare downloads with `SHA256SUMS.txt` from the same release. PowerShell example:

```powershell
Get-FileHash .\IncenseDebt-v0.2.3-alpha.1-windows-x64.zip -Algorithm SHA256
```

完整说明、实机截图、GIF、角色、武器、地图与构建：[项目 README](https://github.com/wikigsroom/joss-debt/blob/v0.2.3-alpha.1/README.md)。当前版本仍需真人手感 / 平衡与移动设备验收。

Full guide, screenshots, GIFs, characters, weapons, maps, and build instructions: [project README](https://github.com/wikigsroom/joss-debt/blob/v0.2.3-alpha.1/README.md). Human feel/balance and mobile-device acceptance remain pending.
