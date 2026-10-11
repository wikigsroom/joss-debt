# 0.5.0 官方联机部署与包体验收

2026-10-11，正式联机版 **0.5.0 / Android code 9**。在 0.4.1 可靠性修复基础上，部署原生 Linux 服务、固定自动连接、整理共灯 UI、完成正式 Android 签名并核对最终发布包。旧版 tag 和附件保持原样。

## 联机复查结论

旧实现存在发送失败不补发、确认缺失永久等待、心跳正常掩盖世界停滞、积压输入跨房间释放、旧进程抢回身份等问题。[0.4.1 审计](43-network-reliability-audit.md)保留 14 类修复、前后复现和 TCP 中转证据；本轮再验证 65 项应用故障，并增加实际公网和线上进程重启验收。

WebSocket 使用 TCP。IP 丢包通常表现为重传延迟、队头阻塞、积压或连接关闭。应用帧主动丢弃不是 IP 层丢包测试；原生 TCP 中转的有序延迟／停滞／切断也不能代表所有运营商网络。

| 故障场景 | 当前处理 | 边界 |
| --- | --- | --- |
| 指令发送失败、确认缺失 | 原编号顺序重试；持久回执避免重复购买／成长 | 750 ms 重试，8 秒未完成则重连；最多 16 个 pending |
| ping 正常但地图停滞 | 状态年龄超过 400 ms 停止输入，2 秒无进展重连 | 公网与共享主机抖动可能触发保护 |
| 移动、技能积压 | 250 ms 无有效输入停止移动／持续射击；1 秒租约过期拒绝 | 过期短按放弃，不能跨场景或暂停代数 |
| 旧快照、旧房间状态 | 连接、房间授权、对局、场景、输入代数、序号校验 | 最新快照确认窗口最多 4 份；合并积压 |
| 普通断线 | 0.5 / 1 / 2 / 4 / 8 秒退避，加 0–200 ms 抖动 | 默认 90 秒恢复；已结算和过期对局不可重开 |
| 第二次断线、确认时序不同 | 清空旧继续确认，双方观察当前恢复代数后确认 | 双方确认前不重新战斗 |
| 重启、检查点损坏 | 完整共享世界与成长；两代注册表引用独立房间文件 | 硬崩溃可丢失最近提交后的尾部 |
| 旧进程接管或覆盖身份 | 持久身份代数、本地保存前核对已提交代数 | token 必须保密；没有账号系统 |

## 本轮修复与实现

固定官方 WSS，旧存档的地址不再覆盖默认；大厅不显示／编辑地址，打开即连接、退出停止。昵称、配装与房间码页在网络鉴权完成时保留控件和键盘焦点，避免回调重建吞掉 Enter。

TextureRect 先设置忽略原图最小尺寸和等比缩放，再绑定纹理，避免 512 像素原图撑大卡片。146 张现有生成图记录透明边界与留白，运行时裁透明边，不重绘原始图像。配装网格、成长卡、三项居中、复制房间码、历史滚动区、偿还按钮统一调整，保留圆角、图标和游戏字体。

线上仅对本游戏 systemd 单元设置 swap=0，降低换页停顿，不改其他应用或全局策略。客户端和 Linux 服务实际共享 37 份一致编译模块。

公网 PvP 测试曾在“回大厅”后、服务器退出确认前寻找房间码。外部测试驱动等待实际确认后通过 32 项；生产字节码不因此变动。布局 fixture 另修正先设置页面再通知状态，避免把上一组偿还页与下一组 PvP 数据混用。失败日志本地保留，这些测试驱动修正不能算生产问题修复。

## 最终包体

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Windows EXE | 1,108,885,112 | `ad63f10b611d53641b483710c63d35539db28aeeec448c71b34b1df57a1e235c` |
| Android APK | 1,022,819,407 | `600ec0d5ef757fbc9f2d50e07fd453ddd668dec3c2fc270006dd5e55923b1d94` |
| Windows server | 110,855,440 | `c7ca5b144f69cc91d3106f5820ff69f9b83aecb4592a2b566c9f1bb1ff1cf905` |
| Linux ELF | 75,106,368 | `1b848e654388fda189b9ac871ef19f391ab166ad9ef684bc4768b621b07c0212` |

线上 ELF 与发布产物摘要一致。ZIP 外层摘要另见 [发布清单](../releases/v0.5.0.manifest.json)，生成时逐个验证 CRC 和解包成员完整摘要。

## 验证分层

[本轮机器证据](reports/public-online-2026-10-11)绑定实际包体。各类检查有重叠，数量不可相加为覆盖率。

