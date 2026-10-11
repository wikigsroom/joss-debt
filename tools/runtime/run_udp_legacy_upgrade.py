"""Crash an official 0.5.0 server and restore its untouched data with 0.6.0."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / '.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
LEGACY_TAG = 'v0.5.0'


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def committed_room(data):
    candidates = []
    for path in (data / 'registry').glob('checkpoint_*.json'):
        try:
            envelope = json.loads(path.read_text('utf8'))
            registry = json.loads(envelope['payload'])
            if len(registry.get('room_revisions', {})) != 1:
                continue
            room_id, revision = next(iter(registry['room_revisions'].items()))
            archive = data / 'rooms' / room_id / ('revision_%016d.json' % int(revision))
            room = json.loads(json.loads(archive.read_text('utf8'))['payload'])
            room['_observed_registry_revision'] = int(envelope['revision'])
            candidates.append((int(envelope['revision']), room))
        except (OSError, ValueError, KeyError):
            continue
    return max(candidates, key=lambda item: item[0])[1] if candidates else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy-zip', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    folder = options.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if (folder / 'server/registry').exists():
        raise RuntimeError('Use an unused isolated acceptance directory')
    checks = []

    def check(passed, name):
        checks.append({'id': name, 'passed': bool(passed)})
        if not passed:
            raise RuntimeError('Legacy upgrade failed: ' + name)

    publication = json.loads((ROOT / 'docs/releases/v0.5.0.publication.json').read_text('utf8'))
    asset = next(item for item in publication['assets'] if item['name'] == options.legacy_zip.name)
    check(digest(options.legacy_zip) == asset['digest'].removeprefix('sha256:'), 'official_legacy_zip_verified')
    legacy_exe = folder / 'legacy-server.exe'
    with zipfile.ZipFile(options.legacy_zip) as bundle:
        member = next(name for name in bundle.namelist() if name.endswith('/IncenseDebtServer.exe') or name == 'IncenseDebtServer.exe')
        legacy_exe.write_bytes(bundle.read(member))
    manifest = json.loads((ROOT / 'docs/releases/v0.5.0.manifest.json').read_text('utf8'))
    check(digest(legacy_exe) == manifest['native_server_sha256']['windows'], 'official_legacy_executable_verified')
    legacy_project = folder / 'legacy-project'
    source_paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', LEGACY_TAG, 'game/scripts/core', 'game/scripts/combat', 'game/scripts/network', 'game/data'], cwd=ROOT, text=True).splitlines()
    source_paths += ['game/tests/online_recovery.gd', 'game/tests/cooperative_recovery.gd']
    for name in source_paths:
        if not name.endswith(('.gd', '.json')):
            continue
        destination = legacy_project / name.removeprefix('game/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(subprocess.check_output(['git', 'show', LEGACY_TAG + ':' + name], cwd=ROOT))
    (legacy_project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Isolated legacy upgrade fixture"\nconfig/version="0.5.0"\n[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n', 'utf8')
    data = folder / 'server'
    data.mkdir()
    port = 19277
    process = None
    server_log = (folder / 'server.log').open('wb')
    native_errors = re.compile(r'SCRIPT ERROR|ERROR:|mbedtls error:', re.I)

    def start_server(executable, version):
        nonlocal process
        process = subprocess.Popen([str(executable), '--headless', '--max-fps', '60', '--', '--bind=127.0.0.1', '--port=' + str(port), '--grace=10', '--data-dir=' + str(data)], cwd=ROOT, stdout=server_log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Native server exited during upgrade')
            try:
                with urllib.request.urlopen('http://127.0.0.1:%d/health' % (port + 1), timeout=1) as response:
                    value = json.load(response)
                if value['version'] == version:
                    check(value['transport'] == (1 if version == '0.5.0' else 2), 'actual_transport_' + version)
                    return value
            except OSError:
                pass
            time.sleep(.1)
        raise RuntimeError('Native server health deadline')

    def run_client(stage, legacy=False):
        project = legacy_project if legacy else ROOT / 'game'
        script = 'res://tests/cooperative_recovery.gd' if legacy else 'res://tests/udp_legacy_restore.gd'
        arguments = [str(ENGINE), '--headless', '--max-fps', '60', '--path', str(project), '--script', script, '--', '--folder=' + str(folder / 'clients'), '--stage=' + stage, '--mode=' + ('restore' if legacy else 'expiry'), '--url=ws://127.0.0.1:' + str(port)]
        result = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=100, creationflags=subprocess.CREATE_NO_WINDOW)
        text = result.stdout.decode('utf8', errors='replace')
        (folder / (stage + '-client.log')).write_text(text, 'utf8')
        check(result.returncode == 0 and not native_errors.search(text), 'clean_' + stage + '_native_client')
        return json.loads((folder / 'clients' / (stage + '-' + ('restore' if legacy else 'expiry') + '-report.json')).read_text('utf8'))

    report = {'passed': False, 'checks': checks, 'recorded_at': datetime.now(timezone.utc).isoformat(), 'legacy_tag': LEGACY_TAG,
              'legacy_server_sha256': digest(legacy_exe), 'new_server_sha256': digest(ROOT / 'build/server/IncenseDebtServer.exe'),
              'production_modified': False, 'virtualization': 'none', 'scope': 'Official legacy packaged server, unchanged isolated durable data, new packaged server and actual native clients. Presentation alone uses new wire precision; canonical authoritative match must remain exactly equal.'}
    try:
        start_server(legacy_exe, '0.5.0')
        report['prepare'] = run_client('prepare', legacy=True)
        before = None
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            before = committed_room(data)
            if before and before.get('suspended'):
                break
            time.sleep(.1)
        check(before is not None and before.get('suspended'), 'legacy_paused_checkpoint_committed')
        process.kill(); process.wait(timeout=8)
        before = committed_room(data)
        start_server(ROOT / 'build/server/IncenseDebtServer.exe', '0.6.0')
        deadline = time.monotonic() + 12
        after = None
        while time.monotonic() < deadline:
            after = committed_room(data)
            if after and after.get('suspended') and after['_observed_registry_revision'] > before['_observed_registry_revision']:
                break
            time.sleep(.1)
        check(after is not None and after['_observed_registry_revision'] > before['_observed_registry_revision'], 'new_server_committed_its_restored_generation')
        check(before['match'] == after['match'], 'entire_authoritative_match_exactly_preserved')
        report['restore'] = run_client('restore')
        check(report['prepare']['passed'] and report['restore']['passed'], 'both_identities_growth_entities_receipts_resume_expiry_restored')
        (data / 'stop').touch(); process.wait(timeout=10)
        server_log.flush()
        check(process.returncode == 0 and not native_errors.search((folder / 'server.log').read_text('utf8', errors='replace')), 'clean_native_servers')
        report['passed'] = True
    finally:
        if process is not None and process.poll() is None:
            process.kill(); process.wait(timeout=8)
        server_log.close()
        (folder / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf8')
    print(json.dumps(report, ensure_ascii=False))
    return int(not report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
