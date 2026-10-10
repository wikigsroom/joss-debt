"""Extract the Sub2-drawn contact, hurt, muzzle and melee keyframes without warping."""
from pathlib import Path
import hashlib
import json
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]

def main():
    source = ROOT / 'output/imagegen/action-revision/impact-fx.png'
    sheet = Image.open(source).convert('RGBA')
    folder = ROOT / 'game/assets/fx/drawn-actions'
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    for row, name in enumerate(['impact','hurt','muzzle','melee']):
        strip = Image.new('RGBA',(1536,256))
        for column in range(6):
            frame = sheet.crop((round(column*sheet.width/6),round(row*sheet.height/4),round((column+1)*sheet.width/6),round((row+1)*sheet.height/4))).resize((256,256),Image.Resampling.LANCZOS)
            if name == 'muzzle': frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            strip.alpha_composite(frame,(column*256,0))
        target = folder / f'{name}.png'
        strip.save(target)
        records.append(dict(name=name,path='res://'+target.relative_to(ROOT/'game').as_posix(),frames=6,frame_size=256,fps=18,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    manifest = dict(source=source.relative_to(ROOT).as_posix(),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),model='gpt-image-2.5',method='independently drawn Sub2 keyframes, alpha preserved, no deformation',strips=records)
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n','utf8')
    print('Installed four drawn FX strips / 24 transparent keyframes.')

if __name__ == '__main__': main()