| 验证 | 结果与范围 |
| --- | --- |
| 最终 Windows 经官方 WSS | 合作 29 项、PvP 32 项，各 33 张捕获；真实键盘／触控、NPC、门口、成长、断线与共同恢复 |
| 最终 Windows 纯键盘 | 107 项，菜单、三槽、离线成长／商店／特殊房、门口、导入回滚 |
| 原生应用帧故障 | 65 项，发送拒绝、确认丢弃、旧消息、接管与事务；不是 IP 丢包 |
| 实际线上进程重启 | 10 项，两个真实 Session 恢复身份、房间、双方角色／成长／地图，并共同继续 |
| Windows／APK 资源 | 2172 项，90 编译模块、7 数据 JSON、1002 动作图集／24048 姿态目录一致 |
| 客户端／服务器 | 分别与实际 Windows、Linux 包的 37 份共享编译模块一致 |
| 最终包软件布局 | 四种视口、92 页、5998 条断言，按钮分离、触控尺寸、无地址文本、图像比例与视觉复核 |
| Android 实际包 | release、非 debuggable、arm64、minSdk 28、target 36、code 9；旧安装数据继承验证 |
| 原生部署 | 18 项，单元、摘要、回环监听、权限、HTTPS、有效 TLS、证书 timer 与专属续期 hook |

布局的裁剪后可见矩形检查只描述可见范围，不证明所有原始控件完整可见；另有按钮重叠、触控、纹理检查与截图审核。X30 fixture 是 Windows 窗口的尺寸／密度／安全区模拟，**不是 Motorola X30 真机验收**。

## 实测与仍需跟进的风险

两间房、四个正式 OnlineSession，经实际 WSS 连续 **60.399 秒**，4542 份状态、59.8898 Hz、RTT p95 358 ms、状态年龄 p95 184 ms，新鲜可游玩帧约 95.39%，会话错误为零。最大模拟 step 32.51 ms；进程最大帧约 1993.963 ms，包含房间启动阶段，不隐藏这类停顿。

一分钟通过不是 SLA 或长时容量保证。共享主机与公网仍有抖动；无自动恢复的原始 WebSocket 压测器曾发生连接关闭，原因未完全隔离。正式 Session 已通过本轮负载和恢复路径，**不声称永不丢包、断线、卡顿或零回退**。维持两间活跃房间，扩容前补长时负载、不同运营商、休眠／切网与 Android 真机验证。

## Android 升级与隐私

新签名 SHA-256 `6d5f9c73c947f025641d0663f7699f78db6c089c070403e4558afee899ca69a3`，旧签名 `66e1cfbcef2c0251d6d74144e6ac845ad713ec0496a266934645f06ca454708c`。APK 内嵌两代证书链，官方 apksig 校验 API 28、32、33、36，installed-data=true、rollback=false。非 Gradle 模板只经验证修改 Manifest minSdk，再 zipalign／签名；私钥和 DPAPI 密码仅本机保存。优先覆盖升级，卸载会删除私有存档；实体设备实际升级尚待确认。

原生 Linux 部署只新增本游戏服务、目录与域名 vhost，使用现有宝塔 Nginx，回环 18777／18778 经 TLS 公开。独立目录 0700、内存硬限制 256 MiB、swap=0。证书有效至 2027-01-09，续期 dry-run、timer 和专属 reload hook 已验证。[运维说明](../../server/README.md)。

政策 **1.6** 已在 [公开 HTTPS](https://xhz.sidcloud.cn/privacy-policy) 生效：主体 **吴国黎**、邮箱 **carzyg@outlook.com**，说明新加坡服务、自动连接和重试、昵称／匿名身份／操作／IP、14 天清理与不上传离线愿簿。共灯入口前展示告知，菜单可看完整政策，退出停止连接。原模板 Word 用原生 Word 渲染并审核全部 14 页，旧 1.5 HTML／Word 独立归档。

## English

0.5.0 deploys native Linux hosting and fixed automatic WSS connection, preserves input focus during authentication, repairs raster-thumbnail sizing and signs a non-debuggable Android 9+ APK with verified legacy lineage. Actual shipping packages pass the separately recorded cooperative, Duel, keyboard, application-fault, live-restart and compiled-parity checks.

The four-session/two-room WAN minute measures 59.89 Hz and RTT p95 358 ms. It is not an SLA: shared-host/network stalls remain, raw clients without recovery have seen closures with an unresolved cause, and physical Android plus sustained capacity remain pending. Application-frame faults are not IP packet-loss tests; hard crashes can lose the uncommitted checkpoint tail. Privacy 1.6 names 吴国黎 and carzyg@outlook.com and keeps offline saves local. Historical releases and evidence remain intact.
