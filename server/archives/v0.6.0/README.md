# 香火债 0.6.0 服务端源码归档 / Incense Debt 0.6.0 server archive

本目录冻结 `v0.6.0` 正式版的共享权威逻辑、原生 Godot 服务工程和公开部署模板。正式 Release 只发布二进制 ZIP；本归档不包含 TLS 私钥、凭据、玩家 token、检查点、日志、缓存或 native binary。

This directory freezes the shared authoritative logic, portable native Godot server project and public deployment templates for release `v0.6.0`. The release publishes binary ZIPs separately; this archive contains no private keys, credentials, player tokens, checkpoints, logs, caches or native binaries.

从仓库根目录运行：

```powershell
python tools/runtime/verify_server_archive.py --version 0.6.0
```

The manifest binds every file to SHA-256, the release tag and the native server build hashes. Rebuilds may differ in native bytes when import metadata changes; the published release remains authoritative.
