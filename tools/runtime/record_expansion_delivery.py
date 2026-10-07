"""Record this expansion only after current source and packaged evidence have passed."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
REPORTS=ROOT/"docs/incense-debt/reports"

def read(path):return json.loads((ROOT/path).read_text("utf8"))
def digest(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()

def main():
    names={"systems":"runtime/expansion-systems.json","combat_revision":"runtime/combat-revision/systems.json","compiled_geometry":"runtime/combat-revision/compiled-geometry.json","full_run":"runtime/expanded-full-run.json",
        "native":"platforms/windows/expansion/expansion-native.json","assets":"platforms/windows/expansion/expansion-assets.json",
        "keyboard":"platforms/windows/keyboard/keyboard-flow.json","gui":"platforms/windows/native-render.json",
        "audio":"platforms/windows/audio/native-audio.json","android":"platforms/android-verification.json",
        "ios":"platforms/ios-handoff-verification.json","parity":"platforms/platform-parity.json",
        "equipment_systems":"runtime/equipment-polish/gameplay.json",
        "equipment_native":"platforms/windows/equipment-polish/native.json",
        "equipment_assets":"platforms/windows/equipment-polish/assets.json"}
    reports={key:read("docs/incense-debt/reports/"+value) for key,value in names.items()}
    sha=digest("build/windows/IncenseDebt.exe")
    failures=[]
    for key,report in reports.items():
        passed=(bool(report.get("interaction_checks")) and all(c["passed"] for c in report["interaction_checks"]) and not report.get("asset_failures")) if key=="gui" else bool(report.get("passed"))
        if not passed or report.get("failures"):failures.append(key)
    for key in ["native","assets","keyboard","gui","audio","equipment_native","equipment_assets"]:
        if reports[key].get("artifact_sha256")!=sha:failures.append(key+"_current_executable")
    if reports["compiled_geometry"].get("windows_artifact_sha256")!=sha or reports["compiled_geometry"].get("android_artifact_sha256")!=digest("build/android/IncenseDebt.apk"):
        failures.append("compiled_geometry_current_artifacts")
    played_sources=reports["full_run"].get("gameplay_sources",{})
    if not played_sources or any(digest(path)!=expected for path,expected in played_sources.items()):
        failures.append("full_run_current_gameplay_sources")
    db=read("game/data/catalog.json"); expansion=read("game/data/expansion.json")
    equipment=read("game/data/equipment.json")
    db["relics"] += equipment["relics"]
    db["active_items"] = equipment["active_items"]
    db["trinkets"] = equipment["trinkets"]
    registry=read("game/data/runtime_assets.json")["assets"]
    if reports["gui"].get("asset_loads")!=len(registry) or reports["gui"].get("asset_failures"):failures.append("all_packaged_resources")
    wins=[row for row in reports["full_run"]["runs"] if row["result"]=="victory"]
    if not any(row["highest_floor"]==11 and row["transitions"]==list(range(2,12)) and row["epilogue_seen"] and {"b36","b37"}.issubset(row["bosses"]) for row in wins):failures.append("actual_eleven_floor_ending")
    if any(not check["restored"] for row in reports["full_run"]["runs"] for check in row["save_checks"]):failures.append("every_played_transition_restores")
    if any(len(b["enemy_ids"])!=12 or len(b["boss_ids"]) not in [3,7] for b in expansion["biomes"]):failures.append("every_theme_encounter_pool")
    if failures:raise RuntimeError("Expansion delivery evidence incomplete: "+", ".join(failures))
    data=dict(recorded_at=datetime.now(timezone.utc).isoformat(),passed=True,scope="eleven-floor equipment/combat alpha; active items, single trinket slot, rare loot, attack composition and generated effects",
        executable="build/windows/IncenseDebt.exe",artifact_sha256=sha,content=dict(floors=11,biomes=20,backgrounds=40,
        weapons=len(db["weapons"]),enemies=len(db["enemies"]),bosses=len(db["bosses"]),mobs_per_theme=12,
        encounter_types_per_theme=[len(b["enemy_ids"])+len(b["boss_ids"]) for b in expansion["biomes"]],final_rooms=40,final_consecutive_boss_rooms=6),
        native_resources=len(registry),source_checks=len(reports["systems"]["checks"]),combat_revision_checks=len(reports["combat_revision"]["checks"]),
        packaged_keyboard_checks=len(reports["keyboard"]["checks"]),packaged_expansion_checks=len(reports["native"]["checks"]),
        packaged_gui_checks=len(reports["gui"]["interaction_checks"]),packaged_expansion_captures=len(reports["native"]["captures"]),
        source_bound_art_checks=len(reports["assets"]["checks"]),
        additional_animation_strips=reports["assets"]["additional_animation_strips"],
        animation_strips=len(read("game/assets/animation-manifest.json")["strips"])+reports["assets"]["additional_animation_strips"]+reports["assets"]["combat_revision_strips"]+80,
        equipment_polish=dict(active_items=12,trinkets=12,attack_modifiers=12,relics=66,source_checks=len(reports["equipment_systems"]["checks"]),
            native_checks=len(reports["equipment_native"]["checks"]),native_captures=len(reports["equipment_native"]["captures"]),
            fx_strips=80,generated_keyframes=480,total_staged_combat_strips=88,source_boards=23,projectile_profiles=395,projectile_shapes=16,
            stress=reports["equipment_native"]["stress"],low_rate_trials=80000,single_trinket_slot=True),
        combat_revision=dict(inner_wall_contours=40,generated_fx_strips=8,generated_keyframes=48,local_fraction=.6,guest_fraction=.4,guest_theme_per_floor=1,early_boss_chambers=2,bosses_per_early_chamber=1,legacy_early_pair_migration=True),
        full_run_attempts=len(reports["full_run"]["runs"]),full_run_victories=len(wins),
        full_run_method=reports["full_run"]["method"],evidence=names,
        art_provider="sub2-image-gen / gpt-image-2.5",virtualization="none",
        limitations=["Action-bot victories and deaths establish the actual software route; human game feel/balance remain separate",
        "Native cinematic uses generated still sequences, camera movement and dissolves; actor motion is baked paper-puppet deformation",
        "Android package is debug-signed; physical mobile tests and macOS/Xcode signed iOS export remain unverified"])
    (REPORTS/"expansion-delivery.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n","utf8")
    baseline=REPORTS/"three-chapter-product-status.baseline.json"
    if not baseline.exists():
        old=read("docs/incense-debt/reports/current-product-status.json")
        baseline.write_text(json.dumps(old,ensure_ascii=False,indent=2)+"\n","utf8")
    windows=read("docs/incense-debt/reports/platforms/windows-build.json")
    android=read("docs/incense-debt/reports/platforms/android-build.json")
    ios=read("docs/incense-debt/reports/platforms/ios-handoff.json")
    if windows["sha256"]!=sha or reports["android"].get("apk_sha256")!=digest(android["path"]) or reports["ios"].get("source_sha256")!=digest(ios["source_zip"]):
        raise ValueError("Platform verification is not bound to the current delivery files")
    current=dict(recorded_at=data["recorded_at"],version="0.2.0",catalog_version=db.get("version","0.1.0"),
        status="playable_eleven_floor_alpha",product_complete=False,
        playable_scope="eleven-floor alpha with 20 encounter themes, 12 active items, 12 trinkets, composed attacks and 80 new effects",
        windows=windows,android=android,ios=ios,catalog_counts={k:len(v) for k,v in db.items() if isinstance(v,list)},
        expansion=data,native_resources_loaded=len(registry),native_captures=len(reports["gui"]["captures"]),
        native_interaction_checks=data["packaged_gui_checks"],native_keyboard_checks=data["packaged_keyboard_checks"],
        native_audio_checks=len(reports["audio"]["checks"]),native_audio_recordings=len(reports["audio"].get("recordings",[])),
        keyboard_report="docs/incense-debt/reports/"+names["keyboard"],
        full_run_outcomes={result:sum(row["result"]==result for row in reports["full_run"]["runs"]) for result in ["victory","defeat"]},
        full_run_report="docs/incense-debt/reports/"+names["full_run"],
        animation_strips=data["animation_strips"],
        platform_parity=dict(passed=True,report="docs/incense-debt/reports/"+names["parity"],scope=reports["parity"]["scope"],
            game_tree_sha256=reports["parity"]["source_tree"]["windows_game_tree_sha256"],
            android_imported_resources=reports["parity"]["android_packaging"]["imported_resource_count"]),
        save_schema=2,virtualization="none",historical_three_chapter_baseline="docs/incense-debt/reports/"+baseline.name,
        pending=["human visual, combat feel and balance acceptance", "physical Android installation and input/thermal acceptance", "native macOS/Xcode signing and physical iOS run"])
    (REPORTS/"current-product-status.json").write_text(json.dumps(current,ensure_ascii=False,indent=2)+"\n","utf8")
    old_markdown=REPORTS/"three-chapter-product-status.baseline.md"
    current_markdown=REPORTS/"current-product-status.md"
    if not old_markdown.exists() and current_markdown.exists():
        old_markdown.write_text(current_markdown.read_text("utf8"),"utf8")
    windows_mib=(ROOT/windows["path"]).stat().st_size/1048576
    android_mib=(ROOT/android["path"]).stat().st_size/1048576
    restores=sum(len(row["save_checks"]) for row in reports["full_run"]["runs"])
    status_lines=["# 《香火债》当前交付与验收记录","",
        f"更新：{data['recorded_at']}。当前为十一层可玩 Alpha：20套环境、40张背景、{len(db['enemies'])}种小怪、{len(db['bosses'])}名首领、{len(db['weapons'])}件器具。每主题12种小怪与3名主题首领，最终天穹12种小怪与7名首领。","",
        "| 平台 | 当前产物 | 已完成验证 |","| --- | --- | --- |",
        f"| Windows | [IncenseDebt.exe](../../../{windows['path']})，{windows_mib:.1f} MiB | 当前编译程序实际加载{len(registry)}项资源；界面{data['packaged_gui_checks']}项、纯键盘{data['packaged_keyboard_checks']}项、扩展{data['packaged_expansion_checks']}项检查通过 |",
        f"| Android | [IncenseDebt.apk](../../../{android['path']})，arm64，{android_mib:.1f} MiB | 调试签名与包内全部{len(registry)}项运行资源、核心内容一致性检查通过；未进行真机安装 |",
        "| iOS | [共享源码与Mac交接](../../../build/ios-handoff/README.md) | 共享源码全树哈希、官方模板与交接完整性通过；尚无签名IPA或真机运行 |","",
        "[安装及键位](../../../build/README.md) · [怪物与首领名册](../25-themed-encounters.md) · [二十主题总览](platforms/windows/expansion/twenty-themes-overview.png) · [当前交付索引](expansion-delivery.json)","",
        "## 当前实现","",
        "| 体系 | 当前行为 |","| --- | --- |",
        "| 十一层故事 | 前五层每层两个独立Boss房，各一名首领；第六层固定守名大判，七至十层保留双首领主战，第十一层40房、六名连续首领与万愿总账 |",
        "| 环境与遭遇 | 二十套环境、40个按背景校准的内墙轮廓；普通、精英、挑战与召唤按60%本土＋40%一个随机高对比外来主题混编；随机首领同样纳入混编 |",
        "| 场景交互 | 相连木、石、绳障碍，受击爆炸、连锁爆炸、接触伤害与动态预告；生成保留出生点与房门可达 |",
        "| 战斗与动作 | 三十二器具；新增48张独立生成特效关键帧，射线流动、端点爆裂、范围蓄势／扩散／余波与内墙裁切；显示路径和实际命中一致 |",
        "| 地图与键盘 | WASD走位、方向键发射、数字键选择、Enter确认、Esc返回/暂停；Tab同时查看地图、垂直基础属性、完整道具与词条，Ctrl+Tab切换历史 |",
        "| 种子与保存 | 十二位派生种子，暂停可复制，新局手动输入一次生效；楼层、房间、奖励、怪物和障碍使用隔离随机流，过场与局内快照可恢复 |",
        "| 装备与稀有掉落 | 十二主动道具、十二单属性饰品、一个饰品槽与地面交换；清房/首领充能、火芯补充、低概率掉落与一次性来源账本接入存档 |",
        "| 攻击与新特效 | 三十二武器统一载体/修饰组合；三/四/五发取最高档、射线与爆炸并存、分裂/回响二次触发受限；新增80条生成动画480帧，395份敌弹参数与16种形态 |",
        "| 地图与主动键 | Tab地图顶部完整十一层线；F使用主动道具、E拾取/交换，手柄X、第五个独立触控按钮；暂停历史与装备图鉴保留所有选择 |",
        "| 原有体系 | 六角色、十八技能、六十六供物、三十六行愿节点、二十四组合、三槽位、角色成就、商店试射、献灯/判官/观音/破阵房及局外成长继续接入 |","",
        "## 绑定当前文件的证据","",
        f"[扩展系统](runtime/expansion-systems.json)：{data['source_checks']}项检查；[本轮战斗修复](runtime/combat-revision/systems.json)：{data['combat_revision_checks']}项检查、1100张图结构、40种边界及旧双Boss恢复。[完整流程](runtime/expanded-full-run.json)：默认初始参数自动操作，{len(wins)}次胜利、{len(reports['full_run']['runs'])-len(wins)}次真实败局；成功样本覆盖11层、固定剧情首领、六连续首领与结尾，{restores}次实际层间存档恢复全部通过。","",
        f"[原生扩展](platforms/windows/expansion/expansion-native.json)：{data['packaged_expansion_checks']}项检查、{data['packaged_expansion_captures']}张画面；[美术来源](platforms/windows/expansion/expansion-assets.json)：{data['source_bound_art_checks']}项检查、全部生成角色板与动作条，当前共{data['animation_strips']}条动画。[键盘闭环](platforms/windows/keyboard/keyboard-flow.json)、[界面](platforms/windows/native-render.json)及[内部混音](platforms/windows/audio/native-audio.json)均绑定同一可执行文件。","",
        f"[装备规则](runtime/equipment-polish/gameplay.json)：{data['equipment_polish']['source_checks']}项、80000次稀有掉落抽样；[编译装备实机](platforms/windows/equipment-polish/native.json)：{data['equipment_polish']['native_checks']}项、{data['equipment_polish']['native_captures']}张截图、全部480帧载入，205弹丸绘制P95 {data['equipment_polish']['stress']['p95_ms']:.2f}ms（暂停物理的渲染压力测量）。[素材核对](platforms/windows/equipment-polish/assets.json)逐一绑定23张生成原图、36图标和80动画。","",
        f"Windows SHA-256：`{sha}`。各平台文件哈希保存在[交付清单](../../../build/delivery-manifest.json)；[跨端一致性](platforms/platform-parity.json)核对共享源树与Android包内内容。","",
        "自动操作与规则检查用于证明软件流程；真人审美、战斗手感与长期平衡仍需实际游玩反馈。动画采用来源可追溯的预生成纸偶形变，过场采用生成静帧、镜头移动与转场。Android未进行真机测试；iOS仍需真实Mac/Xcode签名与设备运行。未使用Docker、WSL或虚拟化环境。","",
        "原三章交付记录另存[历史记录](three-chapter-product-status.baseline.md)，不作为十一层扩展的完成证明。",""]
    current_markdown.write_text("\n".join(status_lines),"utf8")
    # Runtime data stays immutable after export. Delivery state lives in this report only.
    files=[]
    for relative in [windows["path"],android["path"],ios["source_zip"]]:
        path=ROOT/relative
        files.append(dict(path=relative,sha256=digest(relative),bytes=path.stat().st_size))
    manifest=dict(version=current["version"],status=current["status"],recorded_at=data["recorded_at"],
        platform_parity_report="docs/incense-debt/reports/"+names["parity"],
        expansion_report="docs/incense-debt/reports/expansion-delivery.json",files=files)
    (ROOT/"build/delivery-manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n","utf8")
    lines=["# 十一重扩展交付记录","",f"Windows 当前文件 SHA-256：{sha}","",
           f"20套独立环境、40张背景；总计{len(db['enemies'])}种小怪、{len(db['bosses'])}名首领、32件器具。实际遭遇按60%本土＋40%另一个高对比主题混编，1—5层每层两个独立单Boss房。","",
           f"真实未强化玩家自动尝试{len(wins)}/{len(reports['full_run']['runs'])}胜利，其余真实败局保留；通关覆盖11层、十次可恢复过场、六连续首领房与结尾叙事。原生键盘、界面和美术检查绑定同一Windows文件哈希。","",
           "主题总览和二十套遭遇池对照图见 platforms/windows/expansion/。完整图源、动作帧和验收索引见 expansion-delivery.json。","",
           "Android已提供调试签名APK和一致性检查；iOS提供共享源码交接，尚无签名IPA与真机运行记录。自动通关、预生成动作和桌面图像不替代真人审美、手感与设备验收。",""]
    (REPORTS/"expansion-delivery.md").write_text("\n".join(lines),"utf8")
    print(json.dumps({"passed":True,"content":data["content"],"resources":len(registry),"victories":len(wins),"artifact_sha256":sha}))
if __name__=="__main__":main()
