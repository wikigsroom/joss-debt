"""Scoped native staging/activation on the existing host; never prints credentials."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import importlib.util
import json
import re

ROOT = Path(__file__).resolve().parents[2]
# This is the host behind xhz-server.sidcloud.cn. The DPAPI-backed helper is
# intentionally ignored and never enters the repository.
PRIVATE = ROOT / ".local-tools/public-server-2026-10-13"
REMOTE = r'''
import hashlib,json,os,pathlib,pwd,grp,shutil,subprocess,time,urllib.request
version=payload['version']
def run(args):
 p=subprocess.run(args,capture_output=True,text=True,check=True);return p.stdout.strip()
def health(port):
 return json.load(urllib.request.urlopen('http://127.0.0.1:%d/health'%port,timeout=5))
def sha(path):
 digest=hashlib.sha256()
 with open(path,'rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):digest.update(block)
 return digest.hexdigest()
base=pathlib.Path('/opt/incense-debt')
 candidate=base/('candidates/v'+version)
vhost=pathlib.Path('/www/server/panel/vhost/nginx/xhz-server.sidcloud.cn.conf')
nginx='/www/server/nginx/sbin/nginx'
unit='incense-debt-udp-candidate.service'
uid=pwd.getpwnam('incense-debt').pw_uid;gid=grp.getgrnam('incense-debt').gr_gid
if payload['action']=='stage':
 old=health(18778)
 if old['version']!='0.5.0':raise RuntimeError('Unexpected live version before staging')
 active=subprocess.run(['systemctl','is-active',unit],capture_output=True,text=True).stdout.strip()
 if active=='active':
  current=health(19578)
  if current['connections']:raise RuntimeError('Candidate has active clients')
  (pathlib.Path('/var/lib/incense-debt-candidate-v'+version)/'stop').touch()
  time.sleep(.5)
  # --collect removes a transient unit after its graceful exit.
  if subprocess.run(['systemctl','is-active',unit],capture_output=True,text=True).stdout.strip()=='active':run(['systemctl','stop',unit])
 source=pathlib.Path(payload['upload'])
 if sha(source)!=payload['sha256']:raise RuntimeError('Upload checksum mismatch')
 candidate.mkdir(parents=True,exist_ok=True)
 target=candidate/'IncenseDebtServer.x86_64';shutil.copyfile(source,target);target.chmod(0o755)
 tls=pathlib.Path('/etc/incense-debt/tls');tls.mkdir(parents=True,exist_ok=True);os.chown(tls,0,gid);tls.chmod(0o750)
 for name in ['fullchain.pem','privkey.pem']:
  target=tls/name;shutil.copyfile('/etc/letsencrypt/live/incense-debt-public/'+name,target);os.chown(target,0,gid);target.chmod(0o640)
  state=pathlib.Path('/var/lib/incense-debt-candidate-v'+version)
 if state.exists():state.rename(pathlib.Path(str(state)+'-previous-'+str(time.time_ns())))
 state.mkdir(exist_ok=True);os.chown(state,uid,gid);state.chmod(0o700)
 config=dict(payload['config']);config.update(port=19577,data_directory=str(state))
 (candidate/'config.json').write_text(json.dumps(config,indent=2)+'\n');(candidate/'config.json').chmod(0o644)
 # This opens only the dedicated game's UDP port. Other applications stay in place.
 run(['ufw','allow','18779/udp','comment','IncenseDebt DTLS battle'])
  backup=base/('backups/udp-v'+version);backup.mkdir(parents=True,exist_ok=True);backup.chmod(0o700)
 original=vhost.read_text()
 if 'location = /candidate-play' not in original:
  (backup/'nginx-before-stage.conf').write_text(original)
  fragment="""    location = /candidate-play {
        proxy_pass http://127.0.0.1:19577;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
        proxy_buffering off;
        gzip off;
    }
    location = /candidate-health {
        proxy_pass http://127.0.0.1:19578/health;
        add_header Cache-Control no-store always;
    }
