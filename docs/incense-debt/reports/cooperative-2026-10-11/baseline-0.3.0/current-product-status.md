# 《香火债》当前交付与验收记录

当前版本 **0.3.0**：十一层离线肉鸽 + 可选双人对灯，支持快速匹配、双方同一六位数字开房、构筑、战斗、暂停、恢复、结算与再战。客户端与独立服务端均已实际导出、核对并通过原生验证。发布页：[v0.3.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.3.0-alpha.1)；当前公开状态以文末发布回执为准。

| 平台 | 大小 | 实际 SHA-256 |
| --- | --- | --- |
| Windows客户端 | 1057.4 MiB | `4455bd4aa4e9a9a4cae7bc44cc2bfbb2736d7c1db9033910a7dbafa4359db02a` |
| Android APK | 977.9 MiB | `7eb253f85f560df8f324a8a4a87e3351f6a2b28b16f4ea82b4af8c7554dab553` |
| Windows独立服务端 | 105.7 MiB | `61c4846f92f36ce06d26f464e66b2d74ce02195c22dd278b830c2fc441a0b8d8` |

当前验证：双人规则 271 项、真实传输 26 项、服务重启／损坏恢复 57 项、写盘故障 7 项，全部通过。源码与实际 Windows EXE 联机流程各 30 项／33 张捕获；实际 EXE 编译包另经外部原生录制脚本复测 33 项，覆盖右摇杆持续开火与右手技能并生成实机 GIF；实际 EXE 离线键盘 107 项。Windows／Android 2167 项包核对通过、86 份编译脚本一致，3810 项运行资源打包。

Android 0.3.0／code 6、arm64 调试签名，与前一本机 0.2.3 APK 的签名匹配，INTERNET、VIBRATE、Expand 与边到边配置已从包体检查；没有实体手机验收。iOS 保留 0.2.0 历史交接，无 IPA。离线 schema 2 和三槽愿簿不改写，联机身份／战绩独立保存。

服务端默认两房、16 连接。最终二进制两房／四客户端、射线与分裂弹 60 秒实测 59.43 Hz，回环 P95 ping 18 ms，无持久化错误；更高负载的失败记录及前一构建 180 秒数据分别注明版本。没有默认公网游戏主机、WAN 或长期容量结论。Windows 原生长屏触控夹具不代表 Android 真机。

[联机交付与限制](../40-online-delivery.md) · [实际交付回执](online-2026-10-11/delivery.json) · [实机 GIF](online-2026-10-11/media/duel-native.gif) · [服务端运维](../../../server/README.md) · [APK 核对](online-2026-10-11/android.json) · [包体一致](online-2026-10-11/package-parity.json)

此前 0.2.3 的 368 项移动、282 项屏幕矩阵保留为[明确版本的历史记录](online-2026-10-11/baseline-0.2.3/current-product-status.json)；不是 0.3.0 新复测。未更改的动作与掉落原生逐帧证据保留原构建身份，本轮重新核对其实际编译纹理。

隐私政策 **1.4** 已公开到 [xhz.sidcloud.cn](https://xhz.sidcloud.cn/privacy-policy)，主体 **吴国黎**，邮箱 **carzyg@outlook.com**；新联机范围、所选服务、恢复／期限及离线愿簿不上传已同步，13 页现行 Word 逐页核对，11 项匿名 HTTPS 检查均返回 200。

本轮无 Docker、WSL、虚拟化或浏览器。仍需物理 Android／手柄、长期平衡、真实 WAN 与目标主机长时运行，以及发行签名／iOS 验收。

发布状态：**v0.3.0-alpha.1 已公开**，标签提交 `9755f28c5e43167d1ca823ac4abc00522fafba7a`，6 个附件已逐一通过 GitHub 完整 SHA-256 与大小核验；8 项匿名 HTTPS 检查通过。见[发布回执](../../releases/v0.3.0-alpha.1.publication.json)与[公开访问记录](../../releases/v0.3.0-alpha.1.https.json)。
