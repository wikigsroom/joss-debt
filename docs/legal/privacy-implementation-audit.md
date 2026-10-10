# 《香火债》隐私条款与实现核对记录

最新修订：2026-10-09，政策 v1.3，运营主体 **吴国黎**，与用户最新指定的应用资料页主体一致。本篇原始核对基于 Windows / Android 0.2.0 和公开标签 `v0.2.0-alpha.1`。下文旧构建、旧日期、旧署名与旧回执保留为历史记录；最新主体修订见文末，当前软件修订见第 33 篇。这是供维护者复查的实现说明；对玩家公开的条款由 `privacy-policy-content.json` 统一生成 Word、Markdown 和静态网页。

## 与用户模板的对应

保留模板的温馨提示、日期、适用范围、十章顺序、权限清单与第三方清单。原模板是一般联网游戏模板，其中注册、手机号与密码、实名认证、广告、充值、在线反作弊、关联公司共享和统一中国境内存储等描述均没有直接套用到本游戏。

Word 在原始 DOCX 包内替换条款正文与两张表，保留原 A4、页边距、字体、页脚页码、表格列宽和编号定义；补充 Title 与导航标题语义。原模板未修改。参考文档 SHA-256：`662473e9abc64942e91a57dfeca7248c53883468805a658405b5c5af8e790a20`。

## 可核对的事实

| 事项 | 实际情况 | 实现证据 |
| --- | --- | --- |
| 游戏版本与保存位置 | 自定义用户目录 IncenseDebt；Windows 默认 `%APPDATA%\IncenseDebt` | `game/project.godot` 的 `config/version`、`config/use_custom_user_dir`、`config/custom_user_dir_name` |
| Android 权限 | 实际 APK 仅 VIBRATE；没有 INTERNET；`allowBackup=false` | `aapt2 dump permissions` 与 `aapt2 dump xmltree ... AndroidManifest.xml`；同时核对 `game/export_presets.cfg` |
| 账号、联网与广告 | 生产 GDScript 未接入注册、登录、支付、广告、分析、云存档或联网通信 | 搜索 `HTTPRequest`、`HTTPClient`、`WebSocket`、`ENet`、常见统计或广告 SDK；区分 QA 脚本与产品代码 |
| 愿名 | 愿簿中的可选本地输入，最多 12 字符，不是联网账号 | `game/scripts/ui/hub_ui.gd`，`wish.max_length=12`；MetaProgress 保存 |
| 三个存档槽位 | 本地愿簿、设置、成就、成长与进行中的单局；有日志、索引和恢复副本 | `game/scripts/core/save_slots.gd` 与保存实现 |
| 单局观察日志 | 普通模式结算时自动追加到本机 `run_telemetry.jsonl`；无上传、无固定轮转期限、无独立关闭开关 | `game/scripts/core/run_telemetry.gd` 及 run-end 调用；不将源码中含糊的 opt-in 注释当成用户主动开启机制 |
| 引擎运行日志 | 本机 `logs/godot.log` 及轮换文件；当前日志含引擎与图形渲染信息，无自动上传 | 核对真实应用数据目录下文件及诊断类别，不公开用户原始日志内容 |
| 剪贴板 | 用户点击复制或粘贴才操作；导入校验、预览和确认 | `game/scripts/ui/save_transfer_ui.gd`、种子复制 UI |
| 文件导入导出 | 用户主动选择文件；客户端本地处理；不扫描整盘 | 存档传递 UI 的 FileDialog 和 `save_transfer.gd` |
| 文件安全 | 校验、压缩与 Base64 编码提供格式/完整性功能，不能称为保密加密 | `save_transfer.gd`、SaveStore 校验与恢复逻辑 |
| 触觉反馈 | Android 普通振动权限；无危险权限弹窗；游戏设置可关闭 | `game/scripts/core/haptic_feedback.gd` 的 handheld/controller vibration |
| 数据删除 | Windows 删除应用数据文件夹；Android 系统清除数据或卸载；手动导出副本另行删除 | 本机目录结构与实际 APK 的自动备份设置；未编造游戏内账号注销或一键清空功能 |
| 网页 | 独立静态政策页；没有脚本、表单、分析、远程字体或玩家数据库 | `sites/privacy-policy` 的 HTML/CSS 与 CSP 配置；实际托管请求信息另作说明 |
| 开发美术工具 | 未作为玩家数据 SDK 集成 | 开发阶段素材生成与客户端运行的数据通道区分 |

