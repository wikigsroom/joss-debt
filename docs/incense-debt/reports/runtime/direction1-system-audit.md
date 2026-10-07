# 方向 01 运行系统审计

记录时间：2026-10-06T14:27:08.035148+00:00。结果：**通过**。

这份报告把稳定 ID、运行钩子、数据驱动分派和已有自动证据放在一起。内容库中的 `specified`/`design_baseline` 仍是设计层状态；只有本报告的运行证据和各专项报告才决定软件侧是否已经接入。

## 总量

| 系统 | 数量 | 状态 |
| --- | ---: | --- |
| characters | 6 | 通过 |
| routes | 6 | 通过 |
| weapons | 16 | 通过 |
| skills | 18 | 通过 |
| relics | 54 | 通过 |
| talents | 36 | 通过 |
| debt_contracts | 9 | 通过 |
| enemies | 24 | 通过 |
| elite_variants | 6 | 通过 |
| bosses | 5 | 通过 |
| synergies | 24 | 通过 |
| regions | 3 | 通过 |
| room_templates | 18 | 通过 |
| special_rooms | 4 | 通过 |

## 关键解释

- 54 件遗物均有 combat runtime hook；24 套组合矩阵通过 24 个逐 ID 案例，另有 7 个独立钩子逐一通过真实路径。组合引用到 47 件遗物，独立钩子为：`r08, r16, r24, r32, r40, r48, r54`。
- 16 种武器按 `slash`、`ray` 和通用 `projectile` 三条真实 World 分派路径运行；模式名称来自数据，不能用“代码里是否出现每个武器 ID”判断实现完整度。
- 18 个技能由统一 `cast_skill` 入口和数据行驱动，专项扩展测试逐个施放；24 个普通敌人和 5 个 Boss 由数据加载后逐个执行攻击/阶段夹具。
- 精英变体使用 `base_enemy + elite_id` 分派；六种变体的生命、预警、伤害与自然余烬字段已由真实生成/死亡回归逐项核对；没有显式独立分支的 `x03` 仍由 `e09` 的铜盾通用规则处理。
- 所有自动报告只证明软件规则和可复现集成，不能替代真人平衡、手机听测、Android 真机安装或 macOS/Xcode/iOS 验收。

## 失败项

- 无

机器报告：[direction1-system-audit.json](direction1-system-audit.json)。重新生成：

```powershell
python -X utf8 tools/runtime/audit_direction1_system.py
```
