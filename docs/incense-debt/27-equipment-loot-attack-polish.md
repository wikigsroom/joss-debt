# 《香火债》v0.2 · 装备、稀有掉落与攻击打磨


### 主动道具、饰品、稀有掉落与攻击叠加

每局初始携带满充能的**火签筒**。主动道具占一个槽，`F` 使用；普通清房充能 1，首领清房充能 2，火芯额外补 1。回访已清房、读档、召唤怪和训练都不能刷充能或稀有掉落。换主动道具会把旧装备连同真实剩余充能放回地面；恢复和换装不重置充能。满血用归心灯、无装备用转愿骰等无效操作不会扣除充能。

| 主动道具 | 满充能 | 作用 |
| --- | --- | --- |
| 火签筒 | 3 | 向瞄准方向抛出三枚延迟火签，逐段爆发。 |
| 归心灯 | 6 | 恢复2心火；满血时不消耗充能。 |
| 无债铜镜 | 4 | 短暂护身并反射周围敌弹。 |
| 墨砚 | 4 | 铺下墨池，持续伤害并减速恶愿。 |
| 红线卷 | 3 | 朝前织出五道贯穿红线，兼容爆炸供物。 |
| 纸鹤匣 | 3 | 放出追踪纸鹤；兼容散射与命中修饰。 |
| 引灰铃 | 2 | 收拢香灰、纸钱，并恢复20香火。 |
| 莲台印 | 5 | 生成跟随身边的莲印，护身并持续扫荡。 |
| 转愿骰 | 6 | 重掷当前房内未拾取的装备；无装备时不消耗。 |
| 停雨符 | 4 | 消除周围敌弹并短暂冻结普通恶愿。 |
| 风行履 | 3 | 短时提升移速与攻速，并缩短身法冷却。 |
| 雷霆签 | 6 | 释放三轮跳跃雷签，逐个追击邻近目标。 |

**饰品只能持有一件。** 靠近装备按 `E`，原饰品掉在身后，并短暂延迟再次拾取。加成从当前装备实时计算，来回交换不会累积；装备和火芯不会被香灰吸引自动拾取。主动道具、饰品、火芯、修饰供物有各自的图标、发光底座和快捷键提示，`I` → 装备可看详情，暂停页本局记录保留拾取、替换和成长历史。

| 饰品 | 单一属性加成 | 饰品 | 单一属性加成 |
| --- | --- | --- | --- |
| 铜钱坠 | 伤害 +15% | 灯芯扣 | 攻速 +18% |
| 羽铃 | 移速 +12% | 墨尺 | 射程 +25% |
| 风串 | 弹速 +20% | 玉珠 | 暴击率 +8个百分点 |
| 红珀 | 爆炸半径 +28% | 铜环 | 射线宽度 +32% |
| 小莲 | 香灰拾取范围 +35% | 福袋 | 稀有掉落概率 +25% |
| 丝穗 | 清房充能 +50%（余数保留） | 纸扣 | 主攻击击退 +20% |

**稀有掉落**与原来的香灰、纸钱、回血并存：普通敌人基础概率 0.8%，精英 2.5%，首领 8%，首次清房 3.5%；每房最多两件稀有掉落。掉落类型权重为火芯 35%、主动道具 20%、饰品 30%、攻击修饰 15%。福袋将概率乘以 1.25，仍受每房上限限制。宝藏房另有一次性装备底座，奇数层供饰品、偶数层供主动道具，保证单局能接触换装。地上物品、旧装备充能、房间领取记录和低概率来源账本都进入存档。供物槽满时进入替换页；取消保留地上物品，确认后旧供物落回地面。

**叠加采用“攻击载体 + 修饰”的明确规则。** 三叠灯 / 四方纸 / 五瓣签分别给出至少三 / 四 / 五发，取最高档且最多八发；三种同时持有得到五发。爆香核给命中或终点爆炸，光墨匣改为射线，两者能并存，故五瓣签＋光墨匣＋爆香核产生五道带爆炸的射线。穿透、追踪、操控、反弹、分裂、持续场和蓄力也接入全部三十二器具。飞行弹可随瞄准方向转向；即时射线和近战按释放时方向结算。原武器的延迟、火场和多轮脉冲在载体转换后保留。

同一次爆炸 / 范围波次对同一目标只结算一次范围伤害；同次主攻击的供物触发按目标去重。分裂子代最多一层，不能再递归分裂或爆炸，回响保存原攻击构成且不重复触发主攻击钩子。控制弹、延迟弹、回响和范围去重状态也随存档恢复。构筑页底部图标说明当前载体、发数与生效修饰。

