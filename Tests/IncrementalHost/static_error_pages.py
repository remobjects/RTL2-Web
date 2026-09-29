#!/usr/bin/env python3
"""Static httpErrors during startup, normal requests and publication restoration.

Uses disposable sites and only terminates hosts started by this script.
"""
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ebuild', required=True)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--full', action='store_true')
    args = parser.parse_args()
    root = pathlib.Path(tempfile.mkdtemp(prefix='esp-static-errors-')).resolve()
    expected = '<html>Accepted maintenance page.</html>'
    config = '''<configuration>
      <esp.projectSettings><TargetFramework>.NETCore10.0</TargetFramework></esp.projectSettings>
      <system.webServer><httpErrors errorMode="Custom">
        <error statusCode="404" path="/503.html" responseMode="File"/>
        <error statusCode="500" path="/503.html" responseMode="File"/>
        <error statusCode="503" path="/503.html" responseMode="File"/>
      </httpErrors></system.webServer>
    </configuration>'''
    for trigger in (False, True):
        folder = root / ('publication' if trigger else 'ordinary')
        site = folder / 'site'
        (site / 'Bin').mkdir(parents=True)
        shutil.copyfile(args.runtime, site / 'Bin/Elements.Web.dll')
        (site / 'Web.config').write_text(config)
        (site / '503.html').write_text(expected)
        (site / 'Default.aspx').write_text('<%@ Page Language="Oxygene" %>ready')
        (site / 'Boom.aspx').write_text('<%@ Page Language="Oxygene" %><% raise new Exception("original failure"); %>')
        (site / 'Status.ashx').write_text('''<%@ WebHandler Language="Oxygene" Class="StatusHandler" %>
namespace;
uses RemObjects.Elements.Web;
type StatusHandler = public class(IHttpHandler)
public
  method ProcessRequest(c: WebContext);
  begin
    c.Response.StatusCode := 503;
    c.Response.Write("original body");
  end;
end;
end.''')
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        base = f'http://127.0.0.1:{port}'
        command = [args.ebuild, '--serve-web-project', str(site), '--configuration:Debug',
                   f'--port:{port}', '--setting:ESPDebugMode=False',
                   '--setting:ESPIncrementalRecompilation=' + str(not args.full),
                   '--setting:AdditionalReferencePaths=' + str(pathlib.Path(args.runtime).resolve().parent),
                   '--setting:EBuild:ElementsCompilerDll=' + args.compiler]
        if trigger:
            command += ['--require-trigger', '--auth-token:static-error-test',
                        '--setting:ESPPublicationFolder=' + str(folder / 'state')]
        process = None
        log = (folder / 'host.log').open('w')

        def request(path, method='GET', auth=False):
            headers = {'Authorization': 'Bearer static-error-test'} if auth else {}
            req = urllib.request.Request(base + path, method=method, headers=headers)
            try:
                response = urllib.request.urlopen(req, timeout=5)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, response.read().decode(), response.headers

        def wait(check):
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                assert process.poll() is None, (folder / 'host.log').read_text()
                try:
                    if check():
                        return
                except (OSError, TimeoutError):
                    pass
                time.sleep(.02)
            raise AssertionError('Timed out; see ' + str(folder / 'host.log'))

        def start():
            nonlocal process
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)

        def stop():
            if process and process.poll() is None:
                process.terminate()
                process.wait(timeout=15)

        def placeholder():
            code, body, headers = request('/')
            assert (code, body) == (503, expected), ('First startup response', code, body)
            if code == 503 and body == expected:
                assert headers['Cache-Control'] == 'no-store'
                assert headers['Content-Type'].startswith('text/html')
                return True
            return False

        try:
            start()
            if trigger:
                wait(lambda: request('/')[0] == 503)
                assert expected not in request('/')[1], 'Unpublished incoming placeholder leaked'
                code, body, _ = request('/__esp/update', method='POST', auth=True)
                assert code == 202, (code, body)
                operation = json.loads(body)['id']
                wait(lambda: json.loads(request('/__esp/status?format=json&operation=' + operation, auth=True)[1])['operation']['state'] == 'accepted')
            else:
                wait(placeholder)
            wait(lambda: request('/')[:2] == (200, 'ready'))
            for path, status in [('/missing', 404), ('/Boom.aspx', 500), ('/Status.ashx', 503)]:
                code, body, headers = request(path)
                assert (code, body) == (status, expected), (path, code, body)
                assert headers['Cache-Control'] == 'no-store'
                assert request(path, method='HEAD')[:2] == (status, '')
            assert request('/__esp/health')[0] == 200
            assert request('/__esp/unknown')[0] == 404
            if trigger:
                stop()
                (site / '503.html').write_text('UNPUBLISHED FILE')
                (site / 'unpublished.html').write_text('UNPUBLISHED CONFIG')
                (site / 'Web.config').write_text(config.replace('/503.html', '/unpublished.html'))
                start()
                wait(placeholder)
                wait(lambda: request('/')[:2] == (200, 'ready'))
                assert request('/missing')[:2] == (404, expected)
            print('PASS', 'publication restoration' if trigger else 'ordinary startup', 'full' if args.full else 'incremental')
        finally:
            stop()
            log.close()
    print('Fixtures and logs:', root)


if __name__ == '__main__':
    main()
