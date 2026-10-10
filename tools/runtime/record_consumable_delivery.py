"""Bind the pickup revision to measured, verified native application packages."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"
REVISION = REPORTS / "consumables-2026-10-11"


def read(path):
    return json.loads(path.read_text("utf8"))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", "utf8")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    windows = read(REPORTS / "platforms/windows-build.json")
    android = read(REPORTS / "platforms/android-build.json")
    pack = read(REPORTS / "action-mobile-2026-10-09/packaged-parity.json")
    apk = read(REPORTS / "platforms/android-verification.json")
    keyboard = read(REPORTS / "platforms/windows/keyboard/keyboard-flow.json")
    native = read(REVISION / "windows/native.json")
    art = read(REVISION / "art-validation.json")
    manifest = read(ROOT / "game/assets/pickups/manifest.json")
    for artifact in [windows, android]:
        path = ROOT / artifact["path"]
        if artifact["bytes"] != path.stat().st_size or artifact["sha256"] != digest(path):
            raise RuntimeError("Artifact differs from build receipt: " + artifact["path"])
    if not all(report["passed"] for report in [pack, apk, keyboard, native, art]):
        raise RuntimeError("A required pickup delivery verification failed")
    if (pack["windows_sha256"] != windows["sha256"] or pack["android_sha256"] != android["sha256"]
            or keyboard["artifact_sha256"] != windows["sha256"] or native["artifact_sha256"] != windows["sha256"]
            or apk["apk_sha256"] != android["sha256"]):
        raise RuntimeError("A package changed after native verification")
    if len(manifest["records"]) != 19 or pack["matching_pickup_bitmaps"] != 19:
        raise RuntimeError("Incomplete pickup bitmap coverage")
    manifest_hash = digest(ROOT / "game/assets/pickups/manifest.json")
    if native["manifest_sha256"] != manifest_hash or art["manifest_sha256"] != manifest_hash:
        raise RuntimeError("Art changed after verification")
    for path, expected in native["source_script_sha256"].items():
        if digest(ROOT / path) != expected:
            raise RuntimeError("Source script changed after native pickup QA: " + path)
    resources = len(read(ROOT / "game/data/runtime_assets.json")["assets"])
    recorded_at = datetime.now(timezone.utc).isoformat()
    windows.update(device_tested=True, native_runtime_tested=True,
                   native_runtime_report="docs/incense-debt/reports/consumables-2026-10-11/windows/native.json")
    write(REPORTS / "platforms/windows-build.json", windows)
    status = read(REPORTS / "current-product-status.json")
    status.update(recorded_at=recorded_at, windows=windows, android=android,
                  runtime_assets_packaged=resources, matching_compiled_windows_android_scripts=pack["matching_compiled_scripts"],
                  native_keyboard_checks=len(keyboard["checks"]), generated_consumable_objects=6,
                  consumable_runtime_bitmaps=19, consumable_native_checks=len(native["checks"]),
                  consumable_native_captures=len(native["captures"]), consumable_art_checks=len(art["checks"]),
                  consumable_themes_checked=20, consumable_backgrounds_checked=40,
                  pickup_revision="2026-10-11", revision_document="docs/incense-debt/36-consumable-art-update.md",
                  revision_reports="docs/incense-debt/reports/consumables-2026-10-11",
                  prior_package_receipts="docs/incense-debt/reports/consumables-2026-10-11/prior-package-receipts",
                  creature_evidence_reused_with_unchanged_atlases=True)
    write(REPORTS / "current-product-status.json", status)
    delivery = read(ROOT / "build/delivery-manifest.json")
    delivery.update(recorded_at=recorded_at, files=[{"path": row["path"], "sha256": row["sha256"], "bytes": row["bytes"]}
                    for row in [windows, android]], generated_consumable_objects=6, consumable_runtime_bitmaps=19,
                    consumable_revision_document="docs/incense-debt/36-consumable-art-update.md",
                    consumable_native_evidence="docs/incense-debt/reports/consumables-2026-10-11/windows/native.json",
                    runtime_assets=resources, matching_compiled_scripts=pack["matching_compiled_scripts"],
                    prior_package_receipts=status["prior_package_receipts"])
    write(ROOT / "build/delivery-manifest.json", delivery)
    size_windows = windows["bytes"] / 1024 ** 2
    size_android = android["bytes"] / 1024 ** 2
    text = f"""# 《香火债》当前交付与验收记录

