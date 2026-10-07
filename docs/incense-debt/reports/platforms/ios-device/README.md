# iOS 真机验收记录

在真实 macOS + Xcode 生成并签名工程后，分别在 iPhone 与 iPad 完成横屏、安全区、触控、后台恢复、系统文件/剪贴板、声音和至少 45 分钟长局。将记录保存为同目录 `acceptance.json`；`source_sha256` 必须等于当前 iOS 共享源码 ZIP 的 SHA-256，`ipa_sha256` 填写实际签名 IPA 哈希，证据文件必须位于工作区内。

字段模板见 `acceptance.example.json`。完成后运行：

```powershell
python -X utf8 tools/runtime/validate_external_acceptance.py
```
