"""Publish a local, evidence-based delivery index for the playable alpha."""
from collections import Counter
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
from run_native_qa import CAPTURE_NAMES, INTERACTION_CHECKS
from verify_platform_parity import source_tree_hashes, tree_fingerprint

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"


def read(path):
    return json.loads((ROOT / path).read_text("utf8"))


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    expanded=ROOT/"game/data/expansion.json"
    if expanded.is_file() and json.loads(expanded.read_text("utf8")).get("campaign_floors")==11:
        from record_expansion_delivery import main as record_expansion
        return record_expansion()
    catalog = read("docs/incense-debt/data/catalog.json")
    names = {
        "core": "core-tests.json", "content": "expanded-content-tests.json",
        "campaign": "campaign-rules-tests.json", "input": "input-and-run-tests.json",
        "full_runs": "full-run-tests.json", "optional_runs": "optional-runs-tests.json",
        "assets": "asset-verification.json", "bot_navigation": "bot-navigation.json",
        "advanced_input": "advanced-input-tests.json",
        "exploration": "exploration-encounters-tests.json",
        "adaptive_music": "adaptive-music-tests.json",
        "save_transfer": "save-transfer-tests.json",
        "weapon_motion": "weapon-motion-tests.json",
        "run_history": "run-history-tests.json",
        "impact_resume": "impact-resume-tests.json",
        "shop_trial": "shop-trial-tests.json",
        "synergy_matrix": "synergy-matrix-tests.json",
        "route_navigation": "route-navigation-tests.json",
        "route_matrix": "route-matrix-tests.json",
        "route_balance": "route-balance-baseline.json",
        "music_production": "music-production.json",
        "weapon_special_rooms": "weapon-special-room-tests.json",
        "platform_contract": "platform-contract-tests.json",
        "daily_run": "daily-run-tests.json",
        "choice_history": "choice-history-tests.json", "achievements": "achievement-tests.json",
        "run_telemetry": "run-telemetry-tests.json",
        "loot_sampling": "loot-sampling-tests.json",
        "menu_hierarchy": "menu-hierarchy-audit.json",
        "visual_contract": "visual-contract-audit.json",
        "direction1_audit": "direction1-system-audit.json",
    }
    tests = {key: read("docs/incense-debt/reports/runtime/" + name) for key, name in names.items()}
    tests["keyboard_flow"] = read("docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json")
    for key, value in tests.items():
        if not value.get("passed") or value.get("failures"):
            raise ValueError("Unresolved runtime check: " + key)
    windows = read("docs/incense-debt/reports/platforms/windows-build.json")
    if tests["keyboard_flow"].get("artifact_sha256") != windows["sha256"]:
        raise ValueError("Keyboard flow verifies a different executable")
    android = read("docs/incense-debt/reports/platforms/android-build.json")
    apk_check = read("docs/incense-debt/reports/platforms/android-verification.json")
    ios = read("docs/incense-debt/reports/platforms/ios-handoff.json")
    ios_handoff_check = read("docs/incense-debt/reports/platforms/ios-handoff-verification.json")
    platform_parity = read("docs/incense-debt/reports/platforms/platform-parity.json")
    native = read("docs/incense-debt/reports/platforms/windows/native-render.json")
    native_audio = read("docs/incense-debt/reports/platforms/windows/audio/native-audio.json")
    ui_refresh = read("docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json")
    release_readiness = read("docs/incense-debt/reports/release-readiness.json")
    external_acceptance = read("docs/incense-debt/reports/external-acceptance.json") if (REPORTS / "external-acceptance.json").is_file() else {}
    for artifact in [windows, android]:
        if sha(ROOT / artifact["path"]) != artifact["sha256"]:
            raise ValueError("Artifact changed after its build report")
    if sha(ROOT / ios["source_zip"]) != ios["source_sha256"]:
        raise ValueError("iOS source bundle changed after its report")
    if not ios_handoff_check.get("passed") or ios_handoff_check.get("source_sha256") != ios["source_sha256"] or ios_handoff_check.get("template_sha256") != ios.get("ios_template_sha256"):
        raise ValueError("iOS handoff integrity report does not verify the current source/template")
    if not platform_parity.get("passed") or platform_parity.get("failures"):
        raise ValueError("Cross-platform shared-content parity report does not pass")
    parity_platforms = platform_parity.get("platforms", {})
    parity_windows = parity_platforms.get("windows_source", {}).get("artifact", {})
    parity_android = parity_platforms.get("android_apk", {})
    parity_ios = parity_platforms.get("ios_shared_source", {})
    if parity_windows.get("sha256") != windows["sha256"] or parity_android.get("sha256") != android["sha256"] or parity_ios.get("sha256") != ios["source_sha256"]:
        raise ValueError("Cross-platform parity report is not bound to the current artifacts")
    parity_tree = platform_parity.get("source_tree", {})
    current_tree_hash = tree_fingerprint(source_tree_hashes())
    if not parity_tree.get("all_members_match") or parity_tree.get("windows_game_tree_sha256") != current_tree_hash or parity_tree.get("ios_game_tree_sha256") != current_tree_hash:
        raise ValueError("Cross-platform parity report is not bound to the current game source tree")
    parity_android_packaging = platform_parity.get("android_packaging", {})
    runtime_resource_count = len(read("game/data/runtime_assets.json").get("assets", []))
    if not parity_android_packaging.get("all_imported_resources_packaged") or parity_android_packaging.get("imported_resource_count") != runtime_resource_count or not parity_android_packaging.get("compiled_ui_and_weapon_scripts_packaged"):
        raise ValueError("Cross-platform parity report does not cover the packaged Android resource registry")
    if windows["sha256"] != native["artifact_sha256"] or native["asset_failures"]:
        raise ValueError("Native report does not verify the current executable")
    if not ui_refresh["passed"] or ui_refresh["compiled_windows_sha256"] != windows["sha256"]:
        raise ValueError("Rounded UI review does not match the current executable")
    if not native_audio["passed"] or native_audio["failures"] or windows["sha256"] != native_audio.get("artifact_sha256"):
        raise ValueError("Native sample recording does not verify the current executable")
    for recording in native_audio["recordings"]:
        if not recording["saved"] or sha(Path(recording["file"])) != recording["sha256"]:
            raise ValueError("Native audio recording changed after its measured report")
    if not apk_check["passed"] or apk_check["apk_sha256"] != android["sha256"]:
        raise ValueError("APK verification does not match the current package")
    captures = native["captures"]
    if len(captures) != len(CAPTURE_NAMES) or not all(x["saved"] and x.get("state_stable") and Path(x["path"]).is_file() for x in captures):
        raise ValueError("Incomplete native visual evidence")
    if len(native.get("interaction_checks", [])) != INTERACTION_CHECKS or not all(x["passed"] for x in native["interaction_checks"]):
        raise ValueError("Incomplete compiled interaction evidence")
    if release_readiness.get("software_readiness") != "passed":
        raise ValueError("Release-readiness software gates do not pass")
    counts = Counter(x["result"] for x in tests["full_runs"]["runs"])
    verified_assets = tests["assets"]["asset_status_counts"].get("engine_verified", 0)
    optional = tests["optional_runs"]["runs"]
    five_boss_wins = sum(x["result"] == "victory" and len(set(x["bosses"])) == 5 for x in optional)
    characters = {x["id"]: x["name"] for x in catalog["characters"]}
    role_lines = []
    for character, name in characters.items():
        rows = [x for x in tests["full_runs"]["runs"] if x["character"] == character]
        role_lines.append(f"| {name} | " + " | ".join("三章胜利" if x["result"] == "victory" else f"第{x['highest_floor']}章失败" for x in rows) + " |")
    data = {
        "recorded_at": datetime.now(timezone.utc).isoformat(), "version": "0.1.0", "status": "playable_three_chapter_alpha",
        "product_complete": False, "windows": windows, "android": android, "ios": ios,
        "catalog_counts": {key: len(catalog.get(key, [])) for key in ["characters", "routes", "weapons", "skills", "relics", "talents", "debt_contracts", "synergies", "regions", "room_templates", "special_rooms", "enemies", "elite_variants", "bosses"]},
        "ios_handoff_verification": {"passed": ios_handoff_check["passed"], "member_count": ios_handoff_check["member_count"], "report": "docs/incense-debt/reports/platforms/ios-handoff-verification.json"},
        "platform_parity": {"passed": platform_parity["passed"], "core_files": len(platform_parity.get("core_files", {})), "game_member_count": parity_tree.get("windows_game_member_count", 0), "game_tree_sha256": current_tree_hash, "android_imported_resources": parity_android_packaging.get("imported_resource_count", 0), "report": "docs/incense-debt/reports/platforms/platform-parity.json", "scope": platform_parity.get("scope", "")},
        "runtime_assertions": {key: len(tests[key]["checks"]) for key in ["core", "content", "campaign", "input", "advanced_input", "exploration", "route_navigation", "adaptive_music", "save_transfer", "weapon_motion", "weapon_special_rooms", "platform_contract", "run_history", "impact_resume", "shop_trial", "synergy_matrix", "daily_run", "choice_history", "achievements", "run_telemetry", "loot_sampling", "menu_hierarchy", "visual_contract"]},
        "direction1_system_audit": {"passed": tests["direction1_audit"].get("passed", False), "systems": len(tests["direction1_audit"].get("rows", [])), "report": "docs/incense-debt/reports/runtime/direction1-system-audit.json"},
        "route_matrix": {"runs": len(tests["route_matrix"]["runs"]), "victories": sum(x["result"] == "victory" for x in tests["route_matrix"]["runs"]), "focus_routes": sorted({x["focus_route"] for x in tests["route_matrix"]["runs"]})},
        "route_balance_baseline": {"samples": tests["route_balance"].get("source_samples", 0), "routes": len(tests["route_balance"].get("route_rows", [])), "report": "docs/incense-debt/reports/runtime/route-balance-baseline.json"},
        "loot_sampling": {"reward_samples_per_floor": tests["loot_sampling"].get("rarity_by_floor", [{}])[0].get("samples", 0) if tests["loot_sampling"].get("rarity_by_floor") else 0, "economy_samples": tests["loot_sampling"].get("economy", {}).get("scenario_samples", 0), "report": "docs/incense-debt/reports/runtime/loot-sampling-tests.json"},
        "menu_hierarchy": {"checks": len(tests["menu_hierarchy"].get("checks", [])), "report": "docs/incense-debt/reports/runtime/menu-hierarchy-audit.json", "hierarchy": tests["menu_hierarchy"].get("hierarchy", [])},
        "visual_contract": {"checks": len(tests["visual_contract"].get("checks", [])), "report": "docs/incense-debt/reports/runtime/visual-contract-audit.json", "reviewed_concepts": tests["visual_contract"].get("reviewed_concepts", [])},
        "full_run_outcomes": dict(counts), "five_boss_victories": five_boss_wins,
        "native_captures": len(captures), "native_resources_loaded": native["asset_loads"],
        "native_interaction_checks": len(native["interaction_checks"]),
        "native_keyboard_checks": len(tests["keyboard_flow"]["checks"]),
        "keyboard_report": "docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json",
        "native_audio_checks": len(native_audio["checks"]), "native_audio_recordings": len(native_audio["recordings"]),
        "animation_strips": tests["assets"]["animation_strips"], "audio_files": tests["assets"]["audio_files"],
        "music_themes": tests["assets"]["music_themes"], "music_stems": tests["assets"]["music_stems"],
        "save_schema": 2, "manual_save_transfer": ["checked_json_file", "compressed_text"],
        "number_encoding": "ieee754-f64-v1; legacy decimal-json remains readable",
        "held_weapon_combinations": tests["weapon_motion"]["combinations"], "held_body_hand_frame_pairs": tests["weapon_motion"]["frame_pairs"],
        "ui_refresh": {"panel_radius": 24, "vector_icons": ui_refresh["vector_icons"], "body_font": "Incense Rounded", "display_font": "Smiley Sans", "font_files": tests["assets"]["font_files"], "character_trial_forms": 18, "report": "docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json"},
        "release_readiness": {"software": release_readiness["software_readiness"], "release": release_readiness["release_readiness"], "report": "docs/incense-debt/reports/release-readiness.json"},
        "external_acceptance": {"release_ready": bool(external_acceptance.get("release_ready", False)), "report": "docs/incense-debt/reports/external-acceptance.json" if external_acceptance else None},
        "pending": ["human balance and two-route acceptance for every character", "physical Android installation, input, file picker, clipboard and thermal tests",
                    "native macOS/Xcode signing and physical iOS run"],
        "virtualization": "none",
    }
    (REPORTS / "current-product-status.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf8")
    markdown = f"""# 《香火债》当前交付与验收记录

更新日期：{datetime.now(timezone(timedelta(hours=8))).date().isoformat()}。版本：0.1.0。当前交付为可运行的三章 Alpha；正式三端发布尚未完成。软件准入机器审计为 **{release_readiness['software_readiness']}**，正式发布仍为 **{release_readiness['release_readiness']}**，外部证据为 **{'passed' if external_acceptance.get('release_ready') else 'pending_external_acceptance'}**，详见[发布准入清单](19-release-readiness.md)、[机器报告](release-readiness.json)、[外部验收证据](external-acceptance.md)、[方向1完成审计](reports/product-completion-audit.md)和[方向1系统审计](runtime/direction1-system-audit.md)。此表保留原始产品目标，不将内容文件、自动通关或桌面触控截图等同于全部成品验收。

## 运行入口

| 入口 | 实际产物 | 已有证据 | 当前边界 |
| --- | --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，x86_64，{windows['bytes'] / 1024**2:.1f} MiB | 原生RTX 3060窗口运行；最新编译程序{len(captures)}张截图、{len(native['interaction_checks'])}项GUI录入/保存/保护检查、{len(tests['keyboard_flow']['checks'])}项纯键盘流程检查；{native['asset_loads']}项资源全部加载；菜单、成长选择、特殊房、存档与复盘可由键盘操作 | 自动模拟通关与编译画面是分别执行的检查；真人完整整局手感仍需验收 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，arm64，{android['bytes'] / 1024**2:.1f} MiB | APK实际导出；v2/v3签名、内容、许可证、SDK与权限检查通过；{parity_android_packaging.get('imported_resource_count', 0)}项运行资源和核心内容与Windows源/iOS共享源码一致 | 调试签名；Android 7/API 24起；本机ADB未发现真实设备，没有安装或长时真机证据 |
| iOS | [源码与Mac交接说明](../../../build/ios-handoff/README.md) | 共享源码ZIP、官方4.7.2模板、iOS 15起的导出设置与真实Mac脚本；Windows侧交接完整性检查通过，ZIP内{ios_handoff_check['member_count']}个成员核对；{parity_tree.get('windows_game_member_count', 0)}个`game/`文件逐项哈希一致 | 尚无Xcode工程、签名IPA、iPhone/iPad运行；须真实Mac、Xcode、实际开发团队与设备 |
| 编辑工程 | [Godot工程](../../../game/project.godot) | 本地原生Godot 4.7.2导入与运行 | 与Windows、Android共用玩法与数据；未启动Docker、WSL或任何虚拟环境 |

操作与保存说明见[安装及操作](../../../build/README.md)。签名、包体哈希、跨端内容一致性和平台边界可查[Windows](platforms/windows-build.json)、[Android](platforms/android-verification.json)、[iOS](platforms/ios-handoff.json)、[跨端一致性报告](platforms/platform-parity.json)。

## 原始体系与目前实现

| 体系 | 当前实际实现 | 直接验证与尚缺内容 |
| --- | --- | --- |
| 可玩角色 | 纸童、铃师、灯客、傩面、伞灵、墨吏；各有本职天赋、基础焚债和两演化；按行为逐步解锁；图标详情及十八技能试演 | 初始纸童、五种解锁条件与个人三阶段记账已测；详情、未留名试演、真实伤害及训练不改原进度通过编译GUI；每角色两路线的人类通关验收仍缺 |
| 成长与构筑 | 六条路线、36行愿节点、54供物、十六种武器模式；三发散射、射线、可控纸蝶、近战弧与蓄力月刃可组合；22局外购买；供物满槽事务替换；每日种子固定初始供物池 | 前置、候选去重、路线资格、购买恢复与派生预算已测；24套设计联动及7个独立遗物钩子由技能组合矩阵逐项触发；每日挑战{len(tests['daily_run']['checks'])}项检查覆盖日期复现、存档恢复与局外隔离，完整真人平衡仍待验收 |
| 技能与打击 | 18形态；挂烬、灼烧、连债、焚债、返程双命中、招架、护甲、一次复活；0.14秒碰撞击退、精英/首领衰减与静态束缚绳环；纸屑、顿帧和独立声音 | {len(tests['impact_resume']['checks'])}项实际命中/续局检查覆盖远程、近战、控制、盾挡及真实延迟攻击队列；友弹暖金/敌弹玉青；危险弹绘制在爆发特效之后 |
| 掉落与债约 | 独立房间随机流、有效池、稀有度回退、低血治疗保底、奖励领取账本、商店与九种债约；待售武器可进入独立试射 | 九种代价与一次偿还均有检查；{len(tests['shop_trial']['checks'])}项试射检查覆盖十六种实际武器、原构筑复制、训练隔离、返回后原候选/钱包/随机流和真实购买；掉落数学抽样不代替真人平衡观察 |
| 特殊房间与成长账本 | 献灯、判官、观音、破阵四类实体支路房；心火代价、三轮战斗、遗物/武器/天赋/治疗/上限奖励；每房一次性领取 | {len(tests['weapon_special_rooms']['checks'])}项检查覆盖四类房间的路线可达、图标选择、破阵波次、一次性扣除、growth_log、special_rooms 和存档恢复 |
| 探索与敌群 | 三章、18房间几何、24敌人、6精英、3主线与2可选首领；各首领三阶段；物理断绳入口、已行房间状态回访与后段两阵遭遇 | 1,500章节图可达性、720碰撞等价查询、首领阶段及召唤边界已测；{len(tests['exploration']['checks'])}项检查覆盖发现、回访、波次、实际存档恢复和一次结算；可选胜利返回同章 |
| 世界与局外 | 还愿庭、五NPC、留愿/还愿/图鉴/训练/个人页；14故事页、角色短句、三个有条件的结局 | 故事门槛、姓名页去重、个人进度、结局保存与失败写盘回滚已测 |
| 失败与复盘 | 最后一击原始攻击者、十二次近期受击、核心供物图标与本局构筑、已入账善缘及本局新完成愿页；同角色新种子重开 | {len(tests['run_history']['checks'])}项规则检查覆盖攻击者消失、裂弹/延迟/债约弹、护甲/复活、真实存档及记账幂等；编译GUI覆盖实际终局、详情返回、移动触控夹具和新局清理 |
| 输入与恢复 | 鼠标/手柄重映射与冲突交换、三触点双摇杆；编辑布局、镜像、安全区、固定/浮动摇杆、死区与切换攻击；辅助瞄准、事件触觉、拾取范围、叙事滚动字号；横屏恢复须确认；账号与单局同代保存、暂停续局；方向键/Enter/Esc菜单操作，Tab循环焦点，1—4直选，F1详情；暂停页本局记录；开场→槽位→主菜单→角色/挑战/记录→房间分层 | {len(tests['keyboard_flow']['checks'])}项打包程序纯键盘检查覆盖焦点与逐层返回、成长多选、商店试射、特殊房、门切换、存档文字传递和结算；{len(tests['advanced_input']['checks'])}项新输入检查覆盖存档恢复、遮挡、短锁、旧配置默认和误触隔离；{len(tests['choice_history']['checks'])}项本局记录检查覆盖初始构筑、武器/技能/供物/行愿/债约选择、数字键1—4映射、快照恢复与旧存档兼容；{len(tests['achievements']['checks'])}项菜单/成就检查覆盖三槽位、32项成就、幂等归档和角色筛选；另有{len(tests['platform_contract']['checks'])}项共享平台契约检查；真实手机与外部手柄仍待设备验收 |
| 存档迁移与传递 | 明确schema1→2，旧文件保持原样；三个本地愿簿槽位；JSON文件与压缩文字先预览后确认；保留本机设置，独立导入前备份可跨重启恢复；未知版本或内容保护 | {len(tests['save_transfer']['checks'])}项检查使用真实旧版冻结文件，覆盖成对提交、同输入续局、奖励去重、往返与失败回滚；{len(tests['achievements']['checks'])}项成就/槽位检查覆盖独立路径与选择 journal；GUI实际录入、确认、取消和恢复已测；手机文件选择器、软键盘、剪贴板待真机验收 |
| 手持器具与动作 | 六角色×十六器具共96种搭配；四向中性身体、同步手部覆层、实际攻击/蓄力、换装清理、背面遮挡与展开飞伞/旋转铜轮 | {len(tests['weapon_motion']['checks'])}项检查覆盖576对身体/手帧和360个真实战斗输入；24底图编辑区外逐字节保持原RGBA；真人手感与移动透明边继续待验收 |
| 美术、UI与声音 | 四张同源场景、六角色锁定身份、三态断绳门、{tests['assets']['animation_strips']}条透明纸偶动作、{tests['assets']['audio_files']}份48kHz原创声音；{tests['assets']['music_themes']}套32小节主题与{tests['assets']['music_stems']}条音乐分层（含低音量CC0环境纹理）；24圆角、57个矢量图标、圆形/胶囊按钮、资源圆体正文与得意黑标题 | {verified_assets}项素材技术记录通过；动作来自批准原图与局部Sub2补片的纸偶形变；字体、Lucide与Godot许可随包；UI设计母版来自真实原生组件图 |

## 自动战斗样本

[三章测试](runtime/full-run-tests.json)共12次，{counts['victory']}次胜利、{counts['defeat']}次失败，全部进入正常终局。另有[角色路线矩阵](runtime/route-matrix-tests.json)共{len(tests['route_matrix']['runs'])}次，覆盖六名角色的两条本职路线与两种技能演化，{sum(x['result'] == 'victory' for x in tests['route_matrix']['runs'])}次胜利。操作器使用原始生命、伤害、香火和无敌参数；清房后通过正常领取接口收取治疗。自动路线覆盖不等同于玩家胜率或最终平衡结论。

| 角色 | 演化A样本 | 演化B样本 |
| --- | --- | --- |
{chr(10).join(role_lines)}

[可选首领测试](runtime/optional-runs-tests.json)预先开放两个支路，以纸童和傩面分别检查整局；其中{five_boss_wins}次完成全部五名首领，未覆盖战斗属性。Bot自身的墙角走位回归另见[检查记录](runtime/bot-navigation.json)。基本规则{len(tests['core']['checks'])}项、内容{len(tests['content']['checks'])}项、章节/账号/输入{len(tests['campaign']['checks'])}项检查通过；另有输入与首章{len(tests['input']['checks'])}项检查。

探索与波次{len(tests['exploration']['checks'])}项规则夹具通过，包含实际双代校验恢复、新写入器续号、显露后的地图编号、登场免疫、债约按房计数，以及治疗和奖励不重生。另有[物理房门回归](runtime/route-navigation-tests.json){len(tests['route_navigation']['checks'])}项检查，逐一覆盖南、北、东、西门的阈值穿越、反向回访出生点和反方向输入拒绝；它不允许地图按钮或直接 destination 请求代替移动。夹具的强制击杀用于隔离规则，不纳入正常属性整局样本。新增两阵后，旧400秒样本预算截断两场最终首领战；短预算记录保留，完整样本使用与可选整局相同的20分钟逻辑时间上限。路线矩阵使用角色本职路线偏好和提前身法，覆盖六名角色的两条路线与两种演化，全部进入三章胜利；这只是规则与构筑覆盖证据，不替代每角色两路线的人类手感验收。

动态配乐{len(tests['adaptive_music']['checks'])}项规则/原生资源检查通过；[最新编译程序的实际混音](platforms/windows/audio/native-audio.json)有{len(native_audio['checks'])}项检查、六段内部PCM录音。录音与四条原创分层及一条滤波环境纹理按样本对齐拟合，核对探索、节奏、张力、应答、纹理及暂停衰减；另检查后台冻结、完整循环接缝和实际静音。该录音来自游戏内部混音总线，没有使用麦克风；不替代物理手机扬声器、耳机或人类听测。

[跨端内容一致性](platforms/platform-parity.json)已将 Windows 工程与 iOS 共享源码的全部{parity_tree.get('windows_game_member_count', 0)}个`game/`文件逐项做 SHA-256 比对，同时对 Android APK 的{parity_android_packaging.get('imported_resource_count', 0)}项运行资源、导入资源、音乐配置、武器绑定和六份核心 JSON 做包内核对，并绑定当前包体哈希。它只证明静态内容一致，不证明 Android/iOS 真机运行，也不对 Windows 可执行文件内部的封装 PCK 做逐字节读取。

[存档迁移与传递](runtime/save-transfer-tests.json){len(tests['save_transfer']['checks'])}项检查通过。真实旧版原生QA文件在[来源记录](runtime/legacy-save-fixtures.json)留档；验证转存前后原字节、账号/房间/随机流/领取键一致，以及导入后相同30个战斗输入和下一组供物候选。导入前备份独立于双代回退，提交失败或取消不改变进度；预览和恢复都要求明确确认。

[受击与结算记账](runtime/run-history-tests.json){len(tests['run_history']['checks'])}项检查通过。攻击来源随已发出的弹与印区保存；死亡后的愿页读取已提交账本，重复查看、重载与训练不重复发善缘。旧存档缺少的历史与额外奖励归属不会凭空补写。最近十二次记录含攻击前后心火、护甲抵消和回魂签消耗；关闭闪光仍保留方向或地面形状提示。

[击退、控制与延迟续局](runtime/impact-resume-tests.json){len(tests['impact_resume']['checks'])}项检查通过。普通轻击26、重击64逻辑单位，在0.14秒内减速位移；精英乘0.5，首领保留0.15。实际碰撞限制位移，击退不暂停攻击时钟；束缚普通敌上限0.8秒、精英0.3秒、首领免疫。真实重复攻击、扇弹、突进与债约弹经过原生存档后以相同输入继续；新随机流种子按整数身份恢复，旧章节保护小数键保持已消费。记录均为规则与原生夹具证据，未替代真人手感判断。

[灯摊试射隔离](runtime/shop-trial-tests.json){len(tests['shop_trial']['checks'])}项检查通过。待售器具使用真实角色、遗物、行愿和焚债规则复制到无奖励靶场；射击、蓄力、标记、被动和碰撞均在隔离World中结算。返回灯摊后原候选、钱包、库存、房间记录、随机流和购买价格保持原样，随后购买只扣一次。训练胜利、善缘和个人任务不会写入账号；这项原生规则证据仍不等于真人商店选择研究。

[武器模式与特殊房间](runtime/weapon-special-room-tests.json){len(tests['weapon_special_rooms']['checks'])}项检查通过。三生扇生成三发带散布的弹，照骨线按墙体阻挡结算射线，引魂纸蝶按实时瞄准转向，月刃蓄锋在蓄力后释放重弧；献灯、判官、观音沿实体路线门进入并完成一次成长交易，破阵房完成三轮真实波次后打开高阶供物选择，保存后继续保持领取账本。该证据不代替真人构筑平衡与长期收益观察。

[技能组合矩阵](runtime/synergy-matrix-tests.json){len(tests['synergy_matrix']['checks'])}项检查通过。二十四套组合各用真实主攻、焚债、收灰、身法、招架、清房或偿还入口触发，并逐项触发七个未被组合引用的独立遗物钩子；核对三件遗物均有可达的运行路径。组合只做图鉴提示，不注入隐藏套装奖励。该矩阵是规则证据，完整组合的真人手感、平衡与三章胜率仍需验收。

[每日种子](runtime/daily-run-tests.json){len(tests['daily_run']['checks'])}项检查通过。日期、规则版本和初始供物池组成可复现的本地挑战标识；挑战可以正常存档/恢复，但不会把固定池通关转成善缘、角色解锁或路线历史。它不依赖网络时钟、排行榜或服务器。

[数字键与本局记录](runtime/choice-history-tests.json){len(tests['choice_history']['checks'])}项检查通过。PC 端在奖励、技能、商店和债约选择面板按 `1`、`2`、`3`、`4` 即可直接提交对应候选；暂停菜单的“本局记录”按时间倒序展示初始武器/技能、所有后续成长选择和当前构筑摘要。成长账本随单局快照保存恢复，旧存档缺失字段时保持兼容。

[菜单、槽位与角色成就](runtime/achievement-tests.json){len(tests['achievements']['checks'])}项检查通过。标题页把愿簿 1/2/3、继续、新局、每日挑战、还愿庭、成就和设置拆成同级入口；三槽位索引独立写入并保持槽位1旧路径兼容。六名角色各有四项成就，账户另有八项全局成就；成就只在正式非每日/非训练的存档观察中计数，并按 `run.id` 幂等，暂停页和标题页可筛选查看。

[菜单层级与行为审计](runtime/menu-hierarchy-audit.md){len(tests['menu_hierarchy']['checks'])}项检查通过。报告把开场→槽位→主菜单→角色/挑战/记录/设置、房间→暂停子页→房间、终局→构筑/复盘→结算→主菜单，以及愿簿传递→预览→确认/撤销的返回边界绑定到源码、设计文档、{len(tests['keyboard_flow']['checks'])}项纯键盘事件和{len(native['interaction_checks'])}项原生GUI证据；它仍明确保留真人信息密度、系统返回键和移动设备验收边界。

[视觉契约审计](runtime/visual-contract-audit.md){len(tests['visual_contract']['checks'])}项检查通过。三张已审查Sub2概念板（角色、房间/道具、菜单/地图/战斗反馈）均有提示词、尺寸和SHA-256来源；视觉基准同时绑定当前Windows原生截图、字体、圆角UI和725项运行时资源。概念板定义目标风格，不把未经审查的生成图直接替换运行时素材。

[局后平衡观测](runtime/run-telemetry-tests.json){len(tests['run_telemetry']['checks'])}项检查通过。正式局结束时把角色、路线、武器、技能、遗物、房间、受击、连债、资源和结果写入本地 `user://run_telemetry.jsonl`；按 `run_id/result` 幂等，训练与每日挑战隔离。它为真人平衡记录提供可复现的本地输入，不把自动样本写成最终平衡结论。[路线自动基线](runtime/route-balance-baseline.md)另外聚合24局固定Tick样本，按角色×路线输出战斗时长、受击、击杀和剩余心火。[掉落与经济抽样](runtime/loot-sampling-tests.md)每层执行10,000次稀有度、候选去重、治疗保底和三层现金情景抽样，记录期望/观察分布、灯摊前底线及 P10/P90。

## 设计图与程序对照

![原设计与最新Windows程序](runtime/design-vs-runtime.png)

原有设计图与新增菜单·地图·战斗反馈设计板均保持不覆盖；实际生成来源、图片哈希、脚点与动作状态留档。最新Windows编译程序{len(captures)}张场景用于逐项核对地图构图、六角色身份、材质、色板、字体、排版与危险提示。[视觉约定](../17-visual-contract.md)、[来源与画面哈希](runtime/visual-baseline.json)、[技术素材验收](runtime/asset-verification.json)构成可复核证据，没有使用未经验证的视觉相似度百分比。

## 性能的实际范围

最新Windows压力片段为8敌人、240弹；{native['stress']['sampled_render_frames']}个渲染帧中P95为{native['stress']['frame_ms_p95']:.2f}ms，直接world.tick的P95为{native['stress']['world_tick_ms_p95']:.3f}ms。该片段使用原生桌面Compatibility渲染器；不证明长局稳态、最低配置或手机帧率。此release构建的Godot静态内存计数不可用，报告使用null，不将0记为进程内存。

## 正式版本还需落实的项目

真实Android安装、三指触控、刘海安全区、锁屏/后台恢复、文件选择器/软键盘/剪贴板和45分钟热稳定；真实Mac/Xcode的iOS签名构建及iPhone/iPad运行；真人六角色双路线、每种首领与完整组合的手感和平衡、长局音乐及声音设备听测。

新增操作映射、瞄准与反馈、触控布局三页沿用圆角、图标和资源圆体；{len(tests['advanced_input']['checks'])}项输入检查已通过。叙事可放大至150%并通过滚轮、拖动与方向键阅读，操作区域保持可见。拾取倍率只作用于纸钱和余烬，治疗保持24逻辑单位、清房统一收齐；倍率进入单局快照。桌面尺寸注入检查竖屏清输入/停模拟与横屏主动确认，实际旋转、震动和三指触控仍需硬件判断。

清房后的普通出口以实际方向门显示，玩家朝发光门口移动并穿过阈值才切换房间；返回旧房从对应反向门出现，地图只读展示路线。物理断绳线索要在清房后靠近停留0.45秒才显露，之后走到入口并沿入口方向走入才进入断页，交互键和按钮只作靠近后的辅助。回访保持房间治疗和领取状态；清房操作区避开技能和供物栏，手机只保留有用的移动摇杆。第一章前两房仍为三敌一阵，后段两阵保留1.2秒收灰与0.8秒远处登场预警，最后一阵才结算。

配乐主题长约67–116秒，使用完整32小节的回应、留白、发展和回归；三区域/首领共享同步的底层、节奏和张力分轨。层级在下一小节改变，波次与首领转阶段留出一拍，危险提示临时压低配乐。清房恢复疏松，菜单暂停降低音量、后台冻结样本；音乐不改变模拟或掉落随机流。上述范围真实记为Alpha；原设计的正式要求继续保留。

新增愿簿传递、文字录入与预览页面使用同源角色、圆角深灰面板、杏橙主行动和资源圆体；桌面与移动布局各有真实截图。图标取代重复动作长句，预览和覆盖确认保持明确。截图夹具在两次真实绘制完成后才推进页码，报告记录页面状态与冻结的夹具时刻，避免异步截图落到下一页。

本轮UI重构的实际前后对照、字号、字体来源、57个图标、重点色板对比度和原生组件设计图见[UI记录](runtime/ui-refresh/ui-refresh.json)及[前后图](runtime/ui-refresh/ui-before-after.png)。历史Sub2API UI参考编辑请求曾返回400；本轮新增并审查[菜单·地图·战斗反馈设计板](../../../output/imagegen/incense-debt/menu-map-combat-board.png)，原生圆角组件和许可矢量仍负责运行时界面，原Sub2游戏美术继续绑定。
"""
    (REPORTS / "current-product-status.md").write_text(markdown, "utf8")
    manifest = {"version": data["version"], "status": data["status"], "platform_parity_report": "docs/incense-debt/reports/platforms/platform-parity.json",
                "files": [{"path": x["path"], "sha256": x["sha256"], "bytes": x["bytes"]} for x in [windows, android]] +
                         [{"path": ios["source_zip"], "sha256": ios["source_sha256"], "bytes": ios["source_bytes"]}]}
    (ROOT / "build/delivery-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"status": data["status"], "full_run_outcomes": dict(counts), "five_boss_victories": five_boss_wins,
                      "native_captures": len(captures), "artifact_hashes_verified": 3}, ensure_ascii=False))


if __name__ == "__main__":
    main()
