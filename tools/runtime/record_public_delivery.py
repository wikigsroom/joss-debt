"""Bind formal 0.5.0 delivery to accepted clients, live server and native media."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / ".local-tools/public-server-2026-10-13"
PUBLIC = ROOT / "docs/incense-debt/reports/public-online-2026-10-11"
URL = "https://github.com/wikigsroom/joss-debt/releases/tag/v0.5.0"

def digest(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()
def read(path): return json.loads(path.read_text("utf8"))
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")
def require(okay, message):
    if not okay: raise RuntimeError(message)

def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--published", action="store_true")
    args = parser.parse_args()
    PUBLIC.mkdir(parents=True, exist_ok=True)
    win = read(ROOT / "docs/incense-debt/reports/platforms/windows-build.json")
    apk = read(ROOT / "docs/incense-debt/reports/platforms/android-build.json")
    require(win["version"] == apk["version"] == "0.5.0", "Wrong client versions")
    for metadata in [win, apk]: require(digest(ROOT / metadata["path"]) == metadata["sha256"], "Changed client artifact")
    checks = {
        "cooperative-native.json": PRIVATE / "final-package-cooperative/online-native.json",
        "duel-native.json": PRIVATE / "final-package-duel/online-native.json",
        "layout.json": PRIVATE / "layout-final-package/layout.json",
        "network-faults.json": PRIVATE / "network-faults-official-default/network-faults.json",
        "public-recovery.json": PRIVATE / "live-recovery-final/report.json",
        "public-load.json": PRIVATE / "live-session-load/report.json",
        "packaged-parity.json": PRIVATE / "packaged-parity/packaged-parity.json",
        "windows-server-parity.json": PRIVATE / "final-parity-windows/report.json",
        "linux-server-parity.json": PRIVATE / "final-parity-linux/report.json",
        "keyboard-flow.json": ROOT / "docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json",
        "android-verification.json": PRIVATE / "android-verification.json",
        "android-lineage.json": ROOT / "build/android/android-lineage.json",
        "deployment.json": PRIVATE / "deployment-verified.json",
    }
    accepted = {}
    for name, source in checks.items():
        report = read(source)
        require(report["passed"], "Acceptance failed: " + name)
        for key in ["windows_sha256", "artifact_sha256"]:
            if key in report: require(report[key] == win["sha256"], "Stale Windows proof: " + name)
        for key in ["android_sha256", "apk_sha256"]:
            if key in report: require(report[key] == apk["sha256"], "Stale Android proof: " + name)
        for capture in report.get("captures", []):
            if "path" in capture: capture["path"] = "media/" + Path(capture["path"]).name
        accepted[name] = report
        write(PUBLIC / name, report)
    android = accepted["android-verification.json"]
    require(android["build_variant"] == "release" and "sdkVersion:'28'" in android["platform_fields"], "APK is not Android 9+ release")
    require(android["upgrade_signer_matches_previous"] is True, "APK cannot upgrade the legacy signature")
    require(accepted["layout.json"]["artifact_sha256"] == win["sha256"], "Layout did not inspect this exported pack")
    privacy = read(ROOT / ".local-tools/privacy-policy/deployment-verified.json")
    require(privacy["policy_version"] == "1.6", "Official-service policy not deployed")
    write(PUBLIC / "privacy-https.json", privacy)
    media = PUBLIC / "media"; media.mkdir(exist_ok=True)
    capture_folder = PRIVATE / "final-package-cooperative"
    for name in ["coop-hub", "coop-profile", "coop-loadout", "coop-lobby", "coop-growth", "coop-reconnect", "coop-map", "coop-history", "coop-combat", "coop-wide-touch"]:
        source = capture_folder / ("online-" + name + ".png")
        if source.exists(): shutil.copyfile(source, media / (name + ".png"))
    for name in ["x30-coop-replacement", "x30-coop-debt-build", "x30-coop-debt-repay", "x30-loadout", "wide-phone-coop-draft", "tablet-coop-lobby"]:
        shutil.copyfile(PRIVATE / "layout-final-package" / (name + ".png"), media / (name + ".png"))
    frames = []
    for source in sorted(capture_folder.glob("online-motion-*.png")):
        bitmap = Image.open(source).convert("RGB").resize((960, 432), Image.Resampling.LANCZOS)
        frames.append(bitmap.quantize(colors=192))
    require(len(frames) == 20, "Native motion clip is incomplete")
    frames[0].save(media / "cooperative-native.gif", save_all=True, append_images=frames[1:], duration=100, loop=0, disposal=2)
    write(PUBLIC / "media-manifest.json", {"scope": "Actual Windows release EXE through public WSS; prefixed layout images are offline fixtures", "windows_sha256": win["sha256"], "gif_frames": 20, "gif_duration_ms": 100,
        "files": [{"name": p.name, "sha256": digest(p), "bytes": p.stat().st_size} for p in sorted(media.iterdir())]})
    status_path = ROOT / "docs/incense-debt/reports/current-product-status.json"
    status = read(status_path)
    # Retain catalog and historical evidence, clear obsolete publication receipts.
    for key in ["public_release_commit", "public_release_published_at", "publication_receipt", "release_https_verification", "local_build_publication", "public_release_assets"]: status.pop(key, None)
    status.update(recorded_at=datetime.now(timezone.utc).isoformat(), version="0.5.0", status="formal_online_release" if args.published else "verified_pending_publication", product_complete=False,
        windows=win, android=apk, server={"windows": read(ROOT / "build/server/server-build.json"), "linux": read(ROOT / "build/server-linux/server-build.json")},
        public_github_release=args.published, public_release_state="published_stable" if args.published else "prepared_stable", public_release_url=URL,
        public_release_manifest="docs/releases/v0.5.0.manifest.json", public_release_version="0.5.0", privacy_policy_version="1.6", save_schema=2,
        matching_compiled_windows_android_scripts=90, native_keyboard_checks=len(accepted["keyboard-flow.json"]["checks"]), virtualization="none", browser_used=False,
        revision_document="docs/incense-debt/44-public-online-release.md", revision_reports=PUBLIC.relative_to(ROOT).as_posix(),
        online={"default_mode": "coop", "public_game_server_deployed": True, "automatic_connection": True, "editable_endpoint": False, "cooperative_native_checks":29, "duel_native_checks":32,
                "network_fault_checks":65, "grace_seconds":90, "active_room_capacity":2, "public_server_recovery_checks":10, "public_load_report":"docs/incense-debt/reports/public-online-2026-10-11/public-load.json"},
        pending=["Physical Android X30 installation, touch, suspend/resume and upgrade acceptance", "Long-duration WAN play and human balancing; current host is shared and limited to two rooms"])
    if args.published:
        receipt = read(ROOT / "build/release/v0.5.0/publication-receipt.json")
        require(not receipt["draft"] and not receipt["prerelease"], "Release is not publicly stable")
        status.update(public_release_commit=receipt["commit"], public_release_published_at=receipt["published_at"], public_release_assets=receipt["assets"])
    write(status_path, status)
    write(ROOT / "build/delivery-manifest.json", {"version":"0.5.0", "status":status["status"], "recorded_at":status["recorded_at"], "files":[win,apk,*status["server"].values()],
        "revision_report":status["revision_reports"], "revision_document":status["revision_document"], "runtime_assets":3810, "matching_compiled_scripts":90,
        "android_signing":"release; verified legacy key rotation", "android_version_code":9, "android_min_sdk":28, "android_physical_device_tested":False,
        "public_game_server_deployed":True, "save_schema":2, "public_github_release":args.published, "public_release_version":"0.5.0", "public_release_state":status["public_release_state"]})
    text = f"""# 当前产品与验证状态\n\n0.5.0：十一层离线肉鸽、默认双人合作、可选对战，固定官方 WSS 自动连接。公网 Linux 原生服务已部署；GitHub 发布状态：{status['public_release_state']}。\n\nWindows：`{win['sha256']}`。Android 正式签名包：`{apk['sha256']}`，arm64，Android 9+，version code 9。实际 APK 签名链通过 API 28/32/33/36 验证，旧测试签名具有 installed-data 继承能力；Android 真机安装仍待验。\n\n实际 EXE 公网合作 29 项、对战 32 项、离线键盘 107 项；弱网故障 65 项。两个服务端分别与客户端 37 个共享模块一致；Windows/APK 2172 项内容核对、90 份编译脚本一致。页面布局使用独立离线展示夹具，不能代替实际联网流程证明。\n\n实际主机重启恢复 10 项通过，四个实际 Session 客户端双房间持续 60 秒通过。短时测试不证明长时 SLA；共享主机存在调度和公网延迟，当前容量限制两个房间。\n\n[本次详细交付](../44-public-online-release.md) · [原始验证证据](public-online-2026-10-11/) · [历史 0.4.1 基线](public-online-2026-10-11/baseline-0.4.1/)\n"""
    (status_path.parent / "current-product-status.md").write_text(text,"utf8")
    print(json.dumps({"passed":True,"version":"0.5.0","publication":status["public_release_state"],"proofs":len(checks),"windows_sha256":win["sha256"],"android_sha256":apk["sha256"]}))

if __name__ == "__main__": main()
