"""Compare the menu contract with compiled, keyboard-only native behavior evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"


def read(relative):
    return json.loads((ROOT / relative).read_text("utf8"))


def main():
    source = (ROOT / "game/scripts/main.gd").read_text("utf8")
    ui = (ROOT / "game/scripts/ui/modern_ui.gd").read_text("utf8")
    flow = (ROOT / "game/scripts/ui/menu_flow.gd").read_text("utf8")
    navigation = (ROOT / "game/scripts/ui/keyboard_navigation.gd").read_text("utf8")
    doc = (ROOT / "docs/incense-debt/22-menu-save-achievements.md").read_text("utf8")
    native = read("docs/incense-debt/reports/platforms/windows/native-render.json")
    keyboard = read("docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json")
    build = read("docs/incense-debt/reports/platforms/windows-build.json")
    behavior = {item["id"]: item["passed"] for item in keyboard.get("checks", [])}
    checks = []

    def check(name, condition, detail):
        checks.append({"name": name, "passed": bool(condition), "detail": detail})

    def observed(*ids):
        return all(behavior.get(value, False) for value in ids)

    check("title, files and main are three separate native layers", observed("title_to_files", "file_to_main") and all('"' + page + '"' in ui for page in ["splash", "files", "title"]), "InputEventKey Enter traverses splash -> files -> main")
    check("three files switch with arrows and restore independent progress and defaults", observed("slot_arrow_right", "slot_3_independent_defaults", "slot_2_progress_restored"), "slot 2 progress survives a visit to empty slot 3; settings do not leak")
    check("main keeps vertical actions and skips disabled continue", observed("main_arrow_up", "disabled_continue_skipped") and all('"' + label + '"' in flow for label in ["新局", "继续", "挑战", "记录", "设置"]), "directional focus skips a disabled Continue")
    check("character children return one layer and their compact actions do not overlap", observed("locked_character_details", "details_back_one_layer", "loadout_under_character", "character_back_to_main", "compact_character_actions_do_not_overlap", "menu_notice_does_not_cover_actions"), "detail/loadout/character buttons exercised with keyboard; native button and notice rectangles compared")
    check("character selection exposes actual persistent completion marks", '"completion_mark"' in ui and 'achievement_rows(app.selected)' in ui and observed("character_achievements", "character_filter_parent"), "four marks read stable character achievement IDs; filter does not change parent")
    check("challenge rules and character selection precede a real daily start", observed("challenge_character_layer", "challenge_character_back", "keyboard_daily_start"), "daily flag and date key checked after tutorial opens")
    check("stats owns items, bestiary, endings, character statistics and story", observed("stats_layer", "bestiary_under_stats", "endings_under_stats", "statistics_under_stats", "story_hub_returns_stats"), "all Stats children entered and exited using keys")
    check("reading, icons and full choice descriptions have keyboard paths", observed("collection_keyboard_page", "credits_keyboard_scroll", "assistance_scroll_end", "choice_keyboard_full_details", "details_restore_choice_focus"), "PageDown/End change actual scroll values; F1 returns to the same candidate")
    check("settings and its children preserve menu and pause origins", observed("audio_back_to_settings", "credits_back_to_settings", "settings_back_to_main", "pause_nested_settings_parent"), "Esc audio -> settings -> originating parent")
    check("rebind capture, sliders and layout editing close without a pointer", observed("keyboard_slider", "slider_down_moves_focus", "keyboard_rebind_capture", "rebind_cancel_stays_in_controls", "layout_keyboard_move", "layout_tab_escape_editor"), "real native controls handle key input before combat bindings")
    check("all number shortcuts and sequential skill decisions activate real choices", observed("number_choice_1", "number_choice_2", "number_choice_3", "number_choice_4", "queued_growth_complete", "skill_arrow_enter"), "candidate IDs and growth log checked after Enter/number events")
    check("shop, practice, debt and all three special rooms close by keyboard", observed("keyboard_shop_trial_return", "keyboard_shop_purchase", "keyboard_shop_skip", "keyboard_debt_contract", "keyboard_repay", "keyboard_special_sacrifice", "keyboard_special_judge", "keyboard_special_angel", "replacement_keyboard_complete"), "wallet, original shop stock, rewards and replacement slot count checked")
    check("combat, map and inventory form a keyboard loop through physical doors", observed("combat_keyboard_move", "combat_arrow_fire", "keyboard_aim_survives_release", "keyboard_skill", "keyboard_dash", "keyboard_physical_door", "tab_closes_map", "inventory_same_key_closes"), "WASD walks through a real directional door; map never teleports")
    check("pause records and achievements return to pause after filtering", observed("history_returns_pause", "pause_achievement_filter_parent", "continue_to_pause"), "restore explicitly starts on Continue; settings and filters preserve parent")
    check("finished build and review return through their real parents", observed("keyboard_result_review", "build_returns_review", "review_returns_result", "result_returns_main", "keyboard_ending_commit", "keyboard_ending_archive_read"), "finished combat never resumes; ending is committed before archive viewing")
    check("replacement confirmation and save transfer are keyboard safe", observed("cancel_preserves_checkpoint", "keyboard_import_commit", "keyboard_import_undo", "keyboard_exit_cancel") and 'if save_current_run(): show_menu("title")' in source, "overwrite cancel preserves snapshot; import and undo commit paired saves; failed writes hold menu")
    check("design document records comparison, graph, save and keyboard boundaries", all(section in doc for section in ["## 差异审计", "## 菜单状态机", "## 存档模型", "## 角色成就规则", "## 操作契约"]) and "不通过地图按钮或直接修改房间编号跳层" in doc and "尚未实现原作贪婪" in doc, "remaining game-mode and completion-mark differences are explicit")
    binary = ROOT / build["path"]
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    check("all native evidence verifies the same current compiled executable", keyboard.get("passed") and not keyboard.get("failures") and all(item["passed"] for item in native.get("interaction_checks", [])) and all(item["saved"] and item.get("state_stable") for item in native.get("captures", [])) and digest == build["sha256"] == keyboard.get("artifact_sha256") == native.get("artifact_sha256"), "keyboard behavior, ordinary native GUI and viewport captures share the executable hash")
    failures = [item["name"] for item in checks if not item["passed"]]
    report = {"recorded_at": datetime.now(timezone.utc).isoformat(), "passed": not failures,
              "checks": checks, "failures": failures, "compiled_windows_sha256": digest,
              "native_interaction_checks": len(native.get("interaction_checks", [])),
              "keyboard_checks": len(behavior), "keyboard_driver": keyboard.get("driver"),
              "hierarchy": ["splash -> files -> main -> character/challenges/stats/options",
                            "room -> pause -> history/achievements/settings -> room",
                            "result -> review -> build -> review -> result -> main",
                            "save transfer -> preview -> commit or independent undo"],
              "scope": "source/document contract plus compiled native keyboard and GUI fixtures; optional rooms use arranged scenarios; not human balance or physical mobile acceptance"}
    (REPORTS / "runtime/menu-hierarchy-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = ["# 菜单与纯键盘闭环审计", "", "已编译程序的真实键盘事件与常规原生 GUI 回归共同核验层级。", "",
             "标题 → 三份存档 → 主菜单 → 新局／挑战／记录／设置；Esc 按父页返回。", "",
             f"纯键盘检查 {len(behavior)} 项；常规原生交互 {len(native.get('interaction_checks', []))} 项。", "",
             "| 检查 | 结果 | 证据 |", "| --- | --- | --- |"]
    lines += [f"| {item['name']} | {'通过' if item['passed'] else '失败'} | {item['detail']} |" for item in checks]
    lines += ["", "边界：可选房间由固定场景准备；不替代真人三章体验、移动设备或原生系统文件选择器验收。", "",
              "详细差异：[菜单文档](../../22-menu-save-achievements.md)。", "",
              "重跑：python tools/runtime/run_keyboard_qa.py --packaged，然后 python tools/runtime/audit_menu_hierarchy.py。", ""]
    (REPORTS / "runtime/menu-hierarchy-audit.md").write_text("\n".join(lines), "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "keyboard_checks": len(behavior), "failures": failures}, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
