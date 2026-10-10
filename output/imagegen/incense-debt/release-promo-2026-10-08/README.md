# 香火债 / Incense Debt · 发布 Banner 与海报

2026-10-08。当前发布版本：v0.2.0-alpha.1。

主角直接取自当前游戏的纸偶肖像，保留原图脸、椭圆眼、红绳、红衣、铜香炉与木版纹理。图标为不透明的纸偶方图；LOGO 为透明的纯“香火债”中文字标。场景背景由指定 Sub2API / gpt-image-2.5 / high 生成，中文字标采用已有授权字体精确排版。

## 横版 Banner

2560×1080px，适合发布页头图、官网首屏和宽幅宣传。左侧仅“香火债”标题，右侧同源纸偶；玉灰庙宇、朱绳、纸灯和香火余烬连接两侧。背景裁切排除了门楣上类似铭文的图案。

![横版 Banner](banner-preview.png)

## 竖版海报

2160×3240px，2:3 构图，300dpi 元数据。顶部仅“香火债”标题，完整纸偶居中，庙门与灯火形成纵向舞台；没有标语、玩法、平台、版本或英文副标题。按 300dpi 对应约 18.3×27.4cm；文件为 RGB。

![竖版海报](poster-preview.png)

两种主图均提供 PNG、JPG、WebP；layers/ 保存背景、遮罩、纸偶、标题分层 PNG 与原始纸偶抠图，prompts/ 保存实际背景请求。仅标题文字层参与成稿；游戏 LOGO 和应用图标分开交付。

## 文件与排版规格

| 内容 | 主文件 | 配套文件 |
| --- | --- | --- |
| 应用图标 | IncenseDebt-app-icon-1024.png | 1024×1024，RGB，不透明背景 |
| 正式 LOGO | IncenseDebt-logo-1024.png | 1024×1024，RGBA，透明背景，仅“香火债” |
| 横版 Banner | IncenseDebt-banner-2560x1080.png | 同名 JPG、WebP；banner-preview.png |
| 竖版海报 | IncenseDebt-poster-2160x3240.png | 同名 JPG、WebP；poster-preview.png |
| 可编辑分层 | layers/banner-*.png、layers/poster-*.png | 背景、阅读遮罩、角色、文字四层；另有原始纸偶透明抠图 |

Banner 以左侧标题、右侧完整纸偶安排构图；海报以顶部标题、中段完整角色与灯火纵深安排构图。画面中的唯一文字是游戏名“香火债”。预览图与所有 PNG/JPG/WebP 成稿采用同一规则。

字标使用得意黑 Smiley Sans；字体沿用工程中已有的授权文件，许可证保存在 licenses/。配色为煤墨 #171E20、纸米 #F0DFC0、朱红 #BC3C2F、香火金 #E9A34B、灰玉 #9DD6BF；庙宇、红绳、空白愿纸和余烬来自既有世界设定。

背景源图的实际尺寸分别为 1916×821 和 1024×1536；输出图在最终排版时统一缩放到交付尺寸。纸偶保留原始肖像 RGB，仅提取透明轮廓，并保留折纸披片。中文文字由字体排版，背景生成不承担文字绘制。生成请求、源图尺寸和哈希记录在 generation-report.json；成品与来源记录在 media-manifest.json。

发布图片不含宣传语、玩法短语、英文名、平台字样、版本标识或水印。版本与玩法说明保留在发布页的文字栏，不叠入图片。

IncenseDebt-publishing-artwork.zip 收录上述素材、原始背景、分层、提示词与清单；安装包单独交付，完整交付索引见 release-delivery-index.json 与 docs/incense-debt/29-release-promo-assets.md。

## English

The 2560×1080 banner and 2160×3240 poster retain the approved paper spirit. Their only lettering is 香火债. The separate logo is a genuine transparent title-only PNG; the application icon is fully opaque. PNG, JPG, WebP and editable layers are included.