更新：{recorded_at}。本机修订 **0.2.1**，十一层可玩 Alpha；本轮更新掉落消耗品、相关资源 UI 和安装包。公开 GitHub Release 仍为 `v0.2.0-alpha.1`。

| 平台 | 当前产物 | 当前包体验证 |
| --- | --- | --- |
| Windows | [IncenseDebt.exe](../../../build/windows/IncenseDebt.exe)，{size_windows:.1f} MiB | 实际导出程序 {len(native['checks'])} 项掉落检查、91 张捕获，以及 {len(keyboard['checks'])} 项完整键盘流程；全部 19 张新位图通过原生载入和纹理核对 |
| Android | [IncenseDebt.apk](../../../build/android/IncenseDebt.apk)，{size_android:.1f} MiB | arm64 调试签名、版本、权限和 {resources} 项运行资源；{pack['matching_compiled_scripts']} 份编译脚本、19 张消耗品位图和 1,002 张怪物动作图集与 Windows / 源码一致；未进行真机安装 |
| iOS | 0.2.0 历史源码交接 | 本轮没有重建或创建签名 IPA |

掉落物为 sub2-image-gen / gpt-image-2.5 独立生成的红心纸灯、单枚铜钱、双枚红绳铜钱、普通香灰包、高额香灰包和充能火芯。六张原画生成 19 张透明运行位图，统一地面、血条、金币栏、回血商品和火芯拾取提示。40 张背景均检查实际尺寸辨识度。轻微浮动、摆动与同源资源拾取淡出遵从减少动态选项，表现层不改变 RNG 或模拟。

实际检查覆盖资源数值、吸附边界、键盘 E、满充能保留、九个地面物品及完整模拟的存档恢复。存档 schema 2 与原有掉落数值规则保持。源图、SHA-256、前后对照、原生 GIF 与复现入口见[掉落消耗品修订](../36-consumable-art-update.md)。

[当前 Windows 掉落验证](consumables-2026-10-11/windows/native.json) · [美术检查](consumables-2026-10-11/art-validation.json) · [包体核对](action-mobile-2026-10-09/packaged-parity.json) · [键盘流程](platforms/windows/keyboard/keyboard-flow.json) · [Android 检查](platforms/android-verification.json)

既有六角色四向 864 个独立动作姿势、24 个角色 FX 帧、四首随机 BGM、可单独调整的移动触控继续随包交付。全部 402 个怪物身份、1,002 张独立攻击 / 受击图集和 24,048 个姿势保留完整素材；当前包再次核对和载入这些资源。之前的逐帧截图及 17 项战斗状态证据仍绑定其原始哈希，素材未变化，本轮没有重新录制全体怪物。见[全量动作范围](../35-creature-action-completion.md)。

Windows SHA-256：`{windows['sha256']}`。

Android SHA-256：`{android['sha256']}`。

[上轮 0.2.1 安装包与报告](consumables-2026-10-11/prior-package-receipts/docs/incense-debt/reports/current-product-status.json)已经保存；历史 0.2.0 普通游玩及宣传媒体保持各自来源记录。它们不代替当前包验收。当前隐私政策记录仍为 v1.3、主体 吴国黎、邮箱 carzyg@outlook.com，公开核验时间保留在 JSON 中，本轮没有更改政策或重新部署。

Android 真机触屏、触觉、文件选择器与长局温控、真人难度平衡仍待验收；移动 HUD 截图是 Windows 原生移动布局。iOS 仍需要实际 macOS / Xcode 与设备。本轮没有使用 Docker、WSL、虚拟机、模拟器或浏览器。
"""
    (REPORTS / "current-product-status.md").write_text(text, "utf8")
    write(REVISION / "delivery.json", {"recorded_at": recorded_at, "passed": True,
          "windows_sha256": windows["sha256"], "android_sha256": android["sha256"],
          "generated_objects": 6, "runtime_bitmaps": 19, "resources": resources,
          "native_checks": len(native["checks"]), "captures": len(native["captures"]),
          "keyboard_checks": len(keyboard["checks"]), "package_checks": len(pack["checks"]),
          "matching_compiled_scripts": pack["matching_compiled_scripts"],
          "android_physical_device_tested": False, "virtualization": "none"})
    print(json.dumps({"passed": True, "windows_mib": round(size_windows, 1), "android_mib": round(size_android, 1),
                      "resource_count": resources, "package_checks": len(pack["checks"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
