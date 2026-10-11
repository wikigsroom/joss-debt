"""Package only the accepted native clients and dedicated servers for v0.5.0."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TAG = "v0.5.0"
PROOFS = ROOT / "docs/incense-debt/reports/public-online-2026-10-11"

def digest(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()
def read(path): return json.loads(path.read_text("utf8"))
def require(value, message):
    if not value: raise RuntimeError(message)
def archive(path, members):
    if path.exists(): raise RuntimeError("Refusing to overwrite a prepared release archive")
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for source, name in members:
            require(source.is_file(), "Missing archive source: " + str(source))
            bundle.write(source, name)
    with zipfile.ZipFile(path) as bundle:
        require(bundle.testzip() is None, "Archive CRC failed")
        for source, name in members:
            with bundle.open(name) as stream: actual = hashlib.file_digest(stream,"sha256").hexdigest()
            require(actual == digest(source), "Archive bytes differ: " + name)

def main():
    require(not subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).strip(), "Commit accepted source and documentation before packaging")
    source_commit = subprocess.check_output(["git", "rev-parse", "HEAD"],cwd=ROOT).decode().strip()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:game"],cwd=ROOT).decode().strip()
    status = read(ROOT / "docs/incense-debt/reports/current-product-status.json")
    require(status["version"] == "0.5.0", "Wrong product version")
    for name in ["cooperative-native.json","duel-native.json","packaged-parity.json","linux-server-parity.json","windows-server-parity.json","layout.json","keyboard-flow.json","network-faults.json","public-recovery.json","public-load.json","android-lineage.json","android-verification.json","deployment.json"]:
        require(read(PROOFS/name)["passed"], "Failed accepted proof: " + name)
    payload = ROOT / "build/release" / TAG / "assets"; payload.mkdir(parents=True,exist_ok=True)
    guide = ROOT / "docs/releases/START-HERE.md"
    windows = ROOT / "build/windows/IncenseDebt.exe"
    android = ROOT / "build/android/IncenseDebt.apk"
    require(digest(windows) == status["windows"]["sha256"] and digest(android) == status["android"]["sha256"], "Changed accepted clients")
    notices = [(p,"licenses/"+p.name) for p in sorted((ROOT/"game/assets/licenses").iterdir()) if p.is_file()]
    notices += [(p,"licenses/"+p.name) for p in sorted((ROOT/"game/assets/fonts").glob("*OFL*.txt"))]
    notices += [(ROOT/"game/assets/ui/icons/Lucide-LICENSE.txt","licenses/Lucide-LICENSE.txt")]
    archive(payload / f"IncenseDebt-{TAG}-windows-x64.zip", [(windows,"IncenseDebt.exe"),(guide,"START-HERE.md")] + notices)
    apk_target = payload / f"IncenseDebt-{TAG}-android-arm64.apk"
    require(not apk_target.exists(), "Refusing to overwrite APK attachment")
    shutil.copyfile(android, apk_target)
    guide_target = payload / "START-HERE.txt"; shutil.copyfile(guide, guide_target)
    temporary = payload.parent / "server-guides"; temporary.mkdir(exist_ok=True)
    (temporary / "StartServer.cmd").write_text('@echo off\ncd /d "%~dp0"\nIncenseDebtServer.exe --headless --max-fps 60 -- --config=config.json\n',"utf8")
    config = read(ROOT/"server/config.example.json")
    config.update(bind="127.0.0.1",data_directory="./server-data",max_rooms=2,max_connections=16)
    (temporary / "config.json").write_text(json.dumps(config,indent=2)+"\n","utf8")
    win_server = ROOT/"build/server/IncenseDebtServer.exe"
    linux_server = ROOT/"build/server-linux/IncenseDebtServer.x86_64"
    for path, platform in [(win_server,"windows"),(linux_server,"linux")]:
        require(digest(path) == status["server"][platform]["sha256"], "Changed accepted server")
    archive(payload / f"IncenseDebt-{TAG}-server-windows-x64.zip",[(win_server,"IncenseDebtServer.exe"),(ROOT/"build/server/server-build.json","server-build.json"),(temporary/"StartServer.cmd","StartServer.cmd"),(temporary/"config.json","config.json"),(ROOT/"server/README.md","README.md")])
    members = [(linux_server,"IncenseDebtServer.x86_64"),(ROOT/"build/server-linux/server-build.json","server-build.json"),(ROOT/"server/README.md","README.md"),(temporary/"config.json","config.json"),(ROOT/"server/linux/stop.sh","stop.sh")]
    members += [(p,"linux/"+p.name) for p in sorted((ROOT/"server/linux").iterdir()) if p.is_file()]
    archive(payload/f"IncenseDebt-{TAG}-server-linux-x64.zip",members)
    files=[{"name":p.name,"bytes":p.stat().st_size,"sha256":digest(p)} for p in sorted(payload.iterdir())]
    manifest={"version":"0.5.0","tag":TAG,"repository":"wikigsroom/joss-debt","prerelease":False,"default_game_mode":"coop","source_commit":source_commit,"game_git_tree":tree,
        "generated_at":datetime.now(timezone.utc).isoformat(),"public_game_server_deployed":True,"locked_automatic_connection":True,"android_min_sdk":28,"android_version_code":9,"android_signing":"private release key with cryptographically verified legacy lineage",
        "windows_verification":{"passed":True,"sha256":digest(windows),"cooperative_checks":29,"duel_checks":32,"keyboard_checks":107},"android_verification":read(PROOFS/"android-lineage.json"),
        "native_server_sha256":{"windows":digest(win_server),"linux":digest(linux_server)},"privacy_policy_version":"1.6","proofs":"docs/incense-debt/reports/public-online-2026-10-11",
        "readme_motion_path":"public-online-2026-10-11/media/cooperative-native.gif","physical_android_tested":False,"files":files}
    content=json.dumps(manifest,ensure_ascii=False,indent=2)+"\n"
    (payload/"release-manifest.json").write_text(content,"utf8")
    (ROOT/"docs/releases/v0.5.0.manifest.json").write_text(content,"utf8")
    (payload/"SHA256SUMS.txt").write_text("\n".join(digest(p)+"  "+p.name for p in sorted(payload.iterdir()))+"\n","utf8")
    print(json.dumps({"passed":True,"tag":TAG,"attachments":len(list(payload.iterdir())),"game_git_tree":tree,"source_commit":source_commit}))

if __name__ == "__main__": main()
