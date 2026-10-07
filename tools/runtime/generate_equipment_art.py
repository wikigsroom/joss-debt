"""Run bounded, native Sub2 image jobs without reading gateway credentials."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
from PIL import Image
from prepare_equipment_content import ROOT, OUT

SKILL = Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')

def generate(job):
    target = Path(job['output'])
    if not target.exists():
        command = [sys.executable,'-X','utf8',str(SKILL),'generate','--prompt-file',job['prompt'],
            '--model','gpt-image-2.5','--quality','high','--size','1536x1024',
            '--background','transparent','--out',str(target)]
        result = subprocess.run(command,cwd=ROOT,capture_output=True,timeout=600,
            creationflags=subprocess.CREATE_NO_WINDOW)
        (OUT/(job['id']+'.log')).write_bytes(result.stdout+result.stderr)
        if result.returncode: raise RuntimeError(f"{job['id']}: gateway failed; inspect its local log")
    with Image.open(target) as picture:
        picture.load()
        if min(picture.size) < 1024: raise RuntimeError(f"{job['id']}: unexpectedly small image {picture.size}")
        if job['kind'] == 'fx' and abs(picture.width / picture.height - 1.5) > .08:
            raise RuntimeError(f"{job['id']}: unexpected six-by-four sheet aspect {picture.size}")
        info = dict(id=job['id'],path=str(target.relative_to(ROOT)).replace('\\','/'),
            sha256=hashlib.sha256(target.read_bytes()).hexdigest(),dimensions=list(picture.size),mode=picture.mode)
    print('Generated / verified: '+job['id'],flush=True)
    return info

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only',nargs='*')
    args=parser.parse_args()
    jobs=json.loads((OUT/'jobs.json').read_text('utf8'))
    if args.only: jobs=[job for job in jobs if job['id'] in args.only]
    records=[];failures=[]
    with ThreadPoolExecutor(max_workers=3) as pool:
        tasks={pool.submit(generate,job):job['id'] for job in jobs}
        for future in as_completed(tasks):
            try: records.append(future.result())
            except Exception as error:
                failures.append(dict(id=tasks[future],error=str(error)))
                print('Failed: '+tasks[future]+': '+str(error),flush=True)
    report=dict(provider='sub2-image-gen',model='gpt-image-2.5',passed=not failures,
        records=sorted(records,key=lambda row:row['id']),failures=failures)
    (OUT/'generation-report.json').write_text(json.dumps(report,indent=2)+'\n','utf8')
    print(json.dumps({'verified':len(records),'failed':len(failures)}),flush=True)
    return int(bool(failures))

if __name__=='__main__':raise SystemExit(main())
