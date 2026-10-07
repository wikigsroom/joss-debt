# 方向1视觉契约审计

这份报告把 Sub2 视觉参考、素材清单、视觉契约和当前 Windows 原生截图放到同一条证据链；概念设计板定义方向，实际运行截图和运行时资源报告负责证明落地。

## 审计结果

| 检查 | 状态 | 证据摘要 |
| --- | --- | --- |
| approved concept references are registered in the asset manifest | 通过 | missing=[] |
| concept_roster has an existing Sub2 image with stable dimensions and hash | 通过 | file=output/imagegen/incense-debt/characters-roster.png; expected_size=[1536, 1024]; actual_size=[1536, 1024]; provider=sub2-image-gen; model=gpt-image-2.5 |
| concept_roster keeps a reproducible prompt source | 通过 | prompt=docs/incense-debt/assets/prompts/characters-roster.txt |
| concept_paper_room has an existing Sub2 image with stable dimensions and hash | 通过 | file=output/imagegen/incense-debt/paper-lantern-asset-board.png; expected_size=[1536, 1024]; actual_size=[1536, 1024]; provider=sub2-image-gen; model=gpt-image-2.5 |
| concept_paper_room keeps a reproducible prompt source | 通过 | prompt=docs/incense-debt/assets/prompts/paper-lantern-asset-board.txt |
| concept_menu_map_combat has an existing Sub2 image with stable dimensions and hash | 通过 | file=output/imagegen/incense-debt/menu-map-combat-board.png; expected_size=[1672, 941]; actual_size=[1672, 941]; provider=sub2-image-gen; model=gpt-image-2.5 |
| concept_menu_map_combat keeps a reproducible prompt source | 通过 | prompt=docs/incense-debt/assets/prompts/visual/menu-map-combat-board.txt |
| visual contract names the character, room, menu, door and impact references | 通过 | missing=[] |
| the new reference prompt covers all three visual anchors | 通过 | menu, physical room entry and combat feedback are explicit prompt sections |
| visual baseline binds the new board to its current hash | 通过 | baseline_references=4 |
| runtime screenshots and UI evidence remain bound to the current executable | 通过 | compiled=b42d30ac412fbe90299066bc8f32f624544cdbdead870e9253f35f388a7043a0; native=b42d30ac412fbe90299066bc8f32f624544cdbdead870e9253f35f388a7043a0; ui=b42d30ac412fbe90299066bc8f32f624544cdbdead870e9253f35f388a7043a0 |
| native asset and screenshot evidence is green | 通过 | assets=725; captures=90 |
| visual contract keeps concept references separate from runtime replacements | 通过 | concept direction is reviewed while runtime screenshots/assets remain authoritative |

边界：概念图审查通过不等于每个运行时栅格都由新模型逐帧生成；运行时资源、原生截图和设备/真人验收仍按各自报告处理。

机器报告：[visual-contract-audit.json](visual-contract-audit.json)。重新生成：

```powershell
python tools/runtime/audit_visual_contract.py
```
