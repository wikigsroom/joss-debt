# 外部验收证据审计

记录时间：2026-10-06T11:48:56.452462+00:00。

| 门 | 状态 | 完成行/失败数 |
| --- | --- | --- |
| 真人六角色双路线 | `pending_human` | 0/12，0 个问题 |
| Android 真机 | `pending_device` | 20 个问题 |
| iOS 真机 | `pending_device` | 28 个问题 |

总体正式发布证据：`pending_external_acceptance`。

该报告只接受真实玩家/设备记录；空表、桌面模拟触控、自动 Bot 和模拟器不会被升级为通过。

重新生成：

```powershell
python -X utf8 tools/runtime/validate_external_acceptance.py
```
