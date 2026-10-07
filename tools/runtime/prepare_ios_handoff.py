"""Prepare portable sources and pinned Apple templates; never claims an iOS build."""
from pathlib import Path
import hashlib
import json
import zipfile

from verify_ios_handoff import main as verify_handoff

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/ios-handoff"
TEMPLATES = ROOT / ".local-tools/export-templates-4.7.2"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    archive = TEMPLATES / "Godot_v4.7.2-stable_export_templates.tpz"
    lock = json.loads((TEMPLATES / "download-lock.json").read_text("utf8"))
    with archive.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != lock["archive_sha256"]:
            raise ValueError("Export-template archive no longer matches the pinned official hash")
    template = TEMPLATES / "ios.zip"
    if not template.exists():
        with zipfile.ZipFile(archive) as bundle:
            data = bundle.read("templates/ios.zip")
            template.write_bytes(data)
    with zipfile.ZipFile(template) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("iOS template member CRC check failed")
    sources = [p for p in (ROOT / "game").rglob("*") if p.is_file() and ".godot" not in p.parts and p.suffix != ".tmp"]
    sources.append(ROOT / "tools/runtime/export_ios_on_mac.py")
    source_zip = OUT / "IncenseDebt-shared-source.zip"
    with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(sources): bundle.write(path, path.relative_to(ROOT).as_posix())
    report = {"platform": "ios", "status": "native_mac_handoff_prepared", "xcode_project_created": False, "signed_ipa_created": False,
              "physical_device_tested": False, "source_zip": source_zip.relative_to(ROOT).as_posix(),
              "source_sha256": hashlib.sha256(source_zip.read_bytes()).hexdigest(), "source_bytes": source_zip.stat().st_size,
              "ios_template": template.relative_to(ROOT).as_posix(), "ios_template_sha256": hashlib.sha256(template.read_bytes()).hexdigest(),
              "source_template_archive_sha256": lock["archive_sha256"], "minimum_ios_version": "15.0",
              "required_external_environment": ["real macOS host", "Xcode", "Godot 4.7.2 native macOS editor", "owner's actual Apple development team", "iPhone/iPad"], "virtualization": "none"}
    (OUT / "handoff.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    (ROOT / "docs/incense-debt/reports/platforms/ios-handoff.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    (OUT / "README.md").write_text("""# 《香火债》原生 iOS 交接

本目录是共享工程与导出准备，尚未创建 Xcode 工程、签名 IPA 或完成真机测试。

解压 IncenseDebt-shared-source.zip，保留 game/ 与 tools/ 的目录关系。将随工作区提供的 .local-tools/export-templates-4.7.2/ios.zip 放到解压目录的相同位置。Godot 与模板锁定为 4.7.2；工程使用 Compatibility、横屏、iPhone/iPad 和 iOS 15.0 起的目标规格。

在真实 Mac 安装 Xcode 与 Godot 4.7.2 后运行：

```sh
python3 tools/runtime/export_ios_on_mac.py --godot /Applications/Godot.app/Contents/MacOS/Godot --team-id "$APPLE_DEVELOPMENT_TEAM_ID"
```

APPLE_DEVELOPMENT_TEAM_ID 必须是拥有者实际开发团队的十位 ID。若需自有应用标识，增加 --bundle-id 参数。脚本仅生成 Xcode 工程；随后在原生 Xcode 选择自己的团队和真实设备，完成签名、构建及安装。发布到商店不在该脚本内。

真机验收：从初始纸童开始完整十一层，包括第六层固定首领、第七至十层双首领、第十一层连续六首领与结尾；核对20套地图与专属怪物池、40张房间背景；解锁六名角色；双摇杆与第三指施术；刘海安全区；后台存档与过场恢复；系统返回；普通房、精英和 Boss 的持续帧率与热稳定。所有结论登记在平台报告中，不使用模拟器或虚拟环境替代。

官方要求：https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
""", "utf8")
    # Keep the Windows-side integrity evidence in lockstep with every regenerated handoff.
    verify_handoff()
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
