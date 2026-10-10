"""Record this revision's measured packages, keeping older status as history."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
REVISION = REPORTS / "action-mobile-2026-10-09"


def read(path):
    return json.loads((ROOT / path).read_text("utf8"))


def write(path, data):
    (ROOT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf8")


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def main():
    privacy_build = read(".local-tools/privacy-policy/build-status.json")
    privacy_verified = read(".local-tools/privacy-policy/deployment-verified.json")
    for key in ("operator_name", "policy_version", "docx_sha256"):
        if privacy_build[key] != privacy_verified[key]:
            raise RuntimeError("Privacy publication receipt is stale: " + key)
    privacy = dict(version=privacy_build["policy_version"], operator=privacy_build["operator_name"],
                   email=privacy_build["contact_email"],
                   url=privacy_verified["public_url"].rstrip("/") + "/privacy-policy",
                   verified_at=privacy_verified["verified_at"], docx_sha256=privacy_verified["docx_sha256"])
    windows = read("docs/incense-debt/reports/platforms/windows-build.json")
    android = read("docs/incense-debt/reports/platforms/android-build.json")
    pack = read("docs/incense-debt/reports/action-mobile-2026-10-09/packaged-parity.json")
    apk = read("docs/incense-debt/reports/platforms/android-verification.json")
    keyboard = read("docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json")
    matrix = read("docs/incense-debt/reports/action-mobile-2026-10-09/mobile-matrix.json")
    playlist = read("docs/incense-debt/reports/action-mobile-2026-10-09/playlist-tests.json")
    for artifact in (windows, android):
        actual = ROOT / artifact["path"]
        if artifact["sha256"] != digest(actual) or artifact["bytes"] != actual.stat().st_size:
            raise RuntimeError("Build receipt is stale: " + artifact["path"])
    if not all((pack["passed"], apk["passed"], keyboard["passed"], playlist["passed"])):
        raise RuntimeError("Revision verification failed")
    if (pack["windows_sha256"] != windows["sha256"] or pack["android_sha256"] != android["sha256"]
            or apk["apk_sha256"] != android["sha256"] or keyboard["artifact_sha256"] != windows["sha256"]):
        raise RuntimeError("A package changed after its verification")
    if len(matrix["fixtures"]) != 4 or not all(row["passed"] for row in matrix["fixtures"]):
        raise RuntimeError("Incomplete mobile matrix")

    creatures = read("game/assets/creature-actions.json")
    creature_source = read("docs/incense-debt/reports/creature-actions-2026-10-10/source-validation.json")
    creature_native = read("docs/incense-debt/reports/creature-actions-2026-10-10/native-coverage.json")
    creature_suite = read("docs/incense-debt/reports/creature-actions-2026-10-10/native-suite.json")
    creature_hash = digest(ROOT / "game/assets/creature-actions.json")
    if not (creatures.get("complete") and creatures.get("compiled_actors") == 402
            and creatures.get("compiled_action_poses") == 24048
            and creature_source.get("complete") and creature_source.get("compiled_identities") == 402
            and creature_source.get("independent_action_poses") == 24048
            and creature_source.get("manifest_sha256") == creature_hash
            and creature_native.get("complete") and creature_native.get("matched_native_identities") == 402
            and creature_native.get("matched_native_frames") == 24048
            and not creature_native.get("failures")
            and creature_native.get("manifest_sha256") == creature_hash
            and creature_suite.get("manifest_sha256") == creature_hash
            and creature_suite.get("scope_complete") and not creature_suite.get("failures")
            and not creature_suite.get("atlas_failures") and len(creature_suite.get("checks", [])) == 17
            and all(check["passed"] for check in creature_suite["checks"])
            and creature_suite.get("loaded_independent_poses") == 24048
            and pack.get("creature_identities") == 402 and pack.get("creature_frames") == 24048
            and pack.get("matching_creature_atlases") == 1002):
        raise RuntimeError("Creature delivery must match all 402 current identities, native evidence and both packages")

    baseline = REPORTS / "product-status-0.2.0.baseline.json"
    previous_path = REPORTS / "current-product-status.json"
    if not baseline.is_file():
        previous = json.loads(previous_path.read_text("utf8"))
        if previous.get("version") != "0.2.0":
            raise RuntimeError("Expected original 0.2.0 status before revision")
        baseline.write_bytes(previous_path.read_bytes())
        (REPORTS / "product-status-0.2.0.baseline.md").write_bytes((REPORTS / "current-product-status.md").read_bytes())
    history = json.loads(baseline.read_text("utf8"))
    recorded = datetime.now(timezone.utc).isoformat()
    windows.update(native_runtime_tested=True, device_tested=True,
                   native_runtime_report="docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json")
    status = dict(recorded_at=recorded, version="0.2.1", status="playable_eleven_floor_alpha",
                  product_complete=False, playable_scope=history["playable_scope"],
                  windows=windows, android=android, catalog_counts=history["catalog_counts"],
                  ios=dict(status="0.2.0_historical_source_handoff_not_refreshed", version="0.2.0",
                           signed_ipa_created=False, physical_device_tested=False,
                           source_zip=history["ios"]["source_zip"]),
                  runtime_assets_packaged=len(apk["imported_resources_packaged"]),
                  independently_drawn_hero_poses=pack["hero_frames"], drawn_fx_frames=24,
                  independently_drawn_creature_poses=creatures["compiled_action_poses"],
                  independently_drawn_creature_identities=creatures["compiled_actors"],
                  creature_action_atlases=pack["matching_creature_atlases"],
                  creature_actions_complete=True, creature_native_checks=len(creature_suite["checks"]),
                  creature_native_frames=creature_native["matched_native_frames"],
                  creature_action_report="docs/incense-debt/35-creature-action-completion.md",
                  matching_compiled_windows_android_scripts=pack["matching_compiled_scripts"],
                  mobile_checks=sum(row["checks"] for row in matrix["fixtures"]),
                  mobile_native_screenshots=sum(len(row["images"]) for row in matrix["fixtures"]),
                  native_keyboard_checks=len(keyboard["checks"]), random_playlist_checks=len(playlist["checks"]),
                  save_schema=2, virtualization="none", browser_used=False,
                  revision_document="docs/incense-debt/33-action-mobile-update.md",
                  revision_reports="docs/incense-debt/reports/action-mobile-2026-10-09",
                  historical_status="docs/incense-debt/reports/product-status-0.2.0.baseline.json",
                  historical_platform_parity="docs/incense-debt/reports/platforms/platform-parity.json",
                  privacy=privacy,
                  public_github_release="v0.2.0-alpha.1",
                  pending=["physical Android installation, thumb feel, native keyboard/clipboard/file picker, haptics and thermal acceptance",
                           "human visual, combat feel and long-term balance acceptance",
                           "current iOS source handoff, native macOS/Xcode signing and physical iOS run"])
    write("docs/incense-debt/reports/current-product-status.json", status)
    manifest_path = ROOT / "build/delivery-manifest.json"
    old_manifest = ROOT / "build/delivery-manifest-0.2.0.baseline.json"
    if not old_manifest.is_file():
        old_manifest.write_bytes(manifest_path.read_bytes())
    write("build/delivery-manifest.json", dict(version="0.2.1", status="local_verified_alpha",
          recorded_at=recorded, files=[{key: artifact[key] for key in ("path", "sha256", "bytes")} for artifact in (windows, android)],
          revision_report="docs/incense-debt/reports/action-mobile-2026-10-09/packaged-parity.json",
          android_signing="debug", android_physical_device_tested=False,
          creature_actions_complete=True, creature_identities=402,
          independently_drawn_creature_poses=24048, creature_action_atlases=1002,
          creature_native_evidence="docs/incense-debt/reports/creature-actions-2026-10-10/native-coverage.json",
          previous_delivery_manifest="build/delivery-manifest-0.2.0.baseline.json",
          ios_handoff_version="0.2.0_historical", public_github_release="v0.2.0-alpha.1"))
    text = f"""# 《香火债》当前交付与验收记录

