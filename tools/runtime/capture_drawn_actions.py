"""Native engine capture and visual review boards. No hand-built render substitute."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'docs/incense-debt/reports/action-mobile-2026-10-09'
ACTORS=['c_paper','c_bell','c_lantern','c_mask','c_umbrella','c_ink']
STATES=['idle','run','cast','dash','hurt','death']

def main():
    frames=ROOT/'.local-tools/native-action-frames'; frames.mkdir(exist_ok=True)
    startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=subprocess.SW_HIDE
    command=[str(ROOT/'.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'),'--path',str(ROOT/'game'),'--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--resolution','1280x720','--position','-16000,-16000','--script',str(ROOT/'tools/runtime/capture_drawn_actions.gd'),'--','--qa-capture','--qa-output='+str(frames/'saves'),'--action-output='+str(frames)]
    result=subprocess.run(command,cwd=ROOT/'game',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW,timeout=90)
    log=result.stdout.decode('utf8',errors='replace'); (REPORT/'native-actions.log').write_text(log,'utf8')
    if result.returncode or 'ERROR:' in log or 'SCRIPT ERROR' in log: raise RuntimeError(log[-6000:])
    animation=[]
    for column in range(6):
        board=Image.new('RGB',(6*192,6*192))
        for x,actor in enumerate(ACTORS):
            for y,state in enumerate(STATES):
                cell=Image.open(frames/f'{actor}-{state}-{column}.png').convert('RGB')
                board.paste(cell,(x*192,y*192))
        animation.append(board)
    animation[2].save(REPORT/'native-actions.png')
    animation[0].save(REPORT/'native-actions.gif',save_all=True,append_images=animation[1:],duration=150,loop=0)
    comparison=Image.new('RGB',(6*192*2,6*192))
    for x,actor in enumerate(ACTORS):
        for y,state in enumerate(STATES):
            for column in (2,5):
                comparison.paste(Image.open(frames/f'{actor}-{state}-{column}.png'),(x*384+(0 if column==2 else 192),y*192))
    comparison.save(REPORT/'native-action-endpoints.jpg',quality=92)
    print('216 native frames captured; contact board and actual-engine GIF written.')

if __name__=='__main__':main()
