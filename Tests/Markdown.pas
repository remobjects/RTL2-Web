namespace Elements.RTL2.Tests.Shared;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.RTL.Markdown;

type
  MarkdownTests = public class(Test)
  public
    method RendersCommonBlocksAndExtensions;
    begin
      var lHtml := Markdown.ToHtml("# Heading" + #10 + #10 + "A **strong** and ~~deleted~~ [link](https://example.test)." + #10 + #10 + "- [x] done" + #10 + "- [ ] open" + #10 + #10 + "| A | B |" + #10 + "| - | - |" + #10 + "| 1 | 2 |");
      Check.IsTrue(lHtml.Contains("<h1 id=""heading"">Heading</h1>"));
      Check.IsTrue(lHtml.Contains("<strong>strong</strong>"));
      Check.IsTrue(lHtml.Contains("<del>deleted</del>"));
      Check.IsTrue(lHtml.Contains("<a href=""https://example.test"">link</a>"));
      Check.IsTrue(lHtml.Contains("task-list-item"));
      Check.IsTrue(lHtml.Contains("<table>"));
    end;

    method EscapesRawHtmlUnlessEnabled;
    begin
      Check.IsTrue(Markdown.ToHtml("<script>alert(1)</script>").Contains("&lt;script&gt;"));

      var lOptions := new MarkdownOptions;
      lOptions.AllowRawHtml := true;
      Check.IsTrue(Markdown.ToHtml("<span>safe caller choice</span>", lOptions).Contains("<span>safe caller choice</span>"));
    end;

    method RendersMermaidAndOrdinaryCodeFencesDifferently;
    begin
      var lHtml := Markdown.ToHtml("~~~mermaid" + #10 + "flowchart LR" + #10 + "A-->B" + #10 + "~~~" + #10 + #10 + "~~~pas" + #10 + "method Test;" + #10 + "~~~");
      Check.IsTrue(lHtml.Contains("<pre class=""elements-markdown-mermaid mermaid"">"));
      Check.IsTrue(lHtml.Contains("A--&gt;B"));
      Check.IsTrue(lHtml.Contains("<code class=""language-pas"">"));
      Check.IsTrue(Markdown.MermaidBootstrapJavaScript.Contains("securityLevel:'strict'"));
      Check.AreEqual(Markdown.MermaidVersion, "11.16.0");
      Check.IsTrue(lHtml.Contains("</pre>" + #10));
      Check.IsFalse(lHtml.Contains("\n"));
    end;
  end;

end.
