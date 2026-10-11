#!/bin/bash
set -eu
touch /var/lib/incense-debt/stop
if [[ ! ${MAINPID:-} =~ ^[1-9][0-9]*$ ]]; then exit 0; fi
for ((i=0; i<64; i++)); do
    if ! kill -0 "${MAINPID:-0}" 2>/dev/null; then exit 0; fi
    sleep 0.25
done
exit 1