更新：{recorded}。当前本机修订 **0.2.1**，十一层可玩 Alpha；公开 GitHub 发布仍为上一版 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 本轮已完成验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，{windows['bytes']/1048576:.1f} MiB | 实际导出程序 {status['native_keyboard_checks']} 项键盘闭环；载入全部 24,048 个怪物独立动作帧，与 Android {status['matching_compiled_windows_android_scripts']} 份编译脚本一致 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，{android['bytes']/1048576:.1f} MiB | arm64 调试签名、版本、权限及 {status['runtime_assets_packaged']} 项运行资源；全部 1,002 张怪物动作图集与 Windows 一致；未进行真机安装 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建，不作为 0.2.1 全树一致性或签名 IPA 证据 |

本轮实现六名主角的六状态、四朝向、六帧独立动作，共 864 个姿势；新增 24 个动作 FX 帧。移动触点按安全区布局，每杆／按钮独立保存大小与位置；修复跨半屏捕获、死区盲射、清房隐形键、战斗地图入口、满槽替换误触，增加四候选比较、软键盘避让和试操作。四首 Yourset 曲目随包随机轮播。隐私政策 v{privacy['version']} 的主体为 {privacy['operator']}，与应用资料页一致，已部署并通过公开 HTTPS 核验。

全部 296 种小怪、99 名 Boss、6 种精英变体及 1 种召唤符，合计 402 个身份，均已替换为独立绘制的攻击、受击动作。小怪／精英／召唤符每种 48 帧；Boss 的三类攻击及受击每种 96 帧；均为四朝向、每状态六帧。全部 24,048 帧通过来源、完整性、运行采样及原生截图哈希核验，17 项原生战斗检查通过。见[全量动作交付](../35-creature-action-completion.md)、[原生帧证据](creature-actions-2026-10-10/native-coverage.json)和[战斗状态检查](creature-actions-2026-10-10/native-suite.json)。

