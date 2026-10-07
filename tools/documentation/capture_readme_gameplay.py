"""Capture actual unboosted native combat; close the temporary window on exit."""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image
from prepare_readme_media import encode_gif

ROOT=Path(__file__).resolve().parents[2]
FRAMES=ROOT/".local-tools/readme-capture"
MEDIA=ROOT/"docs/media"

def main():
    FRAMES.mkdir(parents=True,exist_ok=True)
    MEDIA.mkdir(parents=True,exist_ok=True)
    engine=ROOT/".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
    artifact=ROOT/"build/windows/IncenseDebt.exe"
    args=[str(engine),"--main-pack",str(artifact),"--script",str(ROOT/"tools/documentation/capture_readme_gameplay.gd"),
          "--rendering-method","gl_compatibility","--rendering-driver","opengl3","--resolution","1280x720","--position","-16000,-16000",
          "--","--output="+str(FRAMES),"--bot-script="+str(ROOT/"game/tests/playthrough_bot.gd")]
    startup=subprocess.STARTUPINFO()
    startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow=subprocess.SW_HIDE
    process=subprocess.Popen(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output,_=process.communicate(timeout=150)
    except subprocess.TimeoutExpired:
        process.kill(); output,_=process.communicate(timeout=5)
        raise RuntimeError("Native README capture timed out; its window was closed")
    log=output.decode("utf8",errors="replace")
    (FRAMES/"capture.log").write_text(log,"utf8")
    if process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
        raise RuntimeError(log)
    report=json.loads((FRAMES/"capture.json").read_text("utf8"))
    report["artifact_sha256"]=hashlib.sha256(artifact.read_bytes()).hexdigest()
    images=[Image.open(frame["file"]).convert("RGB").resize((768,432),Image.Resampling.LANCZOS) for frame in report["frames"]]
    encode_gif(images,MEDIA/"gameplay.gif",200)
    selected=max(report["frames"],key=lambda f:f["enemies"]*3+f["effects"] if f["tick"]>90 else -1)
    Image.open(selected["file"]).convert("RGB").save(MEDIA/"gameplay.webp",quality=94,method=6)
    report["selected_frame"]=selected["tick"]
    for frame in report["frames"]:
        frame["file"]=Path(frame["file"]).name
    report["gif_sha256"]=hashlib.sha256((MEDIA/"gameplay.gif").read_bytes()).hexdigest()
    report["screenshot_sha256"]=hashlib.sha256((MEDIA/"gameplay.webp").read_bytes()).hexdigest()
    (MEDIA/"gameplay-capture.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    print(json.dumps({"frames":len(images),"shots":report["stats"]["shots"],"artifact_sha256":report["artifact_sha256"],"gif_bytes":(MEDIA/"gameplay.gif").stat().st_size}))

if __name__=="__main__":main()
