"""Create an audit design sketch with the game's existing art and licensed fonts."""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/incense-debt/reports/mobile-audit-2026-10-09"
ASSETS = ROOT / "game/assets"
INK = (34, 46, 49)
TEXT = (234, 238, 229)
JADE = (156, 215, 193)
ORANGE = (238, 150, 112)
MUTED = (171, 185, 176)


def font(size, bold=False):
    return ImageFont.truetype(str(ASSETS / "fonts" / ("IncenseRounded-Bold.ttf" if bold else "IncenseRounded-Medium.ttf")), size)


def art(canvas, path, center, size):
    image = Image.open(ASSETS / path).convert("RGBA")
    image = ImageOps.contain(image, (size, size), Image.Resampling.LANCZOS)
    canvas.alpha_composite(image, (int(center[0] - image.width / 2), int(center[1] - image.height / 2)))


def circle(canvas, center, radius, fill, outline=JADE, width=3):
    d = ImageDraw.Draw(canvas)
    x, y = center
    d.ellipse((x-radius, y-radius, x+radius, y+radius), fill=fill, outline=outline, width=width)


def glyph(canvas, kind, center, color=TEXT, size=30):
    d = ImageDraw.Draw(canvas)
    x, y = center
    r = size / 2
    if kind == "pause":
        for offset in [-7, 7]: d.rounded_rectangle((x+offset-3, y-r, x+offset+3, y+r), 3, fill=color)
    elif kind == "map":
        points = [(x-r,y-r+4),(x-r/3,y-r),(x+r/3,y-r+4),(x+r,y-r),(x+r,y+r-4),(x+r/3,y+r),(x-r/3,y+r-4),(x-r,y+r)]
        d.line(points+[points[0]], fill=color, width=3)
        for dx in [-r/3, r/3]: d.line((x+dx,y-r+2,x+dx,y+r-2),fill=color,width=3)
    elif kind == "wind":
        d.line((x-r,y,x+r-4,y),fill=color,width=3)
        d.arc((x+r-11,y-10,x+r+2,y+2),270,95,fill=color,width=3)
        d.line((x-r,y-9,x+3,y-9),fill=color,width=3)
        d.arc((x-1,y-18,x+11,y-7),190,90,fill=color,width=3)
        d.line((x-r,y+9,x+6,y+9),fill=color,width=3)
        d.arc((x+1,y+8,x+13,y+20),270,175,fill=color,width=3)
    elif kind == "heart":
        d.ellipse((x-r,y-r,x+1,y+3),fill=color)
        d.ellipse((x-1,y-r,x+r,y+3),fill=color)
        d.polygon([(x-r,y-2),(x+r,y-2),(x,y+r)],fill=color)
    elif kind == "coin":
        d.ellipse((x-r,y-r,x+r,y+r),outline=color,width=3)
        d.rounded_rectangle((x-3,y-5,x+3,y+5),2,outline=color,width=2)