[完整改动与原问题原因](../33-action-mobile-update.md) · [实际包体核对](action-mobile-2026-10-09/packaged-parity.json) · [移动矩阵](action-mobile-2026-10-09/mobile-matrix.json) · [Windows 键盘运行](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json) · [随机配乐](action-mobile-2026-10-09/playlist-tests.json) · [公开隐私政策](https://xhz.sidcloud.cn/privacy-policy)

四组原生窗口／密度配置合计 {status['mobile_checks']} 项检查、{status['mobile_native_screenshots']} 张画面；使用合成多指及真实应用事件分发，不是 Android 真机测试。配乐 19 项、持械 22 项、高级输入 54 项，以及相关攻击／恢复、组合装备、存档和房门回归通过。机器人终局检查不代表通关平衡。原生动作审查 GIF 使用固定比较节奏，不是完整游玩录屏。

Windows SHA-256：`{windows['sha256']}`。

Android SHA-256：`{android['sha256']}`。

内容规模为二十套环境、四十张背景、二百九十六种小怪、九十九名首领、三十二件器具。正式遭遇按 60% 本土＋40% 单个高对比外来主题混编；前五层各两个独立单 Boss 房；保存继续兼容 schema 2。怪物的攻击、受击已全量重绘；待机、移动、死亡和阶段转换保留各自现有素材方法。

原始 0.2.0 状态另存 [历史说明](product-status-0.2.0.baseline.md) 与 [历史 JSON](product-status-0.2.0.baseline.json)。旧扩展／装备截图、原生性能数值和三平台全树报告只在它们各自的旧哈希范围内成立，不作为新包重新验收的结论。

Android 真机手感、软键盘／剪贴板／文件选择器、触觉、长局温控与真人平衡待验收；iOS 仍需真实 macOS/Xcode 和设备。本轮使用原生 Windows，无 Docker、WSL、模拟器或浏览器。
"""
    (REPORTS / "current-product-status.md").write_text(text, "utf8")
    print(f"Recorded 0.2.1 delivery: {status['mobile_checks']} mobile checks, {status['native_keyboard_checks']} exported keyboard checks; both package hashes verified.")


if __name__ == "__main__":
    main()
