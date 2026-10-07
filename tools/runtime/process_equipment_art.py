"""Normalize 36 generated icons and 480 real keyframes; author enemy signatures."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
import numpy as np
from prepare_equipment_content import ROOT, OUT, ACTIVE, TRINKETS, MODS, FAMILIES

FX = ROOT/'game/assets/fx/equipment-polish'
REPORTS = ROOT/'docs/incense-debt/reports/runtime/equipment-polish'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n','utf8')

def clean_alpha(image):
    pixels=np.array(image.convert('RGBA'))
    # Generated soft glow has low-alpha, colored RGB far outside the silhouette.
    # Remove that spill, retaining a smooth edge rather than an opaque atlas cell.
    alpha=pixels[:,:,3].astype(float)
    pixels[:,:,3]=np.clip((alpha-12)*255/243,0,255).astype(np.uint8)
    pixels[pixels[:,:,3]<4]=0
    return Image.fromarray(pixels)

def cell(image,column,row,columns,rows):
    return image.crop((round(column*image.width/columns),round(row*image.height/rows),
        round((column+1)*image.width/columns),round((row+1)*image.height/rows)))

def main():
    FX.mkdir(parents=True,exist_ok=True);REPORTS.mkdir(parents=True,exist_ok=True)
    records=[];assets=[];icons=[]
    for kind,rows in [('active_items',ACTIVE),('trinkets',TRINKETS),('modifiers',MODS)]:
        source=OUT/(kind+'.png');image=Image.open(source).convert('RGBA')
        folder=ROOT/'game/assets'/('relics' if kind=='modifiers' else kind)
        folder.mkdir(parents=True,exist_ok=True)
        for i,row in enumerate(rows):
            icon=clean_alpha(cell(image,i%4,i//4,4,3));bounds=icon.getbbox()
            if bounds is None: raise RuntimeError('Empty generated icon: '+row[0])
            icon=icon.crop(bounds);icon.thumbnail((234,234),Image.Resampling.LANCZOS)
            canvas=Image.new('RGBA',(256,256));canvas.alpha_composite(icon,((256-icon.width)//2,(256-icon.height)//2))
            destination=folder/(row[0]+'.png');canvas.save(destination)
            records.append(dict(id=row[0],kind=kind,source=source.relative_to(ROOT).as_posix(),source_sha256=sha(source),
                file=destination.relative_to(ROOT).as_posix(),sha256=sha(destination),source_cell=[i%4,i//4],
                source_dimensions=list(image.size),size=[256,256],method='normalized from one generated grid cell, transparent centered anchor'))
            assets.append(dict(file='res://'+destination.relative_to(ROOT/'game').as_posix(),kind='texture',size=[256,256]))
            icons.append(canvas)
    presets=[]
    for family,_ in FAMILIES:
        for group,suffixes in [('beams',['beam_lance','beam_tether','beam_wave','beam_fork']),('areas',['blast','ring','vortex','field'])]:
            source=OUT/f'{family}-{group}.png';image=Image.open(source).convert('RGBA')
            for row,suffix in enumerate(suffixes):
                frames=[clean_alpha(cell(image,column,row,6,4)) for column in range(6)]
                bounds=[frame.getbbox() for frame in frames]
                if any(box is None for box in bounds): raise RuntimeError(f'Empty keyframe in {family}/{suffix}')
                # One shared row scale preserves anticipation/full-burst/decay ratios.
                scale=min(1.,236/max(max(box[2]-box[0],box[3]-box[1]) for box in bounds))
                strip=Image.new('RGBA',(1536,256));hashes=[]
                for column,(frame,box) in enumerate(zip(frames,bounds)):
                    frame=frame.resize((round(frame.width*scale),round(frame.height*scale)),Image.Resampling.LANCZOS)
                    center=((box[0]+box[2])*.5*scale,(box[1]+box[3])*.5*scale)
                    target=Image.new('RGBA',(256,256));target.alpha_composite(frame,(round(128-center[0]),round(128-center[1])))
                    hashes.append(hashlib.sha256(target.tobytes()).hexdigest());strip.alpha_composite(target,(column*256,0))
                if len(set(hashes)) != 6: raise RuntimeError(f'Repeated generated keyframes: {family}/{suffix}')
                id=family+'_'+suffix;destination=FX/(id+'.png');strip.save(destination)
                presets.append(dict(id=id,family=family,shape=suffix,frames=6,file='res://assets/fx/equipment-polish/'+id+'.png'))
                records.append(dict(id=id,kind='fx',file=destination.relative_to(ROOT).as_posix(),source=source.relative_to(ROOT).as_posix(),
                    sha256=sha(destination),source_sha256=sha(source),frames=6,frame_hashes=hashes,
                    method='six independent AI-generated keyframes; one shared row scale, centered anchors, low-alpha spill cleanup'))
                assets.append(dict(file='res://assets/fx/equipment-polish/'+id+'.png',kind='texture',size=[1536,256]))
    manifest=dict(provider='sub2-image-gen',model='gpt-image-2.5',generated_boards=23,icons=36,fx_strips=80,independent_keyframes=480,records=records)
    save_json(FX/'manifest.json',manifest);save_json(ROOT/'game/data/fx_presets.json',dict(version=1,presets=presets))
    catalog=json.loads((ROOT/'game/data/catalog.json').read_text('utf8'))
    biomes=json.loads((ROOT/'game/data/expansion.json').read_text('utf8'))['biomes']
    map_by_id={row['id']:row for row in biomes}
    family_by_ambient={'ember':'ember','water':'prism','coin':'brass','leaf':'lotus','rain':'ink','silk':'thread','wax':'ember',
        'storm':'storm','ash':'smoke','lotus':'lotus','snow_silk':'frost','dust':'brass','bamboo':'lotus','mirror':'prism',
        'seal':'thread','cinder':'ember','wind':'frost','mist':'smoke','judgment':'brass','star':'void'}
    shapes=['drop','diamond','needle','star','ring','petal','scroll','spiral','moon','shuriken','seed','dart','coin','fan','knot','capsule']
    palette={'ember':'#ffac65','ink':'#84bbed','thread':'#ff8495','prism':'#a6f0db','lotus':'#f6b3de','smoke':'#d6d9ee',
        'frost':'#b3e8ff','storm':'#d4a6ff','void':'#b998f6','brass':'#ffe29b'}
    profiles={};theme_index={}
    for table in ['enemies','bosses']:
        for index,row in enumerate(catalog[table]):
            theme=row.get('theme','legacy');theme_key=table+'/'+theme
            role=theme_index.get(theme_key,0);theme_index[theme_key]=role+1
            ambient=map_by_id.get(theme,{}).get('ambient','ember' if index%3==0 else ('ink' if index%3==1 else 'coin'))
            family=family_by_ambient.get(ambient,'ink')
            seed=int(hashlib.sha256(row['id'].encode()).hexdigest()[:8],16)
            scale=(.86 if table=='bosses' else .66)+(role%12)*.046+(index+1)*.000017
            profiles[row['id']]=dict(id=row['id'],table=table,theme=theme,family=family,color=palette[family],
                shape=shapes[(role+seed//97)%len(shapes)],radius_scale=round(scale,6),
                aspect=round(.72+(seed%19)*.048,3),spin=round((1 if seed%2 else -1)*(.35+(seed%13)*.17),3),
                ribs=3+seed%7,trail_layers=2+seed%3,orbit=seed%4,
                signature=f"{row['id']}/{family}/{seed:08x}")
    save_json(ROOT/'game/data/projectile_profiles.json',dict(version=1,profiles=profiles))
    save_json(REPORTS/'asset-production.json',dict(passed=True,**{key:manifest[key] for key in ['provider','model','generated_boards','icons','fx_strips','independent_keyframes']},
        enemy_projectile_profiles=len(profiles),source_bound_records=len(records),records=records))
    registry_path=ROOT/'game/data/runtime_assets.json';registry=json.loads(registry_path.read_text('utf8'))
    by_file={row['file']:row for row in registry['assets']}
    for row in assets: by_file[row['file']]=row
    registry['assets']=[by_file[key] for key in sorted(by_file)];save_json(registry_path,registry)
    contact=Image.new('RGBA',(6*108,6*108),'#182c30')
    for i,icon in enumerate(icons): contact.alpha_composite(icon.resize((100,100),Image.Resampling.LANCZOS),((i%6)*108+4,(i//6)*108+4))
    contact.convert('RGB').save(REPORTS/'equipment-icons.png')
    for family,_ in FAMILIES:
        contact=Image.new('RGBA',(6*128,8*128),'#182c30')
        for row,preset in enumerate([p for p in presets if p['family']==family]):
            strip=Image.open(ROOT/'game'/preset['file'].removeprefix('res://')).convert('RGBA')
            for column in range(6): contact.alpha_composite(strip.crop((column*256,0,(column+1)*256,256)).resize((128,128),Image.Resampling.LANCZOS),(column*128,row*128))
        contact.convert('RGB').save(REPORTS/(family+'-keyframes.png'))
    print(json.dumps({'icons':36,'fx_strips':80,'independent_keyframes':480,'enemy_profiles':len(profiles),'runtime_assets':len(registry['assets'])}))

if __name__=='__main__':main()
