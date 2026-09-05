namespace RemObjects.Elements.RTL.Markdown;

// Clean-room Markdown parser and HTML renderer. It intentionally has no
// dependency on MarkdownDeep, CocoaMarkdown, or platform framework APIs.

type
  MarkdownDialect = public enum (CommonMark, GitHub);

  MarkdownOptions = public class
  public
    property AllowRawHtml: Boolean;
    property EnableTables: Boolean;
    property EnableStrikethrough: Boolean;
    property EnableTaskLists: Boolean;
    property EnableAutolinks: Boolean;
    property GenerateHeadingIds: Boolean;
    property EnableGitHubAlerts: Boolean;
    property IncludeMermaidRuntime: Boolean;

    constructor;
    begin
      EnableTables := true;
      EnableStrikethrough := true;
      EnableTaskLists := true;
      EnableAutolinks := true;
      GenerateHeadingIds := true;
      EnableGitHubAlerts := true;
    end;

    constructor withDialect(aDialect: MarkdownDialect);
    begin
      EnableTables := aDialect = MarkdownDialect.GitHub;
      EnableStrikethrough := aDialect = MarkdownDialect.GitHub;
      EnableTaskLists := aDialect = MarkdownDialect.GitHub;
      EnableAutolinks := true;
      GenerateHeadingIds := aDialect = MarkdownDialect.GitHub;
      EnableGitHubAlerts := aDialect = MarkdownDialect.GitHub;
    end;

    class method CommonMark: not nullable MarkdownOptions;
    begin
      result := new MarkdownOptions withDialect(MarkdownDialect.CommonMark);
    end;

    class method GitHub: not nullable MarkdownOptions;
    begin
      result := new MarkdownOptions withDialect(MarkdownDialect.GitHub);
    end;

    class property Default: not nullable MarkdownOptions := new MarkdownOptions;
  end;

  MarkdownDocument = public class
  private
    fSource: not nullable String;
    fOptions: not nullable MarkdownOptions;
  assembly
    constructor withSource(aSource: not nullable String) Options(aOptions: not nullable MarkdownOptions);
    begin
      fSource := aSource;
      fOptions := aOptions;
    end;
  public
    class method Parse(aSource: nullable String; aOptions: nullable MarkdownOptions := nil): not nullable MarkdownDocument;
    begin
      result := new MarkdownDocument withSource(coalesce(aSource, "")) Options(coalesce(aOptions, MarkdownOptions.Default));
    end;

    method ToHtml: not nullable String;
    begin
      result := MarkdownRenderer.Render(fSource, fOptions);
    end;
  end;

  Markdown = public static class
  public
    class property MermaidVersion: not nullable String := "11.16.0";
    class property MermaidRuntimeJavaScript: not nullable String read MermaidRuntime.JavaScript;
    class property MermaidBootstrapJavaScript: not nullable String := "(async()=>{const m=window.mermaid;if(!m)return;m.initialize({startOnLoad:false,securityLevel:'strict',flowchart:{htmlLabels:false}});for(const e of document.querySelectorAll('pre.elements-markdown-mermaid')){const d=e.textContent||'';const id='elements-mermaid-'+Math.random().toString(36).slice(2);try{const r=await m.render(id,d);const w=document.createElement('div');w.className='elements-markdown-mermaid-svg';w.innerHTML=r.svg;e.replaceWith(w);}catch(x){e.classList.add('elements-markdown-mermaid-error');}}})();";

    class method ToHtml(aSource: nullable String; aOptions: nullable MarkdownOptions := nil): not nullable String;
    begin
      result := MarkdownDocument.Parse(aSource, aOptions).ToHtml;
    end;
  end;

  MarkdownRenderer = assembly static class
  private

    class method EscapeText(aValue: nullable String): not nullable String;
    begin
      var lValue := coalesce(aValue, "");
      result := lValue.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
    end;

    class method EscapeAttribute(aValue: nullable String): not nullable String;
    begin
      result := EscapeText(aValue).Replace("""", "&quot;");
    end;

    class method AppendEscapedCharacter(aOutput: not nullable StringBuilder; aCharacter: Char);
    begin
      case aCharacter of
        '&': aOutput.Append("&amp;");
        '<': aOutput.Append("&lt;");
        '>': aOutput.Append("&gt;");
      else
        aOutput.Append(aCharacter);
      end;
    end;

    class method Lines(aSource: not nullable String): not nullable List<String>;
    begin
      result := new List<String>;
      var lStart := 0;
      for i: Integer := 0 to aSource.Length do begin
        if (i = aSource.Length) or (aSource[i] = #10) then begin
          var lLine := aSource.Substring(lStart, i - lStart);
          if lLine.EndsWith(#13) then
            lLine := lLine.Substring(0, lLine.Length - 1);
          result.Add(lLine);
          lStart := i + 1;
        end;
      end;
    end;

    class method IsBlank(aLine: not nullable String): Boolean;
    begin
      result := length(aLine:Trim) = 0;
    end;

    class method IsThematicBreak(aLine: not nullable String): Boolean;
    begin
      var lValue := aLine.Replace(" ", "").Replace("\t", "");
      if lValue.Length < 3 then exit false;
      var lMarker := lValue[0];
      if not (lMarker in ['-', '*', '_']) then exit false;
      for each lChar in lValue do
        if lChar <> lMarker then exit false;
      result := true;
    end;

    class method HeadingLevel(aLine: not nullable String; out aText: String): Integer;
    begin
      aText := "";
      var lIndex := 0;
      while (lIndex < aLine.Length) and (aLine[lIndex] = '#') do inc(lIndex);
      if (lIndex = 0) or (lIndex > 6) or (lIndex = aLine.Length) or not aLine[lIndex].IsWhitespace then exit 0;
      aText := aLine.Substring(lIndex):Trim;
      while aText.EndsWith("#") do aText := aText.Substring(0, aText.Length - 1):Trim;
      result := lIndex;
    end;

    class method FenceInfo(aLine: not nullable String; out aMarker: Char; out aInfo: String): Boolean;
    begin
      aMarker := #0;
      aInfo := "";
      var lTrimmed := aLine:Trim;
      if lTrimmed.Length < 3 then exit false;
      aMarker := lTrimmed[0];
      if not (aMarker in ['`', '~']) then exit false;
      var lCount := 0;
      while (lCount < lTrimmed.Length) and (lTrimmed[lCount] = aMarker) do inc(lCount);
      if lCount < 3 then exit false;
      aInfo := lTrimmed.Substring(lCount):Trim;
      result := true;
    end;

    class method IsTableDelimiter(aLine: not nullable String): Boolean;
    begin
      var lTrimmed := aLine:Trim;
      if lTrimmed.StartsWith("|") then lTrimmed := lTrimmed.Substring(1);
      if lTrimmed.EndsWith("|") then lTrimmed := lTrimmed.Substring(0, lTrimmed.Length - 1);
      var lParts := lTrimmed.Split('|');
      if length(lParts) = 0 then exit false;
      for each lPart in lParts do begin
        var lPartTrimmed := lPart:Trim;
        if lPartTrimmed.StartsWith(":") then lPartTrimmed := lPartTrimmed.Substring(1);
        if lPartTrimmed.EndsWith(":") then lPartTrimmed := lPartTrimmed.Substring(0, lPartTrimmed.Length - 1);
        if lPartTrimmed.Length < 1 then exit false;
        for each lChar in lPartTrimmed do
          if lChar <> '-' then exit false;
      end;
      result := true;
    end;

    class method TableCells(aLine: not nullable String): not nullable List<String>;
    begin
      var lValue := aLine:Trim;
      if lValue.StartsWith("|") then lValue := lValue.Substring(1);
      if lValue.EndsWith("|") then lValue := lValue.Substring(0, lValue.Length - 1);
      result := new List<String>;
      for each lCell in lValue.Split('|') do result.Add(lCell:Trim);
    end;

    class method TableAlignments(aLine: not nullable String): not nullable List<String>;
    begin
      result := new List<String>;
      for each lCell in TableCells(aLine) do begin
        var lCellTrimmed := lCell:Trim;
        var lStartsWithColon := lCellTrimmed.StartsWith(":");
        var lEndsWithColon := lCellTrimmed.EndsWith(":");
        if lStartsWithColon and lEndsWithColon then
          result.Add("center")
        else if lEndsWithColon then
          result.Add("right")
        else
          result.Add("left");
      end;
    end;

    class method TableAlignmentAttribute(aAlignments: not nullable List<String>; aIndex: Integer): not nullable String;
    begin
      if aIndex >= aAlignments.Count then
        exit "";
      result := " style=""text-align: " + aAlignments[aIndex] + ";""";
    end;

    class method QuoteContent(aLine: not nullable String; out aContent: String): Boolean;
    begin
      aContent := "";
      var lTrimmed := aLine:Trim;
      if not lTrimmed.StartsWith(">") then
        exit false;
      aContent := lTrimmed.Substring(1);
      if aContent.StartsWith(" ") then
        aContent := aContent.Substring(1);
      result := true;
    end;

    class method AlertKind(aText: not nullable String): nullable String;
    begin
      var lText := aText:Trim;
      if not lText.StartsWith("[!") then
        exit;
      var lEnd := lText.IndexOf(']');
      if lEnd < 3 then
        exit;
      var lKind := lText.Substring(2, lEnd - 2):ToLower;
      if lKind in ["note", "tip", "important", "warning", "caution"] then
        result := lKind;
    end;

    class method Slug(aText: not nullable String; aCounts: not nullable Dictionary<String, Integer>): not nullable String;
    begin
      var lBuilder := new StringBuilder;
      var lDash := false;
      for each lChar in aText:ToLower do begin
        if lChar.IsLetterOrNumber then begin lBuilder.Append(lChar); lDash := false; end
        else if not lDash then begin lBuilder.Append('-'); lDash := true; end;
      end;
      var lResult: not nullable String := (lBuilder.ToString as String as not nullable):Trim('-');
      if length(lResult) = 0 then lResult := "section";
      var lCount := coalesce(aCounts[lResult], 0);
      aCounts[lResult] := lCount + 1;
      if lCount > 0 then lResult := lResult + "-" + lCount.ToString;
      result := lResult;
    end;

    class method &Inline(aText: not nullable String; aOptions: not nullable MarkdownOptions): not nullable String;
    begin
      var lOutput := new StringBuilder;
      var i := 0;
      while i < aText.Length do begin
        if (aText[i] = '\\') and (i + 1 < aText.Length) then begin
          AppendEscapedCharacter(lOutput, aText[i + 1]); inc(i, 2); continue;
        end;
        if aOptions.AllowRawHtml and (aText[i] = '<') then begin
          var lEnd := aText.IndexOf('>', i + 1);
          if lEnd >= 0 then begin lOutput.Append(aText.Substring(i, lEnd - i + 1)); i := lEnd + 1; continue; end;
        end;
        if aOptions.EnableAutolinks and (aText[i] = '<') then begin
          var lEnd := aText.IndexOf('>', i + 1);
          if lEnd >= 0 then begin
            var lUrl := aText.Substring(i + 1, lEnd - i - 1);
            if lUrl.Contains(":") then begin lOutput.Append("<a href="""); lOutput.Append(EscapeAttribute(lUrl)); lOutput.Append(""">"); lOutput.Append(EscapeText(lUrl)); lOutput.Append("</a>"); i := lEnd + 1; continue; end;
          end;
        end;
        if (aText[i] = '`') then begin
          var lEnd := aText.IndexOf('`', i + 1);
          if lEnd >= 0 then begin lOutput.Append("<code>"); lOutput.Append(EscapeText(aText.Substring(i + 1, lEnd - i - 1))); lOutput.Append("</code>"); i := lEnd + 1; continue; end;
        end;
        if aOptions.EnableStrikethrough and (i + 1 < aText.Length) and (aText.Substring(i, 2) = "~~") then begin
          var lEnd := aText.IndexOf("~~", i + 2);
          if lEnd >= 0 then begin lOutput.Append("<del>"); lOutput.Append(&Inline(aText.Substring(i + 2, lEnd - i - 2), aOptions)); lOutput.Append("</del>"); i := lEnd + 2; continue; end;
        end;
        var lMarker := if (i + 1 < aText.Length) and ((aText.Substring(i, 2) = "**") or (aText.Substring(i, 2) = "__")) then aText.Substring(i, 2) else aText[i].ToString;
        if (lMarker = "*") or (lMarker = "_") or (lMarker = "**") or (lMarker = "__") then begin
          var lEnd := aText.IndexOf(lMarker, i + lMarker.Length);
          if lEnd >= 0 then begin
            lOutput.Append(if lMarker.Length = 2 then "<strong>" else "<em>");
            lOutput.Append(&Inline(aText.Substring(i + lMarker.Length, lEnd - i - lMarker.Length), aOptions));
            lOutput.Append(if lMarker.Length = 2 then "</strong>" else "</em>");
            i := lEnd + lMarker.Length; continue;
          end;
        end;
        if (aText[i] = '!') and (i + 1 < aText.Length) and (aText[i + 1] = '[') then begin
          var lBracket := aText.IndexOf(']', i + 2);
          if (lBracket >= 0) and (lBracket + 1 < aText.Length) and (aText[lBracket + 1] = '(') then begin
            var lEnd := aText.IndexOf(')', lBracket + 2);
            if lEnd >= 0 then begin lOutput.Append("<img src="""); lOutput.Append(EscapeAttribute(aText.Substring(lBracket + 2, lEnd - lBracket - 2))); lOutput.Append(""" alt="""); lOutput.Append(EscapeAttribute(aText.Substring(i + 2, lBracket - i - 2))); lOutput.Append(""" />"); i := lEnd + 1; continue; end;
          end;
        end;
        if aText[i] = '[' then begin
          var lBracket := aText.IndexOf(']', i + 1);
          if (lBracket >= 0) and (lBracket + 1 < aText.Length) and (aText[lBracket + 1] = '(') then begin
            var lEnd := aText.IndexOf(')', lBracket + 2);
            if lEnd >= 0 then begin lOutput.Append("<a href="""); lOutput.Append(EscapeAttribute(aText.Substring(lBracket + 2, lEnd - lBracket - 2))); lOutput.Append(""">"); lOutput.Append(&Inline(aText.Substring(i + 1, lBracket - i - 1), aOptions)); lOutput.Append("</a>"); i := lEnd + 1; continue; end;
          end;
        end;
        AppendEscapedCharacter(lOutput, aText[i]); inc(i);
      end;
      result := lOutput.ToString;
    end;

  public
    class method Render(aSource: not nullable String; aOptions: not nullable MarkdownOptions): not nullable String;
    begin
      var lLines := Lines(aSource);
      var lOutput := new StringBuilder;
      var lHeadings := new Dictionary<String, Integer>;
      var lContainsMermaid := false;
      var i := 0;
      while i < lLines.Count do begin
        if IsBlank(lLines[i]) then begin
          inc(i);
          continue;
        end;

        var lFenceMarker: Char;
        var lFenceInfo: String;
        if FenceInfo(lLines[i], out lFenceMarker, out lFenceInfo) then begin
          inc(i);
          var lCode := new StringBuilder;
          while i < lLines.Count do begin
            var lCloseMarker: Char;
            var lCloseInfo: String;
            if FenceInfo(lLines[i], out lCloseMarker, out lCloseInfo) and (lCloseMarker = lFenceMarker) then
              break;

            if lCode.Length > 0 then
              lCode.Append(#10);

            lCode.Append(lLines[i]);
            inc(i);
          end;
          if i < lLines.Count then
            inc(i);
          if lFenceInfo:ToLower = "mermaid" then begin lOutput.Append("<pre class=""elements-markdown-mermaid mermaid"">"); lOutput.Append(EscapeText(lCode.ToString)); lOutput.Append("</pre>" + #10); lContainsMermaid := true; end
          else begin lOutput.Append("<pre><code"); if lFenceInfo.Length > 0 then lOutput.Append(" class=""language-" + EscapeAttribute(lFenceInfo) + """"); lOutput.Append(">"); lOutput.Append(EscapeText(lCode.ToString)); lOutput.Append("</code></pre>" + #10); end;
          continue;
        end;
        var lHeadingText: String;
        var lLevel := HeadingLevel(lLines[i], out lHeadingText);
        if lLevel > 0 then begin
          lOutput.Append("<h" + lLevel.ToString);
          if aOptions.GenerateHeadingIds then lOutput.Append(" id=""" + Slug(lHeadingText, lHeadings) + """");
          lOutput.Append(">" + &Inline(lHeadingText, aOptions) + "</h" + lLevel.ToString + ">" + #10); inc(i); continue;
        end;
        if IsThematicBreak(lLines[i]) then begin lOutput.Append("<hr />" + #10); inc(i); continue; end;
        var lQuoteContent: String;
        if QuoteContent(lLines[i], out lQuoteContent) then begin
          var lQuoteLines := new List<String>;
          while (i < lLines.Count) and QuoteContent(lLines[i], out lQuoteContent) do begin
            lQuoteLines.Add(lQuoteContent);
            inc(i);
          end;

          var lAlertKind := if aOptions.EnableGitHubAlerts and (lQuoteLines.Count > 0) then AlertKind(lQuoteLines[0]) else nil;
          if assigned(lAlertKind) then
            lQuoteLines.RemoveAt(0);

          lOutput.Append("<blockquote");
          if assigned(lAlertKind) then
            lOutput.Append(" class=""elements-markdown-alert elements-markdown-alert-" + lAlertKind + """");
          lOutput.Append(">" + #10);
          if assigned(lAlertKind) then
            lOutput.Append("<p class=""elements-markdown-alert-title""><strong>" + lAlertKind:Substring(0, 1):ToUpper + lAlertKind:Substring(1) + "</strong></p>" + #10);
          if lQuoteLines.Count > 0 then
            lOutput.Append("<p>" + &Inline(lQuoteLines.JoinedString(#10), aOptions).Replace(String(#10), "<br />" + #10) + "</p>" + #10);
          lOutput.Append("</blockquote>" + #10);
          continue;
        end;
        if aOptions.EnableTables and (i + 1 < lLines.Count) and lLines[i].Contains("|") and IsTableDelimiter(lLines[i + 1]) then begin
          var lHeaders := TableCells(lLines[i]); var lAlignments := TableAlignments(lLines[i + 1]); lOutput.Append("<table><thead><tr>");
          for each lCell in lHeaders index lCellIndex do lOutput.Append("<th" + TableAlignmentAttribute(lAlignments, lCellIndex) + ">" + &Inline(lCell, aOptions) + "</th>");
          lOutput.Append("</tr></thead><tbody>" + #10); i := i + 2;
          while (i < lLines.Count) and lLines[i].Contains("|") and not IsBlank(lLines[i]) do begin var lCells := TableCells(lLines[i]); lOutput.Append("<tr>"); for each lCell in lCells index lCellIndex do lOutput.Append("<td" + TableAlignmentAttribute(lAlignments, lCellIndex) + ">" + &Inline(lCell, aOptions) + "</td>"); lOutput.Append("</tr>" + #10); inc(i); end;
          lOutput.Append("</tbody></table>" + #10); continue;
        end;
        if lLines[i]:Trim.StartsWith("- ") or lLines[i]:Trim.StartsWith("* ") then begin
          lOutput.Append("<ul>" + #10);
          while (i < lLines.Count) and (lLines[i]:Trim.StartsWith("- ") or lLines[i]:Trim.StartsWith("* ")) do begin
            var lItem := lLines[i]:Trim.Substring(2);
            if aOptions.EnableTaskLists and ((lItem.StartsWith("[ ] ")) or (lItem.StartsWith("[x] ")) or (lItem.StartsWith("[X] "))) then begin
              var lChecked := lItem[1] in ['x', 'X'];
              lItem := lItem.Substring(4);
              lOutput.Append("<li class=""task-list-item""><input type=""checkbox"" disabled" + if lChecked then " checked" else "" + " /> ");
            end
            else begin
              lOutput.Append("<li>");
            end;

            lOutput.Append(&Inline(lItem, aOptions) + "</li>" + #10);
            inc(i);
          end;
          lOutput.Append("</ul>" + #10); continue;
        end;
        var lParagraph := new StringBuilder;
        while (i < lLines.Count) and not IsBlank(lLines[i]) do begin
          if lParagraph.Length > 0 then lParagraph.Append(#10); lParagraph.Append(lLines[i]); inc(i);
        end;
        lOutput.Append("<p>" + &Inline(lParagraph.ToString, aOptions).Replace(String(#10), "<br />" + #10) + "</p>" + #10);
      end;
      if aOptions.IncludeMermaidRuntime and lContainsMermaid then begin
        lOutput.Append("<script>");
        lOutput.Append(Markdown.MermaidRuntimeJavaScript);
        lOutput.Append("</script>" + #10 + "<script>");
        lOutput.Append(Markdown.MermaidBootstrapJavaScript);
        lOutput.Append("</script>" + #10);
      end;

      result := lOutput.ToString;
    end;
  end;

end.
