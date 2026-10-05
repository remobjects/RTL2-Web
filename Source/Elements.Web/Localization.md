# Localization

`Application.ActiveLocalizationManager` resolves through the current website's
`WebApplicationLifetime`. Register a manager during startup. Reading the property
when none is configured throws an `InvalidOperationException` explaining how to
register one. Assigning `nil` clears the registration. Reads and writes are
synchronized. The lifetime releases its manager reference after shutdown
callbacks, so the registered manager remains available during `Application_End`.
It does not dispose website-owned custom managers.

The interface returns plain text:

```pascal
ILocalizationManager = public interface
  method GetText(aContext: WebContext; aKey: String): String;
end;
```

Set `Context.LocalizationLanguage` explicitly before rendering. Unset or `nil`
returns `en`; no URL, query, cookie or request-header language selection happens
automatically. The JSON provider maps empty or invalid language tags to English.
It accepts two/three-letter languages, optional script and region, and variants
(for example `pap`, `nl-NL`, `zh-Hant-TW`, `es-419`, `de-1996`). Filenames use
lowercase tags. Tags cannot introduce path separators or traversal.

## Catalogs and output

By default, catalogs live at `~/App_Private/Localization/<language>.json`:

```json
{
  "home": {
    "note": "Welcome, {name}!"
  }
}
```

`GetText(Context, "home.note")` traverses nested JSON objects. It first tries the
requested language, then `en` in the same folder. Missing, invalid, non-string or
whitespace-only translated values fall back to English. If the required English
fallback catalog is missing/invalid, or its key is missing, blank or non-string,
lookup throws an `InvalidOperationException` naming the catalog and, for key
errors, the key.

Nonblank text is returned exactly, including surrounding whitespace and markup.
Placeholders are left untouched. Encode at the output boundary appropriate to
HTML, attributes, JSON, email or other consumers. The provider does not perform formatting/escaping. ESP templates can use
`<%~"home.note"%>` to pass a string expression to the active manager and HTML-encode
the result. Literal keys require quotes; variables, calls, concatenation and
conditionals use the template language's normal syntax (for example `<%~localKey%>`).
The expression is evaluated once. Surrounding whitespace is ignored. `<%= ... %>`
remains raw output; use ordinary code for non-HTML output.

## Separate website and apps catalogs

Register a custom provider, or configure the built-in provider, in startup:

```pascal
method OnStart; override;
begin
  Application.ActiveLocalizationManager := new JsonLocalizationManager(
    "~/App_Private/Localization",
    FolderResolver := aContext -> begin
      var lPath := aContext.Request.Path;
      if (lPath = "/apps") or lPath.StartsWith("/apps/") then
        exit "~/apps/App_Private/Localization";
      // nil uses BaseFolder.
    end);
end;
```

The constructor's `BaseFolder` is readonly. `FolderResolver` receives the supplied
context for every lookup. A nonblank result overrides the base folder. Configure
the callback at startup and keep it safe for concurrent requests; never change
shared provider configuration to select a request's folder. URL interpretation
(including localized routes) belongs to the website's callback.

Folders are application-relative virtual resource paths. Reads use the supplied
context's `Server.OpenFile`, which supports files under the website's physical
root and private embedded resources supplied by its page factory. They do not
use `WebContext.Current` for resource lookup. Publication/resource registration
remains the website's responsibility.

Parsed catalogs, including failed lookups, are cached only on that context, keyed
by resolved folder and language. There is no shared catalog cache: a subsequent
request sees catalog updates. English fallback never crosses to another folder.

## Transfers

`Server.Transfer` copies `LocalizationLanguage` into the new context before
application/page target initialization. Direct and reflection-wrapped transfers
use the same propagation path, including transfer chains. Target code can change
the language. Context items and other request state are not cloned.

The provider resolves its folder against the target context, so transfers into
`/apps` can switch catalogs while retaining the language. Existing query parsing
and the transfer limit are unchanged; no language query parameter is injected.

## Tests

`Tests/LocalizationTests.pas` uses disposable loopback hosts and a private embedded
catalog fixture. It covers fallback/error handling, language validation, folders,
request caches and updates, supplied-versus-ambient context, startup/reset/shutdown,
missing-manager errors, application isolation, concurrent requests, and direct/reflection-wrapped transfers.

Build `Elements.Web.elements` for `Echoes.Standard`, then build and run
`Tests/Elements.Web.Tests.elements`. Its broader `IntegrationTests` additionally
require the test site and use port 8001; do not run those against an occupied
port. The localization tests reserve their own disposable ports.
