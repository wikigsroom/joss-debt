# 方向 02｜水墨朱砂符 UI 系统

本文件是《香火债》后续 UI 的唯一视觉装配约定。它把已选中的「02｜水墨朱砂符」方向落实为可复用的 Godot 主题、素材目录、页面层级和验收规则。所有新页面先遵守本文件，再添加页面特有内容；页面特有内容不得重新发明颜色、圆角、字体或焦点状态。

## 1. 视觉目标

玩家打开菜单时应先看到一张温暖的宣纸，再看到被墨块托住的操作。纸面负责承载层级和留白，墨块负责交互，朱砂只负责当前选择、危险、确认和关键奖励。界面应像一本可以翻阅的愿簿，而不是把游戏场景硬套上一层半透明黑色窗口。

方向 02 的固定关系如下：

| 层 | 视觉职责 | 当前实现 |
| --- | --- | --- |
| 背景层 | 深褐墨场景、低对比度环境、暂停时压暗 | `UI.BACKGROUND` 与游戏渲染器 |
| 页面层 | 暖宣纸、边缘残墨、梅枝、符纸和留白 | `menu-background.png`，由 `main.gd.panel()` 自动加载 |
| 卡片层 | 墨色圆角牌、纸张边缘或局部笔触纹理 | `UI.SURFACE`、`UI.INSET`、`brush-panel-ink.png` |
| 选择层 | 朱砂笔触、细金线、轻微浮起阴影 | `UI.ACCENT`、`button_styles()`、`UI.select()` |
| 反馈层 | 玉青成功、金色奖励、朱红危险、短促缩放与音效 | `UI.JADE`、`UI.GOLD`、`UI.SEAL` 与现有动效系统 |

## 2. 色彩与字体令牌

颜色只从 `game/scripts/ui/game_theme.gd` 取值。新脚本不要写新的十六进制颜色；若需要语义色，先增加令牌并在本文件登记。

| 令牌 | 色值 | 用途 |
| --- | --- | --- |
| `BACKGROUND` | `#181513` | 游戏场景和暂停遮罩底色 |
| `SURFACE` | `#2C2723` | 墨色卡片与按钮 |
| `INSET` | `#211D1A` | 更深的内凹区域 |
| `LIFTED` | `#40342D` | 悬停、浮起和次级牌面 |
| `EDGE` | `#806B57` | 旧纸边、分割线、弱边框 |
| `CANVAS` | `#EADCC2` | 宣纸页面 |
| `CANVAS_DARK` | `#D6C2A0` | 纸张阴影和次级纸片 |
| `TEXT` | `#F4E6CA` | 墨色牌面上的正文 |
| `MUTED` | `#C2AB8B` | 深色场景中的次级文字 |
| `PAPER_MUTED` | `#765B43` | 宣纸上的次级文字，避免低对比度 |
| `ACCENT` | `#B74432` | 当前按钮、确认、伤害和危险 |
| `SEAL` | `#8D3028` | 印章、终止状态和强危险 |
| `JADE` | `#A5C7AE` | 成功、可用、友方和状态良好 |
| `GOLD` | `#DDB574` | 奖励、稀有、成就和经济 |

字体继续使用已随项目授权并通过 QA 的 `IncenseRounded-Medium.ttf`、`IncenseRounded-Bold.ttf` 与 `SmileySans-Oblique.ttf`。中文缺字由 `NotoSansSC.ttf` 回退。标题用展示体，正文用圆体，数字和键位保持圆体；不要在页面中混入系统默认字体。

## 3. 素材清单与生成约束

素材均由 Sub2 image generation 生成后再导入 Godot，源图和提示词留在 `output/imagegen/ink-ui-2026-10-13/` 与 `output/imagegen/ink-ui-2026-10-14/`，运行时副本在 `game/assets/ui/ink/`。源图允许迭代，运行时文件名和语义不可随意改动。

