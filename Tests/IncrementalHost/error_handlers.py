#!/usr/bin/env python3
"""Exercise application discovery and both error signatures in real ESP hosts."""
import argparse
import http.cookiejar
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def run(args, incremental, legacy, application_format):
    with tempfile.TemporaryDirectory(prefix="esp-application-error-") as folder:
        site = Path(folder)
        (site / "Bin").mkdir()
        (site / "App_Code").mkdir()
        shutil.copy2(args.web_dll, site / "Bin/Elements.Web.dll")
        (site / "Web.config").write_text(f'''<configuration>
<esp.projectSettings><TargetFramework>.NETCore10.0</TargetFramework>
<ESPIncrementalRecompilation>{incremental}</ESPIncrementalRecompilation>
<ESPServeLastGood>False</ESPServeLastGood><ESPDebugMode>True</ESPDebugMode>
</esp.projectSettings><system.webServer><httpErrors errorMode="Custom">
<error statusCode="500" path="/error.aspx" responseMode="ExecuteURL"/>
</httpErrors></system.webServer></configuration>''')
        signature = ("aSender: Object; aArgs: EventArgs" if legacy else
                     "aError: WebErrorContext")
        value = ('''new WebErrorContext(Server.GetLastError, Request.Url.ToAbsoluteString,
          "GET", Request.Path)''' if legacy else "aError")
        end_marker = site / "application-ended.txt"
        members = f"""
    method Application_Start(sender: Object; e: EventArgs);
    begin
      ErrorState.ApplicationStarts := ErrorState.ApplicationStarts+1;
      Application["Started"] := "yes";
    end;
    method Application_End(sender: Object; e: EventArgs);
    begin
      System.IO.File.WriteAllText("{end_marker}", ErrorState.ApplicationStarts.ToString+":"+ErrorState.SessionEnds.ToString);
    end;
    method Application_Error({signature});
    begin
      ErrorState.LastError := {value};
      ErrorState.Calls := ErrorState.Calls+1;
    end;
    method Session_Start(sender: Object; e: EventArgs);
    begin
      Session["Random"] := new Random;
      ErrorState.SessionStarts := ErrorState.SessionStarts+1;
    end;
    method Session_End(sender: Object; e: EventArgs);
    begin
      ErrorState.SessionEndHadRandom := assigned(Session["Random"]);
      ErrorState.SessionEnds := ErrorState.SessionEnds+1;
    end;
"""
        if not legacy:
            members += """
    method Application_Error(sender: Object; e: EventArgs);
    begin
      ErrorState.Calls := ErrorState.Calls+100;
    end;
"""
        (site / "App_Code/ErrorState.pas").write_text('''namespace;
uses RemObjects.Elements.Web;
type
  ErrorState = public class
  public
    class property LastError: WebErrorContext;
    class property Calls: Integer;
    class property ApplicationStarts: Integer;
    class property SessionStarts: Integer;
    class property SessionEnds: Integer;
    class property SessionEndHadRandom: Boolean;
  end;
end.''')
        if application_format == "inline":
            (site / "Global.asax").write_text(
                '<%@ Application Language="Oxygene" %>\n<script runat="server">\n' + members + '\n</script>')
        else:
            (site / "App_Code/Global.pas").write_text(f'''namespace;
uses RemObjects.Elements.Web;
type
  Global = public class(WebApplication)
  protected
{members}
  end;
end.''')
            if application_format == "inherits":
                (site / "Global.asax").write_text('<%@ Application Language="Oxygene" Inherits="Global" %>')
        (site / "Default.aspx").write_text('<%@ Page Language="Oxygene" %><% raise new Exception("original failure"); %>')
        (site / "status.aspx").write_text('<%@ Page Language="Oxygene" %><% Response.StatusCode := 500; %>')
        (site / "session-state.aspx").write_text('''<%@ Page Language="Oxygene" %><% var lSession := Session; %><%= ErrorState.ApplicationStarts %>:<%= Application["Started"] %>:<%= ErrorState.SessionStarts %>:<%= if assigned(lSession["Random"]) then "random" else "missing" %>:<%= ErrorState.SessionEnds %>''')
        (site / "abandon.aspx").write_text('<%@ Page Language="Oxygene" %><% Session.Abandon; %><%= ErrorState.SessionEnds %>:<%= ErrorState.SessionEndHadRandom %>')
        (site / "expire.aspx").write_text('<%@ Page Language="Oxygene" %><% Session.Timeout := 0; %>expired')
        (site / "error.aspx").write_text('<%@ Page Language="Oxygene" %><%= ErrorState.Calls %>:<%= ErrorState.LastError.Exception.Message %>:<%= ErrorState.LastError.RequestUrl %>')
        (site / "broken.aspx").write_text('<%@ Page Language="Oxygene" %><% unknown_identifier_for_error_test; %>')
        # Full builds need a valid initial generation. Lazy builds can notify on
        # the first request to an independently broken page.
        if not incremental:
            (site / "broken.aspx").unlink()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]

        def get(path):
            try:
                response = urllib.request.urlopen(f"http://localhost:{port}{path}", timeout=30)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, response.read().decode()

        with (site / "host.log").open("w") as log:
            process = subprocess.Popen([
                args.ebuild, "--serve-web-project", str(site), f"--port:{port}",
                "--configuration:Debug", f"--setting:EBuild:ElementsCompilerDll={args.compiler}",
                f"--intermediatebasefolder:{site / 'obj'}"
            ], stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise AssertionError("Host exited")
                    try:
                        if json.loads(get('/__esp/diagnostics?format=json')[1])["activeGeneration"] > 0:
                            break
                    except (OSError, KeyError, ValueError):
                        pass
                    time.sleep(.1)
                else:
                    raise AssertionError("Host never published an application")
                code, body = get('/?original=yes')
                assert code == 500 and f'1:original failure:http://localhost:{port}/?original=yes' in body, (code, body)
                code, body = get('/status')
                assert code == 500 and '1:original failure:' in body, (code, body)
                opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
                def session_get(path):
                    with opener.open(f"http://localhost:{port}{path}", timeout=30) as response:
                        return response.read().decode()
                assert session_get('/session-state') == '1:yes:1:random:0'
                assert session_get('/session-state') == '1:yes:1:random:0'
                assert session_get('/abandon') == '1:True'
                assert session_get('/session-state') == '1:yes:2:random:1'
                assert session_get('/expire') == 'expired'
                assert session_get('/session-state') == '1:yes:3:random:2'
                if incremental:
                    code, body = get('/broken')
                    assert code == 500 and '2:Compilation failed.' in body, (code, body)
                assert get('/Global.asax')[0] == 404, "Application source must not be public"
                if application_format == "inline" and incremental and not legacy:
                    generation = json.loads(get('/__esp/diagnostics?format=json')[1])["activeGeneration"]
                    page = site / "status.aspx"
                    page.write_text(page.read_text() + "\n")
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        if json.loads(get('/__esp/diagnostics?format=json')[1])["activeGeneration"] > generation:
                            break
                        time.sleep(.1)
                    else:
                        raise AssertionError("Page edit did not publish a new generation")
                    assert not end_marker.exists(), "Page-only update ended the application lifetime"
                    assert session_get('/session-state') == '1:yes:3:random:2'
                if application_format != "class":
                    generation = json.loads(get('/__esp/diagnostics?format=json')[1])["activeGeneration"]
                    application = site / "Global.asax"
                    application.write_text(application.read_text() + "\n")
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        current = json.loads(get('/__esp/diagnostics?format=json')[1])["activeGeneration"]
                        if current > generation:
                            break
                        time.sleep(.1)
                    else:
                        raise AssertionError("Global.asax edit did not rebuild the application")
                    code, body = get('/?reloaded=yes')
                    assert code == 500 and '1:original failure:' in body, (code, body)
                    assert end_marker.read_text() == '1:3', "Session_End or Application_End did not run on generation retirement"
                if application_format == "inline" and incremental and not legacy:
                    application = site / "Global.asax"
                    broken = application.read_text().replace("ErrorState.Calls := ErrorState.Calls+1;", "missing_application_identifier;")
                    error_line = next(i for i, line in enumerate(broken.splitlines(), 1) if "missing_application_identifier" in line)
                    application.write_text(broken)
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        diagnostics = json.loads(get('/__esp/diagnostics?format=json')[1])["diagnostics"]
                        errors = [d for d in diagnostics if "missing_application_identifier" in (d.get("message") or "")]
                        if errors:
                            assert errors[0]["file"].endswith("Global.asax"), errors
                            assert errors[0]["line"] == error_line, (error_line, errors)
                            break
                        time.sleep(.1)
                    else:
                        raise AssertionError("Global.asax compiler diagnostics missing")
                print(f"PASS: format={application_format}, incremental={incremental}, legacy={legacy}", flush=True)
            except Exception:
                print((site / "host.log").read_text()[-7000:])
                raise
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ebuild", required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--web-dll", required=True)
    args = parser.parse_args()
    for application_format in ("inline", "inherits", "class"):
        for incremental in (True, False):
            for legacy in (False, True):
                run(args, incremental, legacy, application_format)
