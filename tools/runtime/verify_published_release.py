"""Verify anonymous HTTPS access to the published release and its attachments.

GitHub's full-file digests are checked by publish_release.py. This final check
uses no credentials, bounds response reads and confirms public download access.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def fetch(url, limit, prefix=False):
    if not url.startswith("https://"):
        raise RuntimeError("Public verification requires HTTPS")
    headers = {"User-Agent": "IncenseDebt-release-verification"}
    if prefix:
        headers["Range"] = "bytes=0-4095"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=45) as response:
        if not response.url.startswith("https://"):
            raise RuntimeError("Non-HTTPS download redirect")
        data = response.read(limit + (0 if prefix else 1))
        if not prefix and len(data) > limit:
            raise RuntimeError("Public response exceeds verification limit")
        return response.status, {key.lower(): value for key, value in response.headers.items()}, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="v0.3.0-alpha.1")
    args = parser.parse_args()
    receipt = json.loads((ROOT / "build/release" / args.tag / "publication-receipt.json").read_text("utf8"))
    assert receipt["tag"] == args.tag and not receipt["draft"] and receipt["prerelease"]
    checks = []
    status, _, page = fetch(receipt["url"], 2 * 1024 * 1024)
    checks.append({"id": "anonymous_release_page", "url": receipt["url"], "status": status,
                   "passed": status == 200 and args.tag.encode() in page})
    for item in receipt["assets"]:
        small = item["bytes"] < 1024 * 1024
        status, headers, data = fetch(item["url"], 1024 * 1024 if small else 4096, prefix=not small)
        if small:
            valid = status == 200 and len(data) == item["bytes"] and "sha256:" + hashlib.sha256(data).hexdigest() == item["digest"]
        else:
            content_range = headers.get("content-range", "")
            valid = len(data) == 4096 and ((status == 206 and content_range.endswith("/" + str(item["bytes"])))
                                        or (status == 200 and int(headers.get("content-length", 0)) == item["bytes"]))
            valid = valid and (data.startswith(b"PK") if item["name"].endswith((".zip", ".apk")) else True)
        checks.append({"id": "anonymous_asset", "name": item["name"], "url": item["url"], "status": status,
                       "expected_bytes": item["bytes"], "prefix_only": not small, "passed": valid})
    readme_url = f"https://raw.githubusercontent.com/wikigsroom/joss-debt/{args.tag}/README.md"
    status, _, readme = fetch(readme_url, 1024 * 1024)
    checks.append({"id": "tagged_readme_has_online_gif", "url": readme_url, "status": status,
                   "passed": status == 200 and b"online-2026-10-11/media/duel-native.gif" in readme})
    report = {"passed": all(item["passed"] for item in checks), "tag": args.tag, "release_url": receipt["url"],
              "commit": receipt["commit"], "verified_at": datetime.now(timezone.utc).isoformat(), "checks": checks,
              "anonymous": True, "tls_verification": "system default; enabled", "browser_used": False,
              "binary_integrity": "full GitHub SHA-256 verified in publication receipt; HTTPS prefix check here"}
    destination = ROOT / "docs/releases" / (args.tag + ".https.json")
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "url": receipt["url"]}, ensure_ascii=False))
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
