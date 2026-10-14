# 移动端菜单滚动兼容修复（2026-10-14）

## 结论

移动端菜单的上下滑动已经修复。问题来自 Godot 4.7 的 `ScrollContainer`：它会处理鼠标滚轮和键盘滚动，却不会自动把 `InputEventScreenDrag` 转换成垂直滚动。项目此前大量页面直接创建原生 `ScrollContainer`，所以点击按钮可以工作，手指上下拖动却没有任何滚动反馈。

本轮加入统一的 [`touch_scroll_container.gd`](../../game/scripts/ui/touch_scroll_container.gd) 并替换所有菜单列表容器。它保留原有键盘、鼠标和按钮行为，同时为触屏补上拖动、方向锁定和惯性结束；点击不会被误判为滚动。

## 适配行为

| 行为 | 当前规则 | 目的 |
| --- | --- | --- |
| 点击 | 手指移动小于 12 个逻辑像素时不接管事件 | 保留按钮点击、切换、确认和图标预览 |
| 方向判断 | 纵向位移必须达到横向位移的 0.72 倍 | 横向滑动不被纵向列表抢走，减少误滚动 |
| 滚动轴 | 普通菜单只保留垂直滚动；行路图与共同行路地图显式开启双轴平移 | 列表避免窄屏横向溢出，地图仍可查看超出面板的节点 |
| 拖动接管 | 超过死区后才调用 `set_input_as_handled()` | 子按钮仍可收到按下，拖动释放不会提交候选 |
| 惯性 | 速度上限 2200，减速度 2600 | 短滑动也能自然停下，抵达列表边界立即停止 |
| 缩放 | 触点先通过容器的画布逆变换还原到逻辑坐标 | 适配 16:9、20:9、4:3 与高 DPI 界面缩放 |
| 生命周期 | 切换页面、窗口失焦、应用暂停、容器尺寸变化都会取消当前拖动和惯性 | 不把旧页面的手势或回弹带到下一层菜单 |

滚动容器覆盖以下页面：按键映射、瞄准与反馈、庭院/主菜单列表、愿簿与收藏、成长记录、成就、在线房间/技能/债约/路线、行路图列表、结算复盘和故事阅读器，共 16 个运行时列表入口；行路图和共同行路地图另外使用同一容器的双轴平移模式。所有入口都使用同一套触摸阈值，避免不同页面出现不同手感。

## 回归证据

验证脚本 [`verify_mobile_revision.gd`](../../tools/runtime/verify_mobile_revision.gd) 新增了真实触摸事件序列：`ScreenTouch(pressed)` → `ScreenDrag` → `ScreenTouch(released)`。它检查长列表有实际滚动范围、点击仍能切换设置、向上滑动增加 `scroll_vertical`、向下滑动减少 `scroll_vertical`，并将注入点乘以窗口最终变换，覆盖宽屏留白和安全区缩放。

| 原生窗口 | 结果 | 检查 | 原生帧 |
| --- | ---: | ---: | ---: |
| 1280×720（16:9） | 通过 | 100 | 20 |
| 2400×1080（20:9） | 通过 | 100 | 20 |
| 1024×768（4:3） | 通过 | 100 | 20 |
| 1280×720，DPI 320 | 通过 | 100 | 20 |

完整 JSON、原生截图和日志保存在 [`reports/action-mobile-scroll-2026-10-14/`](reports/action-mobile-scroll-2026-10-14/)。代表性长列表截图：

![16:9 移动端瞄准与反馈列表](reports/action-mobile-scroll-2026-10-14/phone-16x9/assistance.png)

![20:9 移动端瞄准与反馈列表](reports/action-mobile-scroll-2026-10-14/phone-20x9/assistance.png)

同一套 100 项用例也在当前 Windows 打包程序上通过，打包矩阵见 [`reports/platforms/windows/mobile-scroll-2026-10-14/mobile-matrix.json`](reports/platforms/windows/mobile-scroll-2026-10-14/mobile-matrix.json)，对应包体 SHA-256 为 `d1a42e0de0fe08722aeb4a8ac8b20ba1faf73e80b9e5234004164032ca357e81`。Android 调试包静态检查通过，APK SHA-256 为 `acfd24fe0f692ae05794029fd0f32ba2b80bbc3b791858f766834584fa8f3a6b`；没有把静态检查当作真机触摸验收。

同轮源码键盘流程通过 107 项检查。原生截图长流程使用 60 FPS 上限，以避免生成式 UI 纹理在无上限桌面渲染下跑完固定 QA 时钟前耗尽超时；该限制只作用于测试驱动，不改变游戏运行帧率。

## 设备范围

本轮验证是 Godot 原生窗口的真实输入分发和多比例触摸注入，没有使用模拟器、Docker、WSL 或虚拟化环境。当前没有连接 Android 真机，因此 Motorola X30 的系统导航栏、厂商手势区、真实触摸采样率和系统级回弹仍需在设备接入后单独验收；源码层的滚动处理、按钮保留、缩放坐标和四种窗口比例已经完成。

## 重跑命令

```powershell
python tools/runtime/verify_mobile_revision.py --report-dir docs/incense-debt/reports/action-mobile-scroll-2026-10-14
python tools/runtime/run_keyboard_qa.py
python tools/runtime/run_native_qa.py
```