实际 Windows 可执行文件 SHA-256：`51b896b4c3deb5a0bb197c44210f5bdd72e95cc216a4dd0961fedd4edee364d9`。

实际 Android APK SHA-256：`69b9e03965780e8f83babce04e31413057edcd4549965541d2996131980c535b`。

## 文本的法律及托管依据

- [中华人民共和国个人信息保护法（工信部官方文本）](https://www.miit.gov.cn/zwgk/zcwj/flfg/art/2022/art_04a0f1fb5df244e39688fd5372623a8d.html)：告知、最小必要、保存期限、权利、儿童信息和境外提供等规则；特别是第十七条要求告知处理者名称及联系方式。
- [Vercel Privacy Notice](https://vercel.com/legal/privacy-notice)：托管服务可能涉及终端访问 IP、系统及请求信息、服务生成的数据和全球基础设施。因此网页与离线游戏分开说明，不使用“完全不涉及个人信息”或“所有数据只留在中国境内”的绝对表述。

## 构建、检查与部署

使用 Codex bundled Python 执行 `tools/legal/build_privacy_policy.py`。生成源为 JSON，三种公开格式使用相同条款内容。运营者公开署名、联系邮箱以及公司适用的注册地址通过本地 operator JSON 提供；`confirmed_for_publication` 表示用户已经提供或明确授权拟定这些公开内容。缺失时只能生成明显标注的本地草稿。本次用户指定 `carzyg@outlook.com`，并明确授权其余内容自行拟定及公开发布；署名采用已核实的游戏仓库所有者公开名称 `wikigsroom（《香火债》开发者）`，按独立开发者填写，没有编造公司名称、注册信息或地址。

`tools/legal/render_docx_native.py` 仅替换 packaged documents renderer 的 PDF 转换步骤：用原生 Microsoft Word COM 以只读方式转换，接着用原 packaged renderer / Poppler 栅格化每一页。Word 创建的实例在 finally 中关闭。没有调用 Docker、WSL 或其他虚拟化环境，也没有修改用户模板。

`tools/legal/deploy_privacy_policy.py` 检查真实信息、Word 逐页审核 SHA、下载文件一致性和七个允许上传的静态文件。`.vercel` 的凭据及所有 QA 文件均排除在上传、Git 和公开页面之外。部署后的 HTML、Word、CSS、图标及政策路径使用无认证 HTTPS 请求核验，不能将受登录保护的地址当成可访问的公开链接。

Vercel 已有 CLI 凭据失效；浏览器连接工具在初始化阶段报路径错误，本次没有打开任何浏览器标签页。最终正式内容已通过原生 Vercel CLI 62.7.0 的官方 `--temporary` 流程发布。首次公开检查发现根路径及别名返回 404，已将它们明确映射至可访问的版本化正文路径，并在同一项目重新部署。当地默认 DNS 无法直接连接 `vercel.app`，最终使用系统已配置的网络代理完成 HTTPS 请求核验；未修改系统网络设置，未跳过 TLS 证书校验，未向公开页面发送认证信息。

首次公开地址为 `temporary-flying-harp-h93w5pm.vercel.app`，属于一小时匿名临时部署，服务端到期时间为 **2026-10-08 16:25:43（UTC+8，Asia/Taipei）**。此历史地址现显示部署已过期；旧回执与认领信息已保存在私有备份中。

2026-10-09 应用户绑定 `xhz.sidcloud.cn` 的要求，完成 Vercel 账户登录并将同一份已审核条款发布到用户的 Sidcloud 团队项目 `xhz-privacy-policy`。当前正式公开地址：[《香火债》隐私政策](https://xhz.sidcloud.cn/privacy-policy)。最新无认证 HTTPS 核验时间为 2026-10-09 01:07:15（UTC+8），七项入口均返回 200，下载 Word 哈希与正式审核版本一致。随后本机无代理直连隐私政策也返回 200，TLS 证书校验启用。该生产部署已归属用户账户。

用户配置 DNS 后，公开查询确认 CNAME 与本项目 TXT 均生效。已执行项目域名验证，Vercel 返回 `verified=true`；配置查询返回 `misconfigured=false`，无 DNS 冲突。正式重新部署得到 `dpl_3Kmq6y9VfVB4QiJUYv7NAeS4KhEj`，状态为 `READY`，自定义域名已成为生产别名。具体解析记录与状态见 [自定义域名说明](custom-domain-xhz.md)。

已完成的文档检查：正式 Word 共 12 页，已重新逐页阅读；原 A4 区段与未改动的 DOCX 包部件保持一致，十章正文与两张表内容完整，署名和邮箱已填入，草稿标记已清除。正式 Word SHA-256：`7d1609d4ad51d62234328edc79ca55d7634788a096a2da8020787bfff2b4d1c8`。公开的根路径、`/privacy`、`/privacy-policy`、版本路径、Word 下载、CSS 和纸偶图标共七项均返回 HTTPS 200；正文包含全部十章及授权的署名、邮箱，安全响应头生效，下载 Word 与逐页审核版本校验一致。公开核验时间：2026-10-08 15:41:31（UTC+8）。浏览器视觉检查仍不可用，不将网络核验称为浏览器视觉验收。状态、渲染与无认证核验回执保存在 `.local-tools/privacy-policy/`。


## 2026-10-09 v1.1 主体修订（历史记录，已由 v1.2 替代）

按用户指定，将运营者名称统一为 **`wikigsroom`**，保留邮箱 **`carzyg@outlook.com`**。本地生成配置、JSON 正文源、Markdown、Word 下载、HTML 主体及页首公开署名均同步修正；当前正文不含“吴国黎”。不沿用早期署名的括号说明作为主体名称。

政策版本 v1.1，更新和生效日期 2026-10-09；根路径、`/privacy`、`/privacy-policy` 指向 `/versions/2026-10-09`。原政策版本保留独立归档。正式 Word 位于 `output/legal/incense-debt-privacy-policy-2026-10-09.docx`，原生 Word / Poppler 渲染 12 页，已逐页阅读。SHA-256：`74f1ee17a81f78d28bb4c7deb628dc4902d1570bd49cd8919569b1291032b063`。

已生产部署至 Sidcloud 的 `xhz-privacy-policy` 项目，部署 ID `dpl_AuCQUVkbQ5SastMnLsGCE9CVGF78`；公开地址：[隐私政策](https://xhz.sidcloud.cn/privacy-policy)。2026-10-09 04:44（Asia/Taipei）重新执行无认证 HTTPS 检查，根路径、两个政策别名、当前版本、Word 下载、CSS、图标共七项均返回 200，下载 Word 哈希与逐页审核文件相同。核验使用普通网络请求，启用 TLS 验证；不称为浏览器视觉或手机验收。

当前生产回执为 `.local-tools/privacy-policy/deployment-verified.json`；逐页审核、原生渲染和部署凭据分别保存，凭据不进入公开站点。本轮没有使用浏览器、Docker、WSL 或模拟器。网站 README 与实现说明被上传白名单排除，修改它们不会改动玩家公开正文。

## 2026-10-09 v1.2：SIDcloud 主体修订（历史记录，已由 v1.3 替代）

用户明确要求隐私网页主体与资料页公司主体 **SIDcloud** 一致。因此将公开运营主体准确名称统一为 **SIDcloud**，邮箱保持 **carzyg@outlook.com**。本地配置的 `organization` 表示已确认的公开主体名称，不编造未提供的企业登记全称或注册地址。本次只更正主体名称，个人信息处理方式保持不变。

政策 v1.2 的更新时间和生效日期均为 2026-10-09。JSON 正文源、生成器、Markdown、现行 HTML、历史 HTML、两份 Word 下载均同步修正。历史 v1.0 条款保持原日期，并附 2026-10-09 主体勘误说明；更正前原件保存在公开目录之外的私有备份。交付状态生成器从已构建和已核验回执读取名称及版本，不再将旧署名写死。发布核验要求各公开页面主体完全一致，且禁止公开 HTML 和 DOCX 出现已退役署名。

现行 Word 与历史 Word 各 12 页，共 24 页，经原生 Microsoft Word / packaged rasterizer 重新渲染，全部逐页查看。现行 Word SHA-256：`95c4355e33828e8339c55a7101035c876cffd5a7c7328b0f9913bc9dffcd6599`。审核回执按两个文档各自的 SHA 绑定，防止用旧审核结果发布新文件。

已生产部署到 Sidcloud 的 `xhz-privacy-policy` 项目：部署 ID **`dpl_7rdfFjzQxAMSeKQqouK4DjywEsD1`**，状态 **READY**，生产域名 **https://xhz.sidcloud.cn**。2026-10-09 **15:31:11（Asia/Taipei）** 执行九项无认证 HTTPS 核验：首页、两个政策别名、当前和历史版本页、两份 Word 下载、CSS、图标均返回 **200**。五个 HTML 正文均含准确的 SIDcloud、指定邮箱、十章条款，且未发现旧主体；两份公开下载均与逐页审核文件 SHA 一致。TLS 校验启用，无需登录可访问。

公开入口：[《香火债》隐私政策](https://xhz.sidcloud.cn/privacy-policy)。最新公开核验回执位于 `.local-tools/privacy-policy/deployment-verified.json`，两份 Word 的逐页审核记录位于 `.local-tools/privacy-policy/visual-review.json`。本次使用原生 Windows 工具，没有使用浏览器、Docker、WSL 或其他虚拟化环境。

## 2026-10-09 v1.3：按最新资料页主体统一为吴国黎

按用户最新明确要求，公开运营主体准确名称统一为 **吴国黎**，替代此前署名；邮箱继续使用 **carzyg@outlook.com**。本地配置按提供的自然人姓名记录为 `individual`，公开条款不编造企业登记信息。本次只更正主体名称及版本说明，原信息处理条款保持一致。

当前版本 v1.3，更新与生效日期为 2026-10-09。主体配置、JSON 正文源、Markdown、现行页面、历史页面及两份 Word 下载均同步更正。历史 v1.0 条款保持原日期，附 2026-10-09 主体勘误说明。发布核验按已确认的主体逐页检查，旧署名会阻止发布；域名 `xhz.sidcloud.cn` 用于站点访问，不作为主体署名。

现行与历史 Word 各 12 页，共 24 页，已原生渲染并逐页查看；署名、邮箱、章节、表格、分页无缺字、重叠或裁切。现行 Word SHA-256：`cb1442056b9659201fa816a73e0445a41a30f50f52176c3be31faacf459406bf`。每份下载的审核结果分别绑定文件 SHA，旧回执不能用于新文件。

已正式部署至 `sidcloud/xhz-privacy-policy`，部署 ID **`dpl_DeuGvAwcSSXaQ1RnUMSqgttC5w6Z`**，状态 **READY**，生产地址 **https://xhz.sidcloud.cn**。2026-10-09 15:51:09（Asia/Taipei）完成九项无认证 HTTPS 核验，全部返回 **200**；五个 HTML 页面均显示吴国黎，未发现旧主体署名，两份公开下载与逐页审核文件的哈希一致。TLS 校验启用，无需登录即可访问。

公开入口：[《香火债》隐私政策](https://xhz.sidcloud.cn/privacy-policy)。最新生产部署及公开验证回执分别保存在 `.local-tools/privacy-policy/production-deployment.json` 和 `.local-tools/privacy-policy/deployment-verified.json`。本次使用原生 Windows、Word 和 Vercel CLI，没有使用浏览器、Docker、WSL 或虚拟化环境。
