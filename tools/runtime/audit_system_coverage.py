"""Build a machine-readable coverage matrix for the Direction 01 product systems.

The matrix is intentionally evidence based: a design row can be complete in the
catalog while its device or human acceptance remains pending. It never upgrades
those pending boundaries just because a file exists.
"""

from datetime import datetime, timezone
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
RUNTIME = REPORTS / "runtime"


def read(relative: str, default=None):
    path = ROOT / relative
    if not path.is_file():
        return default
    return json.loads(path.read_text("utf8"))


def exists(*relative_paths: str) -> bool:
    return all((ROOT / path).is_file() for path in relative_paths)


def passed(report) -> bool:
    return bool(report and report.get("passed") and not report.get("failures"))


def row(system, purpose, design, data, runtime, verification, assets, status, evidence, open_boundary=""):
    return {
        "system": system,
        "purpose": purpose,
        "design": design,
        "data": data,
        "runtime": runtime,
        "verification": verification,
        "assets": assets,
        "status": status,
        "evidence": evidence,
        "open_boundary": open_boundary,
    }


def main() -> None:
    catalog = read("docs/incense-debt/data/catalog.json", {})
    rules = read("docs/incense-debt/data/rules.json", {})
    asset_report = read("docs/incense-debt/reports/runtime/asset-verification.json", {})
    exploration = read("docs/incense-debt/reports/runtime/exploration-encounters-tests.json", {})
    content = read("docs/incense-debt/reports/runtime/expanded-content-tests.json", {})
    campaign = read("docs/incense-debt/reports/runtime/campaign-rules-tests.json", {})
    impact = read("docs/incense-debt/reports/runtime/impact-resume-tests.json", {})
    route_navigation = read("docs/incense-debt/reports/runtime/route-navigation-tests.json", {})
    synergy = read("docs/incense-debt/reports/runtime/synergy-matrix-tests.json", {})
    weapon_special = read("docs/incense-debt/reports/runtime/weapon-special-room-tests.json", {})
    weapon_motion = read("docs/incense-debt/reports/runtime/weapon-motion-tests.json", {})
    save_transfer = read("docs/incense-debt/reports/runtime/save-transfer-tests.json", {})
    audio = read("docs/incense-debt/reports/runtime/adaptive-music-tests.json", {})
    native = read("docs/incense-debt/reports/platforms/windows/native-render.json", {})
    native_audio = read("docs/incense-debt/reports/platforms/windows/audio/native-audio.json", {})
    android = read("docs/incense-debt/reports/platforms/android-verification.json", {})
    ios_handoff = read("docs/incense-debt/reports/platforms/ios-handoff-verification.json", {})
    platform_parity = read("docs/incense-debt/reports/platforms/platform-parity.json", {})
    full_runs = read("docs/incense-debt/reports/runtime/full-run-tests.json", {})
    route_matrix = read("docs/incense-debt/reports/runtime/route-matrix-tests.json", {})
    ui_refresh = read("docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json", {})
    platform_contract = read("docs/incense-debt/reports/runtime/platform-contract-tests.json", {})
    daily_run = read("docs/incense-debt/reports/runtime/daily-run-tests.json", {})
    choice_history = read("docs/incense-debt/reports/runtime/choice-history-tests.json", {})
    achievements = read("docs/incense-debt/reports/runtime/achievement-tests.json", {})
    menu_hierarchy = read("docs/incense-debt/reports/runtime/menu-hierarchy-audit.json", {})
    visual_contract = read("docs/incense-debt/reports/runtime/visual-contract-audit.json", {})
    telemetry = read("docs/incense-debt/reports/runtime/run-telemetry-tests.json", {})
    loot_sampling = read("docs/incense-debt/reports/runtime/loot-sampling-tests.json", {})
    direction1 = read("docs/incense-debt/reports/runtime/direction1-system-audit.json", {})
    external = read("docs/incense-debt/reports/external-acceptance.json", {})
    android_resource_count = platform_parity.get("android_packaging", {}).get("imported_resource_count", android.get("asset_count", 0))
    game_member_count = platform_parity.get("source_tree", {}).get("windows_game_member_count", 0)

    core_verified = passed(exploration) and passed(route_navigation) and exists(
        "docs/incense-debt/02-game-loop-levels.md",
        "game/scripts/combat/world.gd",
        "game/scripts/ui/route_map.gd",
    )
    combat_verified = passed(impact) and exists(
        "docs/incense-debt/04-combat-hit-feedback.md",
        "game/scripts/combat/effects.gd",
        "game/scripts/combat/impact_control.gd",
        "game/scripts/ui/game_renderer.gd",
    )
    content_verified = passed(content) and passed(campaign) and passed(route_matrix) and passed(weapon_special) and passed(direction1) and exists(
        "docs/incense-debt/03-playable-characters.md",
        "docs/incense-debt/05-progression-builds.md",
        "docs/incense-debt/06-loot-economy-debt.md",
        "docs/incense-debt/20-direction1-system-bible.md",
        "game/data/catalog.json",
        "game/data/rules.json",
    )
    direction_verified = passed(weapon_motion) and exists(
        "game/scripts/ui/weapon_motion.gd",
        "game/scripts/ui/game_renderer.gd",
        "game/assets/heroes/c_paper_down.png",
        "game/assets/heroes/c_paper_left.png",
        "game/assets/heroes/c_paper_right.png",
        "game/assets/heroes/c_paper_up.png",
    )
    art_verified = passed(asset_report) and passed(ui_refresh) and passed(choice_history) and passed(achievements) and passed(visual_contract) and exists(
        "docs/incense-debt/10-art-bible.md",
        "docs/incense-debt/11-asset-production.md",
        "docs/incense-debt/17-visual-contract.md",
    )
    audio_verified = passed(audio) and passed(native_audio) and exists(
        "docs/incense-debt/12-audio-narrative.md",
        "game/scripts/ui/audio_director.gd",
    )
    rows = [
        row(
            "核心循环与物理房间门",
            "清房、方向门、回访、断绳入口和地图只读展示",
            "docs/incense-debt/02-game-loop-levels.md",
            "game/data/catalog.json:regions,room_templates",
            "game/scripts/combat/world.gd; game/scripts/ui/route_map.gd",
            "runtime/exploration-encounters-tests.json; runtime/route-navigation-tests.json; platforms/windows/door-navigation.png",
            "game/assets/environment; game/assets/props; game/assets/ui",
            "verified_alpha" if core_verified else "missing",
            "物理门口移动、南北东西四向阈值、反向到达、反方向拒绝和秘密入口方向均有规则与原生画面证据。",
            "手机真机触控与长时运行仍属设备验收。",
        ),
        row(
            "角色、武器与成长路线",
            "六角色、本职天赋、十六武器、十八技能、六路线和局外解锁",
            "docs/incense-debt/03-playable-characters.md; docs/incense-debt/05-progression-builds.md",
            "game/data/catalog.json:characters,weapons,skills,relics,talents; game/data/rules.json",
            "game/scripts/combat/world.gd; game/scripts/core/meta_progress.gd",
            "runtime/expanded-content-tests.json; runtime/campaign-rules-tests.json; runtime/full-run-tests.json; runtime/route-matrix-tests.json",
            "game/assets/heroes; game/assets/skills; game/assets/relics",
            "verified_alpha" if content_verified else "missing",
            "完整内容引用、路线资格、技能演化和六角色两条本职路线的自动覆盖已通过。",
            "真人每角色两条路线的手感与构筑验收仍未完成。",
        ),
        row(
            "每日种子与可复现挑战",
            "按本地日期生成固定种子、初始供物池和可恢复的离线挑战",
            "docs/incense-debt/02-game-loop-levels.md; docs/incense-debt/05-progression-builds.md",
            "game/scripts/core/daily_seed.gd; game/scripts/combat/world.gd",
            "game/scripts/core/meta_progress.gd; game/scripts/core/save_migrations.gd; game/scripts/ui/hub_ui.gd",
            "runtime/daily-run-tests.json; platforms/windows/hub.png",
            "game/assets/ui/icons/crown.svg",
            "verified_alpha" if passed(daily_run) else "missing",
            "日期、规则版本和固定初始池组成稳定挑战身份；每日局可存档恢复，但不会写入善缘、解锁或路线历史。",
            "跨设备相同日期的实际运行与排行榜服务仍未声明，设备验收继续独立。",
        ),
        row(
            "特殊房间与一局成长账本",
            "商店、献灯、判官、观音、破阵分支；心火代价、三轮战斗、武器/遗物/天赋奖励和单次领取",
            "docs/incense-debt/06-loot-economy-debt.md; docs/incense-debt/07-skills-synergies.md",
            "game/data/catalog.json:special_rooms; game/scripts/combat/world.gd:special_room_choices",
            "game/scripts/combat/world.gd; game/scripts/core/save_migrations.gd; game/scripts/ui/modern_ui.gd; game/scripts/ui/game_renderer.gd",
            "runtime/weapon-special-room-tests.json; runtime/save-transfer-tests.json",
            "game/assets/props/special_sacrifice.png; game/assets/props/special_judge.png; game/assets/props/special_angel.png; game/assets/props/chest.png; game/assets/ui/icons",
            "verified_alpha" if passed(weapon_special) else "missing",
            "四类特殊房间均由路线图实际可达；交易房每间只可领取一次，破阵房固定三轮后开放高阶供物；奖励发放、growth_log 和 special_rooms 会随存档恢复。",
            "真实玩家对代价/收益的长期平衡仍需验收。",
        ),
        row(
            "掉落概率与探索经济",
            "每层稀有度、有效候选、三选一去重、路线偏好、治疗保底、灯摊购买力和三层现金曲线",
            "docs/incense-debt/06-loot-economy-debt.md; docs/incense-debt/14-balance-telemetry.md",
            "game/data/rules.json:loot; game/data/catalog.json:relics",
            "game/scripts/combat/world.gd:relic_offer,generate_heal,clear_room; game/tests/loot_sampling.gd",
            "runtime/loot-sampling-tests.json; runtime/loot-sampling-tests.md",
            "game/assets/relics; game/assets/ui/icons",
            "verified_alpha" if passed(loot_sampling) else "missing",
            "三层各10,000次稀有度抽样、1,000组三选一完整性、10,000次治疗概率/保底和10,000个三层主路径经济情景均由共享World与rules.json直接生成；报告保留期望/观察误差、候选池、均值/P10/P90和灯摊前底线。",
            "抽样是规则基线，不替代真人购买、可选支路、债约利息和长期经济体验验收。",
        ),
        row(
            "战斗、命中与打击反馈",
            "标记、债链、焚债、击退、预警、闪避、爆炸和死亡反馈",
            "docs/incense-debt/04-combat-hit-feedback.md",
            "game/data/rules.json:combat; game/data/catalog.json:weapons,skills,enemies,bosses",
            "game/scripts/combat/effects.gd; game/scripts/combat/impact_control.gd; game/scripts/ui/game_renderer.gd",
            "runtime/impact-resume-tests.json; runtime/synergy-matrix-tests.json; platforms/windows/detonate.png",
            "game/assets/skills; game/assets/weapons; game/assets/weapon-bodies; game/assets/held-weapons; game/assets/enemies",
            "verified_alpha" if combat_verified else "missing",
            "延迟攻击、实际碰撞、物理击退和丰富粒子反馈均从共享 World 结算。",
            "真人连射压制感、闪避时机和低端设备粒子舒适度仍需实测。",
        ),
        row(
            "组合搭配与构筑图鉴",
            "二十四套组合的可达路径、组合册和结果/代价说明",
            "docs/incense-debt/07-skills-synergies.md; docs/incense-debt/17-visual-contract.md",
            "game/data/catalog.json:synergies",
            "game/scripts/combat/world.gd:synergy_rows,active_synergies; game/scripts/ui/modern_ui.gd",
            "runtime/synergy-matrix-tests.json; platforms/windows/inventory-synergy.png",
            "game/assets/ui/icons",
            "verified_alpha" if passed(synergy) else "missing",
            "每套组合均由真实主攻、焚债、收灰、身法、招架或清房路径触发，没有隐藏套装奖励。",
            "完整组合的真人理解成本与三章胜率仍需观察。",
        ),
        row(
            "方向性角色朝向与手持动作",
            "射击方向驱动身体朝向、握点、枪口和四向动画",
            "docs/incense-debt/03-playable-characters.md; docs/incense-debt/17-visual-contract.md",
            "game/data/catalog.json:characters,weapons",
            "game/scripts/ui/weapon_motion.gd; game/scripts/ui/game_renderer.gd",
            "runtime/weapon-motion-tests.json; platforms/windows/held-brush-fire.png",
            "game/assets/heroes; game/assets/weapons",
            "verified_alpha" if direction_verified else "missing",
            "六角色×十六器具与四向身体/握点覆盖已接入，攻击方向不再固定朝向。",
            "透明边、真人动作观感和移动端小屏识别度仍需设备验收。",
        ),
        row(
            "叙事、NPC与局外回收",
            "世界背景、五名 NPC、故事页、结局、愿簿和个人任务",
            "docs/incense-debt/01-world-story.md; docs/incense-debt/05-progression-builds.md",
            "game/data/catalog.json:npcs; game/data/rules.json:story",
            "game/scripts/main.gd; game/scripts/core/meta_progress.gd",
            "runtime/campaign-rules-tests.json; platforms/windows/story.png; platforms/windows/endings.png",
            "game/assets/npcs; game/assets/portraits; game/assets/bosses",
            "verified_alpha" if passed(campaign) else "missing",
            "故事门槛、姓名页去重、结局保存和训练隔离已有规则/GUI证据。",
            "全量多语言字典尚未建立，当前首版以简体中文为主。",
        ),
        row(
            "UI、字体、图标与美术一致性",
            "圆角现代 UI、图标优先、字体、色板、地图和特效契约",
            "docs/incense-debt/09-ui-ux-input.md; docs/incense-debt/10-art-bible.md; docs/incense-debt/17-visual-contract.md",
            "docs/incense-debt/data/asset-manifest.json",
            "game/scripts/ui/modern_ui.gd; game/scripts/ui/game_renderer.gd",
            "runtime/ui-refresh/ui-refresh.json; runtime/visual-baseline.json; runtime/visual-contract-audit.json; runtime/choice-history-tests.json; platforms/windows/ui-style.png; platforms/windows/native-render.json",
            "docs/incense-debt/reports/runtime/asset-verification.json",
            "verified_alpha" if art_verified else "missing",
            f"三张Sub2概念板、运行截图、字体、57 个矢量图标、{native.get('interaction_checks', 0) if isinstance(native.get('interaction_checks', 0), int) else len(native.get('interaction_checks', []))} 项原生 GUI 检查和本局成长记录报告相互对照；PC 数字键 1—4 可直接提交候选。",
            "用户最终审美确认、真人色觉与动态舒适度属于后续体验验收。",
        ),
        row(
            "声音与动态配乐",
            "主攻击、命中、警告、技能、门和三层动态音乐",
            "docs/incense-debt/12-audio-narrative.md",
            "docs/incense-debt/data/asset-manifest.json:audio,music",
            "game/scripts/ui/audio_director.gd; game/scripts/ui/music_state.gd",
            "runtime/adaptive-music-tests.json; platforms/windows/audio/native-audio.json",
            "game/assets/audio",
            "verified_alpha" if audio_verified else "missing",
            "资源解码、分层切换、循环接缝、暂停衰减和静音均有技术录音证据。",
            "手机扬声器、耳机和长时听觉舒适度仍需人耳验收。",
        ),
        row(
            "存档、恢复与跨端传递",
            "账号/单局分离、schema 迁移、文件与压缩文字传递和失败回滚",
            "docs/incense-debt/13-cross-platform-engineering.md",
            "game/data/rules.json:save; game/scripts/core/save_migrations.gd",
            "game/scripts/core/save_session.gd; game/scripts/core/save_transfer.gd",
            "runtime/save-transfer-tests.json; runtime/legacy-save-fixtures.json",
            "build/ios-handoff; build/android",
            "verified_alpha" if passed(save_transfer) else "missing",
            "真实 schema1 冻结文件、同输入续局、领取去重、预览确认和失败回滚已验证。",
            "手机系统文件选择器、软键盘、剪贴板和真实跨设备导入仍待设备验收。",
        ),
        row(
            "菜单、愿簿槽位与角色成就",
            "开场、三槽位、主菜单、角色/挑战/记录层级、纯键盘导航和 32 项角色/账户成就",
            "docs/incense-debt/22-menu-save-achievements.md",
            "game/data/achievements.json; game/scripts/core/save_slots.gd",
            "game/scripts/main.gd; game/scripts/ui/menu_flow.gd; game/scripts/ui/keyboard_navigation.gd; game/scripts/core/meta_progress.gd; game/scripts/core/save_migrations.gd",
            "runtime/achievement-tests.json; runtime/choice-history-tests.json; runtime/menu-hierarchy-audit.json; platforms/windows/keyboard/keyboard-flow.json",
            "game/assets/ui/icons; game/assets/fonts",
            "verified_alpha" if passed(achievements) and passed(menu_hierarchy) and exists("docs/incense-debt/22-menu-save-achievements.md", "game/scripts/core/save_slots.gd") else "missing",
            "开场→槽位→主菜单→角色/挑战/记录的层级、逐层返回和焦点恢复已由打包后的原生键盘事件验证；角色成就按 run.id 幂等计数，训练/每日挑战隔离。",
            "原生键盘和桌面截图证据不能替代真人菜单信息密度、长期成就节奏与设备返回键体验。",
        ),
        row(
            "局后平衡观测",
            "把正式局的角色、路线、构筑、受击、资源和结果整理为本地可复现样本",
            "docs/incense-debt/14-balance-telemetry.md",
            "game/scripts/core/run_telemetry.gd",
            "game/scripts/main.gd; game/tests/run_telemetry.gd",
            "runtime/run-telemetry-tests.json; runtime/route-matrix-tests.json",
            "user://run_telemetry.jsonl（本地）",
            "verified_alpha" if passed(telemetry) and exists("game/scripts/core/run_telemetry.gd", "docs/incense-debt/14-balance-telemetry.md") else "missing",
            "正式局终局事件写入 JSONL，按 run_id/result 幂等，并排除训练与每日挑战。",
            "结构化本地样本仍需真人多角色、多路线和设备数据才能形成平衡结论。",
        ),
        row(
            "输入与跨平台运行",
            "鼠键、手柄、双摇杆触控、安全区、后台恢复和三端构建",
            "docs/incense-debt/09-ui-ux-input.md; docs/incense-debt/13-cross-platform-engineering.md",
            "game/data/rules.json:input; game/data/rules.json:platform",
            "game/scripts/ui/input_adapter.gd; game/scripts/ui/touch_layout_editor.gd",
            "runtime/advanced-input-tests.json; platforms/android-verification.json; platforms/ios-handoff-verification.json; platforms/platform-parity.json; platforms/windows/native-render.json",
            "build/windows; build/android; build/ios-handoff",
            "verified_release" if external.get("android_device", {}).get("passed") and external.get("ios_device", {}).get("passed") else ("pending_device" if not android.get("physical_device_tested", False) else "verified_alpha"),
            f"软件路径、桌面原生 GUI、Windows 包、Android 包和 iOS 共享源码交接完整性均已核验；Windows/iOS 的 {game_member_count} 个 game 文件逐项一致，Android 的 {android_resource_count} 项运行资源与核心内容通过包内核对。" if passed(platform_parity) else "软件路径、桌面原生 GUI、Windows 包、Android 包和 iOS 共享源码交接已部分核验。",
            "Android 真机安装/触控/热稳定及 macOS/Xcode 签名、iOS 真机仍缺证据。",
        ),
        row(
            "跨端预算与生命周期契约",
            "固定帧率、弹丸/VFX 上限、内存预算、触控安全区、横屏滞回、触觉和字体资源",
            "docs/incense-debt/13-cross-platform-engineering.md; docs/incense-debt/19-release-readiness.md",
            "game/data/rules.json:platforms",
            "game/scripts/ui/input_adapter.gd; game/scripts/ui/orientation_guard.gd; game/scripts/ui/haptic_feedback.gd",
            "runtime/platform-contract-tests.json",
            "game/assets/fonts; game/data/runtime_assets.json",
            "verified_alpha" if passed(platform_contract) else "missing",
            "共享平台契约以36项固定检查锁定预算、安全区几何、横屏恢复、触觉优先级、动态质量 governor、弹丸上限和字体/资源注册；不把它写成真机性能结果。",
            "真实设备帧率、温度、扬声器和系统文件接口仍需外部验收。",
        ),
        row(
            "方向 01 稳定 ID 到运行钩子",
            "逐条核对角色、路线、武器、技能、遗物、行愿、组合、房间、敌人、精英、Boss 与债约",
            "docs/incense-debt/20-direction1-system-bible.md; docs/incense-debt/16-content-catalog.generated.md",
            "game/data/catalog.json; game/data/rules.json",
            "tools/runtime/audit_direction1_system.py; game/scripts/combat/world.gd; game/scripts/combat/effects.gd",
            "runtime/direction1-system-audit.json; runtime/expanded-content-tests.json; runtime/synergy-matrix-tests.json",
            "game/assets; docs/incense-debt/reports/runtime/asset-verification.json",
            "verified_alpha" if passed(direction1) else "missing",
            "接受数据驱动分派；不要求每个 ID 都写成硬编码分支。54 件遗物和36个行愿均有 combat hook，24 套组合逐 ID 通过，18 个技能、24 个敌人、5 个 Boss、6 个精英和四类特殊房间均有完整数据/运行链。",
            "自动覆盖仍不替代真人构筑平衡和移动设备验收。",
        ),
        row(
            "平衡与正式发布",
            "每角色两路线、三端完整通关、性能、人工手感和发布签名",
            "docs/incense-debt/00-product-vision.md; docs/incense-debt/14-balance-telemetry.md; docs/incense-debt/15-production-validation.md",
            "docs/incense-debt/data/catalog.json; docs/incense-debt/data/rules.json",
            "game/tests/full_run.gd; tools/runtime/record_delivery.py",
            "runtime/full-run-tests.json; reports/current-product-status.json",
            "build/windows; build/android; build/ios-handoff",
            "verified_release" if external.get("release_ready", False) else "pending_human_and_device",
            "自动固定 tick 样本已覆盖六角色×两种演化并正常终局，但这不是玩家胜率。",
            "真人每角色两条路线、移动端长时性能、iOS 签名与三端实机通关仍是 Alpha 的明确边界。",
        ),
    ]

    counts = {
        "characters": len(catalog.get("characters", [])),
        "weapons": len(catalog.get("weapons", [])),
        "skills": len(catalog.get("skills", [])),
        "relics": len(catalog.get("relics", [])),
        "talents": len(catalog.get("talents", [])),
        "synergies": len(catalog.get("synergies", [])),
        "routes": len(catalog.get("routes", [])),
        "regions": len(catalog.get("regions", [])),
        "room_templates": len(catalog.get("room_templates", [])),
        "special_rooms": len(catalog.get("special_rooms", [])),
        "rules": len(rules),
    }
    status_counts = {}
    for item in rows:
        status_counts[item["status"]] = status_counts.get(item["status"], 0) + 1
    result = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "version": "0.1.0",
        "status": "playable_three_chapter_alpha",
        "matrix_status": "audited",
        "catalog_counts": counts,
        "status_counts": status_counts,
        "full_run": {
            "passed": passed(full_runs),
            "runs": len(full_runs.get("runs", [])),
            "victories": sum(x.get("result") == "victory" for x in full_runs.get("runs", [])),
            "defeats": sum(x.get("result") == "defeat" for x in full_runs.get("runs", [])),
            "method": full_runs.get("method", ""),
        },
        "route_matrix": {
            "passed": passed(route_matrix),
            "runs": len(route_matrix.get("runs", [])),
            "victories": sum(x.get("result") == "victory" for x in route_matrix.get("runs", [])),
            "focus_routes": sorted({x.get("focus_route") for x in route_matrix.get("runs", [])}),
            "method": route_matrix.get("method", ""),
        },
        "native": {
            "asset_loads": native.get("asset_loads", 0),
            "captures": len(native.get("captures", [])),
            "interaction_checks": len(native.get("interaction_checks", [])),
        },
        "rows": rows,
        "global_boundaries": [
            "这张矩阵把实现覆盖、自动规则证据、人工体验验收和设备验收分开记录。",
            "pending_human_and_device 不会因为自动 Bot 胜利或资源加载而升级。",
            "首版文字仍以简体中文为主，完整本地化字典属于后续产品阶段。",
        ],
    }
    json_path = REPORTS / "system-coverage.json"
    json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 方向 01 系统覆盖矩阵",
        "",
        "这张表把《香火债》的设计来源、数据、运行代码、验证报告和素材证据放在同一条链路上。`verified_alpha` 代表当前 Alpha 的软件与素材证据已经闭环；`pending_device`、`pending_human_and_device` 保留正式发布所需的真实设备或人工体验边界。",
        "",
        f"记录时间：{result['recorded_at']}。目录统计：六角色 {counts['characters']}、武器 {counts['weapons']}、技能 {counts['skills']}、遗物 {counts['relics']}、行愿 {counts['talents']}、组合 {counts['synergies']}、路线 {counts['routes']}、区域 {counts['regions']}、房间模板 {counts['room_templates']}、特殊房间 {counts['special_rooms']}。",
        "",
        "## 覆盖表",
        "",
        "| 系统 | 设计来源 | 数据 | 运行代码 | 直接验证 | 素材/构建 | 状态 | 当前边界 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in rows:
        lines.append(
            f"| {item['system']} | {item['design']} | {item['data']} | {item['runtime']} | {item['verification']} | {item['assets']} | **{item['status']}** | {item['open_boundary']} |"
        )
    lines += [
        "",
        "## 证据口径",
        "",
        "- 自动固定 tick 样本用于发现规则回归和构筑覆盖；它不等于真人胜率、手感或难度结论。",
        "- 运行截图只证明编译程序的实际状态，与概念图和视觉约定一起使用，不把截图相似度写成百分比。",
        f"- Android 包签名、资源和软件路径已核验；Windows 工程与 iOS 共享源码的全部 game 文件逐项一致，Android APK 的 {android_resource_count} 项运行资源与六份核心 JSON/武器绑定已做静态包内比对。物理设备安装、触控、文件选择器、热稳定仍需真实设备。",
        "- 所有素材生产仍以批准的 Sub2/gpt-image-2.5 参考图、资产清单和许可记录为来源，未经验证的 planned 素材不能计入交付。",
        "",
        "机器可读报告：[system-coverage.json](reports/system-coverage.json)。重新生成：",
        "",
        "```powershell",
        "python -X utf8 tools/runtime/audit_system_coverage.py",
        "```",
        "",
    ]
    (REPORTS.parent / "18-system-coverage.md").write_text("\n".join(lines), "utf8")
    print(json.dumps({"passed": True, "status_counts": status_counts, "json": str(json_path), "markdown": str(REPORTS.parent / "18-system-coverage.md")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
