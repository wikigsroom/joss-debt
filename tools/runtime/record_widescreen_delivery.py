"""Bind the widescreen fix to verified source, native captures and rebuilt packages."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
REVISION = REPORTS / "widescreen-2026-10-11"


def read(path):
    return json.loads(path.read_text("utf8"))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf8")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def check_matrix(filename, version, artifact=None, revision=REVISION):
    matrix = read(revision / filename)
    require(matrix["passed"] and len(matrix["fixtures"]) == 8, "Incomplete screen matrix: " + filename)
    for row in matrix["fixtures"]:
        report = read(ROOT / row["report"])
        require(report["passed"] and all(c["passed"] for c in report["checks"]), "Failed native checks: " + row["fixture"])
        require(report["version"] == version and report["packaged"] == bool(artifact), "Wrong native build: " + row["fixture"])
        require(row["checks"] == len(report["checks"]) and row["captures"] == len(report["captures"]), "Matrix counts differ")
        if artifact:
            require(report["artifact_sha256"] == artifact, "Package changed after native captures")
        for name, expected in report["source_script_sha256"].items():
            require(digest(ROOT / name) == expected, "Source changed after native verification: " + name)
        for capture in report["captures"]:
            require(digest((ROOT / row["report"]).parent / (capture["name"] + ".png")) == capture["sha256"], "Native capture changed")
    return matrix, sum(r["checks"] for r in matrix["fixtures"]), sum(r["captures"] for r in matrix["fixtures"])


def main():
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    windows = read(REPORTS / "platforms/windows-build.json")
    android = read(REPORTS / "platforms/android-build.json")
    pack = read(REPORTS / "action-mobile-2026-10-09/packaged-parity.json")
    apk = read(REPORTS / "platforms/android-verification.json")
    keyboard = read(REPORTS / "platforms/windows/keyboard/keyboard-flow.json")
    for artifact in [windows, android]:
        path = ROOT / artifact["path"]
        require(artifact["bytes"] == path.stat().st_size and artifact["sha256"] == digest(path), "Build receipt differs: " + artifact["path"])
    require(all(r["passed"] for r in [pack, apk, keyboard]), "Package verification failed")
    require(pack["windows_sha256"] == keyboard["artifact_sha256"] == windows["sha256"], "Windows verification is stale")
    require(pack["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Android verification is stale")
    require(all(apk["display_checks"].values()) and apk["upgrade_signer_matches_previous"] is True, "Android display or upgrade check failed")
    source, source_checks, captures = check_matrix("native-matrix.json", version)
    native, native_checks, native_captures = check_matrix("windows-matrix.json", version, windows["sha256"])
    require([r["fixture"] for r in source["fixtures"]] == [r["fixture"] for r in native["fixtures"]], "Source and packaged fixtures differ")
    mobile = read(REVISION / "mobile-regression/mobile-matrix.json")
    require(not mobile["packaged"] and len(mobile["fixtures"]) == 4 and all(r["passed"] for r in mobile["fixtures"]), "Mobile regression incomplete")
    for row in mobile["fixtures"]:
        report = read(REVISION / "mobile-regression" / row["fixture"] / "verification.json")
        require(report["passed"] and not report["failures"] and len(report["checks"]) == row["checks"], "Mobile report differs")
    mobile_checks = sum(r["checks"] for r in mobile["fixtures"])
    mobile_captures = sum(len(r["images"]) for r in mobile["fixtures"])
    media = read(REVISION / "media.json")
    for name, expected in media["outputs_sha256"].items():
        require(digest(REVISION / name) == expected, "Documentation image changed: " + name)
    for row in media["sources"]:
        require(digest(ROOT / row["path"]) == row["sha256"], "Documentation source changed")
    resources = len(read(ROOT / "game/data/runtime_assets.json")["assets"])
    recorded_at = datetime.now(timezone.utc).isoformat()
    relative_revision = REVISION.relative_to(ROOT).as_posix()
    document = "docs/incense-debt/37-mobile-widescreen-adaptation.md"
    windows.update(device_tested=True, native_runtime_tested=True,
                   native_runtime_report="docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json",
                   native_widescreen_report=relative_revision + "/windows-matrix.json")
    android.update(version=version, version_code=4, edge_to_edge=True, signature_verified=True,
                   upgrade_signer_matches_previous=True)
    write(REPORTS / "platforms/windows-build.json", windows)
    write(REPORTS / "platforms/android-build.json", android)
    status = read(REPORTS / "current-product-status.json")
    status.update(recorded_at=recorded_at, version=version, windows=windows, android=android,
                  revision_document=document, revision_reports=relative_revision,
                  runtime_assets_packaged=resources, matching_compiled_windows_android_scripts=pack["matching_compiled_scripts"],
                  package_checks=len(pack["checks"]), native_keyboard_checks=len(keyboard["checks"]),
                  mobile_checks=mobile_checks, mobile_native_screenshots=mobile_captures,
                  mobile_regression_report=relative_revision + "/mobile-regression/mobile-matrix.json",
                  widescreen_fixtures=8, widescreen_source_checks=source_checks, widescreen_packaged_checks=native_checks,
                  widescreen_captures_per_matrix=captures, widescreen_native_report=relative_revision + "/windows-matrix.json",
                  consumable_evidence_version="0.2.1", creature_evidence_version="0.2.1",
                  consumable_evidence_reused_with_unchanged_bitmaps=True,
                  prior_package_receipts=relative_revision + "/prior-package-receipts")
    write(REPORTS / "current-product-status.json", status)
    delivery = read(ROOT / "build/delivery-manifest.json")
    delivery.update(version=version, recorded_at=recorded_at,
                    files=[{k: row[k] for k in ["path", "sha256", "bytes"]} for row in [windows, android]],
                    revision_document=document, runtime_assets=resources, matching_compiled_scripts=pack["matching_compiled_scripts"],
                    widescreen_native_evidence=relative_revision + "/windows-matrix.json",
                    widescreen_source_checks=source_checks, widescreen_packaged_checks=native_checks,
                    widescreen_captures_per_matrix=captures, mobile_regression_checks=mobile_checks,
                    android_version_code=4, android_edge_to_edge=True, android_upgrade_signer_matches_previous=True,
                    consumable_evidence_version="0.2.1", creature_evidence_version="0.2.1",
                    prior_package_receipts=status["prior_package_receipts"])
    write(ROOT / "build/delivery-manifest.json", delivery)
    receipt = dict(recorded_at=recorded_at, version=version, passed=True,
                   windows_sha256=windows["sha256"], android_sha256=android["sha256"],
                   screen_fixtures=8, source_checks=source_checks, packaged_checks=native_checks,
                   source_captures=captures, packaged_captures=native_captures,
                   mobile_regression_checks=mobile_checks, mobile_regression_captures=mobile_captures,
                   keyboard_checks=len(keyboard["checks"]), package_checks=len(pack["checks"]),
                   matching_compiled_scripts=pack["matching_compiled_scripts"], runtime_resources=resources,
                   android_display_checks=apk["display_checks"], android_display_flags=apk["android_display_flags"],
                   android_version_code=4, upgrade_signer_matches_previous=True,
                   android_physical_device_tested=False, virtualization="none", browser_used=False)
    write(REVISION / "delivery.json", receipt)
    text = f"""# 《香火债》当前交付与验收记录

