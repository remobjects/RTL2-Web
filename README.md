# Elements.Web

## Response cookies

`WebResponse.AppendCookie`, `WebResponse.SetCookie` and `WebCookieCollection.Add`
retain cookies with the same name when their paths or domains differ. Each cookie
is emitted as a separate `Set-Cookie` header, including when the response is
flushed, redirected or ended early.

```pascal
Response.AppendCookie(new WebCookie("same", Value := "root", Path := "/"));
Response.AppendCookie(new WebCookie("same", Value := "nested", Path := "/scope"));
```

This emits both `same=root; path=/` and `same=nested; path=/scope`.
Adding a cookie with the same name, path and domain replaces the earlier cookie.
Names and paths are case-sensitive; an omitted path is `/`, and domain comparison
ignores case, matching the lowercase domain used in the header. An omitted domain
remains distinct from an explicitly supplied domain.

`Response.Cookies["same"]` returns the most recently added cookie with that name.
`Count` includes distinct scopes, and `Keys` can contain repeated names. Request
cookie lookup keeps its existing behavior: when the incoming `Cookie` header
repeats a name, the last value wins.

Compatibility: the protected `ImmutableWebCookieCollection.fCookies` storage
changed from `Dictionary<String, WebCookie>` to `List<WebCookie>`. External
subclasses that access this field must adapt to the list and be rebuilt; ordinary
callers can continue using the existing collection methods and properties.
