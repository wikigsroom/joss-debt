"""Publish only the reviewed privacy site; verify public HTTPS without credentials."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse
from urllib.request import Request, ProxyHandler, build_opener, urlopen
from zipfile import ZipFile

from lxml import etree

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / ".local-tools/privacy-policy"
SITE = ROOT / "sites/privacy-policy"
PUBLIC_CUSTOM_HOSTS = {"xhz.sidcloud.cn"}
PREVIOUS_OPERATOR_NAMES = ("wikigsroom", "wikig's room", "wikig’s room", "SIDcloud", "吴国黎")
EXPECTED_PUBLIC_FILES = {
    "index.html", "assets/privacy.css", "assets/paper-spirit.png",
    "versions/2026-10-08.html", "downloads/incense-debt-privacy-policy-2026-10-08.docx",
    "versions/2026-10-09.html", "downloads/incense-debt-privacy-policy-2026-10-09.docx",
    "vercel.json", ".vercelignore",
}


def contains_previous_operator(text, expected_operator):
    # Match previous public names without treating the hosting domain as a name.
    return any(
        re.search(r"(?<![A-Za-z0-9_.])" + re.escape(name) + r"(?![A-Za-z0-9_.])", text, re.IGNORECASE)
        for name in PREVIOUS_OPERATOR_NAMES
        if name.casefold() != expected_operator.casefold()
    )


def publication_gate():
    status = json.loads((QA / "build-status.json").read_text(encoding="utf-8"))
    if not status["publication_ready"] or status["draft"]:
        raise RuntimeError("公开条款尚未就绪：" + "；".join(status["blocking_inputs"]))
    review = json.loads((QA / "visual-review.json").read_text(encoding="utf-8"))
    if review.get("all_pages_reviewed") is not True or review["docx_sha256"] != status["docx_sha256"]:
        raise RuntimeError("当前 Word 文件尚未完成逐页视觉检查")
    public_docx = SITE / "downloads" / Path(status["docx"]).name
    if sha256(public_docx.read_bytes()).hexdigest() != status["docx_sha256"]:
        raise RuntimeError("网站下载的 Word 文件与已检查的版本不一致")
    operator = json.loads((QA / "operator.json").read_text(encoding="utf-8-sig"))
    if status.get("operator_name") != operator["operator_name"] or status.get("contact_email") != operator["contact_email"]:
        raise RuntimeError("政策产物与当前已确认的运营主体信息不一致，请重新构建")
    for path in (SITE / "downloads").glob("*.docx"):
        with ZipFile(path) as package:
            text = " ".join(" ".join(etree.fromstring(package.read(name)).itertext()) for name in package.namelist() if name.endswith(".xml"))
        if status["operator_name"] not in text or contains_previous_operator(text, status["operator_name"]):
            raise RuntimeError("Word 下载仍含旧主体或缺少已确认主体：" + path.name)
        document_review = review.get("documents", {}).get(path.name, {})
        if document_review.get("all_pages_reviewed") is not True or document_review.get("sha256") != sha256(path.read_bytes()).hexdigest():
            raise RuntimeError("Word 下载尚未完成当前文件的逐页视觉检查：" + path.name)
    actual = set()
    for path in SITE.rglob("*"):
        relative = path.relative_to(SITE).as_posix()
        if path.is_symlink():
            raise RuntimeError("Unexpected symlink in deployment site: " + relative)
        if not path.is_file() or relative.startswith(".vercel/") or relative in (".gitignore", "README.md"):
            continue
        actual.add(relative)
    policy = json.loads((ROOT / "docs/legal/privacy-policy-content.json").read_text("utf8"))
    expected = EXPECTED_PUBLIC_FILES | {"versions/" + policy["updated"] + ".html", "downloads/" + Path(status["docx"]).name}
    if actual != expected:
        raise RuntimeError("Unexpected public upload files: " + str(sorted(actual ^ expected)))
    for path in [SITE / "index.html", *sorted((SITE / "versions").glob("*.html"))]:
        page = etree.HTML(path.read_bytes())
        text = " ".join(page.itertext())
        if "".join(page.xpath('//*[@id="operator"]/strong/text()')) != status["operator_name"]:
            raise RuntimeError("政策页面主体与资料页不一致：" + path.name)
        if contains_previous_operator(text, status["operator_name"]):
            raise RuntimeError("政策页面仍包含旧主体：" + path.name)
    html = (SITE / "index.html").read_text(encoding="utf-8")
    for marker in ("待提供", "待补齐", "草稿", "{{"):
        if marker in html:
            raise RuntimeError("Unresolved draft marker in public website: " + marker)
    print(f"Publication gate passed: reviewed DOCX, exact operator, {len(expected)} static upload files.", flush=True)
    return status


def get_public(url, proxy=None):
    request = Request(url, headers={"User-Agent": "IncenseDebt-Privacy-Verification/1.0"})
    opener = build_opener(ProxyHandler({"http": proxy, "https": proxy})) if proxy else None
    open_request = opener.open if opener else urlopen
    with open_request(request, timeout=35) as response:
        body = response.read()
        if response.status != 200:
            raise RuntimeError(f"Public URL returned HTTP {response.status}: {url}")
        if urlparse(response.url).scheme != "https":
            raise RuntimeError("Published URL does not remain HTTPS")
        return body, dict(response.headers), response.url


def verify_public(base, status, proxy=None):
    parsed = urlparse(base)
    if parsed.scheme != "https" or not parsed.hostname or not (
        parsed.hostname.endswith(".vercel.app") or parsed.hostname in PUBLIC_CUSTOM_HOSTS
    ):
        raise RuntimeError("Deployment did not return an approved Vercel HTTPS host")
    base = base.rstrip("/")
    receipt = []
    policy = json.loads((ROOT / "docs/legal/privacy-policy-content.json").read_text("utf8"))
    version_path = "versions/" + policy["updated"]
    docx_path = "downloads/" + Path(status["docx"]).name
    archived_pages = tuple("versions/" + path.stem for path in sorted((SITE / "versions").glob("*.html")) if path.stem != policy["updated"])
    docx_routes = tuple("downloads/" + path.name for path in sorted((SITE / "downloads").glob("*.docx")))
    page_routes = ("", "privacy", "privacy-policy", version_path, *archived_pages)
    for route in (*page_routes, *docx_routes, "assets/privacy.css", "assets/paper-spirit.png"):
        body, headers, resolved = get_public(base + "/" + route, proxy)
        if route in page_routes:
            tree = etree.HTML(body)
            title = "".join(tree.xpath("//title/text()"))
            if "《香火债》隐私政策" not in title:
                raise RuntimeError("Published URL shows a login/interstitial or unexpected page")
            page_text = "".join(tree.itertext())
            if status["contact_email"] not in page_text or status["operator_name"] not in page_text:
                raise RuntimeError("Published policy is missing the authorized developer alias or email")
            if "".join(tree.xpath('//*[@id="operator"]/strong/text()')) != status["operator_name"] or contains_previous_operator(page_text, status["operator_name"]):
                raise RuntimeError("Published operator does not match the exact application profile")
            if len(tree.xpath('//article/section[@id and @id!="notice"]')) != 10:
                raise RuntimeError("Published page is missing policy chapters")
            if tree.xpath("//script|//form|//iframe"):
                raise RuntimeError("Unexpected script, form or embed in the published static policy")
            if any(marker in body.decode("utf-8") for marker in ("待提供", "待补齐", "草稿")):
                raise RuntimeError("Draft placeholders were published")
            lowered = {k.lower(): v for k, v in headers.items()}
            if "script-src 'none'" not in lowered.get("content-security-policy", ""):
                raise RuntimeError("Expected privacy-site security headers were not applied")
        elif route in docx_routes:
            if sha256(body).hexdigest() != sha256((SITE / route).read_bytes()).hexdigest():
                raise RuntimeError("Public DOCX hash differs from reviewed file")
        receipt.append({"url": base + "/" + route, "resolved_url": resolved, "status": 200, "bytes": len(body)})
    return receipt


def deploy_temporary(node_path, cli_path):
    env = dict(os.environ)
    env["VERCEL_TELEMETRY_DISABLED"] = "1"
    command = [str(node_path), str(cli_path), "deploy", "--temporary", "--yes", "--json", "--non-interactive", "--global-config", str(QA / "vercel-anonymous-config")]
    result = subprocess.run(command, cwd=SITE, env=env, capture_output=True, timeout=240)
    (QA / "deployment.stdout.json").write_bytes(result.stdout)
    (QA / "deployment.stderr.log").write_bytes(result.stderr)
    if result.returncode:
        # The CLI's human diagnostics contain no account tokens; keep raw state private.
        diagnostic = result.stderr.decode("utf-8", errors="replace")
        raise RuntimeError("Vercel deployment failed: " + diagnostic[-2400:])
    try:
        output = json.loads(result.stdout.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("Vercel did not return a complete JSON deployment receipt; inspect the private output before retrying") from exc
    return output


def safe_urls(value):
    result = []
    if isinstance(value, dict):
        for key, item in value.items():
            if isinstance(item, str) and (key.lower().endswith("url") or key == "url"):
                url = item if item.startswith("https://") else "https://" + item
                if urlparse(url).hostname and urlparse(url).hostname.endswith(".vercel.app"):
                    result.append(url)
            elif key.lower() not in ("token", "secret", "auth", "claimurl"):
                result.extend(safe_urls(item))
    elif isinstance(value, list):
        for item in value:
            result.extend(safe_urls(item))
    return list(dict.fromkeys(result))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--verify-url")
    parser.add_argument("--proxy", help="Optional existing HTTP proxy for public HTTPS verification; TLS certificate validation remains enabled.")
    parser.add_argument("--node", type=Path, default=Path("D:/Program Files/nodejs/node.exe"))
    parser.add_argument("--cli", type=Path, default=Path("C:/Users/carzy/AppData/Local/npm-cache/_npx/67eb4586ca667318/node_modules/vercel/dist/index.js"))
    args = parser.parse_args()
    status = publication_gate()
    if args.check_only:
        return
    deployment = None
    if args.verify_url:
        base = args.verify_url
    else:
        deployment = deploy_temporary(args.node, args.cli)
        candidates = safe_urls(deployment)
        if not candidates:
            raise RuntimeError("No public deployment URL in CLI receipt; inspect the private receipt before retrying")
        base = candidates[0]
    verified = verify_public(base, status, args.proxy)
    receipt = {
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "public_url": base,
        "docx_sha256": status["docx_sha256"],
        "operator_name": status["operator_name"],
        "policy_version": status["policy_version"],
        "unauthenticated_https_checks": verified,
        "hosting": "Vercel",
    }
    state_path = SITE / ".vercel/anonymous.json"
    if state_path.is_file():
        state = json.loads(state_path.read_text(encoding="utf-8"))
        # Do not print/store the deployment access token in the delivery receipt.
        receipt["temporary"] = True
        receipt["claim_url"] = state.get("claimUrl")
        expiry = state.get("expiresAt")
        if isinstance(expiry, (int, float)):
            receipt["expires_at_utc"] = datetime.fromtimestamp(expiry / 1000, tz=timezone.utc).isoformat()
    (QA / "deployment-verified.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
