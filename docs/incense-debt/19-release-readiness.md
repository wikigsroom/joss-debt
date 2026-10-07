# 《香火债》发布准入与外部验收清单

这份清单把 Alpha 已经具备的软件证据和只能在真实设备、真实工具链或真人体验中取得的证据分开。它不把自动 Bot 通关、资源加载或桌面截图写成正式三端发布完成。

逐项目标与权威证据的机器审计见[方向1完成审计](reports/product-completion-audit.md)。

## 当前门槛

| 门 | 当前状态 | 直接证据 | 通过标准 |
| --- | --- | --- | --- |
| 设计与数据 | 已通过 | `reports/design-validation.json` | 角色、武器、技能、遗物、路线、房间和敌人引用无断链 |
| Windows 软件 | 已通过 Alpha | `reports/platforms/windows/native-render.json`、`build/windows/IncenseDebt.exe` | 原生程序启动、资产加载、GUI 操作和三章路径稳定 |
| Android 包 | 软件包已通过 | `reports/platforms/android-verification.json`、`build/android/IncenseDebt.apk` | 包签名、资源、权限和导出结构通过；仍需真实安装 |
| iOS 共享源码 | 交接已通过 | `reports/platforms/ios-handoff-verification.json`、`build/ios-handoff/README.md` | Windows 与共享 `game/` 树逐项一致；仍需 macOS/Xcode 导出 |
| 规则与存档 | 已通过 Alpha | `reports/runtime/save-transfer-tests.json`、`reports/runtime/impact-resume-tests.json` | 迁移、回滚、暂停续局、特殊房间账本和延迟攻击恢复一致 |
| 音频与 UI | 已通过 Alpha | `reports/platforms/windows/audio/native-audio.json`、`reports/runtime/ui-refresh/ui-refresh.json` | 原生混音、分层音乐、圆角 UI、字体和图标与锁定视觉约定一致 |
| 真人平衡 | 待验收 | `reports/system-coverage.json` 的 `pending_human_and_device` | 六角色各两条路线至少各完成一局，记录难度、伤害、构筑理解和失败原因 |
| 移动真机 | 待验收 | `reports/system-coverage.json` 的 `pending_device` | Android 与 iOS 安装、触控、旋转、后台、文件/剪贴板、热稳定和长局通过 |

## 真人构筑验收

每一行至少完成一局完整三章流程。记录不修改数值，不开启调试无敌或自动拾取；只允许记录版本、角色、路线、主要武器、三件关键遗物、结局、死亡房间和主观评分。

| 角色 | 路线 A | 路线 B |
| --- | --- | --- |
| 纸童 | 火 | 线 |
| 铃师 | 灰 | 风 |
| 灯客 | 火 | 墨 |
| 傩面 | 印 | 灰 |
| 伞灵 | 风 | 线 |
| 墨吏 | 墨 | 印 |

最低记录字段：

```text
版本 / 平台 / 输入设备 / 角色 / 路线 / 演化 / 主武器
每章耗时 / 受击次数 / 关键遗物 / 是否看懂组合 / 是否出现无解房
死亡或胜利房间 / 1-5 操作舒适度 / 1-5 打击反馈 / 1-5 构筑清晰度 / 备注
```

可直接填写的空白表格见 [`human-balance-template.csv`](reports/human-balance-template.csv)，结构校验见 [`human-balance-template.json`](reports/human-balance-template.json)。空白表格只证明 12 组角色/路线没有漏项，不代表真人平衡已经通过。

填写完成后使用 `python -X utf8 tools/runtime/validate_external_acceptance.py` 生成[外部验收证据审计](reports/external-acceptance.md)。Android 字段模板见 `reports/platforms/android-device/acceptance.example.json`，iOS 字段模板见 `reports/platforms/ios-device/acceptance.example.json`。真人记录的 `build_version` 必须匹配当前版本；Android APK、iOS 共享 ZIP 和签名 IPA 均按 SHA-256 核对。该命令会核对当前 APK/交接 ZIP 哈希、真实设备字段、45 分钟热稳定记录、安装/后台/文件接口、iOS Xcode/IPA 信息以及 12 组真人记录；缺失或空白内容保持 pending，不会被自动测试升级。

平衡结论必须至少有三名不同玩家或三次独立整局样本支持；一次自动 Bot 胜利只能说明规则可终止，不能替代这张表。

## Android 真机验收

1. 安装调试 APK，首次启动、冷启动、横屏锁定和返回键行为各记录一次。
2. 使用单指、双指和三指分别验证移动、瞄准、身法/焚债；拖动触点编辑后重启确认布局仍在安全区内。
3. 从战斗切后台 30 秒再恢复；确认输入清零、暂停页出现、继续后没有重复射击或重复领取。
4. 使用系统文件选择器导出/导入存档；使用软键盘完成压缩文字传递；验证失败导入可恢复备份。
5. 连续运行一局至少 45 分钟，记录平均帧率、峰值内存、机身温度、音频中断和返回桌面恢复结果。

## iOS 真机验收

1. 在真实 macOS + Xcode 使用 `build/ios-handoff/README.md` 的模板和导出脚本创建未签名工程，再使用项目 Apple Team 签名。
2. 在 iPhone 与 iPad 各完成启动、横屏、触控布局、暂停/恢复和一间特殊房间。
3. 验证系统来电/控制中心/锁屏后的输入清零、音频暂停、存档写入与恢复。
4. 验证文件/剪贴板传递、软键盘、刘海与 Home 指示条安全区；至少运行 45 分钟记录帧率、内存、温度和声音。
5. 保存 Xcode 版本、Godot 版本、设备型号、签名配置、IPA 哈希和整局结果，附到 `reports/platforms/ios-device/`。

## 发布签字规则

只有当机器报告的 `software_readiness` 通过，并且真人构筑验收、Android 真机、iOS 真机三组记录均通过时，才可把 `status` 从 `playable_three_chapter_alpha` 改成正式发布状态。缺一项就继续保持 Alpha，并把具体失败字段写回覆盖矩阵。

机器报告由以下命令生成：

```powershell
python -X utf8 tools/runtime/validate_release_readiness.py
```
