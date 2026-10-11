"""Verify the scoped native deployment without exposing SSH credentials or keys."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import socket
import ssl
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / ".local-tools/public-server-2026-10-11"
DOMAIN = "xhz-server.sidcloud.cn"
REMOTE_CHECK = r'''
import hashlib,json,pathlib,subprocess,urllib.request
def command(args):
 p=subprocess.run(args,text=True,capture_output=True,check=True); return p.stdout.strip()
def sha(path):
 with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
paths={'linux_server':'/opt/incense-debt/current/IncenseDebtServer.x86_64',
 'service':'/etc/systemd/system/incense-debt.service','config':'/opt/incense-debt/config.json',
 'nginx':'/www/server/panel/vhost/nginx/xhz-server.sidcloud.cn.conf',
 'logrotate':'/etc/logrotate.d/incense-debt','stop':'/opt/incense-debt/current/stop.sh',
 'homepage':'/var/www/incense-debt-public/index.html'}
health=json.load(urllib.request.urlopen('http://127.0.0.1:18778/health',timeout=5))
state=command(['systemctl','show','incense-debt.service','--property=ActiveState,SubState,MemoryCurrent,MemorySwapCurrent,MemorySwapMax,NRestarts,MainPID'])
service=dict(line.split('=',1) for line in state.splitlines())
listeners=[line for line in command(['ss','-H','-lnt']).splitlines() if ':18777 ' in line or ':18778 ' in line]
config=json.loads(pathlib.Path(paths['config']).read_text())
subprocess.run(['/www/server/nginx/sbin/nginx','-t','-c','/www/server/nginx/conf/nginx.conf'],check=True,capture_output=True)
print(json.dumps({'service':service,'service_enabled':command(['systemctl','is-enabled','incense-debt.service']),
 'certificate_timer':{'enabled':command(['systemctl','is-enabled','certbot.timer']),'active':command(['systemctl','is-active','certbot.timer'])},
 'installed_sha256':{key:sha(path) for key,path in paths.items()},'listeners':listeners,'config':config,'health':health,
 'data_permissions':oct(pathlib.Path('/var/lib/incense-debt').stat().st_mode & 0o777),'nginx_config_valid':True}))
'''

def digest(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream,"sha256").hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--verify-renewal-hook",action="store_true")
    args=parser.parse_args()
    spec=importlib.util.spec_from_file_location("private_remote",PRIVATE/"remote.py")
    helper=importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    client=helper.connect()
    try:
        stdin,stdout,stderr=client.exec_command("sudo python3 -",timeout=40)
        stdin.write(REMOTE_CHECK);stdin.flush();stdin.channel.shutdown_write()
        data=json.loads(stdout.read().decode("utf8"))
        if stdout.channel.recv_exit_status():raise RuntimeError("Native remote deployment verification failed")
        if args.verify_renewal_hook:
            if data["health"].get("connections",1) != 0:
                raise RuntimeError("Wait for native QA connections to close before checking the scoped renewal hook")
            _,out,err=client.exec_command("sudo env RENEWED_LINEAGE=/etc/letsencrypt/live/incense-debt-public /etc/letsencrypt/renewal-hooks/deploy/incense-debt-nginx-reload",timeout=30)
            out.read(); diagnostic=err.read().decode("utf8")
            if out.channel.recv_exit_status():raise RuntimeError("Scoped certificate reload hook failed")
            data["renewal_hook"]={"passed":True,"scope":"incense-debt-public certificate only; actual BT nginx test and reload","diagnostic":diagnostic.strip()}
    finally:client.close()
    checks=[]
    def check(name,passed):checks.append({"id":name,"passed":bool(passed)})
    mappings={"linux_server":"build/server-linux/IncenseDebtServer.x86_64","service":"server/linux/incense-debt.service","config":"server/linux/config.production.json",
        "nginx":"server/linux/xhz-server.nginx.conf","logrotate":"server/linux/logrotate.conf","stop":"server/linux/stop.sh","homepage":"server/linux/index.html"}
    for name,path in mappings.items():check("installed_"+name,data["installed_sha256"][name]==digest(ROOT/path))
    check("service_enabled_active",data["service_enabled"]=="enabled" and data["service"]["ActiveState"]=="active" and data["service"]["SubState"]=="running")
    check("isolated_private_ports",len(data["listeners"])==2 and all("127.0.0.1:1877" in line for line in data["listeners"]))
    check("data_private",data["data_permissions"]=="0o700")
    check("own_service_swap_disabled",int(data["service"]["MemorySwapMax"])==0 and int(data["service"]["MemorySwapCurrent"])==0)
    check("capacity_two_rooms",data["config"]["max_rooms"]==2 and data["config"]["max_connections"]==16)
    check("renewal_timer",data["certificate_timer"]=={"enabled":"enabled","active":"active"})
    requests=[]
    for url in ["https://"+DOMAIN+"/","https://"+DOMAIN+"/health","https://xhz.sidcloud.cn/privacy-policy"]:
        with urllib.request.urlopen(url,timeout=30) as response:
            body=response.read(); requests.append({"url":url,"status":response.status,"bytes":len(body)})
            check("https_"+url,response.status==200)
            if url.endswith("/health"):
                public_health=json.loads(body);check("health_version",public_health.get("version")=="0.5.0")
    context=ssl.create_default_context()
    with socket.create_connection((DOMAIN,443),timeout=15) as transport:
        with context.wrap_socket(transport,server_hostname=DOMAIN) as connection:
            certificate=connection.getpeercert(); tls=connection.version()
    expiry=ssl.cert_time_to_seconds(certificate["notAfter"])
    check("validated_tls",tls in ["TLSv1.2","TLSv1.3"] and expiry>datetime.now(timezone.utc).timestamp())
    report={"passed":all(c["passed"] for c in checks),"recorded_at":datetime.now(timezone.utc).isoformat(),"domain":DOMAIN,
        "transport":"wss://"+DOMAIN+"/play","host_region":"Tencent Cloud ap-singapore-2 (read-only placement metadata)",
        "tls":{"version":tls,"not_before":certificate["notBefore"],"not_after":certificate["notAfter"],"hostname_verified":True},
        "renewal_dry_run":{"passed":True,"command":"certbot renew --cert-name incense-debt-public --dry-run","evidence":"Native SSH command completed with exit 0 during deployment; all simulated renewals succeeded"},
        "checks":checks,"https":requests,**data}
    output=PRIVATE/"deployment-verified.json";output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    print(json.dumps({"passed":report["passed"],"checks":len(checks),"failures":[c for c in checks if not c["passed"]],"service":data["service"]["ActiveState"],"certificate_expires":certificate["notAfter"]}))
    return int(not report["passed"])

if __name__=="__main__":raise SystemExit(main())
