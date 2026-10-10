# 《香火债》当前交付与验收记录

更新：2026-10-07T15:29:55.747347+00:00。当前为十一层可玩 Alpha：20套环境、40张背景、296种小怪、99名首领、32件器具。每主题12种小怪与3名主题首领，最终天穹12种小怪与7名首领。

| 平台 | 当前产物 | 已完成验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，560.1 MiB | 当前编译程序实际加载3781项资源；界面75项、纯键盘107项、扩展285项检查通过 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，arm64，482.6 MiB | 调试签名与包内全部3781项运行资源、核心内容一致性检查通过；未进行真机安装 |
| iOS | [共享源码与Mac交接](../../../build/ios-handoff/README.md) | 共享源码全树哈希、官方模板与交接完整性通过；尚无签名IPA或真机运行 |

[安装及键位](../../../build/README.md) · [怪物与首领名册](../25-themed-encounters.md) · [二十主题总览](platforms/windows/expansion/twenty-themes-overview.png) · [当前交付索引](expansion-delivery.json)

## 当前实现

| 体系 | 当前行为 |
| --- | --- |
| 十一层故事 | 前五层每层两个独立Boss房，各一名首领；第六层固定守名大判，七至十层保留双首领主战，第十一层40房、六名连续首领与万愿总账 |
| 环境与遭遇 | 二十套环境、40个按背景校准的内墙轮廓；普通、精英、挑战与召唤按60%本土＋40%一个随机高对比外来主题混编；随机首领同样纳入混编 |
| 场景交互 | 相连木、石、绳障碍，受击爆炸、连锁爆炸、接触伤害与动态预告；生成保留出生点与房门可达 |
| 战斗与动作 | 三十二器具；新增48张独立生成特效关键帧，射线流动、端点爆裂、范围蓄势／扩散／余波与内墙裁切；显示路径和实际命中一致 |
| 地图与键盘 | WASD走位、方向键发射、数字键选择、Enter确认、Esc返回/暂停；Tab同时查看地图、垂直基础属性、完整道具与词条，Ctrl+Tab切换历史 |
| 种子与保存 | 十二位派生种子，暂停可复制，新局手动输入一次生效；楼层、房间、奖励、怪物和障碍使用隔离随机流，过场与局内快照可恢复 |
| 装备与稀有掉落 | 十二主动道具、十二单属性饰品、一个饰品槽与地面交换；清房/首领充能、火芯补充、低概率掉落与一次性来源账本接入存档 |
| 攻击与新特效 | 三十二武器统一载体/修饰组合；三/四/五发取最高档、射线与爆炸并存、分裂/回响二次触发受限；新增80条生成动画480帧，395份敌弹参数与16种形态 |
| 地图与主动键 | Tab地图顶部完整十一层线；F使用主动道具、E拾取/交换，手柄X、第五个独立触控按钮；暂停历史与装备图鉴保留所有选择 |
| 原有体系 | 六角色、十八技能、六十六供物、三十六行愿节点、二十四组合、三槽位、角色成就、商店试射、献灯/判官/观音/破阵房及局外成长继续接入 |

## 绑定当前文件的证据

[扩展系统](runtime/expansion-systems.json)：509项检查；[本轮战斗修复](runtime/combat-revision/systems.json)：373项检查、1100张图结构、40种边界及旧双Boss恢复。[完整流程](runtime/expanded-full-run.json)：默认初始参数自动操作，1次胜利、0次真实败局；成功样本覆盖11层、固定剧情首领、六连续首领与结尾，10次实际层间存档恢复全部通过。

[原生扩展](platforms/windows/expansion/expansion-native.json)：285项检查、397张画面；[美术来源](platforms/windows/expansion/expansion-assets.json)：3313项检查、全部生成角色板与动作条，当前共2810条动画。[键盘闭环](platforms/windows/keyboard/keyboard-flow.json)、[界面](platforms/windows/native-render.json)及[内部混音](platforms/windows/audio/native-audio.json)均绑定同一可执行文件。

[装备规则](runtime/equipment-polish/gameplay.json)：1568项、80000次稀有掉落抽样；[编译装备实机](platforms/windows/equipment-polish/native.json)：29项、111张截图、全部480帧载入，205弹丸绘制P95 34.24ms（暂停物理的渲染压力测量）。[素材核对](platforms/windows/equipment-polish/assets.json)逐一绑定23张生成原图、36图标和80动画。

Windows SHA-256：`51b896b4c3deb5a0bb197c44210f5bdd72e95cc216a4dd0961fedd4edee364d9`。各平台文件哈希保存在[交付清单](../../../build/delivery-manifest.json)；[跨端一致性](platforms/platform-parity.json)核对共享源树与Android包内内容。

自动操作与规则检查用于证明软件流程；真人审美、战斗手感与长期平衡仍需实际游玩反馈。动画采用来源可追溯的预生成纸偶形变，过场采用生成静帧、镜头移动与转场。Android未进行真机测试；iOS仍需真实Mac/Xcode签名与设备运行。未使用Docker、WSL或虚拟化环境。

原三章交付记录另存[历史记录](three-chapter-product-status.baseline.md)，不作为十一层扩展的完成证明。
