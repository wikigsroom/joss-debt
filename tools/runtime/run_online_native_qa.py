"""Run the real native online menu/input flow against a running native server."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:18777")
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--cooperative", action="store_true")
    parser.add_argument("--public-exit-wait", action="store_true", help="Use an external fixture that awaits the WAN leave acknowledgement")
    parser.add_argument("--performance", action="store_true", help="Observe actual cooperative rendering and key-to-visible feedback without changing game bytecode")
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    folder = options.output or ROOT / ".local-tools/online-development" / ("native-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    folder = folder.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    engine = ROOT / ("build/windows/IncenseDebt.exe" if options.packaged else ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    args = [str(engine), "--max-fps", "60", "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3", "--resolution", "1280x720", "--position", "-16000,-16000"]
    if not options.packaged:
        args += ["--path", str(ROOT / "game")]
    fixture_path = None
    if options.performance:
        if not options.packaged or not options.cooperative or options.public_exit_wait:
            raise ValueError('Performance observation requires the packaged cooperative client')
        fixture_path = ROOT/'tools/runtime/measure_online_feedback.gd'
        args[0] = str(ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
        args += ["--main-pack", str(engine), "--script", str(ROOT / "game/tests/online_native_external.gd")]
        args += ["--", "--qa-layout", "--external-fixture=" + str(fixture_path)]
    elif options.public_exit_wait:
        if not options.packaged or options.cooperative:
            raise ValueError("The exit-wait fixture is for packaged Duel acceptance")
        source = (ROOT / "game/scripts/ui/online_native_qa.gd").read_text("utf8")
        original = '\tawait activate("online_return")\n\tawait activate("online_code")'
        if source.count(original) != 1:
            raise RuntimeError("The native fixture leave transition changed")
        source = source.replace(original, '\tawait activate("online_return")\n\tawait until(func(): return app.online.session.room.is_empty() and app.online.session.state == "online")\n\tawait activate("online_code")')
        fixture_path = folder / "duel-wan-fixture.gd"
        fixture_path.write_text(source, "utf8")
        args[0] = str(ROOT / ".local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe")
        args += ["--main-pack", str(engine), "--script", str(ROOT / "game/tests/online_native_external.gd")]
        args += ["--", "--qa-layout", "--external-fixture=" + str(fixture_path)]
    else:
        args += ["--", "--qa-coop" if options.cooperative else "--qa-online"]
    args += ["--qa-output=" + str(folder), "--online-url=" + options.url]
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    proc = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        output, _ = proc.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        proc.kill()
        output, _ = proc.communicate(timeout=5)
        (folder / "online-native.log").write_bytes(output)
        raise RuntimeError("Native online QA exceeded its time limit; the test process was closed.")
    log = output.decode("utf8", errors="replace")
    (folder / "online-native.log").write_text(log, "utf8")
    print(log)
    path = folder / "online-native.json"
    if not path.is_file():
        return 1
    report = json.loads(path.read_text("utf8"))
    report.update(recorded_at=datetime.now(timezone.utc).isoformat(), packaged=options.packaged, transport_endpoint=options.url)
    if fixture_path:
        report.update(external_acceptance_fixture=True, fixture_sha256=hashlib.sha256(fixture_path.read_bytes()).hexdigest(), fixture_change="Observe rendering and local keyboard feedback" if options.performance else "Wait for the actual server leave acknowledgement before navigating the hub; production bytecode unchanged")
    if options.packaged:
        with engine.open("rb") as source:
            report["artifact_sha256"] = hashlib.file_digest(source, "sha256").hexdigest()
    if options.performance and (folder/'render-input.json').is_file():
        performance = json.loads((folder/'render-input.json').read_text('utf8'))
        performance.update(artifact_sha256=report['artifact_sha256'], fixture_sha256=report['fixture_sha256'], transport_endpoint=options.url, recorded_at=report['recorded_at'])
        (folder/'render-input.json').write_text(json.dumps(performance,ensure_ascii=False,indent=2)+'\n','utf8')
    if proc.returncode or "SCRIPT ERROR" in log or "ERROR:" in log or "mbedtls error:" in log:
        report["passed"] = False
        report["failures"].append({"id": "native_execution", "passed": False, "detail": "See online-native.log"})
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf8")
    print(json.dumps({"passed": report["passed"], "checks": len(report["checks"]), "captures": len(report["captures"]), "failures": report["failures"], "report": str(path)}, ensure_ascii=False))
    return int(not report["passed"] or not all(c["saved"] for c in report["captures"]))


if __name__ == "__main__":
    raise SystemExit(main())