`Tab` 地图顶部显示完整十一层节点，已过层、当前层、未来层分色，第六及十一层有首领标识。战斗新增十个特效家族，每家族四种射线和四种范围形态；80 条新动画 / 480 个独立生成关键帧，与原 8 条组成 88 条分阶段战斗动画，是原数量的 **11 倍**。395 个小怪 / 首领来源各有弹丸参数，结合 16 种基础形态、尺寸、旋转、颜色、纹理光晕与尾迹；实际碰撞半径同步尺寸，敌弹保留稳定的玉色危险外沿。轮廓缓存有上限，二次触发与场域均有预算；减少动态、粒子密度与闪光设置继续生效。

[完整规则与验收](27-equipment-loot-attack-polish.md) · [装备数据](../../game/data/equipment.json) · [原生装备证据](reports/platforms/windows/equipment-polish/native.json)


### Active items, one trinket slot, rare loot, and attack composition

Each run starts with a fully charged **Fire-Tag Cylinder**. One active slot uses `F` on PC, `X` on gamepad, or its own touch button. A first room clear grants one charge, a boss clear two, and a battery one. Revisits, loading saves, summons, and training cannot farm charge or rare equipment. Swapping drops the old active with its actual remaining charge. Invalid uses, such as healing at full health or rerolling an empty room, spend no charge.

| Active item | Full charge | Effect |
| --- | --- | --- |
| 火签筒 · Fire-Tag Cylinder | 3 | Three delayed bombs along the aim direction |
| 归心灯 · Returning-Heart Lamp | 6 | Restore two health points |
| 无债铜镜 · Debtless Mirror | 4 | Brief protection and nearby bullet reflection |
| 墨砚 · Inkstone | 4 | Damaging slow field |
| 红线卷 · Red-Thread Spool | 3 | Five piercing beams, compatible with explosion modifiers |
| 纸鹤匣 · Paper-Crane Box | 3 | Seeking cranes with attack modifiers |
| 引灰铃 · Ash Bell | 2 | Collect ash/coins and restore 20 Incense |
| 莲台印 · Lotus Seal | 5 | Following defensive damage field |
| 转愿骰 · Wish Die | 6 | Reroll uncollected equipment in the room |
| 停雨符 · Rain-Stopping Charm | 4 | Clear nearby bullets and briefly freeze ordinary enemies |
| 风行履 · Wind Shoes | 3 | Temporary speed, fire rate, and dodge-cooldown buffs |
| 雷霆签 · Thunder Tags | 6 | Three chain-lightning waves |

**Exactly one trinket can be held.** Press `E` near equipment to exchange it; the previous item drops behind the player with a short pickup delay. Bonuses derive from the currently held item, preventing cumulative swap exploits. The twelve single-stat trinkets improve damage (15%), fire rate (18%), movement (12%), range (25%), shot speed (20%), critical chance (8 percentage points), blast radius (28%), beam width (32%), ash pickup radius (35%), rare-drop probability (25%), room-charge efficiency (50%, retaining fractions), or knockback (20%). Equipment and batteries require deliberate pickup. Inventory → Equipment and the pause history expose slots, charges, pickups, and replacements.

**Rare loot** supplements normal ash/coins/healing: base probabilities are 0.8% for ordinary kills, 2.5% for elites, 8% for bosses, and 3.5% for a first room clear, capped at two rare drops per room. Loot weights are battery 35%, active 20%, trinket 30%, and attack modifier 15%. The luck trinket multiplies probability by 1.25. Treasure rooms additionally provide a once-only equipment pedestal: trinkets on odd floors, active items on even floors. Ground items, charges, collection ledgers, and rare-roll source IDs persist in saves. Full relic inventories open a replacement transaction; cancel preserves the ground item and confirmation drops the replaced relic.

**Attacks combine a carrier with modifiers.** Three/four/five-shot offerings take the highest minimum rather than multiplying; holding all three gives five shots, with an eight-shot ceiling. Beam conversion retains explosion payloads, so five-shot + beam + explosion yields five explosive beams. Piercing, homing, controlled flight, bounce, split, lingering fields, and charging integrate with all 32 weapons. Controlled flight follows aim; instant beams/melee settle at release direction. Delayed bombs, fields, and repeated pulses survive carrier conversion.

An overlapping area wave damages a target once, and primary offering triggers deduplicate by attack/target. Split children stop at generation one and do not recursively split/explode; echoes preserve the original recipe without replaying primary triggers. Delayed recipes and deduplication state survive save/restore. The inventory shows the current carrier, shot count, and modifier chips.

