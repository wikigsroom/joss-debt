# Android 真机验收记录

在真实 Android 设备完成安装、冷启动、双摇杆/三指输入、后台恢复、系统文件选择器、软键盘/剪贴板、声音和至少 45 分钟长局后，将记录保存为同目录 `acceptance.json`。`artifact_sha256` 必须等于当前 `build/android/IncenseDebt.apk` 的 SHA-256；`evidence_files` 中填写的截图或日志必须放在工作区内。

字段模板见 `acceptance.example.json`。完成后运行：

```powershell
python -X utf8 tools/runtime/validate_external_acceptance.py
```
