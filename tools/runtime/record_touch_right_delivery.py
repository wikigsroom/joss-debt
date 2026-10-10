"""Record verified right-hand default controls and the 0.2.3 application packages."""
from datetime import datetime, timezone
import json
import re
from record_widescreen_delivery import ROOT, REPORTS, read, write, digest, require, check_matrix

REVISION = REPORTS / "touch-right-2026-10-11"
DOCUMENT = "docs/incense-debt/38-right-hand-touch-layout.md"


def main():
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(version == "0.2.3", "This receipt describes the 0.2.3 revision")
    windows = read(REPORTS / "platforms/windows-build.json")
    android = read(REPORTS / "platforms/android-build.json")
    pack = read(REPORTS / "action-mobile-2026-10-09/packaged-parity.json")
    apk = read(REPORTS / "platforms/android-verification.json")
    keyboard = read(REPORTS / "platforms/windows/keyboard/keyboard-flow.json")
    for artifact in [windows, android]:
        path = ROOT / artifact["path"]
        require(artifact["bytes"] == path.stat().st_size and artifact["sha256"] == digest(path), "Build receipt differs")
    require(all(r["passed"] for r in [pack, apk, keyboard]), "Required package verification failed")
    require(pack["windows_sha256"] == keyboard["artifact_sha256"] == windows["sha256"], "Stale Windows verification")
    require(pack["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Stale Android verification")
    require(all(apk["display_checks"].values()) and apk["upgrade_signer_matches_previous"] is True, "Android upgrade or display verification failed")
    source, source_checks, source_captures = check_matrix("native-matrix.json", version, revision=REVISION)
    native, native_checks, native_captures = check_matrix("windows-matrix.json", version, windows["sha256"], REVISION)
    require([r["fixture"] for r in source["fixtures"]] == [r["fixture"] for r in native["fixtures"]], "Screen matrices differ")
    for row in native["fixtures"]:
        report = read(ROOT / row["report"])
        require(any(c["id"] == "default-left-movement-right-combat" and c["passed"] for c in report["checks"]), "Right-hand controls were not verified")
    mobile = read(REVISION / "mobile-regression/mobile-matrix.json")
    require(len(mobile["fixtures"]) == 4 and not mobile["packaged"], "Mobile fixture matrix incomplete")
    for row in mobile["fixtures"]:
        report = read(REVISION / "mobile-regression" / row["fixture"] / "verification.json")
        require(row["passed"] and report["passed"] and not report["failures"] and len(report["checks"]) == row["checks"], "Mobile regression failed")
    mobile_checks = sum(r["checks"] for r in mobile["fixtures"])
    mobile_captures = sum(len(r["images"]) for r in mobile["fixtures"])
    media = read(REVISION / "media.json")
    for name, expected in media["outputs_sha256"].items():
        require(digest(REVISION / name) == expected, "Documentation image changed")
    for row in media["sources"]:
        require(digest(ROOT / row["path"]) == row["sha256"], "Native image source changed")
    resources = len(read(ROOT / "game/data/runtime_assets.json")["assets"])
    now = datetime.now(timezone.utc).isoformat()
    relative = REVISION.relative_to(ROOT).as_posix()
    windows.update(version=version, device_tested=True, native_runtime_tested=True,
                   native_runtime_report="docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json",
                   native_widescreen_report=relative + "/windows-matrix.json")
    android.update(version=version, version_code=5, edge_to_edge=True, signature_verified=True,
                   upgrade_signer_matches_previous=True)
    write(REPORTS / "platforms/windows-build.json", windows)
    write(REPORTS / "platforms/android-build.json", android)
    status = read(REPORTS / "current-product-status.json")
    status.update(recorded_at=now, version=version, windows=windows, android=android,
                  revision_document=DOCUMENT, revision_reports=relative,
                  package_checks=len(pack["checks"]), native_keyboard_checks=len(keyboard["checks"]),
                  matching_compiled_windows_android_scripts=pack["matching_compiled_scripts"],
                  mobile_checks=mobile_checks, mobile_native_screenshots=mobile_captures,
                  mobile_regression_report=relative + "/mobile-regression/mobile-matrix.json",
                  widescreen_source_checks=source_checks, widescreen_packaged_checks=native_checks,
                  widescreen_captures_per_matrix=native_captures, widescreen_native_report=relative + "/windows-matrix.json",
                  right_hand_touch_default=True, legacy_default_layouts_upgraded=True,
                  custom_touch_layouts_preserved=True, prior_package_receipts=relative + "/prior-package-receipts")
    write(REPORTS / "current-product-status.json", status)
    delivery = read(ROOT / "build/delivery-manifest.json")
    delivery.update(version=version, recorded_at=now, revision_document=DOCUMENT,
                    files=[{k: row[k] for k in ["path", "sha256", "bytes"]} for row in [windows, android]],
                    widescreen_native_evidence=status["widescreen_native_report"],
                    widescreen_source_checks=source_checks, widescreen_packaged_checks=native_checks,
                    widescreen_captures_per_matrix=native_captures, mobile_regression_checks=mobile_checks,
                    android_version_code=5, android_upgrade_signer_matches_previous=True,
                    right_hand_touch_default=True, legacy_default_layouts_upgraded=True,
                    prior_package_receipts=status["prior_package_receipts"])
    write(ROOT / "build/delivery-manifest.json", delivery)
    receipt = dict(recorded_at=now, version=version, passed=True,
                   windows_sha256=windows["sha256"], android_sha256=android["sha256"],
                   source_checks=source_checks, packaged_checks=native_checks,
                   source_captures=source_captures, packaged_captures=native_captures,
                   mobile_regression_checks=mobile_checks, mobile_regression_captures=mobile_captures,
                   keyboard_checks=len(keyboard["checks"]), package_checks=len(pack["checks"]),
                   matching_compiled_scripts=pack["matching_compiled_scripts"], runtime_resources=resources,
                   android_version_code=5, upgrade_signer_matches_previous=True,
                   default_layout="left movement; right aim, dash, burn-debt skill and active item",
                   custom_positions_preserved=True, oversized_legacy_layouts_preserved_if_migration_would_overlap=True,
                   android_physical_device_tested=False, virtualization="none", browser_used=False)
    write(REVISION / "delivery.json", receipt)
    text = f"""# 《香火债》当前交付与验收记录

更新：{now}。当前本机版本 **{version}**，十一层可玩 Alpha。默认触控改为左手只移动，右手负责瞄准／射击、身法位移、焚债技能和主动道具；包含此前长屏背景、安全区和边到边修复。公开 Release 仍为历史 `v0.2.0-alpha.1`。

| 平台 | 产物 | 实际验收 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，{windows['bytes'] / 1024 ** 2:.1f} MiB | 实际 EXE {len(keyboard['checks'])} 项键盘流程；导出包原生屏幕／切口矩阵 {native_checks} 项、{native_captures} 张捕获 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，{android['bytes'] / 1024 ** 2:.1f} MiB | {version} / code 5、arm64 调试签名；签名与前一份 0.2.2 本地包一致，全屏、边到边与 Expand 通过实际包检查；未连接真机 |
| iOS | 0.2.0 历史源码交接 | 本轮未重建交接包或签名 IPA |

源码移动全流程通过 **{mobile_checks} 项检查、{mobile_captures} 张捕获**。旧手机／平板默认布局经 JSON 重载后自动升级；个别触点大小、透明度和已自定义位置保留。原布局尺寸过大、升级会重叠时保留已有合法设置，玩家可在设置 → 触控恢复新默认。两拇指切换和三指操作均检查了左手持续移动、右手位移、移动方向与瞄准方向分离，以及按钮单次触发。

源码和导出包各检查八组 16:9～21:9、4:3、左右切口和独立打孔；分别通过 {source_checks}、{native_checks} 项检查。真实导出包还通过 {len(pack['checks'])} 项资源／逻辑核对，{pack['matching_compiled_scripts']} 份编译脚本与 Android 一致，包含 {resources} 项运行资源。

[布局说明与原生对照](../38-right-hand-touch-layout.md) · [本轮交付](touch-right-2026-10-11/delivery.json) · [实际包布局矩阵](touch-right-2026-10-11/windows-matrix.json) · [移动回归](touch-right-2026-10-11/mobile-regression/mobile-matrix.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [APK 验收](platforms/android-verification.json)

Windows SHA-256：`{windows['sha256']}`。

Android SHA-256：`{android['sha256']}`。

包名 `org.incensedebt.game`、本机调试签名和 schema 2 存档保持，可覆盖前一份同签名 APK 保留数据。0.2.2 长屏图像、0.2.1 消耗品与怪物 GIF 保留各自的历史来源；不是 Android 真机验收。隐私政策未更改，主体仍为 吴国黎，邮箱 carzyg@outlook.com。

当前未连接 X30。真机拇指舒适度、系统手势、触觉和长局温控，以及实际 iOS 构建仍待验收。本轮未使用 Docker、WSL、虚拟化或浏览器。
"""
    (REPORTS / "current-product-status.md").write_text(text, "utf8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
