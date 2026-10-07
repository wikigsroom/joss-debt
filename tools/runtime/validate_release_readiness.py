"""Audit release gates without pretending to perform physical-device work."""
from datetime import datetime, timezone
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs/incense-debt"
REPORTS = DOCS / "reports"


def read(relative):
    return json.loads((ROOT / relative).read_text("utf8"))


def main():
    status = read("docs/incense-debt/reports/current-product-status.json")
    coverage = read("docs/incense-debt/reports/system-coverage.json")
    design = read("docs/incense-debt/reports/design-validation.json")
    parity = read("docs/incense-debt/reports/platforms/platform-parity.json")
    audio = read("docs/incense-debt/reports/platforms/windows/audio/native-audio.json")
    native = read("docs/incense-debt/reports/platforms/windows/native-render.json")
    keyboard = read("docs/incense-debt/reports/platforms/windows/keyboard/keyboard-flow.json")
    windows_build = read("docs/incense-debt/reports/platforms/windows-build.json")
    android_build = read("docs/incense-debt/reports/platforms/android-build.json")
    android = read("docs/incense-debt/reports/platforms/android-verification.json")
    ios_handoff = read("docs/incense-debt/reports/platforms/ios-handoff.json")
    ios = read("docs/incense-debt/reports/platforms/ios-handoff-verification.json")
    human_template = read("docs/incense-debt/reports/human-balance-template.json")
    completion_audit = read("docs/incense-debt/reports/product-completion-audit.json")
    choice_history = read("docs/incense-debt/reports/runtime/choice-history-tests.json")
    achievements = read("docs/incense-debt/reports/runtime/achievement-tests.json")
    direction1_audit = read("docs/incense-debt/reports/runtime/direction1-system-audit.json")
    external = read("docs/incense-debt/reports/external-acceptance.json") if (REPORTS / "external-acceptance.json").is_file() else {}

    required_docs = [
        "00-product-vision.md", "01-world-story.md", "02-game-loop-levels.md",
        "03-playable-characters.md", "04-combat-hit-feedback.md", "05-progression-builds.md",
        "06-loot-economy-debt.md", "07-skills-synergies.md", "08-enemies-bosses.md",
        "09-ui-ux-input.md", "10-art-bible.md", "11-asset-production.md",
        "12-audio-narrative.md", "13-cross-platform-engineering.md", "14-balance-telemetry.md",
        "15-production-validation.md", "16-content-catalog.generated.md",
        "17-visual-contract.md", "18-system-coverage.md", "19-release-readiness.md",
        "20-direction1-system-bible.md", "21-external-acceptance-runbook.md", "22-menu-save-achievements.md",
    ]
    docs_ok = all((DOCS / name).is_file() for name in required_docs)
    checks = {
        "design_validation": design.get("status") == "design_constraints_passed" and not design.get("errors"),
        "documentation_set": docs_ok,
        "windows_native": native.get("asset_failures", []) == [] and native.get("artifact_sha256") == windows_build.get("sha256"),
        "native_audio": audio.get("passed") and not audio.get("failures") and audio.get("artifact_sha256") == windows_build.get("sha256"),
        "android_package": android.get("passed") and android.get("apk_sha256") == android_build.get("sha256"),
        "ios_handoff": ios.get("passed") and ios.get("source_sha256") == ios_handoff.get("source_sha256"),
        "shared_parity": parity.get("passed") and not parity.get("failures"),
        "native_interactions": len(native.get("interaction_checks", [])) >= 72 and all(row.get("passed") for row in native.get("interaction_checks", [])),
        "native_keyboard_flow": keyboard.get("passed") and not keyboard.get("failures") and len(keyboard.get("checks", [])) >= 103 and keyboard.get("artifact_sha256") == windows_build.get("sha256"),
        "choice_history": choice_history.get("passed") and not choice_history.get("failures"),
        "achievements": achievements.get("passed") and not achievements.get("failures"),
        "direction1_system_audit": direction1_audit.get("passed") and not direction1_audit.get("failures"),
        "human_matrix_structure": human_template.get("passed") and human_template.get("rows") == 12,
        "completion_audit": completion_audit.get("overall") in {"software_verified_external_pending", "release_verified"} and not any(row.get("status") == "failed" for row in completion_audit.get("requirements", [])),
    }
    software_ready = all(checks.values())
    pending = []
    if external:
        for key, label, default_status, default_reason in [
            ("human_balance", "human_balance", "pending_human", "六角色×两路线真人整局记录尚未归档"),
            ("android_device", "android_device", "pending_device", "没有真实 Android 安装、触控、热稳定和45分钟记录"),
            ("ios_device", "ios_device", "pending_device", "没有真实 macOS/Xcode 签名、iPhone/iPad 和 IPA 记录"),
        ]:
            gate = external.get(key, {})
            if not gate.get("passed", False):
                failures = gate.get("failures", [])
                pending.append({"gate": label, "status": gate.get("status", default_status),
                                "reason": "；".join(failures[:3]) if failures else default_reason})
    else:
        pending = [
            {"gate": "human_balance", "status": "pending_human", "reason": "六角色×两路线真人整局记录尚未归档"},
            {"gate": "android_device", "status": "pending_device", "reason": "没有真实 Android 安装、触控、热稳定和45分钟记录"},
            {"gate": "ios_device", "status": "pending_device", "reason": "没有真实 macOS/Xcode 签名、iPhone/iPad 和 IPA 记录"},
        ]
    external_ready = bool(external.get("release_ready", False))
    result = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "status": status.get("status", "unknown"),
        "software_readiness": "passed" if software_ready else "failed",
        "release_readiness": "passed" if software_ready and external_ready else ("pending_external_acceptance" if software_ready else "blocked_by_software_checks"),
        "checks": checks,
        "pending_external_gates": pending,
        "external_acceptance": "docs/incense-debt/reports/external-acceptance.json" if external else None,
        "evidence": {
            "delivery": "docs/incense-debt/reports/current-product-status.json",
            "coverage": "docs/incense-debt/reports/system-coverage.json",
            "parity": "docs/incense-debt/reports/platforms/platform-parity.json",
            "completion_audit": "docs/incense-debt/reports/product-completion-audit.json",
            "direction1_audit": "docs/incense-debt/reports/runtime/direction1-system-audit.json",
        },
        "rule": "Do not promote Alpha until software checks and all external gates are directly evidenced.",
    }
    out = REPORTS / "release-readiness.json"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 发布准入机器审计",
        "",
        f"记录时间：{result['recorded_at']}。当前状态：`{result['status']}`。",
        f"软件准入：**{result['software_readiness']}**；正式发布准入：**{result['release_readiness']}**。",
        "",
        "## 软件检查",
        "",
        "| 检查 | 结果 |",
        "| --- | --- |",
    ]
    for name, passed in checks.items():
        lines.append(f"| {name} | {'通过' if passed else '失败'} |")
    lines += ["", "## 外部门槛", "", "| 门 | 状态 | 原因 |", "| --- | --- | --- |"]
    for row in pending:
        lines.append(f"| {row['gate']} | `{row['status']}` | {row['reason']} |")
    lines += ["", "机器报告只证明软件侧证据一致，不替代真实设备或真人体验。"]
    (REPORTS / "release-readiness.md").write_text("\n".join(lines) + "\n", "utf8")
    print(json.dumps({"software_readiness": result["software_readiness"], "release_readiness": result["release_readiness"], "checks": checks}, ensure_ascii=False))
    raise SystemExit(0 if software_ready else 1)


if __name__ == "__main__":
    main()