def stage():
    scene = Image.open(ASSETS / "environment/paper-temple-arena.png").convert("RGBA").resize((1280,720),Image.Resampling.LANCZOS)
    scene.alpha_composite(Image.new("RGBA", scene.size, (0,0,0,20)))
    d = ImageDraw.Draw(scene)
    d.rounded_rectangle((24,20,236,84),28,fill=INK)
    art(scene,"heroes/c_paper_down.png",(55,52),50)
    for i in range(6): glyph(scene,"heart",(100+i*20,42),ORANGE,14)
    d.rounded_rectangle((91,65,216,70),3,fill=(77,92,84))
    d.rounded_rectangle((91,65,169,70),3,fill=JADE)
    d.rounded_rectangle((526,24,754,80),28,fill=INK)
    glyph(scene,"map",(558,52),JADE,25)
    d.text((584,36),"纸灯巷",font=font(23,True),fill=TEXT)
    d.rounded_rectangle((1010,24,1124,80),28,fill=INK)
    glyph(scene,"coin",(1038,52),(229,186,105),24)
    d.text((1060,34),"10",font=font(25,True),fill=TEXT)
    circle(scene,(1206,54),30,INK,INK)
    glyph(scene,"pause",(1206,54),TEXT,25)
    circle(scene,(642,468),21,(0,0,0,0),(211,172,89),2)
    art(scene,"heroes/c_paper_down.png",(642,440),96)
    # Primary sticks sit symmetrically near the lower safe corners.
    for center,color,delta in [((145,580),JADE,(18,-18)),((1136,580),ORANGE,(20,-28))]:
        circle(scene,center,72,(20,30,32,104),color,2)
        circle(scene,(center[0]+delta[0],center[1]+delta[1]),25,(*color,165),(*color,165),1)
        d.line((center[0],center[1],center[0]+delta[0]*1.9,center[1]+delta[1]*1.9),fill=color,width=3)
    circle(scene,(258,492),46,INK,JADE,3)
    glyph(scene,"wind",(258,492),TEXT,32)
    circle(scene,(1018,480),46,INK,ORANGE,3)
    art(scene,"skills/s01.png",(1018,480),55)
    circle(scene,(1010,640),46,INK,JADE,3)
    art(scene,"active_items/a01.png",(1010,640),47)
    # Small equipped-weapon slot; full build moves to the pause inventory.
    d.rounded_rectangle((25,635,83,695),20,fill=INK)
    art(scene,"weapons/w01.png",(54,665),50)
    return scene


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    proposal = stage()
    proposal.convert("RGB").save(OUT / "proposed-combat-layout.png")
    canvas = Image.new("RGBA",(1760,970),(17,25,29,255))
    d = ImageDraw.Draw(canvas)
    d.text((56,32),"《香火债》安卓操作优化构思",font=font(38,True),fill=TEXT)
    d.text((57,90),"沿用当前游戏美术与字体 · 双拇指优先 · 此图为布局提案",font=font(20),fill=MUTED)
    before = Image.open(OUT / "phone-16x9/combat.png").convert("RGBA")
    for x, image, label, color in [(56,before,"当前布局",MUTED),(910,proposal,"推荐布局",JADE)]:
        d.text((x,146),label,font=font(29,True),fill=color)
        image = image.resize((794,447),Image.Resampling.LANCZOS)
        mask = Image.new("L",image.size,0)
        ImageDraw.Draw(mask).rounded_rectangle((0,0,793,446),24,fill=255)
        canvas.paste(image,(x,200),mask)
    for i,(heading,body) in enumerate([
        ("右手承担过多动作","瞄准、身法、焚债、道具集中在右侧"),
        ("摇杆与动作键距离大","右摇杆位于宽度的 68.75%，偏向屏幕中部"),
        ("大小与捕获范围不统一","固定摇杆仍按半屏捕获，离摇杆很远也能开火"),
    ]):
        y=688+i*76
        d.text((56,y),heading,font=font(24,True),fill=TEXT)
        d.text((56,y+35),body,font=font(20),fill=MUTED)
    for i,(heading,body) in enumerate([
        ("左手：移动 + 身法","身法沿最后移动方向，右手继续掌握瞄准"),
        ("右手：瞄准射击 + 焚债","射击回到右下；技能靠近；道具按装备显隐"),
        ("全屏控件按安全区排布","场景保持原比例；尺寸按 dp；点击地图即暂停查看"),
    ]):
        y=688+i*76
        d.text((910,y),heading,font=font(24,True),fill=JADE)
        d.text((910,y+35),body,font=font(20),fill=MUTED)
    canvas.convert("RGB").save(OUT / "controls-before-proposed.png")
    # These are arithmetic fixtures, not measured handset DPI/density values.
    sizing = []
    for name,width,height,density_dpi in [("720p-density-320",1280,720,320),("1080p-density-480",2400,1080,480)]:
        scale=min(width/1280,height/720)
        calculated=48*density_dpi/160/max(.5,scale)
        capped=max(64,min(90,calculated))
        sizing.append({"fixture":name,"density_dpi_assumed":density_dpi,"screen_scale":scale,
                       "required_logical_height":calculated,"actual_capped_logical_height":capped,
                       "result_dp":capped*scale*160/density_dpi,
                       "cinematic_50_logical_dp":50*scale*160/density_dpi,
                       "replacement_cancel_48_logical_dp":48*scale*160/density_dpi})
    (OUT / "density-size-analysis.json").write_text(json.dumps({"scope":"arithmetic evaluation of current source sizing formula; physical DPI may differ from Android logical density",
                                                              "fixtures":sizing},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Created proposed layout, comparison, and explicit density fixtures.")


if __name__ == "__main__":
    main()
