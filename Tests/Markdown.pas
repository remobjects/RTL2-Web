// Negative guard: escaped punctuation and raw HTML must remain literal in rendered reports.
namespace Elements.RTL2.Tests.Shared;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.RTL.Markdown;

type
  MarkdownTests = public class(Test)
  public
    method RendersEscapedPunctuationLiterally;
    begin
      var lSlash := Char(92).ToString;
      var lOptions := new MarkdownOptions(AllowRawHtml := true);
      var lHtml := Markdown.ToHtml('colon ' + lSlash + '(:' + lSlash + ') expected; ' +
        lSlash + '[open' + lSlash + ']' + lSlash + '(solution-file://open?path=/Other.pas' + lSlash + ') ' +
        lSlash + '<script' + lSlash + '>', lOptions);
      Check.IsTrue(lHtml.Contains('colon (:) expected;'));
      Check.IsTrue(lHtml.Contains('[open](solution-file://open?path=/Other.pas)'));
      Check.IsTrue(lHtml.Contains('&lt;script&gt;'));
      Check.IsFalse(lHtml.Contains('<a href='));
      Check.IsFalse(lHtml.Contains(lSlash));
      var lPath := 'C:' + lSlash + 'Projects' + lSlash + 'Program.pas';
      Check.IsTrue(Markdown.ToHtml(lPath, lOptions).Contains(lPath));
    end;

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

    method NestsReleaseNoteBulletsInsideTheirParent;
    begin
      var lSource := "## New in Elements 14 rev1, November 6" + #10 + #10 +
        "* New [Promethium](/elements/promethium) language frontend: Python comes to Elements" + #10 +
        "* Support for creating Island/Delphi packages (Preview: Delphi 13/Windows)" + #10 +
        "* Island LTO" + #10 +
        "* Support for external .NET Nullability Annotations on .NET base APIs" + #10 +
        "* App Store Connect & Publishing Imporvemnts for Apple platforms" + #10 +
        "  * Connect your App Store Connect account to Fire, Water and Earth" + #10 +
        "  * Package & Notarize macOS apps right from EBuild" + #10 +
        "  * Create Provisioning Profiles, Certificates and Bundle Identifiers for the IDE or CodeBot" + #10 +
        "  * Publish apps to App Store Connect right from EBuild, via the connected account" + #10 +
        "* New Code Model Diagnostics sheet in Fire/Water/Earth to find code problems when IDE Smarts break" + #10 +
        "* Support for WinForms and WPF designers in .NET Core projects, in Vsiual Studio 2022 and 2026";
      for each lOptions in [MarkdownOptions.CommonMark, MarkdownOptions.GitHub] do begin
        var lHtml := Markdown.ToHtml(lSource, lOptions);
        Check.IsTrue(lHtml.Contains("<li>App Store Connect &amp; Publishing Imporvemnts for Apple platforms" + #10 +
          "<ul>" + #10 + "<li>Connect your App Store Connect account to Fire, Water and Earth</li>"));
        Check.IsTrue(lHtml.Contains("<li>Publish apps to App Store Connect right from EBuild, via the connected account</li>" + #10 +
          "</ul>" + #10 + "</li>" + #10 + "<li>New Code Model Diagnostics sheet"));
        Check.IsTrue(lHtml.Contains("<a href=""/elements/promethium"">Promethium</a>"));
      end;
    end;

    method RendersMultipleBulletLevelsAndDedents;
    begin
      var lSource := "- Parent" + #10 + "  * Child" + #10 + "    - Grandchild" + #10 +
        "  * Second child" + #10 + "- Sibling" + #10 + #10 + "After";
      var lExpected := "<ul>" + #10 + "<li>Parent" + #10 + "<ul>" + #10 +
        "<li>Child" + #10 + "<ul>" + #10 + "<li>Grandchild</li>" + #10 + "</ul>" + #10 + "</li>" + #10 +
        "<li>Second child</li>" + #10 + "</ul>" + #10 + "</li>" + #10 +
        "<li>Sibling</li>" + #10 + "</ul>" + #10 + "<p>After</p>" + #10;
      Check.AreEqual(Markdown.ToHtml(lSource), lExpected);
    end;

    method RendersFourSpaceAndTabIndentedBulletLists;
    begin
      var lExpected := "<ul>" + #10 + "<li>Parent" + #10 + "<ul>" + #10 +
        "<li>Child</li>" + #10 + "</ul>" + #10 + "</li>" + #10 + "<li>Sibling</li>" + #10 + "</ul>" + #10;
      Check.AreEqual(Markdown.ToHtml("* Parent" + #10 + "    * Child" + #10 + "* Sibling"), lExpected);
      Check.AreEqual(Markdown.ToHtml("* Parent" + #10 + #9 + "* Child" + #10 + "* Sibling"), lExpected);
    end;

    method KeepsBulletsInTheSameListWhenIndentationVaries;
    begin
      var lSource := " * Parent" + #10 + "     * Child" + #10 + "   * Second child" + #10 + "* Sibling";
      var lExpected := "<ul>" + #10 + "<li>Parent" + #10 + "<ul>" + #10 +
        "<li>Child</li>" + #10 + "<li>Second child</li>" + #10 + "</ul>" + #10 + "</li>" + #10 +
        "<li>Sibling</li>" + #10 + "</ul>" + #10;
      Check.AreEqual(Markdown.ToHtml(lSource), lExpected);
    end;

    method PreservesTaskListsWhenNested;
    begin
      var lSource := "- [x] Parent" + #10 + "  - [ ] Child" + #10 + "- [X] Sibling";
      var lHtml := Markdown.ToHtml(lSource);
      Check.IsTrue(lHtml.Contains("<li class=""task-list-item""><input type=""checkbox"" disabled checked /> Parent" + #10 +
        "<ul>" + #10 + "<li class=""task-list-item""><input type=""checkbox"" disabled /> Child</li>"));
      Check.IsTrue(lHtml.Contains("</ul>" + #10 + "</li>" + #10 +
        "<li class=""task-list-item""><input type=""checkbox"" disabled checked /> Sibling</li>"));
      var lCommonMark := Markdown.ToHtml(lSource, MarkdownOptions.CommonMark);
      Check.IsTrue(lCommonMark.Contains("<li>[x] Parent" + #10 + "<ul>" + #10 + "<li>[ ] Child</li>"));
      Check.IsFalse(lCommonMark.Contains("checkbox"));
    end;

    method PreservesAngleBracketTextThatIsNotHtml;
    begin
      var lOptions := MarkdownOptions.CommonMark;
      lOptions.AllowRawHtml := true;

      var lHtml := Markdown.ToHtml("Sugar.Dictionary<T,U> and System.Collections.Generic.Dictionary<T,U>", lOptions);
      Check.IsTrue(lHtml.Contains("Sugar.Dictionary&lt;T,U&gt;"));
      Check.IsTrue(lHtml.Contains("System.Collections.Generic.Dictionary&lt;T,U&gt;"));

      var lMixedHtml := Markdown.ToHtml("Before <span class=""value"">inside</span> and <https://example.test> after", lOptions);
      Check.IsTrue(lMixedHtml.Contains("<span class=""value"">inside</span>"));
      Check.IsTrue(lMixedHtml.Contains("<a href=""https://example.test"">https://example.test</a>"));
    end;

    method PreservesValidHtmlCommentsWhenEnabled;
    begin
      var lOptions := MarkdownOptions.CommonMark;
      lOptions.AllowRawHtml := true;

      var lBlockSource := "<!-- hidden" + #10 + #10 + "<div>legacy content</div>" + #10 + "-->" + #10 + "## Visible";
      var lBlockHtml := Markdown.ToHtml(lBlockSource, lOptions);
      Check.IsTrue(lBlockHtml.Contains("<!-- hidden" + #10 + #10 + "<div>legacy content</div>" + #10 + "-->"));
      Check.IsTrue(lBlockHtml.Contains("<h2>Visible</h2>"));
      Check.IsFalse(lBlockHtml.Contains("--&gt;"));

      var lInlineHtml := Markdown.ToHtml("Before <!--<span>hidden</span>--> after", lOptions);
      Check.IsTrue(lInlineHtml.Contains("Before <!--<span>hidden</span>--> after"));
      Check.IsFalse(lInlineHtml.Contains("--&gt;"));
    end;

    method AtxHeadingInterruptsParagraphAfterInlineHtml;
    begin
      var lOptions := MarkdownOptions.CommonMark;
      lOptions.AllowRawHtml := true;
      var lHtml := Markdown.ToHtml("<img src=""image.png"" />" + #10 + "## Heading" + #10 + "Body", lOptions);
      Check.IsTrue(lHtml.Contains("<p><img src=""image.png"" /></p>"));
      Check.IsTrue(lHtml.Contains("<h2>Heading</h2>"));
      Check.IsTrue(lHtml.Contains("<p>Body</p>"));
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
