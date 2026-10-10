"""Render native mobile QA fixtures; every hidden native process is closed afterwards."""
from pathlib import Path
import argparse, json, subprocess
from PIL import Image, ImageStat
ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / '.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
REPORT = ROOT / 'docs/incense-debt/reports/action-mobile-2026-10-09'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--fixture')
    args=parser.parse_args()
    matrix=[]
    startup=subprocess.STARTUPINFO(); startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=subprocess.SW_HIDE
    for name, resolution in [('phone-16x9','1280x720'),('phone-20x9','2400x1080'),('tablet-4x3','1024x768'),('phone-density-320','1280x720')]:
        if args.fixture and args.fixture != name: continue
        folder=REPORT/name; folder.mkdir(parents=True,exist_ok=True)
        command=[str(ENGINE),'--path',str(ROOT/'game'),'--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--resolution',resolution,'--position','-16000,-16000','--script',str(ROOT/'tools/runtime/verify_mobile_revision.gd'),'--','--qa-capture','--mobile-ui','--touch-preview','--qa-output='+str(folder/'fixture-saves'),'--audit-output='+str(folder)]
        if name == 'phone-density-320': command.append('--audit-dpi=320')
        try:
            process=subprocess.run(command,cwd=ROOT/'game',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW,timeout=65)
        except subprocess.TimeoutExpired as error:
            (folder/'native.log').write_bytes(error.stdout or b'')
            raise RuntimeError(name+' timed out; native process closed') from error
        log=process.stdout.decode('utf8',errors='replace'); (folder/'native.log').write_text(log,'utf8')
        if process.returncode or 'SCRIPT ERROR' in log or 'ERROR:' in log:
            raise RuntimeError(name+' failed:\n'+log[-6500:])
        images=[]
        for png in sorted(folder.glob('*.png')):
            with Image.open(png) as im:
                variance=sum(ImageStat.Stat(im.convert('RGB')).var)
                if variance<10: raise RuntimeError('Blank native frame: '+str(png))
                images.append(dict(path=png.relative_to(ROOT).as_posix(),size=list(im.size)))
        report=json.loads((folder/'verification.json').read_text('utf8'))
        matrix.append(dict(fixture=name,resolution=resolution,checks=len(report['checks']),passed=report['passed'],images=images))
        print(name+': '+str(len(report['checks']))+' checks passed; '+str(len(images))+' native frames',flush=True)
    (REPORT/'mobile-matrix.json').write_text(json.dumps(dict(scope='Native rendering and synthetic touch; no virtualization or physical handset claim',fixtures=matrix),indent=2)+'\n','utf8')

if __name__=='__main__': main()
