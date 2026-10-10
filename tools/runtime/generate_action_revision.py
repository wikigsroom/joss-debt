"""Sequential bounded jobs through the user's own skill; no alternate provider."""
from pathlib import Path
import argparse, hashlib, json, subprocess, sys
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/action-revision"
CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")

def main():
    p = argparse.ArgumentParser(); p.add_argument("--only", nargs="*"); args=p.parse_args()
    records=[]; jobs=json.loads((OUT / "jobs.json").read_text("utf8"))
    if args.only: jobs=[j for j in jobs if j['id'] in args.only]
    for job in jobs:
        target=ROOT/job['output']
        if not target.is_file():
            print("Drawing independent poses: " + job['id'], flush=True)
            command=[sys.executable,"-X","utf8",str(CLI),"edit","--image",str(ROOT/job['reference']),
                "--prompt-file",str(ROOT/job['prompt']),"--model","gpt-image-2.5","--quality","high",
                "--size","1536x1536","--background","transparent","--out",str(target)]
            result=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=600,creationflags=subprocess.CREATE_NO_WINDOW)
            (OUT/(job['id']+'.log')).write_bytes(result.stdout+result.stderr)
            if result.returncode:
                print("Same-provider request failed: "+job['id']+"; local diagnostic saved.",flush=True)
                return 1
        with Image.open(target) as im:
            im.verify()
            record=dict(id=job['id'],sha256=hashlib.sha256(target.read_bytes()).hexdigest(),size=list(im.size))
        records.append(record)
        (OUT/'generation-progress.json').write_text(json.dumps(dict(provider='sub2-image-gen',model='gpt-image-2.5',verified=records),indent=2)+'\n','utf8')
        print("Verified source: "+job['id'],flush=True)
    return 0
if __name__=='__main__': raise SystemExit(main())
