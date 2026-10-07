"""Build a requirement-by-requirement completion audit for Incense Debt.

The audit intentionally keeps software evidence separate from physical-device
and human-acceptance gates. A green file or automated run cannot promote those
external gates by itself.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"


def read_json(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text("utf8"))


def passed_report(relative: str) -> bool:
    return bool(read_json(relative).get("passed", False))


def requirement(key: str, title: str, status: str, evidence: list[str], boundary: str, details: str) -> dict:
    return {"key": key, "title": title, "status": status, "evidence": evidence, "boundary": boundary, "details": details}


def main() -> None:
    current = read_json("docs/incense-debt/reports/current-product-status.json")
    readiness = read_json("docs/incense-debt/reports/release-readiness.json")
    design = read_json("docs/incense-debt/reports/design-validation.json")
    native = read_json("docs/incense-debt/reports/platforms/windows/native-render.json")
    android = read_json("docs/incense-debt/reports/platforms/android-verification.json")
    ios = read_json("docs/incense-debt/reports/platforms/ios-handoff-verification.json")
    parity = read_json("docs/incense-debt/reports/platforms/platform-parity.json")
    ui = read_json("docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json")
    audio = read_json("docs/incense-debt/reports/platforms/windows/audio/native-audio.json")
    full_run = read_json("docs/incense-debt/reports/runtime/full-run-tests.json")
    route_matrix = read_json("docs/incense-debt/reports/runtime/route-matrix-tests.json")
    telemetry = read_json("docs/incense-debt/reports/runtime/run-telemetry-tests.json")
    route_balance = read_json("docs/incense-debt/reports/runtime/route-balance-baseline.json")
    loot_sampling = read_json("docs/incense-debt/reports/runtime/loot-sampling-tests.json")
    assets = read_json("docs/incense-debt/reports/runtime/asset-verification.json")
    direction1 = read_json("docs/incense-debt/reports/runtime/direction1-system-audit.json")
    menu_hierarchy = read_json("docs/incense-debt/reports/runtime/menu-hierarchy-audit.json")
    visual_contract = read_json("docs/incense-debt/reports/runtime/visual-contract-audit.json")
    external = read_json("docs/incense-debt/reports/external-acceptance.json") if (REPORTS / "external-acceptance.json").is_file() else {}

    root_docs = REPORTS.parent
    numbered_docs = sorted(root_docs.glob("[0-2][0-9]-*.md"))
    docs_ok = (root_docs / "README.md").is_file() and len(numbered_docs) == 23 and (root_docs / "20-direction1-system-bible.md").is_file() and (root_docs / "21-external-acceptance-runbook.md").is_file() and (root_docs / "22-menu-save-achievements.md").is_file()
    full_victories = sum(1 for row in full_run.get("runs", []) if row.get("result") == "victory")
    route_victories = sum(1 for row in route_matrix.get("runs", []) if row.get("result") == "victory")
    counts = design.get("content_counts", {})
    resource_count = int(current.get("native_resources_loaded", 0))
    asset_resource_count = int(assets.get("native_assets_loaded", 0))
    music_stems = int(current.get("music_stems", assets.get("music_stems", 0)))
    music_themes = int(current.get("music_themes", assets.get("music_themes", 0)))

    android_external = external.get("android_device", {})
    ios_external = external.get("ios_device", {})
    human_external = external.get("human_balance", {})
    requirements = [
        requirement("design_and_docs", "方向1设计、故事、交互与配套文档",
                     "verified_alpha" if docs_ok and design.get("status") == "design_constraints_passed" else "failed",
	                     ["docs/incense-debt/README.md", "docs/incense-debt/00-product-vision.md", "docs/incense-debt/19-release-readiness.md", "docs/incense-debt/20-direction1-system-bible.md", "docs/incense-debt/21-external-acceptance-runbook.md", "docs/incense-debt/22-menu-save-achievements.md", "docs/incense-debt/reports/design-validation.json"],
	                     "设计审计通过仍不等于真人审美确认。", f"README 与 00–22 共 {len(numbered_docs) + 1} 份文档；设计数据约束通过。"),
        requirement("playable_loop", "三章可玩循环、房间探索与物理门切换",
                     "verified_alpha" if full_victories == 12 and passed_report("docs/incense-debt/reports/runtime/route-navigation-tests.json") else "failed",
                     ["docs/incense-debt/reports/runtime/full-run-tests.json", "docs/incense-debt/reports/runtime/route-navigation-tests.json", "docs/incense-debt/reports/platforms/windows/door-navigation.png"],
                     "完整真人整局手感仍需记录。", f"三章自动整局 {full_victories}/12 胜利；物理门导航规则通过。"),
        requirement("characters_and_growth", "多角色、多路线、技能演化与局外成长",
                     "verified_alpha" if counts.get("characters") == 6 and counts.get("routes") == 6 and counts.get("skills") == 18 and route_victories == 24 and route_balance.get("source_samples") == 24 and len(route_balance.get("route_rows", [])) == 12 else "failed",
                     ["docs/incense-debt/03-playable-characters.md", "docs/incense-debt/05-progression-builds.md", "docs/incense-debt/reports/runtime/route-matrix-tests.json", "docs/incense-debt/reports/runtime/route-balance-baseline.json", "docs/incense-debt/reports/runtime/campaign-rules-tests.json"],
                     "六角色双路线真人平衡尚未完成。", f"角色 {counts.get('characters')}、路线 {counts.get('routes')}、技能 {counts.get('skills')}；路线矩阵 {route_victories}/24 胜利。"),
        requirement("run_telemetry", "局后平衡观测与本地样本记录",
                     "verified_alpha" if telemetry.get("passed") and not telemetry.get("failures") else "failed",
                     ["docs/incense-debt/14-balance-telemetry.md", "game/scripts/core/run_telemetry.gd", "game/tests/run_telemetry.gd", "docs/incense-debt/reports/runtime/run-telemetry-tests.json"],
                     "本地结构化记录不替代真人平衡、设备性能和听测验收。", f"局后观测 {len(telemetry.get('checks', []))} 项检查通过；按 run_id/result 幂等并隔离训练/每日挑战。"),
        requirement("loot_and_synergies", "掉落、商店、特殊房间、债约与组合搭配",
                     "verified_alpha" if counts.get("relics") == 54 and counts.get("talents") == 36 and counts.get("synergies") == 24 and counts.get("special_rooms") == 4 and passed_report("docs/incense-debt/reports/runtime/shop-trial-tests.json") and passed_report("docs/incense-debt/reports/runtime/synergy-matrix-tests.json") and passed_report("docs/incense-debt/reports/runtime/weapon-special-room-tests.json") and passed_report("docs/incense-debt/reports/runtime/daily-run-tests.json") and loot_sampling.get("passed") and not loot_sampling.get("failures") else "failed",
                     ["docs/incense-debt/06-loot-economy-debt.md", "docs/incense-debt/07-skills-synergies.md", "docs/incense-debt/reports/runtime/shop-trial-tests.json", "docs/incense-debt/reports/runtime/synergy-matrix-tests.json", "docs/incense-debt/reports/runtime/daily-run-tests.json", "docs/incense-debt/reports/runtime/loot-sampling-tests.json"],
                     "掉落概率与组合收益仍需真人长期观察。", f"遗物 {counts.get('relics')}、行愿 {counts.get('talents')}、组合 {counts.get('synergies')}、特殊房间 {counts.get('special_rooms')}；商店、特殊房间、每日固定池、组合矩阵和每层10,000次掉落/三层经济抽样通过。"),
        requirement("combat_and_feedback", "武器类型、打击、方向朝向与粒子反馈",
                     "verified_alpha" if passed_report("docs/incense-debt/reports/runtime/weapon-special-room-tests.json") and passed_report("docs/incense-debt/reports/runtime/weapon-motion-tests.json") and passed_report("docs/incense-debt/reports/runtime/impact-resume-tests.json") else "failed",
                     ["docs/incense-debt/04-combat-hit-feedback.md", "docs/incense-debt/reports/runtime/weapon-special-room-tests.json", "docs/incense-debt/reports/runtime/weapon-motion-tests.json", "docs/incense-debt/reports/runtime/impact-resume-tests.json", "docs/incense-debt/reports/platforms/windows/detonate.png"],
                     "低端设备粒子舒适度与真人操作手感仍需设备/人工验收。", "十六种武器模式、四向持械、击退/束缚/延迟攻击续局及原生打击画面均有证据。"),
        requirement("audio_and_visuals", "地图音乐、音效、素材来源与锁定美术风格",
                     "verified_alpha" if passed_report("docs/incense-debt/reports/runtime/adaptive-music-tests.json") and audio.get("passed", False) and resource_count == asset_resource_count else "failed",
                     ["docs/incense-debt/12-audio-narrative.md", "docs/incense-debt/reports/runtime/adaptive-music-tests.json", "docs/incense-debt/reports/platforms/windows/audio/native-audio.json", "docs/incense-debt/reports/runtime/audio-design-verification.json", "docs/incense-debt/reports/runtime/audio-source-research.json", "docs/incense-debt/reports/runtime/asset-verification.json", "output/imagegen/incense-debt/special-room-prop-board.png"],
                     "手机扬声器、耳机及真人长局听测尚未完成。", f"{music_themes} 套音乐主题、{music_stems} 条分层音轨、{current.get('audio_files')} 份声音与 {resource_count} 项资源已通过软件验证。"),
        requirement("ui_and_input", "现代圆角 UI、图标、字体、PC 键盘与触控适配",
                     "verified_alpha" if ui.get("passed", False) and len(native.get("interaction_checks", [])) == 75 and passed_report("docs/incense-debt/reports/runtime/advanced-input-tests.json") and passed_report("docs/incense-debt/reports/runtime/choice-history-tests.json") and passed_report("docs/incense-debt/reports/runtime/achievement-tests.json") else "failed",
                     ["docs/incense-debt/09-ui-ux-input.md", "docs/incense-debt/22-menu-save-achievements.md", "docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json", "docs/incense-debt/reports/platforms/windows/ui-style.png", "docs/incense-debt/reports/runtime/advanced-input-tests.json", "docs/incense-debt/reports/runtime/choice-history-tests.json", "docs/incense-debt/reports/runtime/achievement-tests.json"],
                     "真实手机安全区、旋转和触控范围仍需设备验收。", f"圆角半径 {ui.get('panel_radius')}、{ui.get('vector_icons')} 个矢量图标、75 项原生 GUI 检查；Tab/方向键/Esc、PC 数字键 1—4、本局记录与触控契约已覆盖。"),
        requirement("menu_hierarchy", "以撒式菜单层级、返回边界与槽位审计",
                     "verified_alpha" if menu_hierarchy.get("passed") and not menu_hierarchy.get("failures") else "failed",
                     ["docs/incense-debt/22-menu-save-achievements.md", "docs/incense-debt/reports/runtime/menu-hierarchy-audit.json", "docs/incense-debt/reports/runtime/menu-hierarchy-audit.md", "docs/incense-debt/reports/platforms/windows/native-render.json"],
                     "桌面键盘与 GUI 场景证据不能替代真人信息密度、系统文件对话框和移动端菜单体验。", f"标题→槽位→主菜单→选角／挑战／记录／设置、暂停子页、复盘逐层返回及存档预览边界通过 {len(menu_hierarchy.get('checks', []))} 项审计，绑定 {menu_hierarchy.get('keyboard_checks', 0)} 项纯键盘及 {menu_hierarchy.get('native_interaction_checks', 0)} 项原生 GUI 检查。"),
        requirement("visual_contract", "Sub2视觉参考、风格绑定与运行时画面对照",
                     "verified_alpha" if visual_contract.get("passed") and not visual_contract.get("failures") else "failed",
                     ["docs/incense-debt/17-visual-contract.md", "docs/incense-debt/data/asset-manifest.json", "docs/incense-debt/assets/prompts/visual/menu-map-combat-board.txt", "docs/incense-debt/reports/runtime/visual-contract-audit.json", "docs/incense-debt/reports/runtime/visual-baseline.json"],
                     "视觉概念板与原生截图不能替代真人审美、低端设备透明边和最终设备显示验收。", f"{len(visual_contract.get('reviewed_concepts', []))} 张Sub2概念板的来源、尺寸、哈希、提示词与当前 {visual_contract.get('runtime_assets', 0)} 项运行时资源/{visual_contract.get('native_captures', 0)} 张截图绑定通过。"),
        requirement("save_and_resume", "存档迁移、回滚、传递与成长账本",
                     "verified_alpha" if current.get("save_schema") == 2 and passed_report("docs/incense-debt/reports/runtime/save-transfer-tests.json") and passed_report("docs/incense-debt/reports/runtime/achievement-tests.json") else "failed",
                     ["docs/incense-debt/13-cross-platform-engineering.md", "docs/incense-debt/22-menu-save-achievements.md", "docs/incense-debt/reports/runtime/save-transfer-tests.json", "docs/incense-debt/reports/runtime/achievement-tests.json", "docs/incense-debt/reports/runtime/ui-refresh/save-roundtrip-regression.json"],
                     "真实手机文件选择器、软键盘与剪贴板仍需设备验收。", "schema2、IEEE754 浮点编码、三槽位 journal、导入预览、失败回滚与成就幂等均已验证。"),
        requirement("windows_delivery", "Windows 原生可运行交付",
                     "verified_alpha" if readiness.get("checks", {}).get("windows_native") and not native.get("asset_failures") and len(native.get("captures", [])) == int(current.get("native_captures", 0)) else "failed",
                     ["build/windows/IncenseDebt.exe", "docs/incense-debt/reports/platforms/windows/native-render.json", "build/delivery-manifest.json"],
                     "真人完整整局与低端机器性能仍需补充。", f"Windows release 构建、{current.get('native_captures')} 张原生截图、{current.get('native_interaction_checks')} 项交互和 {current.get('native_resources_loaded')} 项资源加载通过。"),
        requirement("android_delivery", "Android 跨端包与共享内容",
                     "verified_release" if android_external.get("passed") and android.get("passed") and parity.get("passed") else ("pending_device" if android.get("passed") and parity.get("passed") and not current.get("android", {}).get("device_tested", False) else ("verified_alpha" if android.get("passed") and parity.get("passed") else "failed")),
                     ["build/android/IncenseDebt.apk", "docs/incense-debt/reports/platforms/android-verification.json", "docs/incense-debt/reports/platforms/platform-parity.json", "docs/incense-debt/reports/external-acceptance.json"],
                     "需要真实 Android 安装、触控、后台、文件/剪贴板、温度与 45 分钟长局记录。", f"APK、签名、{resource_count} 项资源与共享源码静态一致性已通过；设备运行尚未取得证据。"),
        requirement("ios_delivery", "iOS 共享工程与原生交接",
                     "verified_release" if ios_external.get("passed") and ios.get("passed") else ("pending_device" if ios.get("passed") and not current.get("ios", {}).get("physical_device_tested", False) else ("verified_alpha" if ios.get("passed") else "failed")),
                     ["build/ios-handoff/README.md", "build/ios-handoff/IncenseDebt-shared-source.zip", "docs/incense-debt/reports/platforms/ios-handoff-verification.json", "docs/incense-debt/reports/external-acceptance.json"],
                     "需要真实 macOS/Xcode 工程、签名 IPA、iPhone/iPad 运行与性能记录。", f"{ios.get('member_count')} 个交接成员和共享 game 树哈希已核对；Windows 环境不能替代 Apple 工具链。"),
        requirement("system_traceability", "方向1稳定 ID 到运行钩子追踪",
                     "verified_alpha" if direction1.get("passed") and not direction1.get("failures") else "failed",
                     ["docs/incense-debt/20-direction1-system-bible.md", "docs/incense-debt/reports/runtime/direction1-system-audit.json", "docs/incense-debt/reports/runtime/synergy-matrix-tests.json"],
                     "逐条运行钩子通过仍不等于真人构筑平衡。", "角色、路线、武器、技能、54件遗物、36个行愿、24套组合、房间、敌人、精英、Boss与债约均有数据—运行—自动证据链。"),
        requirement("human_balance", "真人六角色双路线与正式发布签字", "verified_release" if human_external.get("passed") else "pending_human_and_device",
                     ["docs/incense-debt/reports/human-balance-template.csv", "docs/incense-debt/reports/external-acceptance.json", "docs/incense-debt/reports/release-readiness.json", "docs/incense-debt/reports/system-coverage.json"],
                     "需要六角色×两路线的真人完整整局、难度/伤害/构筑理解记录，以及移动设备共同验收。", "模板结构 12 行完整但当前没有伪造真人记录；自动 Bot 胜利不替代人工体验。"),
    ]

    status_counts: dict[str, int] = {}
    for item in requirements:
        status_counts[item["status"]] = status_counts.get(item["status"], 0) + 1
    external_ready = bool(external.get("release_ready", False))
    release_verified = bool(readiness.get("software_readiness") == "passed" and external_ready and not any(row["status"] == "failed" for row in requirements))
    payload = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "overall": "release_verified" if release_verified else "software_verified_external_pending",
        "product_complete": release_verified,
        "source_status": current.get("status"),
        "status_counts": status_counts,
        "requirements": requirements,
        "authoritative_release_rule": readiness.get("rule"),
        "external_acceptance": "docs/incense-debt/reports/external-acceptance.json" if external else None,
        "virtualization": "none",
    }
    json_path = REPORTS / "product-completion-audit.json"
    md_path = REPORTS / "product-completion-audit.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 《香火债》方向1完成审计", "",
        f"记录时间：{payload['recorded_at']}。总体状态：`{payload['overall']}`。本审计不把自动测试、桌面截图或静态包检查写成真实设备与真人验收。", "",
        "| 要求 | 状态 | 直接证据 | 当前边界 |", "| --- | --- | --- | --- |",
    ]
    for item in requirements:
        evidence = "；".join(f"`{path}`" for path in item["evidence"])
        lines.append(f"| {item['title']} | **{item['status']}** | {evidence} | {item['boundary']} |")
    lines += [
        "", "## 当前软件事实", "",
        f"设计数据：6 角色、6 路线、16 武器、18 技能、54 遗物、36 行愿、24 组合、3 区域、18 房间模板、4 类特殊房间。Windows 原生资源 {current.get('native_resources_loaded')} 项，截图 {current.get('native_captures')} 张；三章自动整局 {full_victories}/12 胜利，路线矩阵 {route_victories}/24 胜利。", "",
        "## 不能在当前主机伪造的门槛", "", "- Android 真机安装、触控、后台恢复、系统文件接口、热稳定与长局。", "- 真实 macOS/Xcode 导出、签名 IPA、iPhone/iPad 运行。", "- 六名角色各两条路线的真人整局与至少三次独立平衡记录。", "", "重新生成：", "", "```powershell", "python tools/runtime/audit_product_completion.py", "```",
    ]
    md_path.write_text("\n".join(lines) + "\n", "utf8")
    print(json.dumps({"overall": payload["overall"], "product_complete": payload["product_complete"], "status_counts": status_counts, "json": str(json_path), "markdown": str(md_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
