"""Build one template-derived Word policy and a matching static website.

Run with the bundled documents Python. Operator details are deliberately external
to the policy model so missing, unconfirmed information cannot pass publication QA.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
from hashlib import sha256
from html import escape
import json
from pathlib import Path
import re
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

from lxml import etree

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = Path("C:/Users/carzy/Downloads/privacy-policy-template.docx")
TEMPLATE_HASH = "662473e9abc64942e91a57dfeca7248c53883468805a658405b5c5af8e790a20"
MODEL = ROOT / "docs/legal/privacy-policy-content.json"
SITE = ROOT / "sites/privacy-policy"
QA = ROOT / ".local-tools/privacy-policy"
POLICY_DATE = json.loads(MODEL.read_text(encoding="utf-8"))["updated"]
OUTPUT = ROOT / f"output/legal/incense-debt-privacy-policy-{POLICY_DATE}.docx"
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
XML = "{http://www.w3.org/XML/1998/namespace}"
NUMERALS = "一 二 三 四 五 六 七 八 九 十".split()


def node(name, **attrs):
    return etree.Element(W + name, {W + k: str(v) for k, v in attrs.items()})


def set_prop(parent, name, **attrs):
    existing = parent.find(W + name)
    if existing is None:
        existing = node(name)
        parent.append(existing)
    for k, v in attrs.items():
        existing.set(W + k, str(v))
    return existing


def replace_text(text, operator):
    for key in ("operator_name", "contact_email"):
        replacement = operator.get(key) or {
            "operator_name": "【运营者名称待提供】",
            "contact_email": "【隐私联系邮箱待提供】",
        }[key]
        text = text.replace("{{" + key + "}}", replacement)
    return text


def load_policy(operator, draft):
    serialized = MODEL.read_text(encoding="utf-8")
    policy = json.loads(serialized)
    # Resolve text recursively without changing user-provided JSON escaping.
    def resolve(value):
        if isinstance(value, str):
            return replace_text(value, operator)
        if isinstance(value, list):
            return [resolve(x) for x in value]
        if isinstance(value, dict):
            return {k: resolve(v) for k, v in value.items()}
        return value
    policy = resolve(policy)
    for section in policy["sections"]:
        expanded = []
        for block in section["blocks"]:
            if block["type"] == "operator_address":
                address = operator.get("registered_address", "").strip()
                if address:
                    expanded.append({"type": "p", "text": "注册地址：" + address + "。"})
                elif operator.get("operator_type") == "company":
                    expanded.append({"type": "p", "text": "注册地址：【公司注册地址待提供】。"})
            else:
                expanded.append(block)
        section["blocks"] = expanded
    policy["draft"] = draft
    policy["operator"] = operator
    return policy


def operator_errors(operator):
    errors = []
    if operator.get("operator_type") not in ("individual", "organization", "company"):
        errors.append("运营者类别缺失或无效")
    if not operator.get("operator_name", "").strip():
        errors.append("运营者／开发者名称缺失")
    email = operator.get("contact_email", "").strip()
    if not re.fullmatch(r"[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+", email):
        errors.append("真实的隐私联系邮箱缺失或格式不正确")
    if operator.get("operator_type") == "company" and not operator.get("registered_address", "").strip():
        errors.append("公司运营者的注册地址缺失")
    if operator.get("confirmed_for_publication") is not True:
        errors.append("运营者信息尚未由用户确认用于公开条款")
    return errors


def build_docx(policy):
    if sha256(TEMPLATE.read_bytes()).hexdigest() != TEMPLATE_HASH:
        raise RuntimeError("Reference template changed; inspect it again before editing.")
    with ZipFile(TEMPLATE) as source:
        document = etree.fromstring(source.read("word/document.xml"))
        styles = etree.fromstring(source.read("word/styles.xml"))
        body = document.find(W + "body")
        paragraphs = body.findall(W + "p")
        tables = body.findall(W + "tbl")
        section_properties = deepcopy(body.find(W + "sectPr"))

        def paragraph(text, prototype=17, bold=None, style=None, keep_next=False, page_break=False):
            result = node("p")
            props = deepcopy(paragraphs[prototype].find(W + "pPr"))
            if props is None:
                props = node("pPr")
            # Keep template spacing/typeface, and protect headings/paragraph tails.
            set_prop(props, "widowControl", val="1")
            if "https://" in text or "%APPDATA%" in text:
                # Avoid stretched Chinese justification around long Latin paths.
                set_prop(props, "jc", val="left")
            if keep_next:
                set_prop(props, "keepNext", val="1")
            if page_break:
                set_prop(props, "pageBreakBefore", val="1")
            if style:
                old = props.find(W + "pStyle")
                if old is not None:
                    props.remove(old)
                props.insert(0, node("pStyle", val=style))
            result.append(props)
            run_props = deepcopy(props.find(W + "rPr"))
            if run_props is None:
                run_props = node("rPr")
            for owner in (run_props, props.find(W + "rPr")):
                if owner is None:
                    continue
                set_prop(owner, "color", val="000000")
                for name in ("u", "highlight", "rPrChange"):
                    existing = owner.find(W + name)
                    if existing is not None:
                        owner.remove(existing)
                if bold is not None:
                    set_prop(owner, "b", val="1" if bold else "0")
                    set_prop(owner, "bCs", val="1" if bold else "0")
            run = node("r")
            run.append(run_props)
            value = node("t")
            value.set(XML + "space", "preserve")
            value.text = text
            run.append(value)
            result.append(run)
            return result

        # Extend the original styles rather than replacing the template stylesheet.
        for style_id, name, level in (("Title", "Title", None), ("PrivacyHeading1", "Privacy Heading 1", 0), ("PrivacyHeading2", "Privacy Heading 2", 1)):
            if styles.find(f"{W}style[@{W}styleId='{style_id}']") is None:
                style = node("style", type="paragraph", styleId=style_id)
                style.append(node("name", val=name))
                style.append(node("basedOn", val="1"))
                style.append(node("next", val="1"))
                style.append(node("qFormat"))
                ppr = node("pPr")
                ppr.append(node("keepNext"))
                if level is not None:
                    ppr.append(node("outlineLvl", val=level))
                style.append(ppr)
                rpr = node("rPr")
                rpr.append(node("color", val="000000"))
                style.append(rpr)
                styles.append(style)

        def policy_table(block):
            template = tables[0 if block["key"] == "permissions" else 1]
            result = deepcopy(template)
            original_rows = template.findall(W + "tr")
            for row in result.findall(W + "tr"):
                result.remove(row)
            for row_index, values in enumerate([block["headers"]] + block["rows"]):
                row = deepcopy(original_rows[0 if row_index == 0 else 1])
                trpr = row.find(W + "trPr")
                if trpr is None:
                    trpr = node("trPr")
                    row.insert(0, trpr)
                set_prop(trpr, "cantSplit", val="1")
                if row_index == 0:
                    set_prop(trpr, "tblHeader", val="1")
                for cell, text in zip(row.findall(W + "tc"), values):
                    original_p = cell.find(W + "p")
                    ppr = deepcopy(original_p.find(W + "pPr"))
                    rpr = deepcopy(original_p.find(W + "r/" + W + "rPr"))
                    if rpr is None:
                        rpr = deepcopy(ppr.find(W + "rPr"))
                    for child in list(cell):
                        if child.tag != W + "tcPr":
                            cell.remove(child)
                    p = node("p")
                    p.append(ppr)
                    set_prop(ppr, "widowControl", val="1")
                    set_prop(rpr, "color", val="000000")
                    set_prop(rpr, "b", val="1" if row_index == 0 else "0")
                    set_prop(rpr, "bCs", val="1" if row_index == 0 else "0")
                    run = node("r")
                    run.append(rpr)
                    t = node("t")
                    t.text = text
                    run.append(t)
                    p.append(run)
                    cell.append(p)
                result.append(row)
            return result

        for child in list(body):
            body.remove(child)
        body.append(paragraph("温馨提示", prototype=0, bold=True, keep_next=True))
        if policy["draft"]:
            body.append(paragraph("未公开发布的草稿：运营者及隐私联系信息待补齐。", bold=True))
        for i, text in enumerate(policy["warm_notice"], 1):
            body.append(paragraph(str(i) + ". " + text))
        body.append(paragraph("请参阅后文了解完整说明及行使权利的方法。"))
        body.append(paragraph("更新日期：" + policy["updated"], prototype=12, page_break=True, keep_next=True))
        body.append(paragraph("生效日期：" + policy["effective"], prototype=12, keep_next=True))
        title = policy["title"] + ("（草稿）" if policy["draft"] else "")
        body.append(paragraph(title, prototype=15, style="Title", keep_next=True))
        body.append(paragraph("政策版本：" + policy["policy_version"] + "；适用范围：" + policy["scope"] + "。"))
        for text in policy["introduction"]:
            body.append(paragraph(text))
        body.append(paragraph("本隐私政策将帮助您了解以下内容：", bold=True, keep_next=True, page_break=True))
        for i, section in enumerate(policy["sections"]):
            body.append(paragraph(NUMERALS[i] + "、" + section["title"]))
        for section in policy["sections"]:
            body.append(paragraph(section["title"], prototype=34, style="PrivacyHeading1", keep_next=True))
            for block in section["blocks"]:
                if block["type"] == "h3":
                    body.append(paragraph(block["text"], prototype=35, style="PrivacyHeading2", keep_next=True))
                elif block["type"] == "table":
                    body.append(policy_table(block))
                    # The reference separates its tables from the following text.
                    body.append(paragraph(""))
                else:
                    body.append(paragraph(block["text"]))
        body.append(section_properties)
        replacements = {
            "word/document.xml": etree.tostring(document, encoding="UTF-8", xml_declaration=True, standalone=True),
            "word/styles.xml": etree.tostring(styles, encoding="UTF-8", xml_declaration=True, standalone=True),
        }
        core = etree.fromstring(source.read("docProps/core.xml"))
        ns = {"dc": "http://purl.org/dc/elements/1.1/", "cp": "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"}
        for tag, value in (("dc:title", title), ("dc:creator", policy["operator"].get("operator_name") or "香火债"), ("cp:lastModifiedBy", policy["operator"].get("operator_name") or "香火债")):
            prefix, local = tag.split(":")
            item = core.find("{" + ns[prefix] + "}" + local)
            if item is None:
                item = etree.SubElement(core, "{" + ns[prefix] + "}" + local)
            item.text = value
        replacements["docProps/core.xml"] = etree.tostring(core, encoding="UTF-8", xml_declaration=True, standalone=True)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as destination:
            for info in source.infolist():
                # writestr mutates offsets on ZipInfo; never mutate the source index.
                destination.writestr(deepcopy(info), replacements.get(info.filename, source.read(info.filename)))
        # Validate package integrity and preserve every unrelated template part.
        with ZipFile(OUTPUT) as output:
            assert output.testzip() is None
            assert set(source.namelist()) == set(output.namelist())
            for name in source.namelist():
                if name not in replacements:
                    assert source.read(name) == output.read(name), name
            check = etree.fromstring(output.read("word/document.xml"))
            assert etree.tostring(check.find(W + "body/" + W + "sectPr")) == etree.tostring(section_properties)
            assert len(check.findall(W + "body/" + W + "tbl")) == 2
    assert sha256(TEMPLATE.read_bytes()).hexdigest() == TEMPLATE_HASH


def html_text(text):
    pieces = []
    offset = 0
    for match in re.finditer(r"https://[A-Za-z0-9./_-]+|[^\s<>@，。；：]+@[^\s<>@，。；：]+\.[A-Za-z]{2,}", text):
        pieces.append(escape(text[offset:match.start()]))
        value = match.group()
        href = value if value.startswith("https://") else "mailto:" + value
        pieces.append(f'<a href="{escape(href, quote=True)}" rel="noreferrer">{escape(value)}</a>')
        offset = match.end()
    pieces.append(escape(text[offset:]))
    return "".join(pieces)


def build_site(policy):
    sections = []
    markdown = ["# " + policy["title"] + ("（草稿）" if policy["draft"] else ""), "", f'更新日期：{policy["updated"]}  \n生效日期：{policy["effective"]}  \n政策版本：{policy["policy_version"]}', "", "适用范围：" + policy["scope"], "", "## 温馨提示", ""]
    if policy["draft"]:
        markdown += ["**未公开发布：运营者名称与隐私联系邮箱待提供。**", ""]
    for i, text in enumerate(policy["warm_notice"], 1):
        markdown.extend([f"{i}. {text}", ""])
    for text in policy["introduction"]:
        markdown.extend([text, ""])
    for i, section in enumerate(policy["sections"]):
        prefix = NUMERALS[i] + "、"
        sections.append(f'<section id="{section["id"]}" aria-labelledby="heading-{section["id"]}"><h2 id="heading-{section["id"]}"><span class="section-number">{i+1:02d}</span>{escape(section["title"])}</h2>')
        markdown.extend(["## " + prefix + section["title"], ""])
        for block in section["blocks"]:
            kind = block["type"]
            if kind in ("p", "h3"):
                sections.append(f'<{kind}>{html_text(block["text"])}</{kind}>')
                markdown.extend([("### " if kind == "h3" else "") + block["text"], ""])
            elif kind == "table":
                label = "权限及能力清单" if block["key"] == "permissions" else "本地组件及网页托管服务清单"
                sections.append(f'<div class="table-scroll" role="region" aria-label="{label}" tabindex="0"><table><caption>{label}</caption><thead><tr>')
                sections.extend(f'<th scope="col">{escape(x)}</th>' for x in block["headers"])
                sections.append("</tr></thead><tbody>")
                markdown += ["| " + " | ".join(block["headers"]) + " |", "| " + " | ".join("---" for _ in block["headers"]) + " |"]
                for row in block["rows"]:
                    sections.append("<tr>" + "".join("<td>" + html_text(cell) + "</td>" for cell in row) + "</tr>")
                    markdown.append("| " + " | ".join(row) + " |")
                sections.append("</tbody></table></div>")
                markdown.append("")
        sections.append("</section>")
    (ROOT / "docs/legal/privacy-policy.md").write_text("\n".join(markdown), encoding="utf-8")
    nav = "".join(f'<li><a href="#{s["id"]}"><span>{i+1:02d}</span>{escape(s["short_title"])}</a></li>' for i, s in enumerate(policy["sections"]))
    notice = "".join(f"<li>{html_text(text)}</li>" for text in policy["warm_notice"])
    intro = "".join("<p>" + html_text(text) + "</p>" for text in policy["introduction"])
    draft_notice = '<div class="draft-banner">本地草稿 · 运营者及隐私联系信息待补齐，尚未公开发布。</div>' if policy["draft"] else ""
    html = f'''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="《香火债》隐私政策：离线游玩、本机存档、权限、手动分享及数据删除说明。">
  <meta name="theme-color" content="#173c35">
  <meta name="color-scheme" content="light">
  <title>{escape(policy["title"])}{' · 草稿' if policy['draft'] else ''}</title>
  <link rel="icon" type="image/png" href="/assets/paper-spirit.png">
  <link rel="stylesheet" href="/assets/privacy.css">
</head>
<body id="top">
  <a class="skip-link" href="#policy">跳到条款正文</a>
  {draft_notice}
  <header class="site-header"><a class="brand" href="#top"><img src="/assets/paper-spirit.png" width="40" height="40" alt="香火债纸偶图标"><span>香火债<small>INCENSE DEBT</small></span></a><a class="header-link" href="#contact">隐私联系 <span aria-hidden="true">↗</span></a></header>
  <main>
    <div class="hero"><div><p class="eyebrow">PRIVACY POLICY</p><h1>隐私政策</h1><p class="hero-copy">关于你的存档、权限与选择。</p><p class="operator" id="operator">运营主体：<strong>{escape(policy['operator']['operator_name'])}</strong></p><div class="metadata"><span>更新 / {policy['updated']}</span><span>生效 / {policy['effective']}</span><span>版本 / {policy['policy_version']}</span></div></div><img class="hero-spirit" src="/assets/paper-spirit.png" width="144" height="144" alt=""></div>
    <div class="principles" aria-label="当前游戏的隐私概况"><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10h16v9H4zM8 10V6a4 4 0 0 1 8 0v4M12 14v2"/></svg>离线游玩</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 3h14v18H5zM9 17h6M9 7h6M9 11h6"/></svg>本机存档</span><span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 16V3M7 8l5-5 5 5M4 14v6h16v-6"/></svg>自主导出</span></div>
    <div class="document-layout"><aside><details class="toc" open><summary>条款目录 <span aria-hidden="true">⌄</span></summary><nav aria-label="隐私政策目录"><ol>{nav}</ol></nav><a class="download" href="/downloads/{OUTPUT.name}" download>下载 Word 文档 <span aria-hidden="true">↓</span></a></details></aside>
      <article id="policy" class="policy-paper"><section class="notice" aria-labelledby="notice-title"><h2 id="notice-title">温馨提示</h2><ol>{notice}</ol></section><div class="policy-intro"><p class="scope"><strong>适用范围</strong><br>{escape(policy['scope'])}</p>{intro}</div>{''.join(sections)}<a class="back-top" href="#top">返回顶部 ↑</a></article>
    </div>
  </main>
  <footer><span>© {policy['updated'][:4]} {escape(policy['operator'].get('operator_name') or '香火债')}</span><span>《香火债》隐私政策 · v{policy['policy_version']}</span><a href="/versions/{policy['updated']}">查看此版本</a></footer>
</body>
</html>
'''
    SITE.mkdir(parents=True, exist_ok=True)
    (SITE / "assets").mkdir(exist_ok=True)
    (SITE / "downloads").mkdir(exist_ok=True)
    (SITE / "versions").mkdir(exist_ok=True)
    (SITE / "index.html").write_text(html, encoding="utf-8")
    (SITE / f"versions/{policy['updated']}.html").write_text(html, encoding="utf-8")
    shutil.copyfile(ROOT / "output/branding/incense-debt/current-paper-spirit/app-icon-128.png", SITE / "assets/paper-spirit.png")
    shutil.copyfile(OUTPUT, SITE / "downloads" / OUTPUT.name)
    return html


def validate_content(policy, html):
    check = etree.HTML(html)
    ids = check.xpath("//*[@id]/@id")
    assert len(ids) == len(set(ids)), "Duplicate HTML IDs"
    assert not check.xpath("//script|//iframe|//form"), "Unexpected active/embedded content"
    for href in check.xpath("//a/@href"):
        if href.startswith("#"):
            assert href[1:] in ids, "Missing anchor " + href
    assert len(policy["sections"]) == 10
    with ZipFile(OUTPUT) as docx:
        document = etree.fromstring(docx.read("word/document.xml"))
        all_text = "".join(document.itertext())
        for section in policy["sections"]:
            assert section["title"] in all_text
            for block in section["blocks"]:
                if "text" in block:
                    assert block["text"] in all_text, "Missing DOCX paragraph"
                if block["type"] == "table":
                    for value in block["headers"] + [x for row in block["rows"] for x in row]:
                        assert value in all_text
    if not policy["draft"]:
        assert "待提供" not in all_text and "待补齐" not in html and "{{" not in all_text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--operator", type=Path, default=QA / "operator.pending.json")
    parser.add_argument("--draft", action="store_true", help="Create a private review draft; never passes deployment gate.")
    args = parser.parse_args()
    operator = json.loads(args.operator.read_text(encoding="utf-8-sig"))
    problems = operator_errors(operator)
    if problems and not args.draft:
        raise SystemExit("Publication input missing: " + "; ".join(problems))
    policy = load_policy(operator, args.draft)
    build_docx(policy)
    html = build_site(policy)
    validate_content(policy, html)
    status = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "draft": args.draft,
        "publication_ready": not args.draft and not problems,
        "blocking_inputs": problems,
        "operator_name": policy["operator"]["operator_name"],
        "contact_email": policy["operator"]["contact_email"],
        "policy_version": policy["policy_version"],
        "docx": str(OUTPUT),
        "docx_sha256": sha256(OUTPUT.read_bytes()).hexdigest(),
        "template_sha256": TEMPLATE_HASH,
        "content_sha256": sha256(MODEL.read_bytes()).hexdigest(),
        "site": str(SITE),
        "chapters": len(policy["sections"]),
        "tables": 2,
        "content_checks": "passed",
        "visual_docx_review": "pending"
    }
    QA.mkdir(parents=True, exist_ok=True)
    (QA / "build-status.json").write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(status, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
