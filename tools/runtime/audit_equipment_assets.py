"""Verify generated equipment sources, distinct frames and current native adoption."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    packaged = '--packaged' in sys.argv
    folder = ROOT / 'docs/incense-debt/reports' / ('platforms/windows/equipment-polish' if packaged else 'runtime/equipment-polish')
    manifest = json.loads((ROOT / 'game/assets/fx/equipment-polish/manifest.json').read_text('utf8'))
    checks = []
    frames = []
    for row in manifest['records']:
        target, source = ROOT / row['file'], ROOT / row['source']
        image = Image.open(target).convert('RGBA')
        good = digest(target) == row['sha256'] and digest(source) == row['source_sha256']
        alpha = image.getchannel('A').getextrema()
        good = good and alpha[0] == 0 and alpha[1] > 200
        if row['kind'] == 'fx':
            hashes = [hashlib.sha256(image.crop((i * 256, 0, (i + 1) * 256, 256)).tobytes()).hexdigest() for i in range(6)]
            good = good and image.size == (1536, 256) and hashes == row['frame_hashes'] and len(set(hashes)) == 6
            frames.extend(hashes)
        else:
            good = good and image.size == (256, 256)
        checks.append({'id': row['id'], 'passed': good})
    checks.append({'id': '480_distinct_generated_frames', 'passed': len(frames) == len(set(frames)) == 480})
    sources = {row['source'] for row in manifest['records']}
    checks.append({'id': '23_actual_source_boards', 'passed': len(sources) == 23})
    profiles = json.loads((ROOT / 'game/data/projectile_profiles.json').read_text('utf8'))['profiles']
    checks.append({'id': '395_projectile_profiles', 'passed': len(profiles) == 395})
    report = {'passed': all(c['passed'] for c in checks), 'checks': checks, 'failures': [c for c in checks if not c['passed']],
              'provider': 'sub2-image-gen', 'model': 'gpt-image-2.5', 'source_boards': len(sources),
              'icons': 36, 'fx_strips': 80, 'unique_frames': len(set(frames)), 'projectile_profiles': len(profiles), 'packaged': packaged}
    if packaged:
        native = json.loads((folder / 'native.json').read_text('utf8'))
        report['artifact_sha256'] = digest(ROOT / 'build/windows/IncenseDebt.exe')
        if not native['passed'] or native.get('artifact_sha256') != report['artifact_sha256'] or native['atlas_frames_loaded'] != 480:
            raise RuntimeError('Generated asset adoption does not match the tested current executable')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'assets.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf8')
    print(json.dumps({k:v for k,v in report.items() if k != 'checks'}, ensure_ascii=False))
    return int(not report['passed'])

if __name__ == '__main__': sys.exit(main())
