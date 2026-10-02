# ESP static-file caching

ESP applies the same cache policy to public physical files and embedded static
resources. Dynamic pages/handlers retain their own response headers. Error-page
transfers and non-GET/HEAD static responses use `no-store`, without validators.

The default is `Cache-Control: no-cache`, with an ETag on Echoes and a
Last-Modified header for physical files. `no-cache` permits storage, but requires
validation before reuse; it is not `no-store`. Matching conditional GET/HEAD
requests return 304 without a body. If-None-Match takes precedence over
If-Modified-Since, including when the ETag does not match. HEAD sends the same
representation headers as GET without transferring the file contents.

## Web.config

ESP supports this subset of the IIS `clientCache` vocabulary:

```xml
<configuration>
  <system.webServer>
    <staticContent>
      <clientCache cacheControlMode="DisableCache" setEtag="true" />
    </staticContent>
  </system.webServer>

  <location path="images">
    <system.webServer>
      <staticContent>
        <clientCache cacheControlMode="UseMaxAge"
                     cacheControlMaxAge="01:00:00" />
      </staticContent>
    </system.webServer>
  </location>

  <location path="assets/versioned">
    <system.webServer>
      <staticContent>
        <clientCache cacheControlMode="UseMaxAge"
                     cacheControlMaxAge="365.00:00:00"
                     cacheControlCustom="public, immutable" />
      </staticContent>
    </system.webServer>
  </location>
</configuration>
```

Only use `immutable` when a content change always produces a different URL.
ESP never infers immutability from a filename or query parameter. Unversioned
files with a positive max-age may remain stale until that lifetime expires.

| Attribute | Behavior |
| --- | --- |
| `cacheControlMode="DisableCache"` | Sends `no-cache`. ESP default. |
| `cacheControlMode="NoControl"` | Adds no cache-control directive or Expires header; validators still apply. |
| `cacheControlMode="UseMaxAge"` | Sends `max-age=N`. |
| `cacheControlMaxAge` | Whole-second `[days.]hh:mm:ss`; defaults to one day when UseMaxAge is selected. Maximum 2^31-1 seconds. |
| `cacheControlMode="UseExpires"` | Sends the fixed HTTP date from `httpExpires`. |
| `httpExpires` | Required for UseExpires, for example `Fri, 01 Jan 2027 00:00:00 GMT`. |
| `cacheControlCustom` | Additional Cache-Control directives, e.g. `public, immutable` or `no-store`. Do not combine contradictory directives. |
| `setEtag` | `true` (default) or `false`; independent of Last-Modified. |

A location matches its exact path and descendants, on directory boundaries and
case-insensitively. The most specific location wins; omitted attributes inherit
from its enclosing location, then the root configuration. Declaration order
does not affect parent/child inheritance. `path="."` sets the root policy.
Locations may name individual files. Wildcards, query strings and parent
traversal are not supported. Only the root Web.config and its location sections
are read; nested Web.config files are not merged. Invalid supported settings
reject factory activation before replacing the current factory.

## Publication and validators

Policies are captured once when the host assigns `WebServer.PageFactory`, from
that factory's physical root (or the server root if the factory has none).
For standalone sites with embedded Web.config, ESP uses the private resource
resolver. Accepted publication roots must be immutable: uploads to the incoming
root cannot change the current policy. Publishing a replacement factory applies
new settings; a content-only publication gets its own policy and validator cache.

Echoes uses SHA-256 over the selected stream, restoring its position afterward.
ETags are stable across factories/restarts when the content is identical. The
bounded per-factory metadata cache holds at most 4096 ETags, with no asset bodies;
embedded resources and physical roots with a PublicationRevision are memoized.
Mutable development files are hashed per request, so same-length edits with a
preserved timestamp still invalidate ETags. Other backends currently use physical
file date validation only; no synthetic content digest is advertised.

Physical Last-Modified dates have HTTP's one-second precision. Embedded resources
have no invented timestamp. If accurate detection of edits within the same
second matters, keep ETags enabled.

Before the first factory, a non-triggered development host captures its physical
root policy when Start is called. Trigger-controlled startup/error pages keep
existing no-store behavior. No settings here change application output caching,
management responses, authorization, private-file filtering or range serving.

## Verification

`Tests/StaticFileTests.pas` uses disposable roots and random loopback ports. It
covers physical and embedded resources, HEAD/304 framing, weak/list/wildcard tag
matching, conditional precedence, same-size timestamp-preserving edits, scoped
inheritance, publication policy capture, invalid configuration and error/dynamic
response isolation. It is included in `Tests/Elements.Web.Tests.elements`.
