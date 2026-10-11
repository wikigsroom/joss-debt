#!/usr/bin/python3
"""Rotate only this game's DTLS files; restart only when its own service is idle."""
import argparse
import hashlib
import os
from pathlib import Path
import grp
import subprocess
import tempfile
import time
import urllib.request
import json
import fcntl

LINEAGE = Path('/etc/letsencrypt/live/incense-debt-public')
TLS = Path('/etc/incense-debt/tls')
MARKER = TLS / 'restart-pending'
DOMAIN = 'xhz-server.sidcloud.cn'


def command(arguments):
    run = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    if run.returncode:
        raise RuntimeError('Certificate operation failed: ' + arguments[1])
    return run.stdout


def validate(folder):
    cert = str(folder / 'fullchain.pem')
    key = str(folder / 'privkey.pem')
    command(['/usr/bin/openssl', 'x509', '-in', cert, '-checkhost', DOMAIN, '-noout'])
    command(['/usr/bin/openssl', 'x509', '-in', cert, '-checkend', '86400', '-noout'])
    command(['/usr/bin/openssl', 'verify', '-CApath', '/etc/ssl/certs', '-untrusted', cert, cert])
    public_cert = command(['/usr/bin/openssl', 'x509', '-in', cert, '-pubkey', '-noout'])
    public_key = command(['/usr/bin/openssl', 'pkey', '-in', key, '-pubout'])
    if public_cert != public_key:
        raise RuntimeError('Certificate and private key do not match')


def atomic_write(destination, data, group_id, mode):
    descriptor, name = tempfile.mkstemp(prefix='.pending-', dir=TLS)
    temporary = Path(name)
    try:
        os.fchown(descriptor, 0, group_id)
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def refresh():
    validate(LINEAGE)
    group_id = grp.getgrnam('incense-debt').gr_gid
    TLS.mkdir(exist_ok=True, parents=True)
    os.chown(TLS, 0, group_id)
    TLS.chmod(0o750)
    certificate = (LINEAGE / 'fullchain.pem').read_bytes()
    private = (LINEAGE / 'privkey.pem').read_bytes()
    # The service reads the pair only at startup. Publish the marker after both
    # atomic replacements, so an idle restart never sees a partly rotated pair.
    atomic_write(TLS / 'fullchain.pem', certificate, group_id, 0o640)
    atomic_write(TLS / 'privkey.pem', private, group_id, 0o640)
    atomic_write(MARKER, hashlib.sha256(certificate).hexdigest().encode() + b'\n', 0, 0o600)


def health():
    with urllib.request.urlopen('http://127.0.0.1:18778/health', timeout=3) as response:
        return json.load(response)


def apply_pending():
    if not MARKER.exists():
        return 'no_pending_rotation'
    before = health()
    if before.get('transport') != 2 or before.get('connections') or before.get('active_rooms'):
        return 'deferred_until_game_service_is_idle'
    validate(TLS)
    command(['/usr/bin/systemctl', 'restart', 'incense-debt.service'])
    for attempt in range(40):
        try:
            after = health()
            if after.get('transport') == 2 and after.get('battle_encrypted'):
                MARKER.unlink(missing_ok=True)
                return 'idle_game_service_restarted'
        except OSError:
            pass
        time.sleep(.25)
    raise RuntimeError('Game service did not recover after certificate rotation')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renewed-lineage')
    parser.add_argument('--apply-pending', action='store_true')
    arguments = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('Certificate rotation requires the installed root service')
    if arguments.renewed_lineage is not None and Path(arguments.renewed_lineage) != LINEAGE:
        return
    TLS.mkdir(exist_ok=True, parents=True)
    descriptor = os.open(TLS / '.rotation.lock', os.O_CREAT | os.O_RDWR, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if arguments.renewed_lineage is not None:
            refresh()
        if arguments.apply_pending:
            print(apply_pending())
    finally:
        os.close(descriptor)


if __name__ == '__main__':
    main()