| 文件 | 作用 | 运行时接入 |
| --- | --- | --- |
| `menu-background.png` | 16:9 宣纸主页面，中央留白、黑墨枝、朱红梅花和符纸 | 纸面 `panel()` 的首选材质 |
| `paper-wash-background.png` | 纸面安全回退，适合小尺寸页面或素材缺失时 | `menu-background` 不可用时自动回退 |
| `brush-panel-ink.png` | 黑色干笔触长牌 | 墨色 `panel()` 的低透明度纹理 |
| `cinnabar-focus-stroke.png` | 朱砂干笔触 | 供后续聚焦卡片、确认态使用 |
| `paper-panel.png` | 带毛边的纸牌 | 收藏详情、说明卡片的可选材质 |
| `brush-focus-frame.png` | 墨线焦点框 | 键盘焦点和选中牌的可选叠层 |
| `cinnabar-seal-round.png` | 几何朱砂印章 | 结算、成就、重要确认的图标材质 |
| `ink-disk-button.png` | 墨圆按钮底 | 紧凑图标按钮和移动端快捷键 |
| `talisman-ribbon.png` | 悬挂符纸 | 页面装饰和节庆主题，不承载文本 |
| `ink-cloud-divider.png` | 云气、梅枝、朱花分隔线 | 所有宣纸页面标题下方的统一装饰 |
| `portrait-frame.png` | 竖向墨线人物框 | 角色选择与图鉴卡片的可选边框 |
| `icons-01.png` | 4×4 生成图标雪碧表 | `UI.ink_icon()` 以 `AtlasTexture` 按语义裁切 |
| `controls-sheet.png` | 控件素材原始雪碧表 | 只作源素材和后续导出依据，不直接铺满页面 |
| `button-kit.png` | 朱砂主按钮、墨色次按钮、悬停/按下/禁用和焦点态素材表 | `game_theme.gd` 的横向 `StyleBoxTexture` 状态 |
| `card-kit.png` | 存档卡、角色卡的墨牌、朱砂选中、禁用灰和宣纸卡素材表 | `game_theme.gd` 的卡片 `StyleBoxTexture`，用于愿簿与角色选择 |
| `button-detail-primary.png` / `button-detail-secondary.png` | 带左侧圆形图标位的长条朱砂/墨色按钮 | 菜单主操作与图标按钮的横向 `StyleBoxTexture` |
| `button-detail-hover.png` / `button-detail-pressed.png` / `button-detail-disabled.png` | 长条按钮的悬停、按下、禁用笔触 | `button_styles()` 的完整状态组 |
| `button-detail-focus.png` | 长条按钮的键盘焦点笔触 | 键盘焦点叠层，保持朱砂边缘 |
| `icon-disk-primary.png` / `ink-disk-button.png` | 图标按钮的整张圆形墨牌；主操作使用朱砂环，返回/工具使用安静墨圆 | `main.gd.icon_button()` 的 `TextureRect` 子层；不做九切拉伸 |
| `button-detail-compact.png` | 紧凑页签和短标签的横向笔触 | 小尺寸操作牌和移动端页签 |
| `tile-ink.png` / `tile-selected-cinnabar.png` / `tile-disabled-ink.png` / `tile-paper.png` | 横向卡片的正常、选中、禁用和宣纸状态 | `compact_card_style()`；避免复用竖向角色卡导致边框变形 |
| `modal-tile-normal.png` / `modal-tile-selected.png` / `modal-tile-disabled.png` / `modal-tile-paper.png` | 设置、布局、辅助等中等尺寸入口的云纹墨牌 | `modal_tile_style()`；修复中等矩形入口回退为纯色圆角块的问题 |
| `title-seal.png` | 标题旁的纵向朱砂印章 | 主菜单标题的 27×48 小型装饰，保持生成纹理比例 |

素材生成提示必须保留以下限制：无可读文字、无品牌标识、中心留白、边缘笔触完整、黑墨与朱砂有明显明度差、透明背景素材必须保留 alpha。图标生成后以 `AtlasTexture` 取区域，禁止用 CSS/矢量重画替代已批准的生成素材。

## 4. 页面层级

菜单层级沿用以撒式「标题 → 愿簿 → 主菜单 → 页面 → 返回」结构，风格调整不改变流程语义：

