"""Audit the approved visual references against the runtime visual contract.

The report distinguishes reviewed concept boards from engine assets. A concept
board can define the target look without silently becoming an unverified runtime
replacement; the actual screenshots and native resource report remain separate
evidence.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "docs/incense-debt/reports"


def read(relative: str, default=None):
    path = ROOT / relative
    if not path.is_file():
        return {} if default is None else default
    return json.loads(path.read_text("utf8"))


def check(checks: list[dict], name: str, passed: bool, detail: str) -> None:
    checks.append({"name": name, "passed": bool(passed), "detail": detail})


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = read("docs/incense-debt/data/asset-manifest.json")
    visual_doc = (ROOT / "docs/incense-debt/17-visual-contract.md").read_text("utf8")
    prompt = (ROOT / "docs/incense-debt/assets/prompts/visual/menu-map-combat-board.txt").read_text("utf8")
    baseline = read("docs/incense-debt/reports/runtime/visual-baseline.json")
    native = read("docs/incense-debt/reports/platforms/windows/native-render.json")
    assets = read("docs/incense-debt/reports/runtime/asset-verification.json")
    ui = read("docs/incense-debt/reports/runtime/ui-refresh/ui-refresh.json")
    rows = {item.get("id"): item for item in manifest.get("assets", [])}
    checks: list[dict] = []

    required = ["concept_roster", "concept_paper_room", "concept_menu_map_combat"]
    missing = [asset_id for asset_id in required if asset_id not in rows]
    check(checks, "approved concept references are registered in the asset manifest", not missing, f"missing={missing}")
    for asset_id in required:
        row = rows.get(asset_id, {})
        file_value = str(row.get("file", ""))
        path = ROOT / file_value if file_value else ROOT / "__missing__"
        actual_size = list(Image.open(path).size) if path.is_file() else []
        check(checks, f"{asset_id} has an existing Sub2 image with stable dimensions and hash",
              row.get("kind") == "concept" and row.get("status") == "reviewed_concept" and row.get("engine_ready") is False and path.is_file() and actual_size == row.get("size") and digest(path) == row.get("sha256"),
              f"file={file_value}; expected_size={row.get('size')}; actual_size={actual_size}; provider={row.get('provider')}; model={row.get('model')}")
        prompt_path = ROOT / str(row.get("prompt", ""))
        check(checks, f"{asset_id} keeps a reproducible prompt source", prompt_path.is_file() and row.get("provider") == "sub2-image-gen" and row.get("model") == "gpt-image-2.5", f"prompt={row.get('prompt')}")

    required_doc_refs = [
        "characters-roster.png", "paper-lantern-asset-board.png", "menu-map-combat-board.png",
        "reports/platforms/windows/ui-style.png", "reports/platforms/windows/menu.png",
        "reports/platforms/windows/door-navigation.png", "reports/platforms/windows/detonate.png",
    ]
    missing_doc_refs = [ref for ref in required_doc_refs if ref not in visual_doc]
    check(checks, "visual contract names the character, room, menu, door and impact references", not missing_doc_refs, f"missing={missing_doc_refs}")
    check(checks, "the new reference prompt covers all three visual anchors", all(token in prompt for token in ["Panel 1", "Panel 2", "Panel 3", "physical exits", "combat feedback"]), "menu, physical room entry and combat feedback are explicit prompt sections")

    baseline_refs = {str(item.get("path")): item for item in baseline.get("references", [])}
    board_entry = baseline_refs.get("output/imagegen/incense-debt/menu-map-combat-board.png", {})
    board_path = ROOT / "output/imagegen/incense-debt/menu-map-combat-board.png"
    check(checks, "visual baseline binds the new board to its current hash", board_path.is_file() and board_entry.get("sha256") == digest(board_path) and board_entry.get("size") == list(Image.open(board_path).size), f"baseline_references={len(baseline.get('references', []))}")
    check(checks, "runtime screenshots and UI evidence remain bound to the current executable", baseline.get("compiled_windows_sha256") == native.get("artifact_sha256") and ui.get("passed") and ui.get("compiled_windows_sha256") == native.get("artifact_sha256"), f"compiled={baseline.get('compiled_windows_sha256')}; native={native.get('artifact_sha256')}; ui={ui.get('compiled_windows_sha256')}")
    check(checks, "native asset and screenshot evidence is green", assets.get("passed") and not assets.get("failures") and native.get("asset_failures", []) == [] and all(item.get("saved") and item.get("state_stable") for item in native.get("captures", [])), f"assets={assets.get('native_assets_loaded')}; captures={len(native.get('captures', []))}")
    check(checks, "visual contract keeps concept references separate from runtime replacements", "未经审查不会直接替换引擎素材" in visual_doc and "运行时" in visual_doc, "concept direction is reviewed while runtime screenshots/assets remain authoritative")

    failures = [item["name"] for item in checks if not item["passed"]]
    report = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "passed": not failures,
        "checks": checks,
        "failures": failures,
        "reviewed_concepts": required,
        "runtime_assets": assets.get("native_assets_loaded", 0),
        "native_captures": len(native.get("captures", [])),
        "scope": "reviewed visual references, prompt provenance, visual contract and current native evidence; concept boards do not silently replace engine assets",
    }
    json_path = REPORTS / "runtime/visual-contract-audit.json"
    md_path = REPORTS / "runtime/visual-contract-audit.md"
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    lines = [
        "# 方向1视觉契约审计", "",
        "这份报告把 Sub2 视觉参考、素材清单、视觉契约和当前 Windows 原生截图放到同一条证据链；概念设计板定义方向，实际运行截图和运行时资源报告负责证明落地。", "",
        "## 审计结果", "", "| 检查 | 状态 | 证据摘要 |", "| --- | --- | --- |",
    ]
    for item in checks:
        lines.append(f"| {item['name']} | {'通过' if item['passed'] else '失败'} | {item['detail']} |")
    lines += ["", "边界：概念图审查通过不等于每个运行时栅格都由新模型逐帧生成；运行时资源、原生截图和设备/真人验收仍按各自报告处理。", "", "机器报告：[visual-contract-audit.json](visual-contract-audit.json)。重新生成：", "", "```powershell", "python tools/runtime/audit_visual_contract.py", "```", ""]
    md_path.write_text("\n".join(lines), "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "failures": failures, "json": str(json_path), "markdown": str(md_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
