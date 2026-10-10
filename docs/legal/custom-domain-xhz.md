# 《香火债》隐私站点自定义域名

配置日期：2026-10-09（Asia/Taipei）。

`xhz.sidcloud.cn` 已添加到用户 Sidcloud 团队的 Vercel 项目 `xhz-privacy-policy`，绑定生产环境，无重定向。当前已通过域名所有权验证，DNS 配置有效：`verified=true`、`misconfigured=false`。域名 DNS 由阿里云／万网的 `dns19.hichina.com`、`dns20.hichina.com` 托管。

正式账户站点已部署，以下自定义域名地址经无登录 HTTPS 请求核验可访问：[https://xhz.sidcloud.cn/privacy-policy](https://xhz.sidcloud.cn/privacy-policy)。

## 阿里云 DNS 记录

以下两条阿里云 DNS 记录已生效，解析线路为“默认”：

| 记录类型 | 主机记录 | 记录值 | TTL |
| --- | --- | --- | --- |
| CNAME | `xhz` | `b8cf0b64966925c2.vercel-dns-017.com` | 600 秒／10 分钟 |
| TXT | `_vercel` | `vc-domain-verify=xhz.sidcloud.cn,42f871ce9098ba0f3cdf` | 600 秒／10 分钟 |

CNAME 指向的完整目标为 `b8cf0b64966925c2.vercel-dns-017.com.`，来自本项目实际配置查询的首选推荐值。阿里云面板中记录值填写表内形式即可，无需 `https://` 或路径。

公开 DNS 查询已确认 `_vercel` 下同时保留本项目及另一个项目的 TXT 验证值。后续维护请保留这些记录；TXT 值作为一整段填写，不手动添加引号。主机记录使用 `xhz` 和 `_vercel`，对应完整名称分别为 `xhz.sidcloud.cn` 与 `_vercel.sidcloud.cn`。

## 生效与验证

2026-10-09 已执行域名验证，并重新部署正式生产版本。部署 ID 为 `dpl_3Kmq6y9VfVB4QiJUYv7NAeS4KhEj`，Vercel 状态为 `READY`，生产别名为 `https://xhz.sidcloud.cn`。所有权与配置状态可在 [Vercel 项目域名设置](https://vercel.com/sidcloud/xhz-privacy-policy/settings/domains)查看。

最终访问入口为 [首页](https://xhz.sidcloud.cn/)和 [隐私政策](https://xhz.sidcloud.cn/privacy-policy)；`/privacy`、`/versions/2026-10-08` 及原 Word 下载路径也保留。2026-10-09 01:07:15（Asia/Taipei）的七项无认证 HTTPS 核验全部返回 200；正文含十章、指定邮箱及开发者署名，下载 Word 与已审核版本 SHA 一致。随后本机不使用代理直连 `/privacy-policy` 也返回 200，TLS 证书校验启用。

维护者可使用已登录的 CLI 手动复查：

```powershell
npx vercel@62.7.0 api /v9/projects/xhz-privacy-policy/domains/xhz.sidcloud.cn/verify --method POST --scope sidcloud
npx vercel@62.7.0 api '/v6/domains/xhz.sidcloud.cn/config?projectId=prj_OmWFMinlYVl8hu0TekuEmERmAuld' --scope sidcloud
```

配置参考：[Vercel 自定义域名说明](https://vercel.com/docs/domains/working-with-domains/add-a-domain)、[项目域名 API](https://vercel.com/docs/rest-api/projects/add-a-domain-to-a-project)。项目绑定和 DNS 查询回执保存于 `.local-tools/privacy-policy/custom-domain-xhz.json`，账户凭据不写入文档或公开网页。

## 历史内容部署：主体 SIDcloud，政策 v1.2

2026-10-09 根据用户明确指定的应用资料页主体，将隐私政策公开运营主体统一为 **SIDcloud**，保留邮箱 **carzyg@outlook.com**。现行正文、历史页面及两份 Word 下载均已更正。生产部署 ID 为 **`dpl_7rdfFjzQxAMSeKQqouK4DjywEsD1`**，状态 **READY**，继续使用本项目既有生产域名和 DNS 记录。

2026-10-09 **15:31:11（Asia/Taipei）**，首页、`/privacy`、`/privacy-policy`、`/versions/2026-10-09`、`/versions/2026-10-08`、两份 Word 下载、CSS、图标共九项无认证 HTTPS 核验全部返回 **200**。页面运营主体与资料页准确一致，未发现旧名称；公开 Word 下载与重新逐页审核的文件哈希一致。最新验证回执保存于 `.local-tools/privacy-policy/deployment-verified.json`，无需修改 DNS 或重新提供账号。

## 最新内容部署：主体吴国黎，政策 v1.3

按用户最新提供的资料页主体，隐私政策运营主体已统一为 **吴国黎**，邮箱为 **carzyg@outlook.com**。当前与历史网页及两份 Word 下载均同步更新，生产部署 ID 为 **`dpl_DeuGvAwcSSXaQ1RnUMSqgttC5w6Z`**，Vercel 状态 **READY**。

2026-10-09 15:51:09（Asia/Taipei）的九项无认证 HTTPS 核验全部返回 **200**，正文署名准确一致，公开 Word 下载与逐页审核文件哈希一致。访问地址为 [隐私政策](https://xhz.sidcloud.cn/privacy-policy)。现有域名及 DNS 记录继续生效；托管项目的 Sidcloud 团队名称不作为政策主体。最新生产与核验回执位于 `.local-tools/privacy-policy/production-deployment.json` 和 `.local-tools/privacy-policy/deployment-verified.json`。
