"""Fetch licensed, pinned UI type and vectors with the native Windows Python runtime."""
from pathlib import Path
import hashlib
import json
import urllib.request
import zipfile
import py7zr
import base64
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".local-tools/fonts"
UI = ROOT / "game/assets/ui/icons"
FONTS = ROOT / "game/assets/fonts"
REPORT = ROOT / "docs/incense-debt/reports/runtime/ui-refresh"
ICONS = "arrow-left arrow-right arrow-up arrow-down book-open pause play settings-2 log-out house lock check x heart shield coins flame wind link refresh-cw sparkles sword wand-sparkles scroll-text map route volume-2 volume-x gamepad-2 mouse crosshair hand smartphone info download upload rotate-ccw eye circle-question-mark chevron-left chevron-right chevron-down crown target pencil sun leaf droplet layers circle-dot music touchpad monitor save folder-open search".split()


def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return path
    req = urllib.request.Request(url, headers={"User-Agent": "IncenseDebt-native-ui"})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            payload = response.read()
    except Exception:
        if not url.startswith("https://raw.githubusercontent.com/"):
            raise
        owner, repo, revision, source_path = url.removeprefix("https://raw.githubusercontent.com/").split("/", 3)
        api = f"https://api.github.com/repos/{owner}/{repo}/contents/{source_path}?ref={revision}"
        request = urllib.request.Request(api, headers={"User-Agent": "IncenseDebt-native-ui"})
        response = json.load(urllib.request.urlopen(request, timeout=30))
        payload = base64.b64decode(response["content"])
    path.write_bytes(payload)
    return path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    REPORT.mkdir(parents=True, exist_ok=True)
    body_url = "https://github.com/CyanoHao/Resource-Han-Rounded/releases/download/v0.990/RHR-CN-0.990.7z"
    title_url = "https://github.com/atelier-anchor/smiley-sans/releases/download/v2.0.1/smiley-sans-v2.0.1.zip"
    archive = fetch(body_url, CACHE / "RHR-CN-0.990.7z")
    with py7zr.SevenZipFile(archive) as bundle:
        names = bundle.getnames()
        targets = [name for name in names if any(word in name.lower() for word in ["medium", "bold", "license", "ofl"])]
        print("Rounded font archive:", json.dumps(targets, ensure_ascii=False))
        if not (CACHE / "rounded-source").exists():
            bundle.extract(CACHE / "rounded-source", targets=targets)
    title = fetch(title_url, CACHE / "smiley-sans-v2.0.1.zip")
    with zipfile.ZipFile(title) as bundle:
        for name in bundle.namelist():
            if name.endswith(".ttf") or "license" in name.lower() or "ofl" in name.lower():
                target = CACHE / "smiley-source" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(bundle.read(name))
    licenses = {
        "ResourceHanRounded-OFL.txt": "https://raw.githubusercontent.com/CyanoHao/Resource-Han-Rounded/master/OFL-License.txt",
        "SmileySans-OFL.txt": "https://raw.githubusercontent.com/atelier-anchor/smiley-sans/v2.0.1/LICENSE",
    }
    for name, url in licenses.items():
        bundled = list((CACHE / "smiley-source").rglob("LICENSE")) if name.startswith("Smiley") else []
        if bundled:
            (FONTS / name).write_bytes(bundled[0].read_bytes())
        else:
            fetch(url, FONTS / name)
    req = urllib.request.Request("https://api.github.com/repos/lucide-icons/lucide/commits/main", headers={"User-Agent": "IncenseDebt-native-ui"})
    revision_file = REPORT / "lucide-revision.txt"
    if revision_file.exists():
        revision = revision_file.read_text("utf8").strip()
    else:
        revision = json.load(urllib.request.urlopen(req, timeout=30))["sha"]
        revision_file.write_text(revision + "\n", "utf8")
    base = "https://raw.githubusercontent.com/lucide-icons/lucide/" + revision
    missing = [name for name in ICONS if not (CACHE / "lucide-source" / (name + ".svg")).exists()]
    if missing:
        bundle_path = fetch("https://codeload.github.com/lucide-icons/lucide/zip/" + revision, CACHE / ("lucide-" + revision + ".zip"))
        with zipfile.ZipFile(bundle_path) as bundle:
            prefix = "lucide-" + revision + "/"
            for name in ICONS:
                source = CACHE / "lucide-source" / (name + ".svg")
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes(bundle.read(prefix + "icons/" + name + ".svg"))
            (UI / "Lucide-LICENSE.txt").write_bytes(bundle.read(prefix + "LICENSE"))
    else:
        fetch(base + "/LICENSE", UI / "Lucide-LICENSE.txt")
    def icon(name):
        original = fetch(base + "/icons/" + name + ".svg", CACHE / "lucide-source" / (name + ".svg"))
        target = UI / (name + ".svg")
        text = original.read_text("utf8").replace('stroke="currentColor"', 'stroke="#ffffff"')
        text = text.replace('width="24"', 'width="96"').replace('height="24"', 'height="96"')
        target.write_text(text, "utf8")
        return {"name": name, "file": str(target.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(target), "source_sha256": sha(original), "source": base + "/icons/" + name + ".svg", "normalization": "original 24-unit vector paths retained; white runtime tint mask, 96px native import for crisp 24–88px presentation"}
    with ThreadPoolExecutor(max_workers=5) as pool:
        icons = list(pool.map(icon, ICONS))
    filled = UI / "heart-solid.svg"
    filled.write_text((UI / "heart.svg").read_text("utf8").replace('fill="none"', 'fill="#ffffff"'), "utf8")
    icons.append({"name": "heart-solid", "file": str(filled.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(filled), "source_sha256": sha(UI / "heart.svg"), "derivative": "same licensed heart path; filled state for health pips"})
    report = {"font_sources": [{"family": "Resource Han Rounded CN", "version": "0.990", "url": body_url, "archive_sha256": sha(archive), "license": "SIL OFL 1.1"}, {"family": "Smiley Sans", "version": "2.0.1", "url": title_url, "archive_sha256": sha(title), "license": "SIL OFL 1.1"}], "vector_icons": icons, "lucide_revision": revision, "icon_license": "ISC (Lucide), MIT (Feather-derived subset); full upstream license included", "virtualization": "none"}
    (REPORT / "licensed-sources.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Native font archives and", len(icons), "licensed vector icons ready.")


if __name__ == "__main__":
    main()
