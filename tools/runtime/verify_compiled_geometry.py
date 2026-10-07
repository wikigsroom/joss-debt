"""Execute Windows/Android packed geometry on the native desktop engine."""
from pathlib import Path
import subprocess
import zipfile
import json
import hashlib

ROOT = Path(__file__).resolve().parents[2]

def main():
    scratch = ROOT / '.local-tools/combat-revision-verify'
    scratch.mkdir(parents=True, exist_ok=True)
    android_script = scratch / 'android_room_geometry.gdc'
    android = ROOT / 'build/android/IncenseDebt.apk'
    windows = ROOT / 'build/windows/IncenseDebt.exe'
    report = ROOT / 'docs/incense-debt/reports/runtime/combat-revision/compiled-geometry.json'
    with zipfile.ZipFile(android) as bundle:
        android_script.write_bytes(bundle.read('assets/scripts/combat/room_geometry.gdc'))
        compiled = [{'file': 'res://' + name.removeprefix('assets/'), 'android_sha256': hashlib.sha256(bundle.read(name)).hexdigest()}
                    for name in bundle.namelist() if name.startswith('assets/scripts/') and name.endswith('.gdc')]
    script_manifest = scratch / 'compiled-scripts.json'
    script_manifest.write_text(json.dumps(compiled), 'utf8')
    args = [str(ROOT / '.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'), '--headless',
            '--main-pack', str(windows), '--script', str(ROOT / 'tools/runtime/probe_packaged_geometry.gd'), '--',
            '--android-script=' + str(android_script), '--windows-artifact=' + str(windows),
            '--android-artifact=' + str(android), '--report=' + str(report), '--compiled-scripts=' + str(script_manifest)]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
    log = (result.stdout + result.stderr).decode('utf8', 'replace')
    print(log)
    if result.returncode or 'SCRIPT ERROR' in log or 'ERROR:' in log or not json.loads(report.read_text('utf8'))['passed']:
        raise RuntimeError('Current compiled geometry did not match or execute correctly')

if __name__ == '__main__': main()
