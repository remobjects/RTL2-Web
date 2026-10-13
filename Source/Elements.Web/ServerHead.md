# ESP server-side head

`<head runat="server">` uses the active page's `Header` (`WebPageHeader`).
Master pages share that same object. A declared ID exposes it to inline code
and code-behind; `Page.Title`, `Header.Title`, and the existing `Head` alias
refer to the same title.

```html
<head runat="server" id="DocumentHead" lang="en">
  <meta charset="utf-8" />
  <title>Default title</title>
  <asp:ContentPlaceHolder ID="HeadContent" runat="server" />
</head>
```

Literal titles and head attributes are initialized before user `OnInit` and
`Page_Init` handlers. Markup entities are decoded once and encoded when rendered.
An explicitly assigned title, including an empty string, overrides the default.
There is one rendered title; when the markup omits it, ESP inserts one after the
opening head tag. With an explicit title element, its position is preserved.

Dynamic `<%...%>` markup inside a server-head title is currently diagnosed by
EBuild. Assign `Page.Title` in code for a dynamic, automatically HTML-encoded title.

`Header.Attributes["lang"] := "nl"` updates a case-insensitive attribute
collection. Use `Header.ID` and `Header.Visible` for the control's ID and
visibility. `Visible="false"` is a server property and is not emitted as HTML.
`Header.Controls.Add(control)` appends a control before the closing head tag;
it receives Context, Parent, Init, Load, rendering, and UnLoad. A hidden head
suppresses its complete rendered body. Static markup and content placeholders
use the ordinary ESP template renderer.

The host and generated code call public `Control.Initialize` once per control.
It first invokes the protected `InitializeTemplate` hook for generated defaults,
then the user `OnInit` hook. Generated master initialization runs before the
content page's Init. User controls retain ESP's existing render-time creation
and Load order, with Init immediately before their first Load. This is not a
full ASP.NET control-tree lifecycle or view-state implementation.

Duplicate, self-closing, and unclosed server heads and duplicate/directly
unclosed titles are rejected. Separate templates cannot register two heads
on the same page. The title element is represented by `Header.Title`, not a
separate title control. Title attributes are currently ignored; use `Header.Title` for the title value. Server-side meta/link types and the ASP.NET StyleSheet
API are outside this implementation.

Build and deploy matching EBuild and Elements.Web versions. Runtime source
belongs in the standalone RTL2.Web repository; EBuild owns markup compilation.

`EspPageHeader.pas` owns header state and rendering. EBuild owns head/title markup compilation and invokes the shared runtime
initialization and rendering hooks.
