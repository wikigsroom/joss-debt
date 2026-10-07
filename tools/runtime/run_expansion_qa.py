"""Native expansion screenshots and keyboard input; close the native process on completion."""
from pathlib import Path
import subprocess
import hashlib
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGED = "--packaged" in sys.argv
ENGINE = ROOT / ("build/windows/IncenseDebt.exe" if PACKAGED else ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
REPORTS = ROOT / "docs/incense-debt/reports" / ("platforms/windows" if PACKAGED else "runtime") / "expansion"

def main():
    REPORTS.mkdir(parents=True,exist_ok=True)
    report_path=REPORTS/"expansion-native.json"
    report_path.unlink(missing_ok=True)
    args=[str(ENGINE),"--rendering-method","gl_compatibility","--rendering-driver","opengl3","--resolution","1280x720","--position","-16000,-16000"]
    if not PACKAGED: args += ["--path",str(ROOT/"game")]
    args += ["--","--qa-expansion","--qa-output="+str(REPORTS)]
    startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=subprocess.SW_HIDE
    process=subprocess.Popen(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
    try: output,_=process.communicate(timeout=660)
    except subprocess.TimeoutExpired:
        process.kill(); output,_=process.communicate(timeout=5)
        (REPORTS/"expansion-native.log").write_text(output.decode("utf8",errors="replace"),"utf8")
        raise RuntimeError("Expansion native QA timed out; process closed.")
    log=output.decode("utf8",errors="replace"); (REPORTS/"expansion-native.log").write_text(log,"utf8")
    print(log)
    if not report_path.exists(): return 1
    report=json.loads(report_path.read_text("utf8")); report["packaged"]=PACKAGED
    if PACKAGED: report["artifact_sha256"]=hashlib.sha256(ENGINE.read_bytes()).hexdigest()
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log: report["passed"]=False
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    for kind in ["scenery","dual","revision-fx"]:
        images=[Image.open(p).convert("RGB").resize((960,540),Image.Resampling.LANCZOS) for p in sorted(REPORTS.glob(f"motion-{kind}-*.png"))]
        if images: images[0].save(REPORTS/(kind+"-motion.gif"),save_all=True,append_images=images[1:],duration=100,loop=0)
    print(json.dumps({"passed":report["passed"],"checks":len(report["checks"]),"captures":len(report["captures"]),"failures":report["failures"]},ensure_ascii=False))
    return int(not report["passed"])
if __name__=="__main__":sys.exit(main())
