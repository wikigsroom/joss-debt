"""Generate the approved direction-02 UI through the user's Sub2API skill CLI."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/imagegen/ink-ui-2026-10-13'
CLI = Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')
REFERENCE = ROOT / 'output/imagegen/incense-debt-menu-ui-directions-2026-10-13/02-ink-cinnabar-talisman.png'
COMMON = ('The attached image is the user-approved art direction for Incense Debt: '
          'warm xuan paper, charcoal sumi-e brush strokes, cinnabar red, restrained jade, '
          'folk talismans and hand-cut paper. Match its painted texture and contemporary '
          'clean game UI craft. Create production art assets, NOT a screenshot or device mockup. '
          'No readable writing, no numbers, no letters, no labels, no logos, no watermark. ')
ICONS = [
    ['play triangle','circular undo arrow','crossed sword','two crossing shuffle arrows',
     'written scroll','small shrine house','three adjustment sliders','exit arrow leaving door',
     'back arrow','close cross','pause parallel bars','crown with three points',
     'four pointed sparkle','sun with eight rays','leaf','shield'],
    ['folded route map','three stacked pages','chain links','flame','gust of wind','ink brush',
     'round info mark','closed padlock','open book','open folder',
     'save disk','refresh arrows','check mark','copy stacked papers','magnifying glass','lightning bolt'],
    ['keyboard','game controller','hand palm','mobile phone','desktop monitor','mouse',
     'touch pad','speaker sound waves','muted speaker','music note','eye','crosshair',
     'bullseye target','water droplet','upload arrow','download arrow'],
    ['up arrow','down arrow','right arrow','diagonal up right arrow',
     'left chevron','right chevron','down chevron','empty circle',
     'dot within circle','question mark within circle','next play double triangle','magic wand sparkle',
     'round stamped talisman emblem','round paper dial','cinnabar knot','ink cloud']
]
JOBS = {
 'menu-background': COMMON + 'Create one landscape 16:9 BACKGROUND ONLY. A pale aged rice-paper page fills the image. Its CENTER 85 percent is blank calm ivory paper for placing live menus. Black ink washes, sparse plum blossoms, red cords, hanging ivory talismans with abstract marks and a tiny candle are restricted to the OUTER 5 percent edges and corners. No existing UI, no paper doll, no buttons, no frames in center. Flat painted illustration. The blank center must remain bright beige, not gray or black.',
 'controls-sheet': COMMON + 'Create a precise THREE columns by THREE rows game UI SPRITE SHEET on pure white, each cell separated by generous pure-white gutters, centered isolated sprite with nothing crossing cell boundaries. Row 1: (1) wide charcoal black rounded brush-stroke pill, (2) wide CINNABAR RED rounded brush-stroke pill, (3) warm ivory paper rectangular PANEL with softly rounded corners and thin hand-brushed black edge. Row 2: (1) wide transparent-center black dry-brush outline pill focus frame, (2) round cinnabar ink SEAL with abstract geometric marks not characters, (3) round charcoal ink disk BUTTON. Row 3: (1) vertical hanging parchment TALISMAN ribbon with red tassel, (2) thin horizontal charcoal cloud-and-plum-branch DIVIDER with one red accent, (3) black hand-brushed rectangular PORTRAIT frame with empty WHITE interior, rough ink corners and no other decoration. All nine assets orthographic, 2D, naturally painted. No shadows outside silhouettes. No text.',
 'button-kit': COMMON + 'Create a precise THREE columns by TWO rows sprite sheet with six isolated horizontal game UI materials on true transparent alpha and generous transparent gutters. Row 1: (1) a long bright CINNABAR vermilion dry-brush stroke with pale rice-paper edge, center blank; (2) a long charcoal sumi-e dry-brush stroke with gray bristle texture and subtle abstract corner seal fragments, center blank; (3) a charcoal hover stroke with restrained cinnabar rim and lifted pale edge, center blank. Row 2: (1) a pressed charcoal stroke with deeper wet-ink center and red flecks, center blank; (2) a disabled warm gray ink wash stroke, center blank; (3) an irregular charcoal and cinnabar double-accent focus outline frame with transparent center. No readable marks, no logos, no characters, no shadows outside silhouettes.',
 'card-kit': COMMON + 'Create a precise TWO columns by TWO rows sprite sheet with four isolated portrait game card materials on true transparent alpha and generous transparent gutters. Row 1: (1) a tall charcoal sumi-e ink plaque card with pale rough rice-paper edge, empty center; (2) a selected tall charcoal card with a strong restrained cinnabar hand-brushed outer rim, empty center. Row 2: (1) a locked disabled tall warm gray ink wash card, empty center; (2) a tall warm xuan-paper card with thin irregular charcoal brush frame and bright paper center. No text, numbers, logos, characters, device frame or shadows outside silhouettes.',
}
for i, icons in enumerate(ICONS, 1):
    JOBS['icons-%02d'%i] = (COMMON + 'Create a SQUARE precisely FOUR columns by FOUR rows sprite sheet with 16 clear WHITE painted monoline UI icons on a perfectly BLACK background. Each icon is centered within its own equal grid cell, generous black gutters. Consistent slightly hand-brushed strokes, elegant but recognizable standard game navigation glyphs, not blobs, not decorative seals, no paper background. The white stroke is thick enough for a 24 pixel icon. The exact row-major order from top-left to bottom-right: ' + '; '.join(icons) + '. No labels, no extra images, no uneven grid.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jobs', nargs='*', choices=list(JOBS))
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    manifest_path = OUT / 'generation-latest.json'
    try:
        manifest = json.loads(manifest_path.read_text(encoding='utf8'))
        if not isinstance(manifest, list): manifest = []
    except (FileNotFoundError, json.JSONDecodeError):
        manifest=[]
    for key in args.jobs or list(JOBS):
        target=OUT/(key+'.png')
        prompt=OUT/(key+'.prompt.txt')
        prompt.write_text(JOBS[key], encoding='utf8')
        if target.exists() and target.stat().st_size > 1000:
            print('Existing '+key, flush=True)
            continue
        cmd=[sys.executable,str(CLI),'edit','--image',str(REFERENCE),'--prompt-file',str(prompt),
             '--model','gpt-image-2.5','--size','1536x1024','--quality','high',
             '--output-format','png','--out',str(target)]
        if key.startswith('icons-'):
            # A square reference preserves uniform glyph-cell geometry on edit providers.
            from PIL import Image,ImageOps
            square=OUT/'reference-square.png'
            if not square.exists(): ImageOps.pad(Image.open(REFERENCE),(1024,1024),color='#eadcc2').save(square)
            cmd[cmd.index('--image')+1]=str(square)
            cmd[cmd.index('--size')+1]='1024x1024'
        for attempt in range(2):
            print('Generating '+key+' attempt '+str(attempt+1),flush=True)
            result=subprocess.run(cmd,cwd=ROOT,timeout=240)
            if result.returncode==0 and target.exists(): break
            if attempt==0: time.sleep(8)
        else: raise RuntimeError('The specified Sub2API model did not generate '+key)
        manifest = [row for row in manifest if row.get('id') != key]
        manifest.append({'id':key,'file':target.relative_to(ROOT).as_posix(),'reference':REFERENCE.relative_to(ROOT).as_posix(),
                         'model':'gpt-image-2.5','created_at':datetime.now(timezone.utc).isoformat()})
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    return 0
if __name__=='__main__': sys.exit(main())
