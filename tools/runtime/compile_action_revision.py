"""Register independently drawn Sub2 poses; never deform or stretch a source pose."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from prepare_action_revision import ROOT, OUT, ACTORS, DIRECTIONS, STATES

FPS = dict(idle=6, run=12, cast=18, dash=30, hurt=18, death=10)
REPORT = ROOT / 'docs/incense-debt/reports/action-mobile-2026-10-09'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def isolated(cell):
    pixels = np.array(cell.convert('RGBA'))
    labels, count = ndimage.label(pixels[:, :, 3] > 32)
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    if count == 0 or areas.max() < 400:
        raise ValueError('Empty or incomplete source cell')
    largest = int(areas.argmax())
    keep = labels == largest
    for label, bounds in enumerate(ndimage.find_objects(labels), 1):
        if label == largest or bounds is None or areas[label] < areas[largest] * .018:
            continue
        ys, xs = bounds
        # Disconnected content touching a cell edge belongs to a neighbouring pose.
        if min(xs.start, ys.start) <= 1 or xs.stop >= cell.width-1 or ys.stop >= cell.height-1:
            continue
        keep |= labels == label
    keep = ndimage.binary_dilation(keep, iterations=1)
    pixels[~keep, 3] = 0
    result = Image.fromarray(pixels)
    return result.crop(result.getbbox())


def grip_points(frame, defaults):
    pixels = np.array(frame)
    r, g, b, a = [pixels[:, :, i].astype(int) for i in range(4)]
    mask = (r > 150) & (g > 120) & (b > 85) & (r-g < 50) & (g-b < 70) & (a > 110)
    mask[:48] = False
    labels, count = ndimage.label(mask)
    areas = np.bincount(labels.ravel())
    candidates = []
    for index in range(1, count+1):
        if 4 <= areas[index] <= 110:
            y, x = ndimage.center_of_mass(mask, labels, index)
            candidates.append((x, y))
    points = []
    for default in defaults:
        chosen = min(candidates, key=lambda p: (p[0]-default[0])**2+(p[1]-default[1])**2) if candidates else default
        if (chosen[0]-default[0])**2+(chosen[1]-default[1])**2 > 26**2:
            chosen = default
        points.append([round(float(chosen[0]), 3), round(float(chosen[1]), 3)])
        if chosen in candidates:
            candidates.remove(chosen)
    return points


def hand_overlay(frame, points):
    mask = Image.new('L', frame.size)
    draw = ImageDraw.Draw(mask)
    for x, y in points:
        draw.ellipse((x-4.1, y-4.2, x+4.1, y+4.2), fill=255)
    pixels = np.array(frame)
    pixels[:, :, 3] = np.minimum(pixels[:, :, 3], np.array(mask))
    return Image.fromarray(pixels)


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / 'game/assets/animation-manifest.json'
    manifest = json.loads(manifest_path.read_text('utf8'))
    manifest['strips'] = [s for s in manifest['strips'] if s['kind'] not in ('character','weapon_body','weapon_hand')]
    rig_path = ROOT / 'game/assets/weapon-rig.json'
    rig = json.loads(rig_path.read_text('utf8'))
    old = json.loads((ROOT / 'docs/incense-debt/reports/runtime/held-weapons/body-processing.json').read_text('utf8'))
    defaults = {(s['actor'], s['direction']): s['points'] for s in old['grips']}
    review = Image.new('RGB', (len(ACTORS)*192, len(STATES)*128), '#24333a')
    gif_frames = [Image.new('RGB', (len(ACTORS)*128, len(STATES)*128), '#24333a') for _ in range(6)]
    records, scales = [], {}
    for actor in ACTORS:
        cells, sources = {}, []
        for direction in DIRECTIONS:
            source = OUT / f'{actor}-{direction}.png'
            sheet = Image.open(source).convert('RGBA')
            sources.append(dict(file=str(source.relative_to(ROOT)).replace('\\','/'), sha256=digest(source)))
            for row, state in enumerate(STATES):
                cells[state,direction] = [isolated(sheet.crop((round(col*sheet.width/6),round(row*sheet.height/6),round((col+1)*sheet.width/6),round((row+1)*sheet.height/6)))) for col in range(6)]
        original_height = np.median([Image.open(ROOT / f'game/assets/weapon-bodies/base/{actor}_{d}.png').getbbox()[3]-Image.open(ROOT / f'game/assets/weapon-bodies/base/{actor}_{d}.png').getbbox()[1] for d in DIRECTIONS])
        standing_height = np.median([cell.height for d in DIRECTIONS for cell in cells['idle', d]])
        scale = min(original_height/standing_height, 89/max(cell.width for row in cells.values() for cell in row), 79/max(cell.height for row in cells.values() for cell in row))
        scales[actor] = round(float(scale), 6)
        rig['actors'][actor] = {}
        for state in STATES:
            atlas, hands = Image.new('RGBA',(576,384)), Image.new('RGBA',(576,384))
            rig['actors'][actor][state] = {}
            for row, direction in enumerate(DIRECTIONS):
                frame_points = []
                for col, cell in enumerate(cells[state,direction]):
                    sized = cell.resize((max(1,round(cell.width*scale)),max(1,round(cell.height*scale))), Image.Resampling.LANCZOS)
                    frame = Image.new('RGBA',(96,96))
                    frame.alpha_composite(sized, ((96-sized.width)//2, 81-sized.height))
                    points = grip_points(frame, defaults[actor,direction])
                    frame_points.append(points)
                    atlas.alpha_composite(frame,(col*96,row*96))
                    hands.alpha_composite(hand_overlay(frame,points),(col*96,row*96))
                    if direction == 'down':
                        gif_frames[col].paste(frame.resize((128,128),Image.Resampling.NEAREST),(ACTORS.index(actor)*128,STATES.index(state)*128),frame.resize((128,128),Image.Resampling.NEAREST))
                        if col in (2,5):
                            review.paste(frame,(ACTORS.index(actor)*192+(0 if col==2 else 96),STATES.index(state)*128+15),frame)
                rig['actors'][actor][state][direction] = frame_points
            for kind, folder, picture in [('character','characters',atlas),('weapon_body','weapon-bodies/animation',atlas),('weapon_hand','weapon-bodies/hands',hands)]:
                target = ROOT / f'game/assets/{folder}/{actor}/{state}.png'
                target.parent.mkdir(parents=True,exist_ok=True)
                picture.save(target)
                record = dict(actor=actor,kind=kind,state=state,frames=6,directions=DIRECTIONS,frame_size=96,fps=FPS[state],anchor=[.5,.84],file=str(target.relative_to(ROOT)).replace('\\','/'),source=sources,sha256=digest(target),method='independently Sub2-drawn key poses; uniform scale and floor registration, no deformation')
                manifest['strips'].append(record)
                records.append(record)
    rig['version'] = 2
    rig['animation_method'] = 'independently_drawn_six_frame_poses'
    rig_path.write_text(json.dumps(rig,ensure_ascii=False,indent=2)+'\n','utf8')
    manifest['method'] = 'Six heroes use independently drawn action atlases; legacy creature atlases retain their original method.'
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8')
    review.save(REPORT/'normalized-actions.png')
    gif_frames[0].save(REPORT/'drawn-actions.gif',save_all=True,append_images=gif_frames[1:],duration=160,loop=0)
    (REPORT/'action-processing.json').write_text(json.dumps(dict(sources=24,independent_poses=864,uniform_actor_scales=scales,strips=records),ensure_ascii=False,indent=2)+'\n','utf8')
    print(f'Installed {len(records)} atlases; 864 independently drawn poses; preserved {len(rig["weapons"])} weapon rigs.')


if __name__ == '__main__': main()
