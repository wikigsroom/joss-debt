# 外部设备与真人验收落档手册

这份手册把最后一段只能在真实玩家、真实 Android 设备、真实 macOS/Xcode 和真实 iPhone/iPad 上取得的证据固定成可重复流程。它不把桌面触控注入、模拟器、虚拟设备或自动 Bot 写成真机通过。

## 开始一轮验收

在拿到当前交付物后，从项目根目录运行：

```powershell
python -X utf8 tools/runtime/init_external_acceptance.py --platform all
```

命令只会创建或刷新两个 `result: pending` 的记录，并自动写入当前 APK 与 iOS 共享源包的 SHA-256。它不会创建通过记录，也不会生成虚假的截图、温度或设备信息。已经存在的记录默认不覆盖；开始新一轮时显式加 `--force`。

## Android

使用 `build/android/IncenseDebt.apk` 在实体 Android 设备上完成安装、冷启动、横屏、单指/双指/三指输入、后台 30 秒恢复、文件选择器、剪贴板与软键盘检查。持续运行至少 45 分钟，记录机型、系统版本、平均帧率、温度、音频中断和恢复结果。

发行包预检可运行 `python -X utf8 tools/runtime/build_native.py android --android-build release`。它需要产品所有者自己的 release keystore；缺少密钥时会安全删除未签名半成品，并保留失败日志，现有调试 APK 不会被覆盖。

把截图、系统录屏、温度记录和安装日志放在 `docs/incense-debt/reports/platforms/android-device/`，在 `acceptance.json` 的 `evidence_files` 中填写相对于项目根目录的路径。只有所有布尔项真实通过、`thermal_minutes >= 45`、`physical_device_tested: true` 且 `artifact_sha256` 等于当前 APK，验证器才会接受。

## iOS

在真实 macOS 上解压 [iOS 共享源包](../../build/ios-handoff/IncenseDebt-shared-source.zip)，按照 [iOS 交接说明](../../build/ios-handoff/README.md) 使用 Xcode 生成工程并用实际 Apple Team 签名。分别在 iPhone 与 iPad 完成启动、横屏安全区、触控、后台恢复、文件/剪贴板、音频和 45 分钟热稳定测试。

把 Xcode 构建日志、签名 IPA 哈希、iPhone/iPad 录屏和温度记录放在 `docs/incense-debt/reports/platforms/ios-device/`。`source_sha256` 必须匹配当前共享源包，`ipa_sha256` 必须是实际签名 IPA 的 64 位 SHA-256，所有运行字段必须来自真实设备。

## 真人构筑矩阵

使用 [human-balance-template.csv](reports/human-balance-template.csv) 完成六名角色各两条路线的完整三章记录。至少三名不同玩家或三次独立会话，填写主要武器、演化、每章耗时、受击、构筑可读性、打击反馈和操作舒适度。

## 收尾校验

依次运行：

```powershell
python -X utf8 tools/runtime/validate_external_acceptance.py
python -X utf8 tools/runtime/validate_release_readiness.py
python -X utf8 tools/runtime/audit_product_completion.py
python -X utf8 tools/runtime/record_delivery.py
```

`validate_external_acceptance.py` 仍显示 `pending` 时，产品保持 Alpha。只有软件准入、12 行真人矩阵、Android 真机和 iOS 真机四组证据同时通过，才能把正式发布状态升级。
