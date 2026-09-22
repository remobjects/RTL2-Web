#!/usr/bin/env python3
"""Exercise the real Core EBuild host, using disposable sites and loopback only."""
import argparse
import concurrent.futures
import http.cookiejar
import pathlib
import re
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def wait_for(check, message, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def run(args, failure_mode, compilation_mode="Incremental"):
    with tempfile.TemporaryDirectory(prefix="esp-incremental-test-") as temporary:
        root = pathlib.Path(temporary)
        site = root / "Site"
        shutil.copytree(pathlib.Path(__file__).parent / "Site", site)
        binary_dir = "RuntimeBin" if failure_mode == "ShowErrors" else "Bin"
        (site / binary_dir).mkdir()
        shutil.copy2(args.web_dll, site / binary_dir / "Elements.Web.dll")
        initial_page = (site / "Default.aspx").read_text()
        initial_failure = compilation_mode == "Incremental" and failure_mode == "KeepLastGood"
        if initial_failure:
            (site / "Default.aspx").write_text(initial_page + "<%= missing_initial_identifier %>")
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        jar = http.cookiejar.CookieJar()
        client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

        def get(path):
            try:
                with client.open(f"http://127.0.0.1:{port}{path}", timeout=10) as response:
                    return response.status, response.read().decode()
            except urllib.error.HTTPError as error:
                return error.code, error.read().decode()

        logfile = root / "host.log"
        with logfile.open("w") as output:
            process = subprocess.Popen([
                str(args.ebuild), "--serve-web-project", str(site),
                "--configuration:Debug", f"--port:{port}",
                f"--setting:EBuild:ElementsCompilerDll={args.compiler}",
                f"--setting:ESPServeLastGood={failure_mode == 'KeepLastGood'}",
                f"--setting:ESPIncrementalRecompilation={compilation_mode == 'Incremental'}",
                f"--setting:BinFolder={binary_dir}",
            ], stdout=output, stderr=subprocess.STDOUT)
            try:
                def log():
                    text = logfile.read_text()
                    if process.poll() is not None:
                        raise AssertionError(f"Host exited: {text[-6000:]}")
                    return text

                def activations():
                    if compilation_mode == "Full":
                        return [(compiled, "0", timing, "full") for compiled, timing in re.findall(r"ESP full build: (\d+) compiled, (\d+) ms", log())]
                    return re.findall(r"Activated ESP generation \d+: (\d+) compiled, (\d+) reused, (\d+) ms; application (\w+)", log())

                def change(path, old, new, compiled, recycled=False):
                    before = len(activations())
                    file = site / path
                    file.write_text(file.read_text().replace(old, new))
                    rows = wait_for(lambda: (rows if len(rows := activations()) > before else None), f"No activation after {path}")
                    row = rows[-1]
                    assert int(row[0]) == compiled, (path, row)
                    if compilation_mode != "Full":
                        assert row[3] == ("recycled" if recycled else "preserved"), row
                    print(f"{compilation_mode}/{failure_mode}: {path}: compiled={row[0]} reused={row[1]} time={row[2]}ms {row[3]}", flush=True)

                if initial_failure:
                    wait_for(lambda: "Initial compilation failed; watching" in log(), "Host did not remain watching after initial failure")
                    (site / "Default.aspx").write_text(initial_page)
                wait_for(lambda: activations(), "Initial build failed")
                status, first = get("/")
                assert status == 200 and "session=1" in first, first
                if compilation_mode == "Full":
                    change("Default.aspx", "page=one-v1", "page=one-v2", 1)
                    assert "page=one-v2" in get("/")[1]
                    change("Shared.ascx", "control=v1", "control=v2", 1)
                    assert "control=v2" in get("/")[1]
                    change("App_Code/State.pas", "readonly;", "readonly; // changed", 1)
                    assert get("/")[0] == 200
                    print("PASS Full: same-fixture rebuild comparison", flush=True)
                    return
                token = re.search(r"appcode=([^\s<]+)", first)[1]
                change("Default.aspx", "page=one-v1", "page=one-v2", 1)
                status, second = get("/")
                assert status == 200 and "session=2" in second and f"appcode={token}" in second and f"application={token}" in second, second
                change("Shared.ascx", "control=v1", "control=v2", 3)
                assert "control=v2" in get("/")[1] and token in get("/Other")[1]

                count = len(activations())
                compiler_calls = log().count("ESP compiling ")
                (site / "site.css").write_text("body { color: blue; }")
                time.sleep(0.8)
                assert len(activations()) == count, "Static edit triggered activation"
                assert log().count("ESP compiling ") == compiler_calls, "Static edit invoked the compiler"
                assert "blue" in get("/site.css")[1]
                assert get("/App_Private/catalog.txt")[0] == 404
                assert "private-catalog" in get("/")[1]

                change("App_Code/State.pas", "readonly;", "readonly; // changed", 5, True)
                status, recycled = get("/")
                assert status == 200 and "session=1" in recycled and f"appcode={token}" not in recycled, recycled

                failures = log().count("Incremental ESP build failed")
                page = site / "Default.aspx"
                good_page = page.read_text()
                page.write_text(good_page.replace("page=one-v2", "<%= missing_identifier %>"))
                wait_for(lambda: log().count("Incremental ESP build failed") > failures, "Expected compiler failure")
                status, body = get("/")
                assert status == (500 if failure_mode == "ShowErrors" else 200), (status, body)
                if failure_mode == "ShowErrors":
                    assert "missing_identifier" in body, "Compiler diagnostics missing from error page"
                else:
                    assert "page=one-v2" in body
                assert get("/Other")[0] == 200, "Unrelated route failed"
                change("Default.aspx", "<%= missing_identifier %>", "page=one-v3", 1)
                assert "page=one-v3" in get("/")[1]

                # A slow request must retain old App_Code and Application values.
                slow = site / "Slow.aspx"
                before = len(activations())
                slow.write_text('''<%@ Page Language="Oxygene" %>
<% var lBefore := SiteState.Token;
RemObjects.Elements.Web.Application["slow-started"] := "yes";
System.Threading.Thread.Sleep(2500); %>
before=<%=lBefore%> after=<%=SiteState.Token%>
application=<%=RemObjects.Elements.Web.Application["token"]%>
''')
                wait_for(lambda: len(activations()) > before, "Added route did not activate")
                # Polling this page signals that Slow has entered its old lifetime.
                probe = site / "Probe.aspx"
                before = len(activations())
                probe.write_text('<%@ Page Language="Oxygene" %>started=<%=RemObjects.Elements.Web.Application["slow-started"]%>')
                wait_for(lambda: len(activations()) > before, "Probe did not activate")
                old_token = re.search(r"appcode=([^\s<]+)", get("/")[1])[1]
                with concurrent.futures.ThreadPoolExecutor() as pool:
                    request = pool.submit(get, "/Slow")
                    wait_for(lambda: "started=yes" in get("/Probe")[1], "Slow request did not start")
                    change("App_Code/State.pas", "// changed", "// changed again", 7, True)
                    status, held = request.result()
                assert status == 200 and f"before={old_token}" in held and f"after={old_token}" in held and f"application={old_token}" in held, held

                before = len(activations())
                probe.rename(site / "Renamed.aspx")
                wait_for(lambda: len(activations()) > before, "Renamed route did not activate")
                assert get("/Probe")[0] == 404 and get("/Renamed")[0] == 200
                before = len(activations())
                (site / "Renamed.aspx").unlink()
                wait_for(lambda: len(activations()) > before, "Deleted route did not activate")
                assert get("/Renamed")[0] == 404

                # A canonical-name conflict must not alias the handler to the page.
                before = len(activations())
                (site / "Conflict.aspx").write_text('<%@ Page Language="Oxygene" %>conflict-page')
                (site / "Conflict.ashx").write_text('''<%@ WebHandler Language="Oxygene" Class="ConflictHandler" %>
namespace;
type
  ConflictHandler = public class(System.Web.IHttpHandler)
  public
    method ProcessRequest(Context: System.Web.HttpContext);
    begin
      Context.Response.ContentType := "text/plain";
      Context.Response.Write("conflict-handler");
    end;
    property IsReusable: Boolean read false;
  end;
end.
''')
                wait_for(lambda: len(activations()) > before, "Conflicting routes did not activate")
                assert "conflict-page" in get("/Conflict.aspx")[1]
                assert "conflict-handler" in get("/Conflict.ashx")[1]

                # Collect only in the test, never as part of production retirement.
                before = len(activations())
                (site / "Collect.aspx").write_text('''<%@ Page Language="Oxygene" %>
<% var lKey := "old-context";
if not assigned(RemObjects.Elements.Web.Application[lKey]) then
  RemObjects.Elements.Web.Application[lKey] := new System.WeakReference(System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(self.GetType.Assembly));
System.GC.Collect;
System.GC.WaitForPendingFinalizers;
System.GC.Collect;
%>alive=<%=(RemObjects.Elements.Web.Application[lKey] as System.WeakReference).IsAlive%>version=one
''')
                wait_for(lambda: len(activations()) > before, "Collection probe did not activate")
                assert "alive=True" in get("/Collect")[1]
                change("Collect.aspx", "version=one", "version=two", 1)
                wait_for(lambda: "alive=False" in get("/Collect")[1], "Retired context remained rooted", timeout=10)

                unit_count = sum(map(int, activations()[-1][:2]))
                change("App_Private/catalog.txt", "private-catalog", "private-catalog-updated", unit_count, True)
                assert "private-catalog-updated" in get("/")[1]
                assert get("/App_Private/catalog.txt")[0] == 404
                change("Web.config", "</configuration>", "<!-- configuration edit -->\n</configuration>", unit_count, True)

                # Change an input after compilation actually starts, not just during debounce.
                calls = log().count("ESP compiling ")
                discards = log().count("discarding candidate")
                for index in range(12):
                    (site / f"Burst{index}.aspx").write_text('<%@ Page Language="Oxygene" %>burst=' + str(index))
                wait_for(lambda: log().count("ESP compiling ") > calls, "Burst compilation did not start")
                # App_Code is already selected before the new page units compile.
                # Mutating a page not yet visited could legitimately be incorporated
                # into this candidate without needing a discard.
                state_file = site / "App_Code" / "State.pas"
                state_file.write_text(state_file.read_text() + "\n// changed during compilation\n")
                page.write_text(page.read_text().replace("page=one-v3", "page=latest"))
                wait_for(lambda: log().count("discarding candidate") > discards, "Stale candidate was not discarded")
                wait_for(lambda: "page=latest" in get("/")[1], "Latest edit was lost")
                assert "burst=11" in get("/Burst11")[1]

                print(f"PASS {failure_mode}: state preservation/reset, dependent closure, static/private resources, failed-build recovery, in-flight lifetime, route rename/delete/conflicts, context collection, private/config recycle, stale-input rejection", flush=True)
            except Exception:
                print(logfile.read_text()[-10000:], flush=True)
                raise
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ebuild", type=pathlib.Path, required=True)
    parser.add_argument("--compiler", type=pathlib.Path, required=True)
    parser.add_argument("--web-dll", type=pathlib.Path, required=True)
    options = parser.parse_args()
    for mode in ("KeepLastGood", "ShowErrors"):
        run(options, mode)
    run(options, "KeepLastGood", "Full")