1. 标题页和愿簿选择：宣纸页面；角色图和存档卡为墨牌；当前存档用朱砂外框。
2. 主菜单：宣纸页面；右侧纵向操作牌；左侧角色纸片；底部资源胶囊和键盘提示。
3. 记录、图鉴、结局、统计、角色成长：宣纸页面；网格卡片使用墨牌；锁定内容使用低亮度和单一锁图标。
4. 暂停、背包、成长、设置、联机：深色墨色模态层；朱砂只强调当前页签、确认和危险操作。
5. 房间内 HUD：沿用深墨场景和小型圆角牌；拾取物、血量、金币、技能冷却必须优先用图标，文字作为辅助。
6. 结果、成就、导入导出和退出确认：优先使用朱砂印章或朱砂边框，让玩家一眼识别“需要确认的状态”。

`MenuFlow.shell()` 已统一创建宣纸页面，并在标题下插入生成的 `ink-cloud-divider`；主菜单标题旁固定使用小型 `title-seal`。`main.gd.panel()` 根据最近的面板边界加载宣纸或墨色笔触材质；嵌套的墨牌和按钮会覆盖页面文字对比规则，避免深色卡片出现黑字。图标按钮使用完整圆形贴图子层，长条图标按钮使用带左侧图标位的 detail 笔触，设置等中型入口使用独立 modal tile，横向卡片使用独立 tile 素材，三者不会互相拉伸替代。

## 5. 交互状态

所有可操作控件必须同时支持鼠标、键盘/手柄焦点和触控的同一语义。键盘焦点必须可见：普通牌为朱砂描边，主操作为浅纸描边；悬停只改变笔触亮度，不移动布局；按下状态缩小阴影并进入更深的朱砂；禁用状态降低饱和度但保留文字可读性。

快捷键在界面底部只显示图标加短词：方向键选择、Enter 确认、Esc 返回、Tab 切换、F1 查看详情。技能选择保持 `1/2/3/4` 数字键闭环，暂停页的成长/记录/设置入口必须能用方向键和 Enter 到达。移动端只显示必要的圆形图标按钮，左侧保留移动摇杆，位移和爆炸技能留在右侧。

## 6. 响应式规则

桌面页面基准为 1280×720，宣纸页面安全区为 `Rect2(64, 42, 1152, 636)`。窄屏或移动端保持横屏内容比例，页面缩放时优先缩小边距和间距，不能让按钮文字或图标互相覆盖。卡片最小触控高为 64 px，移动端为 `mobile_button_height`；图标优先保持正方形区域并使用 `STRETCH_KEEP_ASPECT_CENTERED`。

页面装饰不得遮住按钮命中区。`ink-cloud-divider`、符纸和梅枝只能放在留白区；若屏幕宽度不足，隐藏装饰而保留交互元素和标题。

## 7. 验收清单

- 页面主背景为宣纸或深墨，不能回到旧的绿色/灰色主题。
- 所有新颜色来自 `game_theme.gd`，所有圆角和阴影由统一工厂创建。
- 纸面上的次级文字使用 `PAPER_MUTED`，墨牌上的正文使用 `TEXT`。
- 当前选择、危险、确认和成功状态在 1 秒内能被视觉区分。
- 键盘 QA 的 107 项检查全部通过，尤其是数字技能选择、暂停记录、Tab/F1/Esc 和返回闭环。
- 原生 OpenGL 截图中的菜单、存档、记录、设置、暂停、背包和特殊房间没有素材加载错误。
- 生成素材必须有运行时副本、尺寸记录和源图留档；缺失素材只能走已定义的回退，不得静默使用随机占位图。
- 图标按钮不得用九切拉伸圆形素材；整张圆盘以 `TextureRect` 保持比例，确保图标、边缘和朱砂环不分离。

## 8. 修改顺序

新页面先调用 `MenuFlow.shell()` 或 `main.gd.panel()`，再添加页面内容；需要新装饰时先在 `output/imagegen/ink-ui-2026-10-13/` 或最新日期目录生成并视觉检查，再复制到 `game/assets/ui/ink/` 并运行 Godot 导入。完成后执行键盘 QA 和原生截图 QA，再更新本文件的素材表或验收记录。
