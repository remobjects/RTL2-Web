# Incremental ESP host regression fixture

This fixture exercises real compiler invocations and HTTP requests, not a mocked
planner. It creates disposable sites and starts its own hosts on random loopback
ports. It never deploys or modifies the website checkout.

## Running

Build Core EBuild and `Elements.Web` (`Echoes.Standard`) from the matching source
trees. Then run:

```sh
python3 Tests/IncrementalHost/run.py \
  --ebuild /path/to/EBuild-osx-arm64 \
  --compiler /path/to/matching/RemObjects.Elements.dll \
  --web-dll /path/to/Elements.Web.dll
```

Use a compiler compatible with that EBuild's CodeGen assemblies. An unrelated
installed compiler can fail before compiling any website code.

The script checks both values of `ESPServeLastGood`, then rebuilds the same
five-unit fixture in full mode for comparison. Reported timings are host-side
build/activation times, excluding watcher debounce and HTTP polling.

Coverage includes page/control dependency closure, sessions and application
values, App_Code statics, initial build recovery, failed-build overlays and
correction, in-flight requests, route additions/renames/deletions and canonical
name collisions, live static files, private files, configuration/private-resource
recycling, rapid edits during compilation, and collectible assembly contexts.
Only the collection test explicitly requests garbage collection; the host never
forces it.

## Enabling the host

Use Core EBuild with these optional `Web.config` project settings:

```xml
<esp.projectSettings>
  <ESPIncrementalRecompilation>True</ESPIncrementalRecompilation>
  <ESPServeLastGood>True</ESPServeLastGood>
</esp.projectSettings>
```

Equivalent command-line overrides:

```sh
EBuild --serve-web-project /path/to/Site --configuration:Debug \
  --setting:ESPIncrementalRecompilation=True \
  --setting:ESPServeLastGood=False
```

`ESPIncrementalRecompilation=False` and `ESPServeLastGood=True` are the defaults.
Setting `ESPServeLastGood=False` shows build errors on affected dynamic routes
instead of serving their previous working version. Classic EBuild rejects incremental
mode with a diagnostic; it does not fall back silently. Initial failure keeps
the process watching; HTTP becomes available after the first successful build.

Page/control/master edits retain the application lifetime, sessions and
application values. App_Code, unowned shared code, private resources, reference
changes and configuration changes create a new lifetime. Rebuilt-unit statics
reset; unchanged-unit statics survive. Existing requests retain their snapshot.
Files read directly from disk remain live files, not frozen copies.

Assemblies are compiled eagerly and sequentially into unique output locations.
Shared code-behind, matching declared partial classes and dependency cycles are
grouped. Arbitrary code-only references between template units are not inferred;
move such shared code into App_Code, refactor/group it, or use full mode. Generated
dependencies outside the selected graph fail explicitly. There is no automatic
fallback, persistent cross-restart cache or first-request compilation.

Unload is cooperative. Background work or application-held page objects can
retain old assemblies. Host-pinned framework/runtime replacements require a
restart. When replacing the installed toolchain or externally resolved packages,
restart the host as well; file watching currently covers the website and its
configured binary folder, not the complete installed reference/package trees.

## Validation boundaries

The fixture is intentionally small: incremental compilation can be slower than
one full compiler invocation for shared changes. Its main assertions are the
exact changed-unit count and state preservation, not a universal speedup.

The full production website and installed-reference/package replacement paths
need separate qualification before enabling this mode there. The standalone
runtime regression suite also needs a coherent EBuild/compiler pair: the older
EBuild branch lacks newer ASPX generation fixes used by some current tests.
