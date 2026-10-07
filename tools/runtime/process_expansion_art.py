"""Crop the reviewed Sub2 boards and precompute textured FX, scenery and pose strips."""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates
from compile_paper_animation import deform
from process_assets import split_atlas

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "game/assets"

def normalized(image, size):
    image = image.convert("RGBA")
    bbox = image.getbbox()
    if bbox is None: raise ValueError("Empty subject")
    content = image.crop(bbox)
    content.thumbnail((int(size*.84), int(size*.78)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size,size))
    canvas.alpha_composite(content, ((size-content.width)//2, int(size*.84)-content.height))
    return canvas

def pose(source, state, frame, count, style, index):
    image = deform(source, state, frame, count)
    n = image.width
    phase = frame / max(1,count-1)
    if state in ["move", "attack_a", "attack_b", "attack_c", "attack", "tell"]:
        # Warp one complete premultiplied silhouette: each limb exists once.
        # Smooth masks articulate limbs/head while retaining the original paper art.
        y,x = np.mgrid[:n,:n].astype(float)
        cycle = frame/count*math.tau
        impulse = math.sin(phase*math.pi) if state != "move" else math.sin(cycle)
        side = np.clip((np.abs(x-n*.5)-n*.13)/(n*.17),0,1)
        upper = np.exp(-((y-n*.40)/(n*.20))**2)
        foot = np.clip((y-n*.63)/(n*.20),0,1)
        hand = side*upper
        sign = np.sign(x-n*.5)
        amplitude = n*(.038+index%4*.006)
        dx = sign*amplitude*impulse*hand
        dy = -abs(impulse)*n*.04*hand
        if state == "move":
            dy += sign*math.sin(cycle)*n*.035*foot
            if style in ["serpent","sine"]:
                dx += np.sin(y/n*math.tau+cycle)*n*.032
            if style in ["orbit","strafe","retreat","procession"]:
                dx += math.sin(cycle)*n*.015*np.clip((n*.84-y)/(n*.70),0,1)
        elif state == "attack_b":
            dx += np.sin(y/n*math.tau)*n*.025*impulse
        elif state == "attack_c":
            dy += n*.035*impulse*np.clip((n*.84-y)/(n*.65),0,1)
        rgba=np.asarray(image,dtype=float)/255
        rgba[:,:,:3] *= rgba[:,:,3:4]
        warped=np.stack([map_coordinates(rgba[:,:,c],[y-dy,x-dx],order=1,mode="constant",cval=0) for c in range(4)],axis=2)
        warped[:,:,:3] /= np.maximum(warped[:,:,3:4],1e-9)
        warped[warped[:,:,3]<1/255]=0
        image=Image.fromarray(np.clip(warped*255,0,255).astype(np.uint8))
        if style in ["hop","pounce","bounce"] and state == "move":
            shifted = Image.new("RGBA",(n,n))
            shifted.alpha_composite(image,(0,-round(abs(impulse)*n*.045)))
            image = shifted
    return image

def main():
    manifest = json.loads((ROOT / "docs/incense-debt/assets/expansion-production.json").read_text("utf8"))
    catalog = json.loads((ROOT / "game/data/catalog.json").read_text("utf8"))
    definitions = {r["id"]:r for table in ["bosses","enemies"] for r in catalog[table]}
    records=[]
    animations=[]
    rig_path=ASSETS/"weapon-rig.json"
    rig=json.loads(rig_path.read_text("utf8"))
    report_path=ROOT/"docs/incense-debt/assets/expansion-processed.json"
    cached=json.loads(report_path.read_text("utf8")) if report_path.is_file() else {}
    def checkpoint():
        report={"records":records,"animations":animations,"generated_jobs":len({r['source'] for r in records}),"required_jobs":len(manifest['jobs']),
            "status":"processed" if len({r['source'] for r in records})==len(manifest['jobs']) else "partial",
            "animation":"precomputed paper-puppet poses derived from generated art; articulated limbs and motion profiles, not independent AI frames"}
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    for job in manifest["jobs"]:
        path = ROOT / job["output"]
        if not path.is_file(): continue
        source_hash=hashlib.sha256(path.read_bytes()).hexdigest()
        signature=hashlib.sha256(json.dumps(job["layout"],sort_keys=True).encode("utf8")).hexdigest()
        previous=[r for r in cached.get("records",[]) if r["source"]==job["output"] and r["source_sha256"]==source_hash
                  and (job["layout"]["kind"]!="rooms" or r.get("processing_signature")==signature)]
        old_animations=[r for r in cached.get("animations",[]) if r["id"] in job["layout"]["ids"]]
        if len(previous)==len(job["layout"]["ids"]) and all((ROOT/r["path"]).is_file() and (not r.get("sha256") or hashlib.sha256((ROOT/r["path"]).read_bytes()).hexdigest()==r["sha256"]) for r in previous) and all((ROOT/a["path"]).is_file() and hashlib.sha256((ROOT/a["path"]).read_bytes()).hexdigest()==a["sha256"] for a in old_animations):
            for r in previous:r.setdefault("sha256",hashlib.sha256((ROOT/r["path"]).read_bytes()).hexdigest())
            records.extend(previous);animations.extend(old_animations);checkpoint();continue
        print("Processing " + job["name"],flush=True)
        source = Image.open(path).convert("RGBA")
        layout = job["layout"]
        cols,rows=layout["columns"],layout["rows"]
        kind=layout["kind"]
        try:
            cutouts=split_atlas(path,cols,rows,set(range(len(layout["ids"]))))[1] if kind in ["bosses","enemies","weapons","obstacles"] else None
        except ValueError as error:
            print("Source requires regeneration: "+str(error),flush=True)
            continue
        for i,identity in enumerate(layout["ids"]):
            crop=source.crop((round(i%cols*source.width/cols),round(i//cols*source.height/rows),round((i%cols+1)*source.width/cols),round((i//cols+1)*source.height/rows)))
            if "rects" in layout: crop=source.crop(tuple(layout["rects"][i]))
            if cutouts is not None: crop=cutouts[i][0]
            if kind in ["rooms","story"]:
                image=crop.resize((1280,720),Image.Resampling.LANCZOS)
                folder="environment/expansion" if kind=="rooms" else "story/expansion"
            elif kind=="fx":
                image=crop
                folder="fx/expansion"
            else:
                image=normalized(crop,256 if kind=="bosses" else 128)
                folder=kind
            destination=ASSETS/folder/(identity+".png")
            destination.parent.mkdir(parents=True,exist_ok=True)
            image.save(destination)
            records.append({"id":identity,"kind":kind,"source":job["output"],"source_sha256":source_hash,"path":destination.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(destination.read_bytes()).hexdigest(),"processing_signature":signature})
            if kind=="weapons":
                held=image.copy()
                held_path=ASSETS/"held-weapons"/(identity+".png")
                held.save(held_path)
                aimed=identity not in ["w18","w19","w20","w22","w27","w32"]
                grips={"w17":[.35,.57],"w21":[.45,.67],"w23":[.49,.72],"w24":[.52,.65],"w25":[.39,.61],"w28":[.50,.67],"w29":[.47,.70],"w30":[.46,.67],"w31":[.40,.64]}
                rig["weapons"][identity]={"texture":"res://assets/held-weapons/"+identity+".png","grip":grips.get(identity,[.50,.67]),"size":42 if aimed else 35,"aimed":aimed,"mirror_outward":False,
                    "source":job["output"],"method":"held form cropped from the same generated implement; paper identity unchanged"}
            if kind in ["bosses","enemies"]:
                states={"idle":6,"move":8,"tell":5,"attack":6,"hurt":2,"death":6} if kind=="enemies" else {"idle":6,"move":8,"attack_a":8,"attack_b":8,"attack_c":8,"phase":6,"hurt":2,"death":8}
                target=ASSETS/("boss-animation" if kind=="bosses" else "enemy-animation")/identity
                target.mkdir(parents=True,exist_ok=True)
                for state,count in states.items():
                    strip=Image.new("RGBA",(image.width*count,image.height))
                    for frame in range(count):
                        rendered=pose(image,state,frame,count,definitions[identity].get("movement",""),i)
                        strip.alpha_composite(rendered,(image.width*frame,0))
                    strip_path=target/(state+".png")
                    strip.save(strip_path)
                    animations.append({"id":identity,"state":state,"frames":count,"frame_size":image.width,
                        "path":strip_path.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(strip_path.read_bytes()).hexdigest()})
            if kind=="fx":
                size=(256,96) if identity.startswith("beam_") else (192,192)
                base=image.copy()
                bbox=base.getbbox()
                if bbox is None: raise ValueError(identity+" has no visible texture")
                base=base.crop(bbox)
                base.thumbnail(size,Image.Resampling.LANCZOS)
                target=ASSETS/"fx/expansion/animation"
                target.mkdir(parents=True,exist_ok=True)
                count=12
                strip=Image.new("RGBA",(size[0]*count,size[1]))
                for frame in range(count):
                    t=frame/(count-1)
                    scale=.35+t*.65 if identity.startswith("blast_") or identity=="shockwave" else .88+math.sin(frame/count*math.tau)*.12
                    sprite=base.resize((max(1,int(base.width*scale)),max(1,int(base.height*scale))),Image.Resampling.LANCZOS)
                    alpha=np.asarray(sprite.getchannel("A")).astype(float)
                    if identity.startswith("blast_") or identity=="shockwave": alpha *= math.sin(t*math.pi)**.55
                    sprite.putalpha(Image.fromarray(np.clip(alpha,0,255).astype(np.uint8)))
                    strip.alpha_composite(sprite,(size[0]*frame+(size[0]-sprite.width)//2,(size[1]-sprite.height)//2))
                strip.save(target/(identity+".png"))
            if kind=="obstacles" and identity in ["bamboo_wall","stone_wall","rope_wall"]:
                folder=ASSETS/"obstacles/connected"/identity
                folder.mkdir(parents=True,exist_ok=True)
                tile=image.resize((80,80),Image.Resampling.LANCZOS)
                joint=tile.crop((28,38,52,59)).resize((36,20),Image.Resampling.LANCZOS)
                for mask in range(16):
                    canvas=Image.new("RGBA",(80,80))
                    for bit,angle,point in [(0,90,(30,0)),(1,0,(44,38)),(2,90,(30,44)),(3,0,(0,38))]:
                        if mask&(1<<bit): canvas.alpha_composite(joint.rotate(angle,expand=True),point)
                    canvas.alpha_composite(tile)
                    canvas.save(folder/(str(mask)+".png"))
        checkpoint()
    # Existing five bosses also need locomotion when encountered in random pools.
    for i in range(1,6):
        identity=f"b{i:02}"
        previous=[a for a in cached.get("animations",[]) if a["id"]==identity and a["state"]=="move"]
        if previous and all((ROOT/a["path"]).is_file() and hashlib.sha256((ROOT/a["path"]).read_bytes()).hexdigest()==a["sha256"] for a in previous):
            animations.extend(previous);continue
        image=Image.open(ASSETS/"bosses"/(identity+".png")).convert("RGBA")
        strip=Image.new("RGBA",(image.width*8,image.height))
        for frame in range(8): strip.alpha_composite(pose(image,"move",frame,8,"orbit",i),(image.width*frame,0))
        strip_path=ASSETS/"boss-animation"/identity/"move.png"
        strip.save(strip_path)
        animations.append({"id":identity,"state":"move","frames":8,"frame_size":image.width,
            "path":strip_path.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(strip_path.read_bytes()).hexdigest()})
    report={"records":records,"animations":animations,"generated_jobs":len({r['source'] for r in records}),"required_jobs":len(manifest['jobs']),
        "status":"processed" if len({r['source'] for r in records})==len(manifest['jobs']) else "partial",
        "animation":"precomputed paper-puppet poses derived from generated art; articulated limbs and motion profiles, not independent AI frames"}
    (ROOT/"docs/incense-debt/assets/expansion-processed.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    rig_path.write_text(json.dumps(rig,ensure_ascii=False,indent=2)+"\n","utf8")
    print(json.dumps({"status":report['status'],"records":len(records),"jobs":report['generated_jobs']},ensure_ascii=False))

if __name__=="__main__":main()
