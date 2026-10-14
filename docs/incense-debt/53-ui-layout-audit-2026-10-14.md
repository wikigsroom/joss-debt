# UI 版式与文字边界复查（2026-10-14）

本轮针对主菜单、角色页、成长页、愿簿传递、故事阅读、暂停页、道具选单、供物选择、结算复盘、路线地图、设置页和移动端触控页做了统一复查。目标是让文字始终留在自己的安全框内，让按钮保持设计稿的横向比例，同时保留移动端足够的触控面积。

## 已修复的问题

| 问题 | 修复位置 | 处理方式 |
| --- | --- | --- |
| 标签文字被字体真实行高裁掉 | [`main.gd`](../../game/scripts/main.gd) | `label()` 根据实际字体度量缩小字号、计算最大行数、启用省略裁切，并为多行内容设置受限自动换行。 |
| 长按钮标题越过笔刷边缘 | [`main.gd`](../../game/scripts/main.gd) | `fit_button_text()` 测量当前字体和可用宽度，在保留 13px 可读下限的前提下动态缩小按钮字号；按钮仍保留完整的点击区域。 |
| 手机端普通按钮被统一拉成 80/90px | [`main.gd`](../../game/scripts/main.gd) | 普通按钮仅保留 64px 触控下限；确实需要大触控区的导航、确认和摇杆布局仍由页面显式指定尺寸。 |
| 笔刷贴图在长按钮上纵向变形 | [`game_theme.gd`](../../game/scripts/ui/game_theme.gd) | `brush_style()` 改为九切贴图，锁定笔刷四边的像素边界，只拉伸中段。 |
| 暂停页和供物选择页的动作条过高 | [`modern_ui.gd`](../../game/scripts/ui/modern_ui.gd) | 移动端动作条封顶 72px，避免 90px 视觉条带挤压内容。 |
| 成长记录右侧摘要压到完成徽章 | [`modern_ui.gd`](../../game/scripts/ui/modern_ui.gd) | 摘要框左移并预留徽章安全区。 |
| 移动端通知条覆盖角色/存档/替换页底部按钮 | [`main.gd`](../../game/scripts/main.gd) | 非战斗页的临时通知移到顶部 32px 轻量条；战斗页仍使用战斗 HUD 的通知位置。 |
| 故事阅读和愿簿粘贴页无法用手指拖动长文本 | [`narrative_reader.gd`](../../game/scripts/ui/narrative_reader.gd)、[`touch_text_scroll.gd`](../../game/scripts/ui/touch_text_scroll.gd) | 为中文段落按实际宽度计算最小高度，并补上触摸拖动、惯性和边界钳制。粘贴文本仍可编辑，滚动层只在超过拖动死区后接管手势。 |
| 键盘提示压在底部动作区 | [`keyboard_navigation.gd`](../../game/scripts/ui/keyboard_navigation.gd) | 根据当前页最后一个按钮的位置把提示放到底部空白或顶部窄条；Tab 在文本编辑器获得焦点时仍能切换菜单控件。 |
| 自定义提示文本越出提示卡片 | [`rounded_button.gd`](../../game/scripts/ui/rounded_button.gd) | 提示标签启用省略裁切并受限于提示面板。 |

## 覆盖范围

复查包含以下页面和游玩状态：

- 主菜单、存档槽位、角色选择、角色详情、角色成就、初始器具；
- 设置、声音、按键映射、辅助说明、触控布局、愿簿传递与导入预览；
- 故事阅读、还愿庭、收藏/图鉴、路线地图、成长记录、结算复盘；
- 暂停菜单、道具/愿簿选单、供物三选一、商店试射、特殊房间、替换确认；
- 战斗 HUD、技能提示、主动道具、饰品、掉落提示和清房后的入口提示。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| Godot `--check-only`（`main.gd`） | 通过 |
| Windows 原生 UI QA | 90 张截图，运行通过 |
| 移动端 16:9 | 100 项检查通过，20 张原生帧 |
| 移动端 20:9 | 100 项检查通过，20 张原生帧 |
| 移动端 4:3 | 100 项检查通过，20 张原生帧 |
| 移动端高 DPI（320） | 100 项检查通过，20 张原生帧 |
| 无 Docker/WSL/模拟器 | 符合约束 |

截图证据位于 [`reports/ui-layout-2026-10-14/`](reports/ui-layout-2026-10-14/)，原生页面截图位于 [`reports/runtime/`](reports/runtime/)。

最近一次完整键盘流程报告共运行 112 项检查。菜单、暂停、技能数字键 1/2/3/4、Tab 地图、保存预览前后的焦点路径均在前置步骤通过；剩余导入相关失败来自 QA 进程以隐藏窗口运行时 Windows `DisplayServer` 无法打开系统剪贴板（日志为 `Unable to open clipboard`），不是 UI 几何或焦点路径错误。后续隐藏宿主重跑可能在同一剪贴板调用处提前超时，未出现新的 GDScript 错误。真实可见桌面运行时仍使用系统剪贴板，导入页同时保留文本框直接编辑路径。

## 重跑命令

```powershell
& .local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://scripts/main.gd
python tools/runtime/run_native_qa.py
python tools/runtime/verify_mobile_revision.py --report-dir docs/incense-debt/reports/ui-layout-2026-10-14
python tools/runtime/run_keyboard_qa.py
```