更新：{recorded_at}。本机修订 **{version}**，十一层可玩 Alpha；本轮修复手机长屏两侧黑边，完善前摄、安全区和横屏翻转。公开 GitHub Release 仍为历史 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 当前包体验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，{windows['bytes'] / 1024 ** 2:.1f} MiB | 实际 EXE {len(keyboard['checks'])} 项键盘流程；同一导出包在原生 Godot 中通过八组屏幕／切口的 {native_checks} 项检查、{native_captures} 张捕获 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，{android['bytes'] / 1024 ** 2:.1f} MiB | {version} / versionCode 4、arm64 调试签名；APK 内确含全屏、边到边与移动 Expand，签名与旧包一致；未连接真机 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建交接包或创建签名 IPA |

两套屏幕矩阵均覆盖 16:9、19.5:9、20:9、21:9、4:3、左右前摄与独立打孔。背景延伸至整张视口，完整战斗房间仍按原比例绘制；碰撞、四向出口、HUD、双摇杆和瞄准坐标通过复查。遮罩覆盖全屏，系统安全区域变化时重排并释放旧触点。源码移动全流程另通过 **{mobile_checks} 项检查、{mobile_captures} 张捕获**。

当前包通过 **{len(pack['checks'])} 项资源与逻辑核对**；Windows / Android 的 {pack['matching_compiled_scripts']} 份编译脚本、19 张消耗品位图、1,002 张怪物图集及 {resources} 项运行资源与源码对应。此前 0.2.1 的消耗品 GIF、105 项拾取检查、91 张捕获和怪物逐帧证据保留原始版本／哈希，相关素材未改变。

[黑边修复、实际对照与重现](../37-mobile-widescreen-adaptation.md) · [本轮交付](widescreen-2026-10-11/delivery.json) · [实际包屏幕矩阵](widescreen-2026-10-11/windows-matrix.json) · [移动全流程](widescreen-2026-10-11/mobile-regression/mobile-matrix.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [键盘流程](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json)

Windows SHA-256：`{windows['sha256']}`。

Android SHA-256：`{android['sha256']}`。

新版包名仍为 `org.incensedebt.game`，与上一份本地 APK 使用同一签名，存档 schema 2 不变，可覆盖升级保留应用数据。旧包收据已原样归档到 [previous receipts](widescreen-2026-10-11/prior-package-receipts/docs/incense-debt/reports/current-product-status.json)。隐私主体仍为 吴国黎、邮箱 carzyg@outlook.com；本轮没有更改或重新部署隐私政策。

当前没有连接摩托罗拉 X30，原生窗口中模拟的前摄／密度／触摸不能代替设备上的系统全屏与手势验收。Android 真机操作、触觉、长局温控、真人平衡及实际 iOS 构建仍待验收。本轮未调用 Docker、WSL、虚拟化或浏览器。
"""
    (REPORTS / "current-product-status.md").write_text(text, "utf8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
