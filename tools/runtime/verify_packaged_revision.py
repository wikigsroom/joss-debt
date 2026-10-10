"""Open the EXE's embedded pack with the matching native Godot test runner."""
from pathlib import Path
import hashlib,json,re,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'docs/incense-debt/reports/action-mobile-2026-10-09'

def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def runtime_remap(data):
    # Godot's exporter removes editor-only [deps]/[params] and adds a trailing
    # NUL. Compare the entire runtime section, including importer, UID, target
    # and texture metadata; verify the actual exported bytes across platforms.
    selected=False
    lines=[]
    for line in data.decode('utf8').rstrip('\0').splitlines():
        header=line.strip()
        if header.startswith('[') and header.endswith(']'):
            if selected:break
            selected=header=='[remap]'
        elif selected:
            lines.append(line)
    if not lines:raise RuntimeError('Missing runtime import remap')
    return '\n'.join(lines).strip()

def main():
    sources=['game/data/music_playlist.json','game/assets/weapon-rig.json','game/data/runtime_assets.json','game/assets/fx/drawn-actions/manifest.json','game/assets/creature-actions.json']
    creatures=json.loads((ROOT/'game/assets/creature-actions.json').read_text('utf8'))
    if not creatures.get('complete') or creatures.get('compiled_actors')!=402 or creatures.get('compiled_action_poses')!=24048:
        raise RuntimeError('Creature action shipping coverage is incomplete; do not verify a partial release as complete')
    expected={'res://'+path.removeprefix('game/'):digest(ROOT/path) for path in sources}
    apk=ROOT/'build/android/IncenseDebt.apk'; exe=ROOT/'build/windows/IncenseDebt.exe'
    with zipfile.ZipFile(apk) as bundle:
        names=set(bundle.namelist())
        for path in sources:
            member='assets/'+path.removeprefix('game/')
            if hashlib.sha256(bundle.read(member)).hexdigest()!=digest(ROOT/path):raise RuntimeError('Stale APK member: '+member)
        for actor in creatures['actors'].values():
            for strip in actor['states'].values():
                relative=strip['path'].removeprefix('res://')
                if digest(ROOT/'game'/relative)!=strip['sha256']:raise RuntimeError('Stale source creature atlas: '+relative)
                mapping=relative+'.import'
                current=(ROOT/'game'/mapping).read_bytes()
                packed_mapping=bundle.read('assets/'+mapping)
                if runtime_remap(packed_mapping)!=runtime_remap(current):raise RuntimeError('Stale APK creature runtime remap: '+relative)
                target=re.search(r'path="res://([^"]+)"',current.decode('utf8'))
                if not target:raise RuntimeError('Missing creature texture import target: '+relative)
                imported=target[1]
                source_hash=digest(ROOT/'game'/imported)
                if hashlib.sha256(bundle.read('assets/'+imported)).hexdigest()!=source_hash:raise RuntimeError('Stale APK creature texture: '+relative)
                expected['res://'+mapping]=hashlib.sha256(packed_mapping).hexdigest()
                expected['res://'+imported]=source_hash
        # GDC bytes must match both platforms. Godot executes the Windows side below.
        for member in sorted(p for p in names if p.startswith('assets/scripts/') and p.endswith('.gdc')):
            expected['res://'+member.removeprefix('assets/')]=hashlib.sha256(bundle.read(member)).hexdigest()
        playlist=json.loads(bundle.read('assets/data/music_playlist.json'))
        for track in playlist['tracks']:
            mapping='assets/'+track['path'].removeprefix('res://')+'.import'
            text=bundle.read(mapping).decode('utf8')
            target=re.search(r'path="res://([^"]+)"',text)
            if not target or 'assets/'+target[1] not in names: raise RuntimeError('Unpackaged song: '+track['id'])
    temporary=ROOT/'.local-tools/revision-pack-expected.json'; temporary.write_text(json.dumps(expected),'utf8')
    native_log=REPORT/'packaged-windows.log'; native_log.unlink(missing_ok=True)
    try:
        runner=ROOT/'.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
        # Release templates omit --script. The editor runner supports it while
        # --main-pack ensures res:// reads the actual exported pack, not game/.
        result=subprocess.run([str(runner),'--headless','--main-pack',str(exe),'--log-file',str(native_log),'--script',str(ROOT/'tools/runtime/verify_packaged_revision.gd'),'--','--expected='+str(temporary),'--report='+str(REPORT/'packaged-windows.json')],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
    except subprocess.TimeoutExpired as error:
        log=native_log.read_text('utf8',errors='replace') if native_log.is_file() else (error.stdout or b'').decode('utf8',errors='replace')
        raise RuntimeError('Packaged verifier timed out; process closed:\n'+log[-6000:]) from error
    log=result.stdout.decode('utf8',errors='replace')
    if native_log.is_file(): log+=native_log.read_text('utf8',errors='replace')
    native_log.write_text(log,'utf8')
    if result.returncode or 'SCRIPT ERROR' in log or 'ERROR:' in log:raise RuntimeError(log[-6000:])
    report=json.loads((REPORT/'packaged-windows.json').read_text('utf8'))
    script_count=sum(path.endswith('.gdc') for path in expected)
    report.update(windows_sha256=digest(exe),android_sha256=digest(apk),matching_compiled_scripts=script_count,matching_data=sources,matching_creature_atlases=sum(len(actor['states']) for actor in creatures['actors'].values()),creature_import_remaps_match_source=True,creature_compiled_texture_bytes_match_source=True,android_device_tested=False)
    (REPORT/'packaged-parity.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8')
    print(f'Actual exported Windows pack passed {len(report["checks"])} checks in native Godot; {script_count} compiled scripts match Android; four songs and all hero/creature drawn poses packaged.')

if __name__=='__main__':main()
