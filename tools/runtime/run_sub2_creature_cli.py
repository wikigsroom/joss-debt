"""Execute the configured skill CLI with a patient, process-local HTTP timeout.

The skill file and credentials are never inspected, changed, copied or logged.
Only urllib's timeout is adjusted; endpoint, model, quality and arguments remain
the configured CLI's responsibility. This does not alter another Python process.
"""
from pathlib import Path
import runpy
import sys
import urllib.request

CLI = Path("C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py")
TIMEOUT_FLOOR = 540
original_urlopen = urllib.request.urlopen


def patient_urlopen(*args, **kwargs):
    positional = list(args)
    if len(positional) >= 3:
        positional[2] = max(TIMEOUT_FLOOR, positional[2]) if isinstance(positional[2], (float, int)) else TIMEOUT_FLOOR
    else:
        requested = kwargs.get("timeout", TIMEOUT_FLOOR)
        kwargs["timeout"] = max(TIMEOUT_FLOOR, requested) if isinstance(requested, (float, int)) else TIMEOUT_FLOOR
    return original_urlopen(*positional, **kwargs)


if __name__ == "__main__":
    urllib.request.urlopen = patient_urlopen
    sys.argv = [str(CLI), *sys.argv[1:]]
    print("Configured Sub2 CLI; process-local HTTP timeout floor: 540 seconds.", flush=True)
    runpy.run_path(str(CLI), run_name="__main__")
