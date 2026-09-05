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

    method PreservesUnicodeInlineText;
    begin
      var lText := "sealed — café Ω 🚀";
      Check.IsTrue(Markdown.ToHtml(lText).Contains(lText));
    end;

    method RendersBlockquotesAlertsAndTableAlignment;
    begin
      var lHtml := Markdown.ToHtml("> [!NOTE]" + #10 + "> Keep shared behavior aligned." + #10 + #10 + "| Left | Center | Right |" + #10 + "| :--- | :---: | ---: |" + #10 + "| A | B | C |");
      Check.IsTrue(lHtml.Contains("<blockquote class=""elements-markdown-alert elements-markdown-alert-note"">"));
      Check.IsTrue(lHtml.Contains("<strong>Note</strong>"));
      Check.IsTrue(lHtml.Contains("Keep shared behavior aligned."));
      Check.IsTrue(lHtml.Contains("<th style=""text-align: center;"">Center</th>"));
      Check.IsTrue(lHtml.Contains("<td style=""text-align: right;"">C</td>"));
    end;

    method AllowsGitHubExtensionsToBeDisabled;
    begin
      var lHtml := Markdown.ToHtml("> [!NOTE]" + #10 + "> This remains an ordinary quote.", MarkdownOptions.CommonMark);
      Check.IsTrue(lHtml.Contains("<blockquote>"));
      Check.IsFalse(lHtml.Contains("elements-markdown-alert"));
      Check.IsTrue(lHtml.Contains("[!NOTE]"));
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
