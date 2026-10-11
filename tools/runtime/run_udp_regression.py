"""Bounded native networking regressions, including explicit certificate negatives."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
ENGINE=ROOT/'.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args=parser.parse_args();folder=args.output.resolve()
    if folder.exists(): raise RuntimeError('Use a new output directory; prior isolated identities/checkpoints must not affect a fresh regression')
    folder.mkdir(parents=True)
    cases=[('state_stream',[]),('remote_interpolation',[]),('attack_prediction',[]),
        ('cooperative_transport',['--folder='+str(folder/'cooperative-transport-private')]),
        ('network_faults',['--output='+str(folder/'faults.json')]),
        ('udp_security',['--output='+str(folder/'security')]),
        ('udp_unavailable',['--output='+str(folder/'unavailable.json')]),
        ('dtls_certificate_negative',['--mode=hostname','--output='+str(folder/'certificate-hostname.json')]),
        ('dtls_certificate_negative',['--mode=trust','--output='+str(folder/'certificate-trust.json')])]
    results=[]
    for index,(name,arguments) in enumerate(cases):
        command=[str(ENGINE),'--headless','--max-fps','120','--path',str(ROOT/'game'),'--script','res://tests/'+name+'.gd','--',*arguments]
        run=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        log=run.stdout.decode('utf8',errors='replace');(folder/(str(index)+'-'+name+'.log')).write_text(log,'utf8')
        errors=[line for line in log.splitlines() if line.startswith('ERROR:') or line.startswith('SCRIPT ERROR') or line.startswith('mbedtls error:')]
        allowed=[]
        if name=='dtls_certificate_negative':
            # Only these intentionally induced certificate verification/alert
            # messages are expected. Script errors and unrelated TLS errors fail.
            for line in errors:
                if line in ['ERROR: TLS handshake error: -9984','ERROR: TLS handshake error: -30592','mbedtls error: returned -0x2700','mbedtls error: returned -0x7780']:allowed.append(line)
        unexpected=[line for line in errors if line not in allowed]
        checks=len(re.findall(r'(?:PASS |passed=true)',log))
        failed=bool(re.search(r'\bFAIL |RESULT.*false|failures=[1-9]',log))
        result={'case':name,'arguments':arguments if name=='dtls_certificate_negative' else [],'passed':run.returncode==0 and not failed and not unexpected,
            'checks':checks,'exit_code':run.returncode,'expected_certificate_errors':allowed,'unexpected_native_errors':unexpected,
            'script_sha256':hashlib.sha256((ROOT/'game/tests'/(name+'.gd')).read_bytes()).hexdigest()}
        results.append(result);print(json.dumps({k:v for k,v in result.items() if k!='script_sha256'}),flush=True)
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'game/scripts').rglob('*.gd'))}
    result={'passed':all(r['passed'] for r in results),'recorded_at':datetime.now(timezone.utc).isoformat(),'cases':results,'source_hashes':hashes,
        'virtualization':'none','physical_android_tested':False,'scope':'Native Godot development regressions and actual DTLS sockets in isolated storage. Intentional certificate failures are classified by exact error message only.'}
    (folder/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
    return int(not result['passed'])

if __name__=='__main__':raise SystemExit(main())
