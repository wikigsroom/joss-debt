"""Create portable README images from verified native captures and diagram data."""
from pathlib import Path
import hashlib
import json
import re
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageSequence

ROOT=Path(__file__).resolve().parents[2]
MEDIA=ROOT/"docs/media"
NATIVE=ROOT/"docs/incense-debt/reports/platforms/windows"
SOURCES={
    "main-menu":"keyboard/keyboard-main.png",
    "save-slots":"keyboard/keyboard-files.png",
    "characters":"keyboard/keyboard-characters.png",
    "character-details":"character-details.png",
    "pause":"modern-pause.png",
    "build-map":"expansion/map-final-build.png",
    "early-boss-map":"expansion/early-1-two-boss-chambers-map.png",
    "shop":"keyboard/keyboard-shop.png",
    "mixed-encounter":"expansion/mixed-m01.png",
    "ray":"expansion/weapon-w14.png",
    "boss":"expansion/early-1-boss-13.png",
    "boss-alternative":"expansion/early-1-boss-14.png",
    "themes":"expansion/twenty-themes-overview.png",
    "final-floor":"expansion/environment-m20-a.png",
    "equipment-inventory":"equipment-polish/equipment-inventory.png",
    "equipment-timeline":"equipment-polish/equipment-map-floor-06.png",
    "equipment-ground":"equipment-polish/equipment-ground-prompt.png",
    "equipment-five-beams":"equipment-polish/equipment-five-explosive-beams.png",
    "equipment-history":"equipment-polish/equipment-history.png",
    "equipment-touch":"equipment-polish/equipment-touch-hud.png",
}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def encode_gif(images,path,duration):
    """Use one palette and transparent deltas to retain actual motion compactly."""
    images=[im.convert("RGB") for im in images]
    sample=Image.new("RGB",(images[0].width,images[0].height*6))
    for i,index in enumerate(np.linspace(0,len(images)-1,6,dtype=int)):
        sample.paste(images[index],(0,i*images[0].height))
    palette=sample.quantize(colors=255,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    colors=palette.getpalette()[:768]
    colors[765:768]=colors[:3]
    palette.putpalette(colors)
    frames=[]; previous=None
    for image in images:
        indexed=image.quantize(palette=palette,dither=Image.Dither.NONE)
        pixels=np.asarray(indexed).copy()
        pixels[pixels==255]=0
        delta=pixels.copy()
        if previous is not None:delta[pixels==previous]=255
        frame=Image.fromarray(delta)
        frame.putpalette(colors)
        frame.info["transparency"]=255
        frames.append(frame); previous=pixels
    frames[0].save(path,save_all=True,append_images=frames[1:],duration=duration,loop=0,transparency=255,disposal=1,optimize=False)
    # Verify composition, rather than merely trusting encoder success.
    with Image.open(path) as output:
        decoded=[frame.convert("RGB") for frame in ImageSequence.Iterator(output)]
    if len(decoded)!=len(images):raise ValueError("GIF did not preserve the recorded frame count")
    for original,actual in zip(images,decoded):
        expected=original.quantize(palette=palette,dither=Image.Dither.NONE).convert("RGB")
        if not np.array_equal(np.asarray(expected),np.asarray(actual)):
            raise ValueError("GIF transparency changed a captured frame")

def font(size,weight=600):
    face=ImageFont.truetype(str(ROOT/"game/assets/fonts/NotoSansSC.ttf"),size)
    face.set_variation_by_axes([weight])
    return face

def diagram():
    image=Image.new("RGB",(2000,1460),"#152123")
    d=ImageDraw.Draw(image)
    white="#edf2e7"; muted="#a7b5af"; peach="#ee956f"; line="#526868"
    def center(value,x,y,size=27,color=white,weight=600):
        f=font(size,weight); box=d.textbbox((0,0),value,font=f)
        d.text((x-(box[2]-box[0])/2,y),value,font=f,fill=color)
    def node(x,y,w,h,cn,en,accent=False):
        d.rounded_rectangle((x,y,x+w,y+h),radius=26,fill=peach if accent else "#26383b",outline=peach if accent else line,width=2)
        center(cn,x+w/2,y+16,32,"#152123" if accent else white)
        center(en,x+w/2,y+60,23,"#253032" if accent else muted)
    center("香火债 · 菜单与游玩层级",1000,30,48)
    center("INCENSE DEBT · MENU AND PLAY FLOW",1000,96,25,muted)
    for y in [245,390]:d.line((1000,y,1000,y+40),fill=peach,width=4)
    node(780,145,440,100,"标题","Title / splash")
    node(780,290,440,100,"三份独立愿簿","Three independent save slots")
    node(780,435,440,100,"主菜单","Main menu",True)
    d.line((1000,535,1000,580),fill=peach,width=4)
    d.line((166,580,1834,580),fill=line,width=4)
    groups=[
        ("新局","New run",[("角色选择","Character"),("详情与器具","Details / loadout"),("替换确认","Replace confirmation"),("教学与入局","Tutorial / start")]),
        ("继续","Continue",[("恢复暂停页","Resume confirmation"),("返回房间","Return to combat")]),
        ("挑战","Challenge",[("每日规则","Daily rules"),("挑战选角","Character"),("确认与开始","Confirm / start")]),
        ("记录","Records",[("成就","Achievements"),("物品与怪物","Items / bestiary"),("结局与统计","Endings / stats"),("旧愿故事","Collected stories")]),
        ("还愿庭","Courtyard",[("局外成长","Meta progression"),("器具与债约","Gear / contracts"),("图鉴与训练","Archive / training"),("角色留名","Character progress")]),
        ("设置","Settings",[("声音与按键","Audio / controls"),("辅助与触控","Assist / touch"),("愿簿传递","Save transfer"),("致谢","Credits")]),
        ("离开","Quit",[("保存确认","Save confirmation"),("退出程序","Exit application")]),
    ]
    for i,(cn,en,children) in enumerate(groups):
        x=36+i*278; cx=x+130
        d.line((cx,580,cx,620),fill=line,width=4)
        node(x,620,260,108,cn,en)
        d.line((cx,728,cx,755),fill=line,width=4)
        d.rounded_rectangle((x,755,x+260,1088),radius=24,fill="#1d2d30")
        for j,(child_cn,child_en) in enumerate(children):
            center(child_cn,cx,778+j*74,25)
            center(child_en,cx,816+j*74,18,muted,500)
    d.rounded_rectangle((68,1144,1932,1328),radius=30,fill="#26383b",outline=line,width=2)
    center("房间 → 行路图 / 构筑 / 成长选择 / 商店 / 特殊房 / 暂停",1000,1162,34)
    center("Combat → map · build · rewards · shop · special rooms · pause",1000,1224,25,muted)
    center("清房后走入方向门 · F 主动 · E 换装 · Enter 确认 · Esc 返回 · 1—4 选择",1000,1352,29,peach)
    center("Walk through doors · F active · E swap · Confirm · Back · Number choices",1000,1400,21,muted)
    path=MEDIA/"menu-flow.png"; image.save(path,optimize=True)
    return {"path":path.relative_to(ROOT).as_posix(),"sha256":digest(path),"kind":"bilingual documentation diagram","source":"docs/incense-debt/22-menu-save-achievements.md"}

def main():
    MEDIA.mkdir(parents=True,exist_ok=True)
    build=json.loads((ROOT/"docs/incense-debt/reports/platforms/windows-build.json").read_text("utf8"))
    records=[]
    for name,relative in SOURCES.items():
        source=NATIVE/relative; target=MEDIA/(name+".webp")
        Image.open(source).convert("RGB").save(target,quality=92,method=6)
        records.append({"path":target.relative_to(ROOT).as_posix(),"source":source.relative_to(ROOT).as_posix(),"source_sha256":digest(source),"sha256":digest(target),"kind":"native Windows screenshot","artifact_sha256":build["sha256"]})
    for name,filename in [("combat-fx","expansion/revision-fx-motion.gif"),("boss-motion","expansion/dual-motion.gif"),("scenery","expansion/scenery-motion.gif"),
                          ("equipment-combination","equipment-polish/motion-combined.gif"),("equipment-storm","equipment-polish/fx-storm.gif")]:
        source=NATIVE/filename
        with Image.open(source) as im:
            frames=[frame.convert("RGB").resize((768,432),Image.Resampling.LANCZOS) for frame in ImageSequence.Iterator(im)]
            duration=im.info.get("duration",100)
        target=MEDIA/(name+".gif");encode_gif(frames,target,duration)
        records.append({"path":target.relative_to(ROOT).as_posix(),"source":source.relative_to(ROOT).as_posix(),"source_sha256":digest(source),"sha256":digest(target),"frames":len(frames),"kind":"native scripted combat demonstration","artifact_sha256":build["sha256"]})
    capture=ROOT/".local-tools/readme-capture/capture.json"
    if capture.exists():
        report=json.loads(capture.read_text("utf8"))
        images=[Image.open(Path(frame["file"])).convert("RGB").resize((768,432),Image.Resampling.LANCZOS) for frame in report["frames"]]
        encode_gif(images,MEDIA/"gameplay.gif",200)
        proof=json.loads((MEDIA/"gameplay-capture.json").read_text("utf8"))
        proof["gif_sha256"]=digest(MEDIA/"gameplay.gif")
        (MEDIA/"gameplay-capture.json").write_text(json.dumps(proof,ensure_ascii=False,indent=2)+"\n","utf8")
        records.append({"path":"docs/media/gameplay.gif","sha256":proof["gif_sha256"],"frames":len(images),"kind":"normal initial-stats native gameplay capture","artifact_sha256":proof["artifact_sha256"]})
        records.append({"path":"docs/media/gameplay.webp","sha256":digest(MEDIA/"gameplay.webp"),"kind":"normal gameplay screenshot","artifact_sha256":proof["artifact_sha256"]})
    records.append(diagram())
    (MEDIA/"manifest.json").write_text(json.dumps({"artifact_sha256":build["sha256"],"records":records,"processing":"Screenshot WEBP compression; global-palette GIFs with transparent frame deltas, frame-by-frame decoded composition checked; original viewport geometry preserved","originals":"Original captures are preserved locally; images directly linked by design documents remain versioned"},ensure_ascii=False,indent=2)+"\n","utf8")
    # Keep all existing Markdown media references usable without all QA frames.
    keep=set()
    for md in list((ROOT/"docs").rglob("*.md"))+list((ROOT/"build").glob("*.md")):
        for dest in re.findall(r'!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)',md.read_text("utf8")):
            if dest.startswith(("http:","https:","#")):continue
            path=(md.parent/dest.split("#",1)[0]).resolve()
            if path.is_file() and path.suffix.lower() in [".png",".gif",".webp",".svg"] and path.is_relative_to(ROOT/"docs/incense-debt/reports"):
                keep.add(path.relative_to(ROOT).as_posix())
    ignore=ROOT/".gitignore";text=ignore.read_text("utf8").split("# Documentation-linked original captures",1)[0].rstrip()
    ignore.write_text(text+"\n\n# Documentation-linked original captures\n"+"\n".join("!/"+p for p in sorted(keep))+"\n","utf8")
    print(json.dumps({"media_files":len(records),"readme_media_mib":round(sum((ROOT/r["path"]).stat().st_size for r in records)/1048576,2),"original_document_images":len(keep),"artifact_sha256":build["sha256"]}))

if __name__=="__main__":main()
