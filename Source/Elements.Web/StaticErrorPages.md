# Static HTTP error pages

.NET ESP supports static error files in the existing `Web.config` section:

```xml
<configuration>
  <system.webServer>
    <httpErrors errorMode="Custom">
      <error statusCode="503" path="/503.html" responseMode="File" />
    </httpErrors>
  </system.webServer>
</configuration>
```

In ESP, `path` is relative to the website root, with an optional `/` or `~/`
prefix. This differs from IIS physical-file paths. The file is read directly;
it is not executed as a page or handler. Use a self-contained HTML document
with inline styles and images for startup placeholders.

`File` can be used for other statuses, including 404 and 500, alongside
`ExecuteURL` and `Redirect`. The response retains the original error status,
uses the file's content type, and sends `Cache-Control: no-store`. HEAD requests
have no response body. Missing, unreadable, or disallowed files use the built-in
error page. Public static-file restrictions apply; source files, private/bin
folders, path traversal, and symbolic links/reparse points are rejected.

Existing ESP rule ordering and `clear`/`remove` behavior apply. As with existing
ESP `httpErrors` handling, `errorMode="Detailed"` disables these rules;
`DetailedLocalOnly` does not currently distinguish local requests. This does
not implement IIS substatus, language-prefix, or existingResponse semantics.

The Core ESP host loads static rules and file contents before compiling:

- Ordinary hosts load the website's `Web.config`, and refresh the startup rules
  when retrying the initial build.
- Trigger-controlled hosts load only the validated accepted publication when
  restoring it. Incoming uploads never supply startup placeholders. Before the
  first accepted publication, the built-in placeholder is used.
- Once a generation is active, its own compiled error rules and content root
  govern normal requests. Management and diagnostic endpoints are unaffected.

This requires updated Elements.Web and EBuild binaries. Existing four-argument
`WebErrorPage` constructors remain supported; the new five-argument overload's
last argument selects static-file mode. Custom hosts can call
`WebServer.LoadStaticErrorPages(root)` before starting compilation. Non-.NET
runtime backends fall back to built-in pages for File rules until they provide
safe link checking. No new command-line option is needed.
