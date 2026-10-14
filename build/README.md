# 原生构建与发布 / Native builds and release

当前正式联机版 **0.6.2 / Android code 12**。Windows x64、Android 9+ arm64、Linux／Windows 独立服务端。离线十一层、双人共灯、可选对灯；官方客户端进入共灯自动连接。

See [current delivery](../docs/incense-debt/reports/current-product-status.md), [audit](../docs/incense-debt/44-public-online-release.md), and [Release](https://github.com/wikigsroom/joss-debt/releases/tag/v0.5.0).

| Build | 本地路径 / Local path |
| --- | --- |
| Windows | windows/IncenseDebt.exe |
| Android release | android/IncenseDebt.apk |
| Windows server | server/IncenseDebtServer.exe |
| Linux server | server-linux/IncenseDebtServer.x86_64 |
| Release payload | release/v0.6.2/assets/ |

## 构建 / Build

Godot 4.7.2、Android SDK 36、JDK 21、Python，全部原生工具。Windows 可直接导出 Linux ELF；不使用 Docker、WSL、VM 或模拟器。导出前检查全量素材，第三方声明随 Windows ZIP 保留。

```powershell
python tools/runtime/build_native.py windows
python tools/runtime/sign_android_release.py --export
python tools/runtime/build_online_server.py --platform both
```

`build_native.py android` 默认生成开发调试包；正式发布仅使用签名工具。私有 JKS 和密码保存在本机忽略目录，DPAPI 保护密码，不进入 Git；未来升级需保留同一材料和迁移链。

非 Gradle 模板 minSdk 不能被 Godot 预设直接覆写。正式工具校验并只调整二进制 Manifest 的 minSdk 至 28，再 ZIP 对齐、嵌入官方迁移链签名。实际 API、debuggable、签名和数据继承均从最终 APK 验证。

The native signing pipeline uses a private release key with a legacy certificate lineage. It validates and adjusts the prebuilt manifest minSdk to 28 before alignment and signing. Keep private signing material for future updates; never publish it.

## 验收 / Acceptance

```powershell
python tools/runtime/run_keyboard_qa.py --packaged
python tools/runtime/run_online_native_qa.py --packaged --cooperative --url wss://xhz-server.sidcloud.cn/play
python tools/runtime/verify_packaged_revision.py
python tools/runtime/verify_android.py
python tools/runtime/verify_android_lineage.py
```

外部布局 fixture 使用实际 Windows main-pack，桌面／X30 尺寸／宽屏手机／平板覆盖不等于 Android 真机验收。公网 PvP 的 `--public-exit-wait` 只给外部测试驱动增加等待退出确认，生产字节码不变。所有记录绑定实际包体 SHA-256。

Layout fixtures inspect the exported Windows pack. They are not Android-device tests. Public Duel acceptance waits for the server leave acknowledgement in an external fixture; production bytecode is unchanged.

## 发布 / Publish

完成源码与验收文档后提交，再生成附件；发布清单提交后创建注释 tag、推送 main 与 tag。发布工具拒绝脏工作区、源码或摘要不符。

```powershell
python tools/runtime/record_public_delivery.py
python tools/runtime/package_public_release.py
python tools/runtime/publish_release.py --tag v0.6.2
python tools/runtime/verify_published_release.py --tag v0.6.2
```

[v0.5.0 清单](../docs/releases/v0.5.0.manifest.json)：先草稿上传，逐份完整 SHA-256／大小核对后公开正式版；归档还校验 CRC 与每个解包成员。旧 Alpha tag／附件不改写。没有本輪 iOS IPA，历史源码交接不能安装。

Archives verify CRC and every member's full hash. Publication checks GitHub attachment digests before a stable release goes public. Historical tags/assets remain intact; no signed iOS IPA is included.
