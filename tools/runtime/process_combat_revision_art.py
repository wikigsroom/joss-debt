"""Extract 48 actually generated keyframes, retaining their relative charge/blast sizes."""
from pathlib import Path
import hashlib
import json
import statistics
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'game/assets/fx/combat-revision'
NAMES={'beams':['beam_amber','beam_ink','beam_thread','beam_prism'],
       'areas':['blast_flame','blast_ink','blast_lotus','shockwave']}

def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    records=[]
    for kind,names in NAMES.items():
        path=ROOT/f'output/imagegen/incense-debt/combat-revision/{kind}.png'
        source=Image.open(path).convert('RGBA')
        if source.size != (1536,1024): raise ValueError('Unexpected source grid')
        for row,name in enumerate(names):
            cells=[]
            centers=[]
            for column in range(6):
                cell=source.crop((column*256,row*256,(column+1)*256,(row+1)*256))
                pixels=np.array(cell)
                pixels[pixels[:,:,3]<8]=0
                cell=Image.fromarray(pixels)
                bbox=cell.getbbox()
                if bbox is None: raise ValueError('Missing generated keyframe')
                cells.append(cell)
                centers.append(((bbox[0]+bbox[2])/2,(bbox[1]+bbox[3])/2))
            # One scale for the entire row: a small charge stays small and the
            # expanding shock is not independently enlarged to match it.
            scale=min(1.0,236/max(max(c.getbbox()[2]-c.getbbox()[0],c.getbbox()[3]-c.getbbox()[1]) for c in cells))
            strip=Image.new('RGBA',(1536,256))
            frame_hashes=[]
            for column,(cell,center) in enumerate(zip(cells,centers)):
                frame=Image.new('RGBA',(256,256))
                resized=cell.resize((round(256*scale),round(256*scale)),Image.Resampling.LANCZOS)
                frame.alpha_composite(resized,(round(128-center[0]*scale),round(128-center[1]*scale)))
                strip.alpha_composite(frame,(column*256,0))
                frame_hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
            destination=OUTPUT/(name+'.png')
            strip.save(destination)
            records.append(dict(id=name,path=destination.relative_to(ROOT).as_posix(),source=path.relative_to(ROOT).as_posix(),
                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
                frames=6,frame_size=[256,256],frame_hashes=frame_hashes,method='six distinct AI-generated keyframes; shared row scale, normalized anchors'))
    data=dict(provider='sub2-image-gen/gpt-image-2.5',frames=48,records=records)
    (OUTPUT/'manifest.json').write_text(json.dumps(data,indent=2)+'\n','utf8')
    contact=Image.new('RGBA',(1536,8*256),'#192524')
    for index,record in enumerate(records): contact.alpha_composite(Image.open(ROOT/record['path']),(0,index*256))
    review=ROOT/'docs/incense-debt/reports/runtime/combat-revision/fx-keyframes.png'
    review.parent.mkdir(parents=True,exist_ok=True)
    contact.convert('RGB').save(review)
    print('8 sprite strips, 48 distinct source-bound generated keyframes.')

if __name__=='__main__':main()
