"""Real native clients against the isolated Linux candidate, with full-run health."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import importlib.util
import subprocess
import time
import urllib.request
import re

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT/'.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
VERSION = re.search(r'config/version="([^"]+)"', (ROOT/'game/project.godot').read_text('utf8')).group(1)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=3600)
    parser.add_argument('--url', default='wss://xhz-server.sidcloud.cn/candidate-play')
    parser.add_argument('--health', default='https://xhz-server.sidcloud.cn/candidate-health')
    parser.add_argument('--rooms', type=int, default=2)
    parser.add_argument('--weapons', default='w07,w14,w11,w25', help='Real campaign loadouts, in client order')
    parser.add_argument('--fixture', type=Path, help='Optional external diagnostic fixture; production Session and server remain unchanged')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    folder=args.output.resolve()
    if folder.exists(): raise RuntimeError('Use a new WAN output directory and fresh private client identities')
    folder.mkdir(parents=True)
    def health():
        with urllib.request.urlopen(args.health, timeout=15) as response:return json.load(response)
    first=health()
    if first['version']!=VERSION or first['transport']!=2 or not first['battle_encrypted']:
        raise RuntimeError(f'Expected encrypted {VERSION} server')
    spec=importlib.util.spec_from_file_location('private_remote', ROOT/'.local-tools/public-server-2026-10-13/remote.py')
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    unit='incense-debt-udp-candidate.service' if 'candidate-play' in args.url else 'incense-debt.service'
    target=('/opt/incense-debt/candidates/v'+VERSION+'/IncenseDebtServer.x86_64') if 'candidate-play' in args.url else '/opt/incense-debt/current/IncenseDebtServer.x86_64'
    def native_check():
        remote=helper.connect()
        try:
            stdin,stdout,stderr=remote.exec_command('sudo python3 -',timeout=20)
            script='''import hashlib,subprocess,pathlib,json,re
unit=UNIT
pid=subprocess.check_output(['systemctl','show',unit,'--property=MainPID','--value'],text=True).strip()
digest=hashlib.sha256()
with open(TARGET,'rb') as source:
 for block in iter(lambda:source.read(1024*1024),b''):digest.update(block)
digest=digest.hexdigest()
status=pathlib.Path('/proc/'+pid+'/status').read_text()
memory={key:int(re.search(r'^'+key+r':\\s*(\\d+)',status,re.M)[1])*1024 for key in ['VmRSS','VmHWM']}
journal=subprocess.check_output(['journalctl','-u',unit,'_PID='+pid,'--no-pager','-o','cat'],text=True)
errors=[line for line in journal.splitlines() if re.search(r'SCRIPT ERROR|ERROR:|mbedtls error:',line,re.I)]
print(json.dumps({'sha256':digest,'pid':int(pid),'memory':memory,'native_errors':errors}))
'''.replace('UNIT',repr(unit)).replace('TARGET',repr(target))
            stdin.write(script);stdin.flush();stdin.channel.shutdown_write();raw=stdout.read().decode('utf8')
            if stdout.channel.recv_exit_status():raise RuntimeError('Native installed checksum/journal verification failed')
            return json.loads(raw)
        finally:remote.close()
    before_native=native_check();installed=before_native['sha256']
    expected=hashlib.sha256((ROOT/'build/server-linux/IncenseDebtServer.x86_64').read_bytes()).hexdigest()
    if installed!=expected:raise RuntimeError('Actual installed server differs from the local accepted binary')
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'game/scripts').rglob('*.gd'))}
    samples=[]
    fixture = args.fixture.resolve() if args.fixture else ROOT/'game/tests/udp_soak.gd'
    with (folder/'traffic.log').open('wb') as log:
        process=subprocess.Popen([str(ENGINE),'--headless','--max-fps','60','--path',str(ROOT/'game'),
            '--script',str(fixture),'--','--url='+args.url,'--rooms='+str(args.rooms),
            '--seconds='+str(args.seconds),'--weapons='+args.weapons,'--game-mode=coop',
            '--output='+str(folder/'clients.json')],stdout=log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline=time.monotonic()+args.seconds+80
            while process.poll() is None and time.monotonic()<deadline:
                value=health();value['sample_monotonic']=time.monotonic();samples.append(value);time.sleep(1)
            if process.poll() is None:raise RuntimeError('WAN load exceeded bounded deadline')
        finally:
            if process.poll() is None:process.kill();process.wait(timeout=8)
    clients=json.loads((folder/'clients.json').read_text('utf8'))
    text=(folder/'traffic.log').read_text('utf8', errors='replace')
    steady=[s for s in samples if s['connections']==args.rooms*2]
    tick=(steady[-1]['tick']-steady[0]['tick'])/(steady[-1]['sample_monotonic']-steady[0]['sample_monotonic']) if len(steady)>1 else 0
    last=samples[-1]
    after_native=native_check()
    clean=not re.search(r'SCRIPT ERROR|ERROR:|mbedtls error:',text,re.I) and not after_native['native_errors'] and before_native['pid']==after_native['pid'] and after_native['sha256']==installed
    child_returncode=process.returncode
    # One 60 Hz frame is 16.7 ms. A rare scheduler/checkpoint hitch may span
    # one additional frame, but a third frame is a visible simulation stall.
    # The client-side state-age and RTT gates cover the actual playable path.
    # A 60 Hz frame is 16.7 ms; p99 may fill one frame under WAN load while
    # p999 still catches a visible third-frame simulation hitch.
    passed=clients['passed'] and child_returncode==0 and clean and tick>=58 and clients['state_age_p95_ms']<150 and clients['ping_p95_ms']<250 and last['lifetime_step']['p990_ms_upper_bound']<16.7 and last['lifetime_step']['p999_ms_upper_bound']<33.4 and last['combat_stalls_over_100ms']==0 and all(not s['storage_fault'] and s['persistence_errors']==0 for s in samples)
    result={'passed':passed,'recorded_at':datetime.now(timezone.utc).isoformat(),'transport':'ENet/DTLS',
        'endpoint':args.url,'health_endpoint':args.health,'virtualization':'none','clients':clients,'tick_hz':tick,
        'lifetime_step':last['lifetime_step'],'lifetime_process':last['lifetime_process'],
        'combat_stalls_over_100ms':last['combat_stalls_over_100ms'],'child_returncode':child_returncode,
        'source_hashes_at_start':hashes,
        'server_sha256':installed,
        'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),
        'clean_native_log':clean,'native_server':after_native,'samples':samples,'scope':str(args.rooms*2)+' native Windows headless production sessions and the native Linux server over actual WAN. No physical Android or rendering evidence.'}
    (folder/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
    print(json.dumps({k:v for k,v in result.items() if k not in ['samples','source_hashes_at_start']},ensure_ascii=False))
    return int(not passed)

if __name__=='__main__':raise SystemExit(main())
