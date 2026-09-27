#!/usr/bin/env python3
"""Real ESP diagnostic replacement and request history, on disposable sites."""
import argparse
import json
import pathlib
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def run(args, incremental):
    with tempfile.TemporaryDirectory(prefix="esp-diagnostics-") as tmp:
        root = pathlib.Path(tmp)
        site = root / "Site"
        site.mkdir()
        (site / "Bin").mkdir()
        shutil.copy2(args.web_dll, site / "Bin/Elements.Web.dll")
        (site / "Web.config").write_text('<configuration><esp.projectSettings><TargetFramework>.NETCore10.0</TargetFramework></esp.projectSettings></configuration>')
        page = site / "Default.aspx"
        good = '<%@ Page Language="Oxygene" %>working'
        warning = good + '<%= RemObjects.Elements.RTL.DateTime.UtcNow.AddMinutes(1) %>'
        page.write_text(warning)
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]

        def get(path):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=30) as response:
                    return response.status, response.read().decode()
            except urllib.error.HTTPError as error:
                return error.code, error.read().decode()

        def diagnostics():
            return json.loads(get('/__esp/diagnostics?format=json')[1])

        def wait(check):
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise AssertionError(log.read_text())
                try:
                    value = check()
                    if value:
                        return value
                except (OSError, ValueError):
                    pass
                time.sleep(.15)
            raise AssertionError(log.read_text()[-10000:])

        log = root / "host.log"
        with log.open('w') as output:
            proc = subprocess.Popen([
                str(args.ebuild), '--serve-web-project', str(site), '--configuration:Debug',
                f'--port:{port}', f'--setting:EBuild:ElementsCompilerDll={args.compiler}',
                f'--setting:ESPIncrementalRecompilation={incremental}',
                '--setting:ESPServeLastGood=False', '--setting:ESPDebugMode=True',
            ], stdout=output, stderr=subprocess.STDOUT)
            try:
                wait(lambda: diagnostics().get('activeGeneration', 0) > 0)
                assert get('/')[0] == 200
                current = wait(lambda: (d if any(x['severity'] == 'Warning' for x in d['diagnostics']) else None) if (d := diagnostics()) else None)
                assert 'AddMinutes' in json.dumps(current), current
                generation = current['generation']
                page.write_text(good + '<%= unknown_diagnostics_identifier %>')
                wait(lambda: diagnostics()['generation'] > generation)
                if incremental:
                    wait(lambda: get('/')[0] == 500)
                broken = wait(lambda: (d if any(x['severity'] == 'Error' for x in d['diagnostics']) else None) if (d := diagnostics()) else None)
                assert 'unknown_diagnostics_identifier' in json.dumps(broken), broken
                history = json.loads(get('/__esp/errors?format=json')[1])['errors']
                if incremental:
                    assert any(x['path'] == '/' and x['status'] == 500 for x in history), history
                else:
                    assert get('/')[0] == 200  # Full mode retains its previous generation.
                generation = broken['generation']
                page.write_text(good)
                wait(lambda: diagnostics()['generation'] > generation)
                wait(lambda: get('/')[0] == 200)
                wait(lambda: not diagnostics()['diagnostics'])
                history_after = json.loads(get('/__esp/errors?format=json')[1])['errors']
                assert len(history_after) >= len(history)
                assert get('/__esp/diagnostics')[0] == 200
                assert get('/__esp/errors')[0] == 200
                print(f'PASS {"lazy" if incremental else "full"}: warnings, build failure, correction clears diagnostics; existing request behavior and history preserved', flush=True)
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ebuild', type=pathlib.Path, required=True)
    parser.add_argument('--compiler', type=pathlib.Path, required=True)
    parser.add_argument('--web-dll', type=pathlib.Path, required=True)
    args = parser.parse_args()
    for incremental in (True, False):
        run(args, incremental)
