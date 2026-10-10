"""Edit native gameplay and animated paper-spirit key art into a 45-second trailer."""
from pathlib import Path
import json
import math
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from create_logo_candidates import ROOT, font, text_center
from create_store_artwork import KIT, SOURCE, INK, PAPER, RED, GOLD, JADE, hero, background, shade, brand

FFMPEG, FFPROBE = shutil.which("ffmpeg"), shutil.which("ffprobe")
WORK = ROOT / ".local-tools/store-trailer-edit"
SIZE, FPS = (1920, 1080), 30
CAPTIONS = ["挂余烬，点亮第一笔旧账", "让红绳，连起整场战斗", "射线 × 散射 × 爆裂", "同一局里，写出自己的打法", "十一重旧账，等你推门"]


def probe(path):
    result = subprocess.run([FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
                            capture_output=True, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    return json.loads(result.stdout)


def execute(args, logfile):
    with logfile.open("wb") as log:
        result = subprocess.run([FFMPEG, "-y", "-hide_banner", "-loglevel", "warning"] + args, stdout=log,
                                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError(logfile.read_text("utf-8", errors="replace")[-8000:])


def smooth(value):
    value = min(1.0, max(0.0, value))
    return 1.0 - (1.0 - value) ** 3


def offset_layer(canvas, layer, opacity, dx=0, dy=0):
    if opacity <= 0: return
    if opacity < 1:
        layer = layer.copy()
        layer.putalpha(layer.getchannel("A").point(lambda a: round(a * opacity)))
    canvas.alpha_composite(layer, (round(dx), round(dy)))


def typography(kind):
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    brand(d, 135, 214 if kind == "intro" else 175, 273, 43, 530 if kind == "intro" else 491)
    d.text((148, 692 if kind == "intro" else 637), "一愿未还，百债成灰。", font=font("NotoSansSC.ttf", 44), fill=PAPER, anchor="lt")
    if kind == "intro":
        d.text((150, 826), "PAPER   /   FIRE   /   DEBT", font=font("IncenseRounded-Bold.ttf", 24), fill=JADE, anchor="lt")
    else:
        d.text((148, 743), "现在，点灯入旧城", font=font("NotoSansSC.ttf", 32), fill="#D3C7AB", anchor="lt")
        for i, text in enumerate(["WINDOWS", "ANDROID"]):
            x = 148 + i * 304
            d.rounded_rectangle((x, 835, x+276, 915), radius=40, fill=(23, 36, 33, 238), outline=JADE if i else GOLD, width=2)
            text_center(d, x+138, 860, text, font("IncenseRounded-Bold.ttf", 28), PAPER)
        d.text((152, 967), "v0.2.0 ALPHA   ·   离线单人", font=font("NotoSansSC.ttf", 23), fill="#C7BA9C", anchor="lt")
    return layer


def animate_card(kind, duration):
    path = WORK / (kind + ".mp4")
    scene = "01-lantern-background.png" if kind == "intro" else "05-celestial-background.png"
    bg = background(SOURCE / scene, (2036, 1145))
    actor = hero()
    height = 910
    actor = actor.resize((round(actor.width*height/actor.height), height), Image.Resampling.LANCZOS)
    lettering = typography(kind)
    shadow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.ellipse((1250, 942, 1790, 1032),fill=(0,8,6,160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(25))
    rng = np.random.default_rng(7007 if kind == "intro" else 11011)
    motes = [(float(rng.uniform(0,1920)),float(rng.uniform(0,1080)),float(rng.uniform(1.5,4)),float(rng.uniform(20,55)),float(rng.uniform(0,math.tau))) for _ in range(44)]
    frames = round(duration*FPS)
    cmd = [FFMPEG,"-y","-hide_banner","-loglevel","warning","-f","rawvideo","-pix_fmt","rgb24","-s","1920x1080","-r",str(FPS),"-i","pipe:0",
           "-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-frames:v",str(frames),"-t",str(duration),
           "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-movflags","+faststart",str(path)]
    with (WORK/(kind+".log")).open("wb") as log:
        process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            for frame in range(frames):
                t = frame/FPS
                x = round(55+18*t/duration)
                y = round(32-12*t/duration)
                im = bg.crop((x,y,x+1920,y+1080))
                shade(im,.79)
                im.alpha_composite(shadow)
                entering = smooth((t-.05)/.7)
                im.alpha_composite(actor,(round(1477-actor.width/2+28*(1-entering)),round(105+2.4*math.sin(t*1.25))))
                offset_layer(im,lettering,smooth((t-.14)/.62),dy=24*(1-smooth((t-.14)/.62)))
                particles = Image.new("RGBA",SIZE,(0,0,0,0))
                pd = ImageDraw.Draw(particles)
                for px,py,radius,speed,phase in motes:
                    mx = px+9*math.sin(t*.7+phase)
                    my = (py-speed*t)%1080
                    alpha = round((95+50*math.sin(t*1.1+phase))*entering)
                    pd.ellipse((mx-radius,my-radius,mx+radius,my+radius),fill=(235,157,78,alpha))
                im.alpha_composite(particles)
                if kind == "intro" and t<.25:
                    im.alpha_composite(Image.new("RGBA",SIZE,(23,30,32,round(255*(1-t/.25)))))
                if kind == "outro" and t>duration-.45:
                    im.alpha_composite(Image.new("RGBA",SIZE,(23,30,32,round(255*(t-duration+.45)/.45))))
                if frame==round(min(2.3,duration-.6)*FPS): im.convert("RGB").save(KIT/"previews"/("trailer-"+kind+".jpg"),quality=93)
                process.stdin.write(im.convert("RGB").tobytes())
            process.stdin.close()
            result=process.wait(timeout=120)
        except Exception:
            process.kill();process.wait(timeout=10)
            raise
    if result: raise RuntimeError((WORK/(kind+".log")).read_text("utf-8",errors="replace"))
    print("Animated trailer card: "+kind,flush=True)
    return path


def caption_image(index):
    layer=Image.new("RGBA",SIZE,(0,0,0,0))
    d=ImageDraw.Draw(layer)
    text=CAPTIONS[index]
    face=font("NotoSansSC.ttf",34)
    bounds=d.textbbox((0,0),text,font=face)
    width=bounds[2]-bounds[0]+88
    x=(1920-width)/2
    d.rounded_rectangle((x,960,x+width,1045),radius=42,fill=(18,28,26,230),outline=(157,214,191,130),width=1)
    text_center(d,960,984,text,face,PAPER)
    path=WORK/f"caption-{index}.png"
    layer.save(path)
    return path


def gameplay_clip(index, native):
    path=WORK/f"game-{index}.mp4"
    overlay=caption_image(index)
    start=index*8+.45
    execute(["-ss",str(start),"-i",str(native),"-loop","1","-framerate","30","-i",str(overlay),
        "-filter_complex","[0:v]setpts=PTS-STARTPTS,format=yuv420p[v];[1:v]format=rgba,fade=t=in:st=0.08:d=0.35:alpha=1[c];[v][c]overlay=0:0:shortest=1:format=auto,format=yuv420p[out]",
        "-map","[out]","-map","0:a:0","-t","7.2","-r","30","-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-ar","48000","-movflags","+faststart",str(path)],WORK/f"game-{index}.log")
    print("Edited native trailer shot: "+str(index+1),flush=True)
    return path


def assemble(clips):
    output=KIT/"videos/IncenseDebt-trailer-45s.mp4"
    args=[]
    for path in clips:args.extend(["-i",str(path)])
    args.extend(["-stream_loop","-1","-i",str(ROOT/"game/assets/audio/paper_lane_loop.ogg")])
    filters=[]
    for i in range(7):filters.append(f"[{i}:v]settb=AVTB,setpts=PTS-STARTPTS,format=yuv420p[v{i}]")
    previous="v0"
    for i,offset in enumerate([3.3,10.2,17.1,24.0,30.9,37.8],start=1):
        name=f"xf{i}"
        filters.append(f"[{previous}][v{i}]xfade=transition=fade:duration=0.3:offset={offset}[{name}]")
        previous=name
    for i in range(7):filters.append(f"[{i}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts=PTS-STARTPTS[a{i}]")
    audio_previous="a0"
    for i in range(1,7):
        name=f"af{i}"
        filters.append(f"[{audio_previous}][a{i}]acrossfade=d=0.3:c1=tri:c2=tri[{name}]")
        audio_previous=name
    filters.append("[7:a]atrim=duration=45,asetpts=PTS-STARTPTS,aresample=48000,volume='if(between(t,3.3,37.8),0.30,0.75)':eval=frame,afade=t=in:d=0.35,afade=t=out:st=43.2:d=1.8[bed]")
    filters.append(f"[{audio_previous}][bed]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.92[mix]")
    filterfile=WORK/"edit-filter.txt"
    filterfile.write_text(";\n".join(filters),"utf-8")
    args.extend(["-filter_complex_script",str(filterfile),"-map",f"[{previous}]","-map","[mix]","-t","45","-frames:v","1350","-r","30",
                 "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-color_primaries","bt709","-color_trc","bt709","-colorspace","bt709",
                 "-c:a","aac","-b:a","192k","-ar","48000","-movflags","+faststart",str(output)])
    execute(args,WORK/"assemble.log")
    info=probe(output)
    assert abs(float(info["format"]["duration"])-45)<=.04
    assert next(s for s in info["streams"] if s["codec_type"]=="video")["nb_frames"]=="1350"
    report=dict(duration=45,dimensions=[1920,1080],fps=30,clips=[p.relative_to(ROOT).as_posix() for p in clips],
                native_source="sources/native-showcase-40s.mp4" if (KIT/"sources/native-showcase-40s.mp4").exists() else "videos/native-showcase-40s.mp4",cut_offsets=[3.3,10.2,17.1,24.0,30.9,37.8],transition_seconds=.3,
                source_bgm="game/assets/audio/paper_lane_loop.ogg",native_audio="Original native BGM and attack/hit SFX retained",narration=False,
                sources="Actual embedded gameplay; original paper-spirit RGB cutout; Sub2 scene art; existing game fonts",media_probe=info)
    (KIT/"videos/trailer-edit.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf-8")
    print(json.dumps({"trailer":str(output),"duration":info["format"]["duration"],"bytes":output.stat().st_size}),flush=True)
    return output


def previews(video):
    times=[2.5,6.5,13.5,20.8,27.5,34.5,40.8,43.8]
    board=Image.new("RGB",(1920,1160),INK)
    d=ImageDraw.Draw(board)
    d.text((36,24),"香火债 · 45 秒宣传片关键帧",font=font("NotoSansSC.ttf",30),fill=PAPER,anchor="lt")
    for i,t in enumerate(times):
        path=WORK/f"review-{i}.png"
        execute(["-ss",str(t),"-i",str(video),"-frames:v","1",str(path)],WORK/f"review-{i}.log")
        with Image.open(path) as im:
            shot=im.convert("RGB").resize((450,253),Image.Resampling.LANCZOS)
        x,y=36+(i%4)*474,90+(i//4)*342
        board.paste(shot,(x,y))
        d.text((x,y+266),f"{t:04.1f}s",font=font("IncenseRounded-Bold.ttf",23),fill=JADE,anchor="lt")
    board=board.crop((0,0,1920,790))
    board.save(KIT/"previews/trailer-contact-sheet.jpg",quality=94)


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    (KIT/"videos").mkdir(exist_ok=True)
    native=KIT/"videos/native-showcase-40s.mp4"
    if not native.is_file():native=KIT/"sources/native-showcase-40s.mp4"
    assert native.is_file(),"Native showcase capture is required"
    intro=animate_card("intro",3.6)
    shots=[gameplay_clip(i,native) for i in range(5)]
    outro=animate_card("outro",7.2)
    output=assemble([intro]+shots+[outro])
    previews(output)


if __name__=="__main__":main()
