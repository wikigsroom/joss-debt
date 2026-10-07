"""Author collision contours in the actual 1280x720 background image coordinates."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
# left, top, right, bottom, clipped-corner depth. A/B are individually reviewed.
CONTOURS = [
    [(191,155,1084,592,60),(197,144,1088,594,55)],
    [(215,133,1060,546,26),(225,128,1060,550,30)],
    [(204,152,1080,587,130),(185,142,1092,592,88)],
    [(203,146,1080,596,65),(218,153,1077,584,70)],
    [(192,151,1106,600,25),(202,144,1110,600,20)],
    [(195,172,1088,595,80),(210,146,1072,575,55)],
    [(220,158,1085,610,45),(205,142,1079,610,55)],
    [(225,157,1066,589,70),(218,148,1067,587,90)],
    [(217,157,1067,590,45),(222,147,1058,590,22)],
    [(225,164,1070,557,70),(238,164,1058,552,58)],
    [(182,152,1099,580,34),(190,152,1097,580,35)],
    [(210,140,1075,581,110),(217,142,1074,584,28)],
    [(211,168,1079,608,70),(211,142,1075,600,55)],
    [(217,152,1072,555,32),(225,139,1062,565,70)],
    [(225,170,1062,551,32),(230,173,1058,548,30)],
    [(230,170,1065,565,65),(238,171,1058,566,40)],
    [(218,145,1080,572,35),(218,148,1076,570,20)],
    [(212,154,1080,567,55),(235,151,1060,567,65)],
    [(190,166,1090,576,32),(215,156,1074,578,45)],
    [(189,159,1098,555,65),(205,164,1082,558,80)],
]

def polygon(values):
    l,t,r,b,c = values
    return [[l+c,t],[r-c,t],[r,t+c],[r,b-c],[r-c,b],[l+c,b],[l,b-c],[l,t+c]]

def main():
    records = {}
    pages = []
    font = ImageFont.truetype(str(ROOT/'game/assets/fonts/NotoSansSC.ttf'),18)
    for index, variants in enumerate(CONTOURS,1):
        for variant, values in enumerate(variants):
            key = f'm{index:02d}_{"ab"[variant]}'
            path = ROOT / f'game/assets/environment/expansion/{key}.png'
            points = polygon(values)
            records[key] = dict(polygon=points,source=path.relative_to(ROOT).as_posix(),
                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),space='background_1280x720')
            image = Image.open(path).convert('RGB')
            draw = ImageDraw.Draw(image)
            draw.line([tuple(p) for p in points+[points[0]]], fill='#2affbb',width=5)
            for x,y in points: draw.ellipse((x-5,y-5,x+5,y+5),fill='white')
            draw.text((570,values[1]+10),key,font=font,fill='white',stroke_width=2,stroke_fill='black')
            pages.append(image.resize((640,360),Image.Resampling.LANCZOS))
    (ROOT/'game/data/arena_boundaries.json').write_text(json.dumps(dict(version=1,rooms=records),indent=2)+'\n','utf8')
    output = ROOT/'docs/incense-debt/reports/runtime/combat-revision'
    output.mkdir(parents=True,exist_ok=True)
    for group in range(4):
        sheet = Image.new('RGB',(1280,1800),'#192524')
        for cell in range(10): sheet.paste(pages[group*10+cell],(cell%2*640,cell//2*360))
        sheet.save(output/f'boundaries-{group+1:02d}.png')
    print('40 source-bound inner-wall polygons and four review sheets saved.')

if __name__=='__main__': main()
