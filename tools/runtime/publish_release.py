"""Upload the prepared Alpha to a draft, verify server digests, then publish it.

Uses the user's existing native GitHub CLI authentication. It never handles,
prints, copies, or commits API tokens. Repeated calls skip matching attachments.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

from package_release import ROOT, TAG

REPO = "wikigsroom/joss-debt"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default=TAG,
                        help="Prepared, annotated Alpha tag to publish")
    parser.add_argument("--title", help="Release title; defaults to the game and tag")
    parser.add_argument("--gh", default=shutil.which("gh") or
                        str(ROOT / ".local-tools/github-cli/bin/gh.exe"))
    args = parser.parse_args()
    tag = args.tag
    if not re.fullmatch(r"v\d+\.\d+\.\d+-alpha\.\d+", tag):
        raise RuntimeError("Expected a versioned Alpha tag")
    gh = str(Path(args.gh).resolve())
    directory = ROOT / "build/release" / tag
    payload = directory / "assets"
    notes = ROOT / "docs/releases" / (tag + ".md")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).strip():
        raise RuntimeError("Commit the release documentation and tools before publishing")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    tagged = subprocess.check_output(["git", "rev-parse", tag + "^{commit}"], cwd=ROOT).decode().strip()
    if tagged != head:
        raise RuntimeError("Release tag must point to the reviewed current commit")
    remote = subprocess.check_output(["git", "ls-remote", "origin", "refs/heads/main",
                                      "refs/tags/" + tag, "refs/tags/" + tag + "^{}"], cwd=ROOT).decode()
    if not any(line.split() == [head, "refs/heads/main"] for line in remote.splitlines()):
        raise RuntimeError("Push the current main commit before publishing")
    if not any(line.split() == [head, "refs/tags/" + tag + "^{}"] for line in remote.splitlines()):
        raise RuntimeError("Push the annotated release tag before publishing")
    manifest = json.loads((payload / "release-manifest.json").read_text("utf8"))
    game_tree = subprocess.check_output(["git", "rev-parse", tag + ":game"], cwd=ROOT).decode().strip()
    if manifest["tag"] != tag or manifest["repository"] != REPO or manifest["prerelease"] is not True:
        raise RuntimeError("Prepared manifest does not describe this Alpha release")
    if manifest["game_git_tree"] != game_tree:
        raise RuntimeError("Release game tree differs from the tag")
    if not manifest["windows_verification"]["passed"]:
        raise RuntimeError("Windows release did not pass native verification")
    expected = {}
    for line in (payload / "SHA256SUMS.txt").read_text("utf8").splitlines():
        sha, name = line.split("  ", 1)
        path = (payload / name).resolve()
        if not path.is_relative_to(payload) or digest(path) != sha:
            raise RuntimeError(f"Attachment no longer matches its checksum: {name}")
        expected[name] = {"sha256": sha, "bytes": path.stat().st_size}
    expected["SHA256SUMS.txt"] = {"sha256": digest(payload / "SHA256SUMS.txt"),
                                 "bytes": (payload / "SHA256SUMS.txt").stat().st_size}
    for row in manifest["files"]:
        if expected[row["name"]] != {"sha256": row["sha256"], "bytes": row["bytes"]}:
            raise RuntimeError("Manifest and checksums disagree")

    env = os.environ.copy()
    env.pop("GH_DEBUG", None)
    env["GH_PROMPT_DISABLED"] = "1"
    env["GH_NO_UPDATE_NOTIFIER"] = "1"

    def command(*parts, timeout=180, optional=False):
        result = subprocess.run([gh, *parts], cwd=ROOT, env=env, capture_output=True,
                                timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
        output = (result.stdout + result.stderr).decode("utf8", errors="replace")
        if result.returncode and not optional:
            raise RuntimeError(output.strip())
        return result.returncode, output

    release_id = None

    def release(optional=False):
        nonlocal release_id
        # The tag endpoint omits drafts. Discover our draft through the
        # authenticated release list, then query its stable numeric ID.
        if release_id is None:
            _, output = command("api", f"repos/{REPO}/releases?per_page=100",
                                "--paginate", "--slurp")
            candidates = [row for page in json.loads(output) for row in page
                          if row["tag_name"] == tag]
            if not candidates:
                if optional:
                    return None
                raise RuntimeError("The created draft was not found in the authenticated release list")
            if len(candidates) != 1:
                raise RuntimeError("Multiple releases use the requested tag; review before uploading")
            release_id = candidates[0]["id"]
        _, output = command("api", f"repos/{REPO}/releases/{release_id}")
        return json.loads(output)

    def matching(row, name):
        wanted = expected[name]
        return row and row["state"] == "uploaded" and row["size"] == wanted["bytes"] and \
            row.get("digest") == "sha256:" + wanted["sha256"]

    state = release(optional=True)
    if state is None:
        print("Creating the prerelease draft at the verified tag...", flush=True)
        command("release", "create", tag, "--repo", REPO, "--draft", "--prerelease",
                "--verify-tag", "--target", head, "--title",
                args.title or f"香火债 / Incense Debt {tag}",
                "--notes-file", str(notes))
        state = release()
    if not state["draft"]:
        assets = {row["name"]: row for row in state["assets"]}
        if set(assets) != set(expected) or not all(matching(assets.get(name), name) for name in expected):
            raise RuntimeError("A published release exists with different attachments")
    else:
        unexpected = {row["name"] for row in state["assets"]} - set(expected)
        if unexpected:
            raise RuntimeError("Draft contains unrecognized assets; review without deleting them")
        for name in expected:
            state = release()
            existing = next((row for row in state["assets"] if row["name"] == name), None)
            if matching(existing, name):
                print("Already verified: " + name, flush=True)
                continue
            if existing:
                raise RuntimeError(f"Draft attachment differs from the prepared file: {name}")
            print(f"Uploading {name} ({expected[name]['bytes'] / 1048576:.1f} MiB)...", flush=True)
            command("release", "upload", tag, str(payload / name), "--repo", REPO, timeout=1800)
            state = release()
            row = next((row for row in state["assets"] if row["name"] == name), None)
            if not matching(row, name):
                raise RuntimeError(f"GitHub attachment digest/size did not match: {name}")
            print("GitHub SHA-256 verified: " + name, flush=True)
        state = release()
        assets = {row["name"]: row for row in state["assets"]}
        if set(assets) != set(expected) or not all(matching(assets.get(name), name) for name in expected):
            raise RuntimeError("Draft is incomplete or differs from the prepared files")
        print("All attachments verified. Publishing the Alpha prerelease...", flush=True)
        command("release", "edit", tag, "--repo", REPO, "--draft=false", "--prerelease",
                "--target", head, "--notes-file", str(notes))
        state = release()
    assets = {row["name"]: row for row in state["assets"]}
    if state["draft"] or not state["prerelease"] or set(assets) != set(expected) or \
            not all(matching(assets.get(name), name) for name in expected):
        raise RuntimeError("Published release does not match the verified Alpha")
    if state["body"].strip() != notes.read_text("utf8").strip():
        raise RuntimeError("Published notes differ from the reviewed bilingual notes")
    receipt = {"url": state["html_url"], "tag": tag, "commit": head,
               "draft": state["draft"], "prerelease": state["prerelease"],
               "published_at": state["published_at"],
               "assets": [{"name": row["name"], "bytes": row["size"], "digest": row["digest"],
                           "url": row["browser_download_url"]} for row in state["assets"]]}
    (directory / "publication-receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
