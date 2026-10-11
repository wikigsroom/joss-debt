# 共灯：双人合作闯关

0.4.0 默认联机玩法为「共灯合作」：两个玩家在同一间真实肉鸽房间中协作，完成十一层路线。入口仍是同服快速匹配或六位数字房间。大厅可切换「对灯切磋」，两个模式的匹配队列相互独立；同码房间拒绝另一模式的加入。

## 房间与战斗

服务器拥有唯一地图、房间几何、怪物、Boss、子弹、范围攻击、延迟攻击、场景物件、掉落与随机流；两名玩家各有身体、血量、武器、技能、装备、成长和攻击归属。客户端发送移动、瞄准和行动，显示服务器状态，不在各自设备生成另一份怪物。普通怪血量乘 1.65，Boss 乘 1.75；这是 Alpha 初始系数，尚需真人合作平衡验证。

NPC 选择最近的存活玩家作为目标。两人共用内墙、障碍、攻击碰撞与场景危险，友方攻击不伤队友。近战、散射、蓄力、射线、爆炸、引导弹等复用已有 32 件武器；子弹、范围和持续灼烧保存施放者归属，个人连锁、被动触发和冷却不会因切换处理玩家而串用。

清房后，**两个存活玩家一起靠近同一扇物理门**才进入下一房。第一人先到门口会等待队友；地图页不能远程传送。两人到达换层阶梯后才进入下一层。倒地队友须先救起，不能借出口拖走。房间结构、主题、60% 本层／40% 另一随机层怪物混编及独立 Boss 房沿用当前单人地图系统。

## 成长、交易与救援

| 内容 | 合作行为 |
| --- | --- |
| 金币 | 同一个钱包；拾取和购买由服务器结算一次，另一人的余额立即同步 |
| 红心 | 优先给予附近受伤的存活玩家；不会凭拾取复制两份治疗 |
| 经验与清房奖励 | 双方获得各自成长，房间公共奖励只提交一次 |
| 技能与遗物 | 各自选卡；支持数字 1–4、分页、可支付的重抽和满槽替换，选完一方等待另一方 |
| 商店、献祭、判官、观音、债约 | 同一房间的个人候选；共享费用实时核验，个人生命代价与所得分别记录 |
| 债约 | 各自保留契约与利息；影响环境的风险在共享房间生效；层末可用共享金币偿还自己的债约 |
| 装备 | E 靠近实际物件拾取／交换；主动道具 F、身法和技能保持个人冷却 |
| 倒地 | 一人血量归零仍可等待救援；两人都倒地则合作失败 |
| 救援 | 靠近倒地队友按 E，原地保持约 3 秒；走远或救援者受伤会中断，重复按 E 不重置有效进度 |
| 复起 | 恢复两格生命并短暂保护，使用现有纸莲素材和粒子表现 |
| 结局 | 十一层完成后团队胜利；离开／恢复超时为团队中止，双方均不产生 PvP 胜场 |

合作成长使用各自角色的本职路线和演化。联机所有角色、武器、技能可配装，离线三槽解锁不提供联机门槛；本地愿簿、单人局与成就不上传、不被合作结算改写。合作胜负与对战胜负分别保存在匿名联机身份记录中。

## 菜单与恢复

Esc 使双方停战；I 展示双方构筑与全部历史选择，Tab 展示当前楼层路线。双方在线的合作菜单暂停没有 90 秒强制终止；真正断线后重新开始默认 90 秒恢复窗口。清房选卡、交易和暂停都清空旧输入，双方确认后回到原先阶段。

服务端周期保存完整共享世界与两个个人上下文，包括位置、生命、技能、成长候选、随机流、延迟攻击和救援。发送给客户端的轻量场景不携带每颗子弹的模拟配方或内部命中账册；这些数据仍存在完整恢复检查点中。每人完整成长历史只发送一次，不在演员状态中重复展开。

注册表的两代提交分别引用独立的不可变房间文件，包括等待、暂停和结果阶段。即使房间没有移动，也不能让两代注册表只指向同一个可损坏文件。后台写入先提交所有房间，再提交注册表，保留两代所引用的文件；同步控制事务使用相同规则。实际写入失败使双方停战，恢复后再确认继续。

新协议为 **2**，规则指纹 **cooperative-1-duel-2**。0.3.0 客户端与 0.4.0 服务端不能混用。升级前结束旧局并备份整个服务端数据目录，更新后使用新的数据目录；单人 schema 2 与三槽保存独立兼容。

## 模块与验证

- `cooperative_world.gd`：共享模拟、个人上下文切换、救援、门口、成长、交易与完整保存。
- `cooperative_match.gd`：准备、倒数、选择、合作结局、展示快照与请求约束。
- `server_runtime.gd`：模式隔离匹配、事务、恢复与唯一结果。
- `online_session.gd`：真实 WebSocket、输入、展示副本、重连与匿名身份。
- `online_ui.gd`、`online_controller.gd`、`game_renderer.gd`：键盘／触控、共享战场、倒地、历史和地图。

规则检查、真实传输、实际 EXE 的菜单与换房，以及独立服务端崩溃、损坏回退与写盘故障分别验收。[交付记录](42-cooperative-delivery.md)明确区分规则夹具、原生实机、APK 结构检查与待完成的 Android 真机／公网验证。

## English

Co-Light is the default 0.4.0 multiplayer mode: two players share the actual eleven-floor roguelite campaign. Quick matching and six-digit rooms require the same server and selected mode. Optional Duel remains available with a separate queue.

The authoritative server owns one room, geometry, NPCs, bosses, projectiles, hazards, objects, loot and RNG. Each player keeps personal health, weapons, skills, equipment, growth, cooldowns and attack ownership. NPCs target the nearest surviving player; friendly fire is disabled. Both living players must approach the same physical door or floor exit. The map cannot teleport the team.

Coins are shared and spent once; healing and equipment remain individual. Both receive personal progression and make independent choices with keys 1–4. Shops, sacrifice, judge, angel and debt encounters reuse real campaign rules. Floor checkpoints allow repayment of one's own debts using the team wallet. One fallen player can be revived by interacting nearby and staying for three seconds; moving away or taking damage interrupts rescue. Repeated interaction does not reset progress. Both down means team defeat; completing eleven floors means team victory.

Esc pauses the team, I shows both build histories, and Tab opens the floor map. A cooperative menu pause has no deadline while both players stay connected. A real disconnect starts the default 90-second grace period; both players confirm to resume. Full checkpoints retain the shared world, both personal contexts, RNG and pending choices. Presentation snapshots omit only simulation-private recipes and duplicate histories. Independent immutable room generations support consistent corruption fallback, including while paused.

Protocol 2 / ruleset cooperative-1-duel-2 requires matching 0.4.0 clients and server. Finish old matches, back up the complete server directory and start with a new data folder after upgrading. Offline schema-2 saves remain separate. No default public game host is provisioned; see the server guide and delivery limits.
