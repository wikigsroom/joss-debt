# 菜单与纯键盘闭环审计

已编译程序的真实键盘事件与常规原生 GUI 回归共同核验层级。

标题 → 三份存档 → 主菜单 → 新局／挑战／记录／设置；Esc 按父页返回。

纯键盘检查 105 项；常规原生交互 75 项。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| title, files and main are three separate native layers | 通过 | InputEventKey Enter traverses splash -> files -> main |
| three files switch with arrows and restore independent progress and defaults | 通过 | slot 2 progress survives a visit to empty slot 3; settings do not leak |
| main keeps vertical actions and skips disabled continue | 通过 | directional focus skips a disabled Continue |
| character children return one layer and their compact actions do not overlap | 通过 | detail/loadout/character buttons exercised with keyboard; native button and notice rectangles compared |
| character selection exposes actual persistent completion marks | 通过 | four marks read stable character achievement IDs; filter does not change parent |
| challenge rules and character selection precede a real daily start | 通过 | daily flag and date key checked after tutorial opens |
| stats owns items, bestiary, endings, character statistics and story | 通过 | all Stats children entered and exited using keys |
| reading, icons and full choice descriptions have keyboard paths | 通过 | PageDown/End change actual scroll values; F1 returns to the same candidate |
| settings and its children preserve menu and pause origins | 通过 | Esc audio -> settings -> originating parent |
| rebind capture, sliders and layout editing close without a pointer | 通过 | real native controls handle key input before combat bindings |
| all number shortcuts and sequential skill decisions activate real choices | 通过 | candidate IDs and growth log checked after Enter/number events |
| shop, practice, debt and all three special rooms close by keyboard | 通过 | wallet, original shop stock, rewards and replacement slot count checked |
| combat, map and inventory form a keyboard loop through physical doors | 通过 | WASD walks through a real directional door; map never teleports |
| pause records and achievements return to pause after filtering | 通过 | restore explicitly starts on Continue; settings and filters preserve parent |
| finished build and review return through their real parents | 通过 | finished combat never resumes; ending is committed before archive viewing |
| replacement confirmation and save transfer are keyboard safe | 通过 | overwrite cancel preserves snapshot; import and undo commit paired saves; failed writes hold menu |
| design document records comparison, graph, save and keyboard boundaries | 通过 | remaining game-mode and completion-mark differences are explicit |
| all native evidence verifies the same current compiled executable | 通过 | keyboard behavior, ordinary native GUI and viewport captures share the executable hash |

边界：可选房间由固定场景准备；不替代真人三章体验、移动设备或原生系统文件选择器验收。

详细差异：[菜单文档](../../22-menu-save-achievements.md)。

重跑：python tools/runtime/run_keyboard_qa.py --packaged，然后 python tools/runtime/audit_menu_hierarchy.py。
