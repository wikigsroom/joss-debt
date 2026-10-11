"""Run actual authoritative cooperative sessions through native UDP impairment."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import json
import hashlib
from concurrent.futures import ThreadPoolExecutor
from run_network_reselection_probe import ROOT, run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--output', type=Path, default=ROOT / '.local-tools/udp-development/battle-qa')
    parser.add_argument('--case', choices=['all', 'loopback', 'rtt100-loss3', 'rtt200-loss5', 'rtt350-loss10', 'duplicate-reorder', 'burst300ms', 'burst1s', 'burst3s'], default='all')
    parser.add_argument('--cases', nargs='+', choices=['loopback', 'rtt100-loss3', 'rtt200-loss5', 'rtt350-loss10', 'duplicate-reorder', 'burst300ms', 'burst1s', 'burst3s'])
    parser.add_argument('--seconds', type=float, default=8)
    parser.add_argument('--parallel', type=int, choices=[1, 2, 3], default=1)
    parser.add_argument('--main-pack', type=Path, help='Use the actual exported client bytecode and resources')
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    cases = [('loopback', 0, 0, 0, 0, 0), ('rtt100-loss3', 50, 20, .03, 0, 0), ('rtt200-loss5', 100, 35, .05, 0, 0),
             ('rtt350-loss10', 175, 50, .1, 0, 0), ('duplicate-reorder', 50, 50, .03, .1, 0),
             ('burst300ms', 50, 20, .03, 0, .3), ('burst1s', 50, 20, .03, 0, 1), ('burst3s', 50, 20, .03, 0, 3)]
    selected = [(index, case) for index, case in enumerate(cases) if (case[0] in args.cases if args.cases else args.case in ('all', case[0]))]
    if args.seconds > 10 and any(case[5] for _, case in selected):
        raise ValueError('Long transport windows require continuous-link cases; burst recovery uses the short dedicated fixture')
    def execute(item):
        index, case = item
        return run_case(args.godot.resolve(), folder, index, *case[:4], script=ROOT / 'game/tests/udp_battle.gd', deadline=args.seconds+120, duplicates=case[4], burst_seconds=case[5], duration_seconds=args.seconds, main_pack=args.main_pack.resolve() if args.main_pack else None)
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        reports = list(pool.map(execute, selected))
    result = {'passed': all(case['passed'] for case in reports), 'recorded_at': datetime.now(timezone.utc).isoformat(),
              'scope': 'Actual development ServerRuntime and OnlineSession cooperative gameplay through real UDP datagram delay/jitter/loss. Native Windows headless; isolated state. Not shipping-package, WAN, Android or rendering acceptance.',
              'production_modified': False, 'virtualization': 'none', 'cases': reports}
    result.update(requested_combat_seconds=args.seconds, native_process_parallelism=args.parallel,
                  compiled_client_pack=bool(args.main_pack), client_sha256=hashlib.sha256(args.main_pack.read_bytes()).hexdigest() if args.main_pack else None,
                  fixture_sha256=hashlib.sha256((ROOT/'game/tests/udp_battle.gd').read_bytes()).hexdigest())
    if args.main_pack:
        result['scope']='Actual exported client bytecode, native test runner, authoritative cooperative transport and an external UDP impairment proxy. An invulnerable room isolates transport; full campaigns, server performance, rendering and WAN have separate acceptance.'
    (folder / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