The map now displays all eleven floor nodes, marking completed/current/future floors and major bosses. Ten effects families add four beam and four area forms each: **80 new strips / 480 distinct generated keyframes**, making **88 staged combat strips, 11× the prior eight**. All 395 enemy/boss sources have profile parameters built from 16 shapes, size, spin, color, textured aura, and trails. Actual collision radii follow size; hostile shots retain jade danger outlines. Bounded geometry caches, secondary-effect budgets, reduced motion, and particle/flash controls limit rendering cost.

[Detailed rules and evidence](27-equipment-loot-attack-polish.md) · [Equipment definitions](../../game/data/equipment.json) · [Packaged native evidence](reports/platforms/windows/equipment-polish/native.json)

## 六项需求与交付证据

| 需求 | 当前实现 | 实际验收 |
| --- | --- | --- |
| 主动道具 | 12种、单槽、充能与无效使用保护，键鼠/手柄/触控输入 | 每件真实效果、拒绝条件、交换与充能；编译实机F与触控按钮 |
| 单槽饰品 | 12种单属性，换装落地，属性只来自当前饰品 | 全部饰品与80次反复交换、拾取冷却、无累积 |
| 低概率掉落 | 四来源独立概率、装备/火芯/修饰、上限与持久化 | 80000次抽样、召唤/训练排除、清房重复与读档防刷 |
| 完整层级线 | Tab页11节点与完成/当前/未来状态 | 第1/6/11层原生截图与节点状态检查 |
| 兼容叠加 | 32武器统一组合、最大散射、爆炸射线、分裂/回响限代、延迟恢复 | 32×8组真实命中场景、空间去重、损坏档拒绝、回响/分裂读档 |
| 丰富特效与敌弹 | 80新增条480帧、10家族、395参数16形态 | 116素材逐项SHA核对、111原生截图、480帧载入及205弹丸压力测量 |

[规则回归](reports/runtime/equipment-polish/gameplay.json)共1568项通过；[其他系统回归](reports/runtime/equipment-polish/regression.json)记录21套检查，原509项扩展与373项边界规则继续通过。[完整十一层流程](reports/runtime/expanded-full-run.json)在正常初始参数下实际通关，129个清房、151次实体门、40次主动使用、13次换装、十次跨层存档恢复，无跳关或直接设置胜利。

[Windows编译装备实机](reports/platforms/windows/equipment-polish/native.json)与[美术来源核验](reports/platforms/windows/equipment-polish/assets.json)绑定当前可执行文件。主菜单与纯键盘原生检查分别覆盖75与107项；[编译代码核验](reports/runtime/combat-revision/compiled-geometry.json)逐一比较Windows与Android的69份编译脚本，并实际执行两份碰撞/窄道实现。最终可下载包另外运行同样的装备检查，结果保存在版本[发布清单](../releases/v0.2.0-alpha.1.manifest.json)中。

## 存档兼容与预算

应用版本为0.2.0；内容数据库基础版本保留0.1.0，存档schema仍为2。旧存档缺少新槽位时补入火签筒和空饰品，不改旧成长。当前档验证装备ID、充能范围、地面物品、来源账本、延迟组合、供物替换事务与图鉴发现记录；未知装备和恶意/损坏组合拒绝恢复。敌弹展示参数由已验证敌人来源重建。

每次攻击二次触发预算48；同屏弹丸240、场域48、延迟项120；每房稀有掉落2。弹丸轮廓网格缓存1024项；绘制粒子预算随设置缩放，敌弹核心与危险边界始终保留。205弹丸压力指标是暂停物理的桌面渲染场景，不能推算手机帧率或长期整局性能。实际最新耗时见原生报告。

[生成来源](reports/runtime/equipment-polish/asset-production.json)保留23张Sub2API/gpt-image-2.5原图、36图标、80条透明动画及480帧SHA；[运行清单](../../game/assets/fx/equipment-polish/manifest.json)逐条对应。新增特效数量为此前8条的10倍，加上原8条合计88条，即11倍；这不代表审美满意度或性能的倍数。

## 发布范围

Windows提供已运行验证的原生release导出。Android提供重新构建并验证签名/资源的arm64调试APK；没有以桌面验证代替真机结论。iOS提供同源交接ZIP，尚无签名IPA。真人战斗手感、长期平衡与手机热稳定仍需实际游玩验收。整个制作与验证使用Windows原生工具，未使用Docker、WSL、浏览器或虚拟化环境。
