# 发布准入机器审计

记录时间：2026-10-06T14:29:00.971934+00:00。当前状态：`playable_three_chapter_alpha`。
软件准入：**passed**；正式发布准入：**pending_external_acceptance**。

## 软件检查

| 检查 | 结果 |
| --- | --- |
| design_validation | 通过 |
| documentation_set | 通过 |
| windows_native | 通过 |
| native_audio | 通过 |
| android_package | 通过 |
| ios_handoff | 通过 |
| shared_parity | 通过 |
| native_interactions | 通过 |
| native_keyboard_flow | 通过 |
| choice_history | 通过 |
| achievements | 通过 |
| direction1_system_audit | 通过 |
| human_matrix_structure | 通过 |
| completion_audit | 通过 |

## 外部门槛

| 门 | 状态 | 原因 |
| --- | --- | --- |
| human_balance | `pending_human` | 六角色×两路线真人整局记录尚未归档 |
| android_device | `pending_device` | result must be passed after a real-device run；physical_device_tested must be true；missing device_model |
| ios_device | `pending_device` | result must be passed after a real-device run；physical_device_tested must be true；missing device_model |

机器报告只证明软件侧证据一致，不替代真实设备或真人体验。
