"""Bind network fault evidence to 0.4.1 exports; preserve published 0.4.0 receipts.

Only acceptance reports and reviewed native captures leave the private fixtures.
Never copy server registries, credentials, logs or platform device identifiers.
"""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import shutil

from PIL import Image
from record_online_delivery import ROOT, REPORTS, digest, passed, read, require, write

TARGET = REPORTS / "network-reliability-2026-10-11"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", type=Path, default=ROOT / ".local-tools/network-audit-2026-10-11")
    args = parser.parse_args()
    local = args.fixtures.resolve()
    require(local.is_relative_to(ROOT / ".local-tools"), "Fixtures must be inside .local-tools")
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text("utf8")).group(1)
    require(version == "0.4.1", "This receipt binds the 0.4.1 reliability patch")
    artifacts = {
        "windows": read(REPORTS / "platforms/windows-build.json"),
        "android": read(REPORTS / "platforms/android-build.json"),
        "server": read(ROOT / "build/server/server-build.json"),
    }
    for artifact in artifacts.values():
        path = ROOT / artifact["path"]
        require(artifact["version"] == version and path.stat().st_size == artifact["bytes"]
                and digest(path) == artifact["sha256"], "Stale exported artifact: " + artifact["path"])
    windows, android, server = [artifacts[name] for name in ("windows", "android", "server")]
    for relative, sha in server["shared_source_sha256"].items():
        require(digest(ROOT / "game" / relative) == sha, "Source changed after server export: " + relative)

    sources = {
        "faults.json": local / "faults-delivery/network-faults.json",
        "tcp.json": local / "tcp-delivery/network-link.json",
        "recovery.json": local / "recovery-delivery/recovery-report.json",
        "storage.json": local / "storage-delivery/storage-report.json",
        "upgrade.json": local / "upgrade-delivery/upgrade.json",
        "load.json": local / "load-delivery/load-report.json",
        "combat.json": local / "combat-delivery.json",
        "transport.json": local / "transport-delivery/cooperative-transport.json",
        "native.json": local / "native-cooperative/online-native.json",
        "duel-native.json": local / "native-duel/online-native.json",
        "duel-combat.json": local / "duel-combat.json",
        "offline-core.json": REPORTS / "runtime/core-tests.json",
        "keyboard.json": REPORTS / "platforms/windows/keyboard/keyboard-flow.json",
        "package-parity.json": REPORTS / "action-mobile-2026-10-09/packaged-parity.json",
        "client-server-parity.json": ROOT / ".local-tools/cooperative-development/client-server-parity/report.json",
        "android.json": TARGET / "android.json",
        "server-build.json": ROOT / "build/server/server-build.json",
    }
    proofs = {name: read(path) for name, path in sources.items()}
    require(all(passed(value) for value in proofs.values()), "A required acceptance report failed")
    expected = {"faults.json": 65, "tcp.json": 18, "storage.json": 7, "combat.json": 125,
                "transport.json": 32, "native.json": 27, "duel-native.json": 30,
                "duel-combat.json": 271, "offline-core.json": 36, "keyboard.json": 107,
                "package-parity.json": 2171, "client-server-parity.json": 37}
    for name, count in expected.items():
        checks = proofs[name]["checks"]
        require(len(checks) == count, "Unexpected coverage: " + name)
        require(all(not isinstance(row, dict) or row.get("passed", False) for row in checks), "Failed check: " + name)
    recovery_count = sum(len(case[stage]["checks"]) for case in proofs["recovery.json"]["scenarios"] for stage in ("prepare", "restore"))
    upgrade_count = sum(len(stage["checks"]) for stage in proofs["upgrade.json"]["stages"].values())
    require(recovery_count == 57 and upgrade_count == 12, "Recovery/upgrade coverage changed")
    for name in ("tcp.json", "recovery.json", "storage.json", "load.json", "client-server-parity.json"):
        require(proofs[name]["server_sha256"] == server["sha256"], "Evidence used another server: " + name)
    require(proofs["upgrade.json"]["new_server_sha256"] == server["sha256"], "Upgrade used another server")
    require(proofs["storage.json"]["fault_hold_seconds"] == 3, "Storage fault was not held long enough")
    parity = proofs["package-parity.json"]
    shared = proofs["client-server-parity.json"]
    require(parity["windows_sha256"] == shared["windows_sha256"] == windows["sha256"], "Client parity is stale")
    apk = proofs["android.json"]
    require(parity["android_sha256"] == apk["apk_sha256"] == android["sha256"], "Android parity is stale")
    require(apk["signature_verified"] and apk["internet_expected"] and apk["internet_permission_matches_source"]
            and apk["upgrade_signer_matches_previous"], "APK contract failed")
    require("versionCode='8'" in apk["package"] and "versionName='0.4.1'" in apk["package"], "APK version mismatch")
    for key in ("devices", "adb_devices", "connected_devices", "physical_devices", "device_serial"):
        apk.pop(key, None)
    proofs["recovery.json"]["fixture_grace_seconds"] = 10
    native = proofs["native.json"]
    for name in ("native.json", "duel-native.json", "keyboard.json"):
        row = proofs[name]
        require(row["packaged"] and row["artifact_sha256"] == windows["sha256"], "Flow ran other client bytes: " + name)
        for capture in row.get("captures", []):
            path = (Path(capture["path"]) if "path" in capture else
                    sources[name].parent / ("keyboard-" + capture["name"] + ".png")).resolve()
            require(capture["saved"] and path.is_file() and path.is_relative_to(ROOT), "Missing native capture")
            capture.update(path=path.relative_to(ROOT).as_posix(), source_sha256=digest(path))
    for name, report in proofs.items():
        write(TARGET / name, report)

    baseline = {"before_commit": "e918f85faff4923fbf8c50f407c00dc865d9e2f8", "before_version": "0.4.0",
                "before": read(local / "baseline-before/baseline.json"),
                "after_initial_patch": read(local / "baseline-after/baseline.json"),
                "final_patch_regression": "faults.json", "final_version": version}
    require(all(not row["passed"] for row in baseline["before"]["checks"]), "Baseline did not reproduce the failures")
    require(all(row["passed"] for row in baseline["after_initial_patch"]["checks"]), "Baseline repairs failed")
    write(TARGET / "baseline.json", baseline)

    media = TARGET / "media"
    media.mkdir(exist_ok=True)
    captures = local / "native-cooperative"
    records = []
    for name in ("hub", "lobby", "combat", "pause", "map", "reconnect", "wide-touch", "growth", "history", "next-room", "result"):
        source = captures / ("online-coop-" + name + ".png")
        destination = media / (name + ".webp")
        with Image.open(source) as image:
            image.convert("RGB").save(destination, "WEBP", quality=88, method=6)
        records.append({"file": destination.relative_to(ROOT).as_posix(), "sha256": digest(destination),
                        "source_png_sha256": digest(source), "capture": name, "proof": "native.json"})
    frames = []
    frame_sources = [captures / ("online-motion-%02d.png" % index) for index in range(20)]
    for source in frame_sources:
        with Image.open(source) as image:
            frame = image.convert("RGB")
        frame.thumbnail((1200, 540), Image.Resampling.LANCZOS)
        frames.append(frame.quantize(colors=192, method=Image.Quantize.MEDIANCUT))
    gif = media / "cooperative-native.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=False, disposal=2)
    records.append({"file": gif.relative_to(ROOT).as_posix(), "sha256": digest(gif), "frames": 20,
                    "source_png_sha256": [digest(path) for path in frame_sources], "proof": "native.json",
                    "playback_ms_per_frame": 100, "silent": True, "capture": "shared NPC combat with native touchscreen held"})
    write(TARGET / "media-manifest.json", {"version": version, "windows_sha256": windows["sha256"],
          "server_sha256": server["sha256"], "real_transport": True, "physical_android": False,
          "execution": "actual Windows EXE, native input, separate exported server", "records": records})

    checks = {name.removesuffix(".json"): count for name, count in expected.items()}
    checks.update(recovery=recovery_count, upgrade=upgrade_count)
    source_paths = sorted([*(ROOT / "game/scripts").rglob("*.gd"), *(ROOT / "game/tests").rglob("*.gd"),
                           *(ROOT / "game/data").glob("*.json"), ROOT / "game/project.godot",
                           ROOT / "game/export_presets.cfg", ROOT / "server/main.gd"])
    receipt = {"passed": True, "version": version, "recorded_at": datetime.now(timezone.utc).isoformat(),
               "artifacts": artifacts, "checks": checks, "native_captures": len(native["captures"]),
               "runtime_resources": len(apk["imported_resources_packaged"]), "matching_compiled_scripts": parity["matching_compiled_scripts"],
               "source_sha256": {path.relative_to(ROOT).as_posix(): digest(path) for path in source_paths},
               "proofs": [{"path": (TARGET / name).relative_to(ROOT).as_posix(), "sha256": digest(TARGET / name)} for name in [*proofs, "baseline.json", "media-manifest.json"]],
               "local_build_publication": "not_published", "public_release_version": "0.4.0", "transport_revision": 1,
               "limits": {"default_rooms": 2, "default_connections": 16, "reconnect_seconds": 90,
                          "public_game_server_deployed": False, "physical_android_tested": False, "wan_latency_tested": False,
                          "load_scope": "local two rooms/four clients, first room, 60 seconds; not long-campaign capacity",
                          "expiry_fixture_grace_seconds": 10,
                          "ip_packet_loss_injection": False, "hard_crash_uncommitted_tail_may_roll_back": True},
               "virtualization": "none", "browser_used": False}
    write(TARGET / "audit.json", receipt)

    historical = TARGET / "baseline-0.4.0"
    historical.mkdir(exist_ok=True)
    for source in (REPORTS / "current-product-status.json", REPORTS / "current-product-status.md", ROOT / "build/delivery-manifest.json"):
        destination = historical / source.name
        if not destination.exists():
            require(read(source).get("version") == "0.4.0" if source.suffix == ".json" else "当前版本 **0.4.0**" in source.read_text("utf8"), "Unexpected baseline status")
            shutil.copyfile(source, destination)
    status = read(historical / "current-product-status.json")
    windows.update(native_runtime_tested=True, device_tested=True, native_runtime_report=(TARGET / "keyboard.json").relative_to(ROOT).as_posix(),
                   native_online_report=(TARGET / "native.json").relative_to(ROOT).as_posix())
    android.update(version_code=8, edge_to_edge=True, signature_verified=True, upgrade_signer_matches_previous=True)
    status.update(recorded_at=receipt["recorded_at"], version=version, windows=windows, android=android, server=server,
                  revision_reports=TARGET.relative_to(ROOT).as_posix(), revision_document="docs/incense-debt/43-network-reliability-audit.md",
                  native_keyboard_checks=107, package_checks=2171, local_build_publication="not_published",
                  prior_online_acceptance={"version": "0.4.0", "report": (historical / "current-product-status.json").relative_to(ROOT).as_posix()})
    status["online"].update(checks=checks, transport_revision=1, input_timeout_ms=250, state_timeout_ms=2000,
                            maximum_unacked_snapshots=4, reliable_control_retry_ms=750)
    status["public_release_state"] = "historical_0.4.0_published_current_0.4.1_not_published"
    write(REPORTS / "current-product-status.json", status)
    manifest = read(historical / "delivery-manifest.json")
    manifest.update(version=version, status="verified_network_reliability_alpha_local", recorded_at=receipt["recorded_at"],
                    files=[{key: artifact[key] for key in ("path", "sha256", "bytes")} for artifact in artifacts.values()],
                    revision_reports=TARGET.relative_to(ROOT).as_posix(), revision_report=(TARGET / "audit.json").relative_to(ROOT).as_posix(),
                    revision_document="docs/incense-debt/43-network-reliability-audit.md", checks=checks, android_version_code=8,
                    local_build_publication="not_published", public_release_version="0.4.0", public_release_state=status["public_release_state"],
                    previous_delivery_manifest=(historical / "delivery-manifest.json").relative_to(ROOT).as_posix())
    write(ROOT / "build/delivery-manifest.json", manifest)
    load = proofs["load.json"]["runs"][0]
    rows = "\n".join(f"| {label} | {item['bytes'] / 2**20:.1f} MiB | `{item['sha256']}` |"
                     for label, item in zip(("Windows 客户端", "Android APK", "Windows 独立服务端"), artifacts.values()))
    (REPORTS / "current-product-status.md").write_text(f"""# 《香火债》当前交付与验收记录

当前源码与本地修复包为 **0.4.1**。默认共灯合作闯十一层，保留离线单人与可选对灯。公开 [v0.4.0-alpha.1](https://github.com/wikigsroom/joss-debt/releases/tag/v0.4.0-alpha.1) 仍为旧版，附件和标签没有改动；0.4.1 尚未发布。

| 本地产物 | 大小 | 实际 SHA-256 |
| --- | --- | --- |
{rows}

联机应用故障 **65** 项、独立 TCP 中转 **18** 项、实际服务端崩溃／损坏恢复 **57** 项、持续写盘故障 **7** 项和原生 0.4.0 数据升级 **12** 项通过。应用消息丢弃与 TCP 字节停滞分开记录，没有宣称做过真实 IP 丢包或公网验收。

合作规则 **125** 项、真实传输 **32** 项、实际 EXE 合作流程 **27** 项／31 张捕获、可选对战规则 **271** 项／实际 EXE 流程 **30** 项通过。离线核心 **36** 项、实际 EXE 纯键盘流程 **107** 项通过。

Windows／Android 包体 **2171** 项、**90** 份编译脚本、**3810** 项运行资源通过核对；独立服务端与客户端 **37** 份共享编译模块一致。Android 为 **0.4.1／code 8**，arm64 调试签名，升级签名一致。没有实体手机安装或网络切换验收；iOS 保留 0.2.0 历史交接，无新版 IPA。

最终服务端两房／四客户端、射线与散射的 60 秒本机负载：**{load['tick_hz']:.2f} Hz**，step P95 **{load['step_p95_ms']:.2f} ms**，process P99 **{load['process_p99_ms']:.2f} ms**。这只是首房间短时验证，不能代表十一层长时容量或 WAN。

恢复默认 90 秒，双方重新确认后继续；双方在线的菜单暂停没有断线期限。客户端与服务器需一起更新到 transport revision 1。旧 0.4.0 检查点可以恢复，离线 schema 2 三槽保持独立。硬崩溃后可能回退到最近一次成功检查点；两代均损坏时保留原文件并拒绝覆盖。

[详细复查](../43-network-reliability-audit.md) · [结构化回执](network-reliability-2026-10-11/audit.json) · [实机 GIF](network-reliability-2026-10-11/media/cooperative-native.gif) · [媒体来源](network-reliability-2026-10-11/media-manifest.json) · [运维](../../../server/README.md) · [旧版发布回执](../../releases/v0.4.0-alpha.1.publication.json)

隐私政策沿用已发布的 **1.5**：[xhz.sidcloud.cn/privacy-policy](https://xhz.sidcloud.cn/privacy-policy)，主体 **吴国黎**，邮箱 **carzyg@outlook.com**。本轮没有新增隐私收集或网页部署。

全程原生 Windows，无 Docker、WSL、虚拟机、模拟器或浏览器。当前没有默认公网游戏服务器；实体 Android 网络切换／后台恢复、真实 WAN、长时合作平衡与目标主机容量仍待验证。
""", "utf8")
    print({"passed": True, "version": version, "checks": checks, "report": str(TARGET / "audit.json")})


if __name__ == "__main__":
    main()