"""
  anchor='    location = /health {'
  if original.count(anchor)!=1:raise RuntimeError('Unexpected scoped vhost')
  vhost.write_text(original.replace(anchor,fragment+anchor))
  try:run([nginx,'-t']);run([nginx,'-s','reload'])
  except Exception:vhost.write_text(original);raise
 active=subprocess.run(['systemctl','is-active',unit],capture_output=True,text=True).stdout.strip()
 if active!='active':
  run(['systemd-run','--unit=incense-debt-udp-candidate','--collect','--property=User=incense-debt','--property=Group=incense-debt',
       '--property=WorkingDirectory='+str(candidate),'--property=NoNewPrivileges=true','--property=ProtectSystem=strict',
       '--property=ProtectHome=true','--property=ReadWritePaths='+str(state),'--property=UMask=0077',
       '--property=MemoryMax=256M','--property=MemorySwapMax=0',str(candidate/'IncenseDebtServer.x86_64'),
       '--headless','--max-fps','60','--','--config='+str(candidate/'config.json')])
 ready=None
 for attempt in range(50):
  try:ready=health(19578);break
  except OSError:time.sleep(.1)
 if ready is None:
  # Diagnostic contains engine errors only; neither key nor player files are read.
  diagnostic=run(['journalctl','-u',unit,'--no-pager','-n','30'])
  print(json.dumps({'passed':False,'diagnostic':diagnostic}));raise SystemExit(1)
  print(json.dumps({'passed':ready['version']==version and ready['transport']==2 and ready['battle_encrypted'],
  'action':'stage','candidate_health':ready,'live_health':health(18778),'installed_sha256':sha(candidate/'IncenseDebtServer.x86_64'),
  'udp_port':18779,'candidate_endpoint':'wss://xhz-server.sidcloud.cn/candidate-play',
  'tls_permissions':{name:oct((tls/name).stat().st_mode&0o777) for name in ['fullchain.pem','privkey.pem']}}))
elif payload['action']=='status':
 candidate=None
 try:candidate=health(19578)
 except OSError:pass
 print(json.dumps({'live_health':health(18778),'candidate_health':candidate}))
elif payload['action']=='sync':
 # Refresh an already promoted 0.6.x service while preserving its checkpoint.
 # The live room must be empty so the authoritative state can be flushed first.
 live=health(18778)
 if live.get('connections') or live.get('active_rooms') or live.get('queued'):
  raise RuntimeError('Active players prevent the synchronized release switch')
 source=pathlib.Path(payload['upload'])
 if sha(source)!=payload['sha256']:raise RuntimeError('Upload checksum mismatch')
 old_target=pathlib.Path(os.path.realpath(base/'current'))
 old_binary=old_target/'IncenseDebtServer.x86_64'
 old_hash=sha(old_binary)
 sync_id=payload['sha256'][:16]
 backup=base/'backups'/('sync-'+sync_id)
 backup.mkdir(parents=True,exist_ok=True);backup.chmod(0o700)
 (backup/'previous-target.txt').write_text(str(old_target)+'\n')
 (backup/'previous-sha256.txt').write_text(old_hash+'\n')
 shutil.copyfile(base/'config.json',backup/'config-before-sync.json')
 run(['systemctl','stop','incense-debt.service'])
 if (backup/'player-state').exists():shutil.rmtree(backup/'player-state')
 shutil.copytree('/var/lib/incense-debt',backup/'player-state')
 release=base/'releases'/(payload['version']+'-sync-'+sync_id)
 release.mkdir(parents=True,exist_ok=True)
 target=release/'IncenseDebtServer.x86_64';shutil.copyfile(source,target);target.chmod(0o755)
 stop=release/'stop.sh';stop.write_text(payload['stop_script']);stop.chmod(0o755)
 service_path=pathlib.Path('/etc/systemd/system/incense-debt.service')
 service_path.write_text(payload['public_files']['service']);os.chown(service_path,0,0);service_path.chmod(0o644)
 (base/'config.json').write_text(json.dumps(payload['config'],indent=2)+'\n');(base/'config.json').chmod(0o644)
 run(['systemctl','daemon-reload'])
 link=base/'current-next'
 if link.exists() or link.is_symlink():link.unlink()
 link.symlink_to(release);os.replace(link,base/'current')
 try:
  run(['systemctl','start','incense-debt.service'])
  fresh=None
  for attempt in range(80):
   try:fresh=health(18778);break
   except OSError:time.sleep(.25)
  if not fresh or fresh.get('version')!=payload['version'] or fresh.get('transport')!=2 or not fresh.get('battle_encrypted'):
   raise RuntimeError('Synchronized live server unhealthy')
 except Exception:
  run(['systemctl','stop','incense-debt.service'])
  failed=backup/'failed-player-state'
  if pathlib.Path('/var/lib/incense-debt').exists():os.rename('/var/lib/incense-debt',failed)
  shutil.copytree(backup/'player-state','/var/lib/incense-debt')
  for path in [pathlib.Path('/var/lib/incense-debt'),*pathlib.Path('/var/lib/incense-debt').rglob('*')]:os.chown(path,uid,gid)
  if (base/'current').exists() or (base/'current').is_symlink():(base/'current').unlink()
  (base/'current').symlink_to(old_target)
  shutil.copyfile(backup/'config-before-sync.json',base/'config.json')
  run(['systemctl','daemon-reload']);run(['systemctl','start','incense-debt.service']);raise
 service=run(['systemctl','show','incense-debt.service','--property=ActiveState,SubState,MainPID,NRestarts'])
 print(json.dumps({'passed':True,'action':'sync','health':fresh,'installed_sha256':sha(target),'previous_sha256':old_hash,
  'release':str(release),'backup':str(backup),'service':service,'endpoint':'wss://xhz-server.sidcloud.cn/play','udp_port':18779}))
elif payload['action']=='activate':
 live=health(18778);staged=health(19578)
 if live['connections'] or live['active_rooms'] or staged['connections'] or staged['active_rooms']:
  raise RuntimeError('Active players prevent a scoped release switch')
  if staged['version']!=version or sha(candidate/'IncenseDebtServer.x86_64')!=payload['sha256']:
  raise RuntimeError('Candidate version or checksum changed')
  backup=base/('backups/udp-v'+version);backup.mkdir(parents=True,exist_ok=True);backup.chmod(0o700)
 old_target=os.readlink(base/'current')
 (backup/'previous-target.txt').write_text(old_target+'\n')
 shutil.copyfile(base/'config.json',backup/'config-before-upgrade.json')
 run(['systemctl','stop','incense-debt.service'])
 # Backup only after the previous native service has committed its final checkpoint.
 if not (backup/'player-state').exists():shutil.copytree('/var/lib/incense-debt',backup/'player-state')
 run(['systemctl','stop',unit])
 # Public helpers are installed as root-owned files; credentials remain in the
 # pre-existing private lineage. Only this game's units and web page change.
 destinations={
  'service':'/etc/systemd/system/incense-debt.service',
  'certificate_service':'/etc/systemd/system/incense-debt-certificate.service',
  'certificate_timer':'/etc/systemd/system/incense-debt-certificate.timer',
  'certificate_refresh':'/usr/local/lib/incense-debt/certificate_refresh.py',
  'renewal_hook':'/etc/letsencrypt/renewal-hooks/deploy/incense-debt-nginx-reload',
  'homepage':'/var/www/incense-debt-public/index.html'}
 for name,target in destinations.items():
  path=pathlib.Path(target);path.parent.mkdir(parents=True,exist_ok=True)
  path.write_text(payload['public_files'][name]);os.chown(path,0,0)
  path.chmod(0o755 if name in ['certificate_refresh','renewal_hook'] else 0o644)
 run(['systemctl','daemon-reload'])
  release=base/('releases/'+version);release.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(candidate/'IncenseDebtServer.x86_64',release/'IncenseDebtServer.x86_64');(release/'IncenseDebtServer.x86_64').chmod(0o755)
 (release/'stop.sh').write_text(payload['stop_script']);(release/'stop.sh').chmod(0o755)
 (base/'config.json').write_text(json.dumps(payload['config'],indent=2)+'\n');(base/'config.json').chmod(0o644)
 temp=base/'current-next';temp.symlink_to(release);os.replace(temp,base/'current')
 try:
  run(['systemctl','start','incense-debt.service'])
  fresh=None
  for attempt in range(50):
   try:fresh=health(18778);break
   except OSError:time.sleep(.1)
   if not fresh or fresh['version']!=version or not fresh['battle_encrypted']:raise RuntimeError('New live server unhealthy')
 except Exception:
  run(['systemctl','stop','incense-debt.service'])
  # Restore the coherent private checkpoint and binary together, before any clients enter.
  failed=base/('backups/udp-v'+version+'/failed-player-state')
  os.rename('/var/lib/incense-debt',failed);shutil.copytree(backup/'player-state','/var/lib/incense-debt')
  for path in [pathlib.Path('/var/lib/incense-debt'),*pathlib.Path('/var/lib/incense-debt').rglob('*')]:os.chown(path,uid,gid)
  (base/'current').unlink();(base/'current').symlink_to(old_target)
  shutil.copyfile(backup/'config-before-upgrade.json',base/'config.json');run(['systemctl','start','incense-debt.service']);raise
 # Remove the temporary route by restoring the scoped pre-stage vhost.
 vhost.write_text((backup/'nginx-before-stage.conf').read_text());run([nginx,'-t']);run([nginx,'-s','reload'])
 run(['systemctl','enable','--now','incense-debt-certificate.timer'])
 print(json.dumps({'passed':True,'action':'activate','health':fresh,'installed_sha256':sha(release/'IncenseDebtServer.x86_64'),
  'private_backup_created':True,'previous_version':live['version'],'endpoint':'wss://xhz-server.sidcloud.cn/play','udp_port':18779}))
else:raise RuntimeError('Unknown action')
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['stage', 'status', 'activate', 'sync'])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = ROOT / 'build/server-linux/IncenseDebtServer.x86_64'
    version = re.search(r'config/version="([^"]+)"', (ROOT/'game/project.godot').read_text('utf8')).group(1)
    with binary.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    payload = {'action': args.action, 'version': version, 'sha256': digest,
               'config': json.loads((ROOT/'server/linux/config.production.json').read_text('utf8')),
               'stop_script': (ROOT/'server/linux/stop.sh').read_text('utf8')}
    payload['public_files'] = {name:(ROOT/'server/linux'/path).read_text('utf8') for name,path in {
        'service':'incense-debt.service','certificate_service':'incense-debt-certificate.service',
        'certificate_timer':'incense-debt-certificate.timer','certificate_refresh':'certificate_refresh.py',
        'renewal_hook':'incense-debt-nginx-reload','homepage':'index.html'}.items()}
    spec = importlib.util.spec_from_file_location('private_remote', PRIVATE/'remote.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    client = helper.connect()
    try:
        if args.action in ['stage', 'sync']:
            upload = '/tmp/incense-debt-v' + version + '-' + digest[:16] + '.x86_64'
            with client.open_sftp() as sftp:
                try: existing_size = sftp.stat(upload).st_size
                except OSError: existing_size = -1
                if existing_size != binary.stat().st_size: sftp.put(str(binary), upload)
            payload['upload'] = upload
        stdin, stdout, stderr = client.exec_command('sudo python3 -', timeout=60)
        stdin.write('import json\npayload=json.loads(' + repr(json.dumps(payload)) + ')\n' + REMOTE)
        stdin.flush(); stdin.channel.shutdown_write()
        raw = stdout.read().decode('utf8'); diagnostic = stderr.read().decode('utf8')
        if stdout.channel.recv_exit_status():
            raise RuntimeError('Scoped native deployment failed: ' + raw + diagnostic)
        result = json.loads(raw)
    finally:
        client.close()
    result.update(recorded_at=datetime.now(timezone.utc).isoformat(), virtualization='none')
    output = (args.output or ROOT/'.local-tools/udp-development'/('remote-'+args.action+'.json')).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', 'utf8')
    print(json.dumps(result, ensure_ascii=False))
    return int(result.get('passed') is False)


if __name__ == '__main__':
    raise SystemExit(main())
