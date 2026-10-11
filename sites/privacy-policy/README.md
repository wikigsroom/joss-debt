# 《香火债》隐私政策网页

当前政策 **v1.6 / 2026-10-11**，覆盖 0.5.0 官方共灯自动连接与对灯。主体 **吴国黎**、邮箱 carzyg@outlook.com；新加坡托管，普通断线自动重试，离线愿簿不上传。主菜单共灯入口前有处理告知，退出停止联机。

公开地址：[隐私政策](https://xhz.sidcloud.cn/privacy-policy)。既有 Sidcloud 账户项目 xhz-privacy-policy，生产部署 dpl_5gimqpYnJ2B85tV7udoUrBHzRpYk。共 15 项无认证 HTTPS 核验通过，公开 Word 与原生 Word 14 页审核产物摘要一致。旧 1.5 HTML／Word 独立归档，旧日期和 1.4 保留。

此 README 被 .vercelignore 排除，不上传为玩家页面。部署只允许静态文件，不含生成工具、日志、SSH／签名密钥或凭据。回执在 .local-tools/privacy-policy/deployment-verified.json；公开副本在 docs/incense-debt/reports/public-online-2026-10-11/privacy-https.json。

## 完成运营者信息

本次已将用户指定和授权的公开信息写入 `.local-tools/privacy-policy/operator.json`：

```json
{
  "operator_name": "吴国黎",
  "contact_email": "carzyg@outlook.com",
  "operator_type": "individual",
  "registered_address": "",
  "confirmed_for_publication": true
}
```

此处的 `individual` 记录用户明确提供的公开姓名吴国黎；页面按该姓名署名，不将托管团队或仓库账号作为运营主体。需要载入完整企业登记信息时使用 `company` 并填写实际注册地址。`confirmed_for_publication` 只在用户已给出或明确授权公开信息后填写 true；不得伪造法律身份或用示例邮箱代替。

## 构建与复查

在仓库根目录用已加载的 bundled Python 执行：

```text
tools/legal/build_privacy_policy.py --operator .local-tools/privacy-policy/operator.json
tools/legal/render_docx_native.py output/legal/incense-debt-privacy-policy-2026-10-11.docx --output_dir .local-tools/privacy-policy/policy-render-final --emit_pdf
```

检查新渲染的每一页，确认吴国黎、邮箱、日期、章节、表格及分页均正常。将所有公开 Word 文件的 SHA-256、页数与逐页审核结果记录到 `.local-tools/privacy-policy/visual-review.json` 的 `documents` 字段；已有文件的审核 SHA 不能用于新生成的文件。文档渲染用原生 Word 和 packaged rasterizer，不使用 Docker 或 WSL。

## Vercel 发布

Vercel CLI 62.7.0 已完成账户登录，本目录已关联 `sidcloud/xhz-privacy-policy`。链接项目时产生的账户环境凭据已移入 `.local-tools/privacy-policy/`，不进入上传目录或 Git。后续更新应使用已关联项目的正式生产部署。

```text
tools/legal/deploy_privacy_policy.py --check-only
npx vercel@62.7.0 deploy --prod --yes --scope sidcloud --cwd sites/privacy-policy
```

第二条命令会将 13 个已检查的静态文件（含三份历史政策归档）更新至正式生产项目。前置检查要求完成运营者信息及 Word 逐页审核；`.vercel`、`.env*`、本机凭据和 QA 文件均排除上传。随后使用发布工具的 `--verify-url https://xhz.sidcloud.cn` 模式核验公开入口、Word 下载及其他资源，不使用登录凭据访问公开站点。

如当地 DNS 不能直连 Vercel，可通过 `--proxy` 指定已有 HTTP 代理进行公开检查，保持 TLS 证书验证。只复查现有部署时使用 `--verify-url`，避免再次上传。当前 `vercel.json` 的三个入口均指向 `/versions/2026-10-11`，其正文与 `index.html` 相同。

现行 Word 13 页，v1.4 历史 Word 13 页，另两份历史 Word 各 12 页，逐页审核分别绑定其文件哈希。发布核验检查三个入口、四个版本页、四份 Word 下载、CSS 及图标；页面主体必须与已确认配置完全一致。自定义域名的项目绑定与 DNS 记录见 `.local-tools/privacy-policy/custom-domain-xhz.json`。`deploy_privacy_policy.py` 无参数模式保留此前匿名临时部署实现，正式项目更新使用上述生产部署命令。Vercel 仅托管静态条款，不承担游戏 WebSocket 服务。

页面路径：`/`、`/privacy`、`/privacy-policy`；现行版本：`/versions/2026-10-11`；现行 Word：`/downloads/incense-debt-privacy-policy-2026-10-11.docx`。历史日期 `2026-10-08`、`2026-10-09` 及 0.3.0 对应的 `/versions/2026-10-11-v1.4` 同样可访问；旧 v1.4 Word 下载名以 `-v1.4.docx` 结尾。
