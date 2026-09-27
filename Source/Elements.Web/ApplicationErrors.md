# Application error notifications

On .NET ESP, declare the handler in the site's `Global.asax`:

```aspx
<%@ Application Language="Oxygene" %>
<script runat="server">
  method Application_Error(aError: WebErrorContext);
  begin
    // Queue a notification using aError.Exception and aError.RequestUrl.
  end;
</script>
```

ESP compiles server script blocks into a `WebApplication` subclass in the
application unit. `Import` directives and `Inherits` (with optional `CodeFile` or
`CodeBehind`) use the existing template compiler. Application source is never
served as a static file. Editing `Global.asax` rebuilds the application unit and
its dependent pages, following the existing publication settings.

This feature wires `Application_Error` only. Other lifecycle methods such as
`Application_Start`, `Application_End` and `Session_Start` may compile but are
not invoked by this implementation.

Alternatively, put one public, concrete `WebApplication` subclass in
`App_Code/Global.pas` (the class name is arbitrary). It must have a public
parameterless constructor. ESP discovers it in the application's compiled
assembly; no `Web.config` registration is needed. An `Inherits` application uses
the generated derived class, rather than also invoking its concrete base class.

```pascal
namespace MyWebsite;

uses
  RemObjects.Elements.Web;

type
  Global = public class(WebApplication)
  protected

    method Application_Error(aError: WebErrorContext);
    begin
      // Queue your own notification using aError.Exception,
      // aError.RequestUrl and aError.CompilationDiagnostics.
    end;

  end;

end.
```

The legacy signature is also supported:

```pascal
method Application_Error(aSender: Object; aArgs: EventArgs);
begin
  var lException := Server.GetLastError;
  // Context, Request, Response and Server refer to this failing request.
end;
```

`System.Web.HttpApplication` is an alias for `WebApplication`. Protected/private
inherited handlers are supported. If both signatures exist, only the typed
signature runs, even if it is inherited. Methods must return void and be
non-generic instance methods. Each notification uses a fresh application
instance; do not keep application-wide state in its instance fields.

`WebErrorContext` contains:

- `Exception`: the original exception, with reflection invocation wrappers removed.
- `StatusCode`: 500 for an unhandled exception.
- `RequestUrl`: the original absolute URL, including its query string, before
  transfers or error-page routing.
- `RequestMethod`: the original HTTP method.
- `PagePath`: the executing virtual route at the failure, including after a transfer.
- `TimestampUtc`: when ESP captured the failure.
- `CompilationDiagnostics`: copied diagnostic values with severity, code,
  message, filename, source filename, line and column; empty for other exceptions.

The context has no live request or response reference and can be retained for
queued work. Its properties and diagnostic values are read-only; each access to
the diagnostics array returns a copy. The original exception itself is retained,
so holding this context can keep its application generation alive. Notification
code should choose which URL/query and exception details to send externally.

ESP calls the handler synchronously before normal custom or built-in error-page
processing. Queue slow notification work yourself. An exception from the handler
is logged and does not replace the original error or stop error-page processing.
Exceptions from a custom error page do not recursively invoke the handler.
Explicit status codes, including manually returned 500s and ordinary 404s, do
not invoke it. This is a notification hook; clearing or suppressing errors is
not part of this API.

A working application assembly must exist. Lazy page-compilation failures can
notify the already-built App_Code handler. An initial full-site or App_Code
compilation failure cannot execute a handler that failed to compile. Build and
validation timing is unchanged.

Custom hosts can override `WebPageFactory.CreateApplication` to register an
application explicitly. Non-.NET hosts can use that registration and override
`WebApplication.OnError`; automatic class/signature discovery is .NET-only.
