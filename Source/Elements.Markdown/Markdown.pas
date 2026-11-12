namespace RemObjects.Elements.RTL.Markdown;

// Clean-room Markdown parser and HTML renderer. It intentionally has no
// dependency on MarkdownDeep, CocoaMarkdown, or platform framework APIs.

type
  MarkdownDialect = public enum (CommonMark, GitHub);

  MarkdownUrlRewriter = public block(aUrl: not nullable String): nullable String;

  MarkdownOptions = public class
  public
    property AllowRawHtml: Boolean;
    // Return nil to preserve the destination, or an empty string to clear it.
    property RewriteUrl: nullable MarkdownUrlRewriter;
    property EnableTables: Boolean;
    property EnableStrikethrough: Boolean;
    property EnableTaskLists: Boolean;
    property EnableAutolinks: Boolean;
    property GenerateHeadingIds: Boolean;
    property UseLegacyHeadingIds: Boolean;
    property EnableFootnotes: Boolean;
    property EnableGitHubAlerts: Boolean;
    property IncludeMermaidRuntime: Boolean;

    constructor;
    begin
      EnableTables := true;
      EnableStrikethrough := true;
      EnableTaskLists := true;
      EnableAutolinks := true;
      GenerateHeadingIds := true;
      EnableFootnotes := true;
      EnableGitHubAlerts := true;
    end;

    constructor withDialect(aDialect: MarkdownDialect);
    begin
      EnableTables := aDialect = MarkdownDialect.GitHub;
      EnableStrikethrough := aDialect = MarkdownDialect.GitHub;
      EnableTaskLists := aDialect = MarkdownDialect.GitHub;
      EnableAutolinks := true;
      GenerateHeadingIds := aDialect = MarkdownDialect.GitHub;
      EnableFootnotes := aDialect = MarkdownDialect.GitHub;
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

  MarkdownFootnote = assembly class
  public
    property LabelName: not nullable String;
    property Lines: not nullable List<String> := new List<String>;
    property Number: Integer;
    property ReferenceCount: Integer;

    constructor(aLabel: not nullable String);
    begin
      LabelName := aLabel;
    end;

    method ReferenceId(aOccurrence: Integer): not nullable String;
    begin
      result := "fnref:" + LabelName;
      if aOccurrence > 1 then
        result := result + ":" + aOccurrence.ToString;
    end;
  end;

  MarkdownFootnotes = assembly class
  public
    property Definitions: not nullable Dictionary<String, MarkdownFootnote> := new Dictionary<String, MarkdownFootnote>;
    property Ordered: not nullable List<MarkdownFootnote> := new List<MarkdownFootnote>;
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

    class method IsAsciiLetter(aCharacter: Char): Boolean;
    begin
      result := ((aCharacter >= 'a') and (aCharacter <= 'z')) or ((aCharacter >= 'A') and (aCharacter <= 'Z'));
    end;

    class method IsAsciiDigit(aCharacter: Char): Boolean;
    begin
      result := (aCharacter >= '0') and (aCharacter <= '9');
    end;

    class method IsHtmlTagNameCharacter(aCharacter: Char): Boolean;
    begin
      result := IsAsciiLetter(aCharacter) or IsAsciiDigit(aCharacter) or (aCharacter = '-');
    end;

    class method IsHtmlAttributeNameStart(aCharacter: Char): Boolean;
    begin
      result := IsAsciiLetter(aCharacter) or (aCharacter = '_') or (aCharacter = ':');
    end;

    class method IsHtmlAttributeNameCharacter(aCharacter: Char): Boolean;
    begin
      result := IsHtmlAttributeNameStart(aCharacter) or IsAsciiDigit(aCharacter) or (aCharacter = '.') or (aCharacter = '-');
    end;

    class method RawHtmlEnd(aText: not nullable String; aStart: Integer): Integer;
    begin
      result := -1;
      if (aStart < 0) or (aStart >= aText.Length) or (aText[aStart] <> '<') then
        exit;

      if (aStart + 1 < aText.Length) and (aText[aStart + 1] = '?') then begin
        var lEnd := aText.IndexOf("?>", aStart + 2);
        if lEnd >= 0 then
          result := lEnd + 1;
        exit;
      end;

      if (aStart + 8 < aText.Length) and (aText.Substring(aStart, 9) = "<![CDATA[") then begin
        var lEnd := aText.IndexOf("]]>", aStart + 9);
        if lEnd >= 0 then
          result := lEnd + 2;
        exit;
      end;

      if (aStart + 2 < aText.Length) and (aText[aStart + 1] = '!') and IsAsciiLetter(aText[aStart + 2]) then begin
        var lEnd := aText.IndexOf('>', aStart + 3);
        if lEnd >= 0 then
          result := lEnd;
        exit;
      end;

      var lIndex := aStart + 1;
      var lClosing := false;
      if (lIndex < aText.Length) and (aText[lIndex] = '/') then begin
        lClosing := true;
        inc(lIndex);
      end;

      if (lIndex >= aText.Length) or not IsAsciiLetter(aText[lIndex]) then
        exit;
      inc(lIndex);
      while (lIndex < aText.Length) and IsHtmlTagNameCharacter(aText[lIndex]) do
        inc(lIndex);

      if lClosing then begin
        while (lIndex < aText.Length) and aText[lIndex].IsWhitespace do
          inc(lIndex);
        if (lIndex < aText.Length) and (aText[lIndex] = '>') then
          result := lIndex;
        exit;
      end;

      while lIndex < aText.Length do begin
        if aText[lIndex] = '>' then
          exit lIndex;
        if aText[lIndex] = '/' then begin
          if (lIndex + 1 < aText.Length) and (aText[lIndex + 1] = '>') then
            exit lIndex + 1;
          exit;
        end;
        if not aText[lIndex].IsWhitespace then
          exit;

        while (lIndex < aText.Length) and aText[lIndex].IsWhitespace do
          inc(lIndex);
        if lIndex >= aText.Length then
          exit;
        if aText[lIndex] = '>' then
          exit lIndex;
        if aText[lIndex] = '/' then begin
          if (lIndex + 1 < aText.Length) and (aText[lIndex + 1] = '>') then
            exit lIndex + 1;
          exit;
        end;
        if not IsHtmlAttributeNameStart(aText[lIndex]) then
          exit;

        inc(lIndex);
        while (lIndex < aText.Length) and IsHtmlAttributeNameCharacter(aText[lIndex]) do
          inc(lIndex);
        while (lIndex < aText.Length) and aText[lIndex].IsWhitespace do
          inc(lIndex);
        if (lIndex < aText.Length) and (aText[lIndex] = '=') then begin
          inc(lIndex);
          while (lIndex < aText.Length) and aText[lIndex].IsWhitespace do
            inc(lIndex);
          if lIndex >= aText.Length then
            exit;

          if (aText[lIndex] = Char(34)) or (aText[lIndex] = Char(39)) then begin
            var lQuote := aText[lIndex];
            inc(lIndex);
            while (lIndex < aText.Length) and (aText[lIndex] <> lQuote) do
              inc(lIndex);
            if lIndex >= aText.Length then
              exit;
            inc(lIndex);
          end
          else begin
            var lValueStart := lIndex;
            while (lIndex < aText.Length) and not aText[lIndex].IsWhitespace and not (aText[lIndex] in [Char(34), Char(39), '=', '<', '>', '`']) do
              inc(lIndex);
            if lIndex = lValueStart then
              exit;
          end;
        end;
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

    class method HeadingLevel(aLine: not nullable String; out aText: String; aLegacy: Boolean := false): Integer;
    begin
      aText := "";
      var lIndex := 0;
      while (lIndex < aLine.Length) and (aLine[lIndex] = '#') do inc(lIndex);
      if (lIndex = 0) or (lIndex > 6) or (lIndex = aLine.Length) or (not aLegacy and not aLine[lIndex].IsWhitespace) then exit 0;
      aText := aLine.Substring(lIndex):Trim;
      while aText.EndsWith("#") do aText := aText.Substring(0, aText.Length - 1):Trim;
      result := lIndex;
    end;

    class method SetextHeadingLevel(aLine: not nullable String): Integer;
    begin
      var lUnderline := aLine.TrimEnd;
      if (lUnderline.Length = 0) or not (lUnderline[0] in ['=', '-']) then
        exit 0;
      for each lCharacter in lUnderline do
        if lCharacter <> lUnderline[0] then
          exit 0;
      result := if lUnderline[0] = '=' then 1 else 2;
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
        if lChar.IsLetterOrNumber then begin
          lBuilder.Append(lChar);
          lDash := false;
        end
        else if not lDash then begin
          lBuilder.Append('-');
          lDash := true;
        end;
      end;
      var lResult := (lBuilder.ToString as String):Trim('-');
      if length(lResult) = 0 then
        lResult := "section";
      var lCount := coalesce(aCounts[lResult], 0);
      aCounts[lResult] := lCount + 1;
      if lCount > 0 then
        lResult := lResult + "-" + lCount.ToString;
      result := lResult as not nullable;
    end;

    // Preserve the heading IDs published by MarkdownDeep.
    class method LegacyHeadingId(aText: not nullable String; aUsedIds: not nullable Dictionary<String, Integer>): not nullable String;
    begin
      var lText := new StringBuilder;
      var i := 0;
      while i < aText.Length do begin
        if (aText[i] = #92) and (i + 1 < aText.Length) and
           (aText[i + 1] in [#33..#47, #58..#64, #91..#96, #123..#126]) then begin
          inc(i, 2);
          continue;
        end;
        if aText[i] = '&' then begin
          var lEnd := i + 1;
          if (lEnd < aText.Length) and (aText[lEnd] = '#') then
            inc(lEnd);
          var lNameStart := lEnd;
          while (lEnd < aText.Length) and (IsAsciiLetter(aText[lEnd]) or IsAsciiDigit(aText[lEnd])) do
            inc(lEnd);
          if (lEnd > lNameStart) and (lEnd < aText.Length) and (aText[lEnd] = ';') then begin
            i := lEnd + 1;
            continue;
          end;
        end;
        if (aText[i] = '_') and ((i = 0) or not aText[i - 1].IsLetterOrNumber) then begin
          var lDelimiter := if (i + 1 < aText.Length) and (aText[i + 1] = '_') then "__" else "_";
          var lContent := i + lDelimiter.Length;
          var lEnd := aText.IndexOf(lDelimiter, lContent);
          if (lEnd > lContent) and not aText[lContent].IsWhitespace and not aText[lEnd - 1].IsWhitespace then begin
            lText.Append(aText.Substring(lContent, lEnd - lContent));
            i := lEnd + lDelimiter.Length;
            continue;
          end;
        end;
        if aText[i] = '`' then begin
          var lStart := i;
          while (i < aText.Length) and (aText[i] = '`') do
            inc(i);
          var lDelimiter := aText.Substring(lStart, i - lStart);
          var lEnd := aText.IndexOf(lDelimiter, i);
          while lEnd >= 0 do begin
            var lAfter := lEnd + lDelimiter.Length;
            if (aText[lEnd - 1] <> '`') and ((lAfter = aText.Length) or (aText[lAfter] <> '`')) then begin
              i := lAfter;
              break;
            end;
            lEnd := aText.IndexOf(lDelimiter, lEnd + 1);
          end;
          continue;
        end;
        if aText[i] = '<' then begin
          var lEnd := RawHtmlEnd(aText, i);
          if lEnd >= 0 then begin
            i := lEnd + 1;
            continue;
          end;
        end;
        if aText[i] = '[' then begin
          var lBracket := aText.IndexOf(']', i + 1);
          if (lBracket > i + 1) and (lBracket + 1 < aText.Length) and (aText[lBracket + 1] = '(') then begin
            var lEnd: Integer;
            if assigned(ReadDestination(aText, lBracket + 2, out lEnd)) then begin
              lText.Append(aText.Substring(i + 1, lBracket - i - 1));
              i := lEnd + 1;
              continue;
            end;
          end;
        end;
        lText.Append(aText[i]);
        inc(i);
      end;

      var lSlug := new StringBuilder;
      for each lCharacter in (lText.ToString as String):ToLowerInvariant do begin
        if (lSlug.Length = 0) and not lCharacter.IsLetter then
          continue;
        if lCharacter.IsLetterOrNumber or (lCharacter in ['_', '-', '.']) then
          lSlug.Append(lCharacter)
        else if lCharacter in [' ', #10] then
          lSlug.Append('-');
      end;

      var lBase := if lSlug.Length > 0 then lSlug.ToString as not nullable else "section";
      result := lBase;
      var lSuffix := 1;
      while aUsedIds.ContainsKey(result) do begin
        result := lBase + "-" + lSuffix.ToString;
        inc(lSuffix);
      end;
      aUsedIds[result] := 1;
    end;

    class method FootnoteLabel(aText: not nullable String; aStart: Integer; aEnd: Integer): nullable String;
    begin
      if (aEnd <= aStart + 2) or (aText[aStart + 1] <> '^') then
        exit nil;

      var lLabel := aText.Substring(aStart + 2, aEnd - aStart - 2);
      for each lCharacter in lLabel do
        if not (lCharacter.IsLetterOrNumber or (lCharacter in ['-', '_', '.'])) then
          exit nil;
      result := lLabel;
    end;

    class method CollectFootnotes(aLines: not nullable List<String>; aOptions: not nullable MarkdownOptions;
      aFootnotes: not nullable MarkdownFootnotes): not nullable List<String>;
    begin
      result := new List<String>;
      var lFence := Char(0);
      var lInComment := false;
      var i := 0;
      while i < aLines.Count do begin
        var lLine := aLines[i];
        inc(i);
        var lTrimmed := lLine.TrimStart;
        var lMarker: Char;
        var lInfo: String;
        if not lInComment and FenceInfo(lLine, out lMarker, out lInfo) then begin
          if lFence = #0 then
            lFence := lMarker
          else if lFence = lMarker then
            lFence := #0;
          result.Add(lLine);
          continue;
        end;
        if (lFence = #0) and aOptions.AllowRawHtml and (lInComment or lTrimmed.StartsWith("<!--")) then begin
          lInComment := not lLine.Contains("-->");
          result.Add(lLine);
          continue;
        end;

        var lLabel: nullable String;
        var lBracket := lTrimmed.IndexOf(']');
        if (lFence = #0) and (lLine.Length - lTrimmed.Length <= 3) and
           not lLine.StartsWith(#9) and lTrimmed.StartsWith("[^") and
           (lBracket >= 0) and (lBracket + 1 < lTrimmed.Length) and (lTrimmed[lBracket + 1] = ':') then
          lLabel := FootnoteLabel(lTrimmed, 0, lBracket);
        if not assigned(lLabel) then begin
          result.Add(lLine);
          continue;
        end;

        var lNote := new MarkdownFootnote(lLabel);
        lNote.Lines.Add(lTrimmed.Substring(lBracket + 2).TrimStart);
        var lBlankCount := 0;
        while i < aLines.Count do begin
          lLine := aLines[i];
          if IsBlank(lLine) then begin
            inc(lBlankCount);
            inc(i);
            continue;
          end;

          var lIndent := if lLine.StartsWith("    ") then 4 else if lLine.StartsWith(#9) then 1 else 0;
          if lIndent = 0 then begin
            var lHeading: String;
            // A definition may start on the following line, as in Markdown Extra.
            if (lBlankCount > 0) or (lNote.Lines.Count <> 1) or not IsBlank(lNote.Lines[0]) or
               lLine.TrimStart.StartsWith("[^") or FenceInfo(lLine, out lMarker, out lInfo) or
               (HeadingLevel(lLine, out lHeading) > 0) then
              break;
          end;

          for lBlank := 1 to lBlankCount do
            lNote.Lines.Add("");
          lBlankCount := 0;
          lNote.Lines.Add(lLine.Substring(lIndent));
          inc(i);
        end;
        if not aFootnotes.Definitions.ContainsKey(lLabel) then
          aFootnotes.Definitions[lLabel] := lNote;
        result.Add("");
      end;
    end;

    class method ReadDestination(aText: not nullable String; aStart: Integer; out aEnd: Integer): nullable String;
    begin
      aEnd := -1;
      var lDepth := 0;
      var lSegmentStart := aStart;
      var lDecoded: nullable StringBuilder;
      var i := aStart;
      while i < aText.Length do begin
        var lCharacter := aText[i];
        if lCharacter.IsWhitespace then
          exit nil;
        if (lCharacter = #92) and (i + 1 < aText.Length) and (aText[i + 1] in ['(', ')', #92]) then begin
          if not assigned(lDecoded) then
            lDecoded := new StringBuilder;
          lDecoded.Append(aText.Substring(lSegmentStart, i - lSegmentStart));
          lDecoded.Append(aText[i + 1]);
          inc(i, 2);
          lSegmentStart := i;
          continue;
        end;
        if lCharacter = '(' then
          inc(lDepth)
        else if lCharacter = ')' then begin
          if lDepth = 0 then begin
            aEnd := i;
            var lTail := aText.Substring(lSegmentStart, i - lSegmentStart);
            if not assigned(lDecoded) then
              exit lTail;
            lDecoded.Append(lTail);
            exit lDecoded.ToString;
          end;
          dec(lDepth);
        end;
        inc(i);
      end;
      exit nil;
    end;

    class method IsAutolinkUrl(aUrl: not nullable String): Boolean;
    begin
      var lColon := aUrl.IndexOf(':');
      if (lColon < 2) or (lColon > 32) or not IsAsciiLetter(aUrl[0]) then
        exit false;
      for i := 1 to lColon - 1 do
        if not (IsAsciiLetter(aUrl[i]) or IsAsciiDigit(aUrl[i]) or (aUrl[i] in ['+', '-', '.'])) then
          exit false;
      for i := lColon + 1 to aUrl.Length - 1 do
        if aUrl[i].IsWhitespace or (aUrl[i] in ['<', '>']) then
          exit false;
      result := true;
    end;

    class method RewriteDestination(aUrl: not nullable String; aOptions: not nullable MarkdownOptions): not nullable String;
    begin
      var lRewrite := aOptions.RewriteUrl;
      if assigned(lRewrite) then
        exit coalesce(lRewrite(aUrl), aUrl);
      result := aUrl;
    end;

    class method &Inline(aText: not nullable String; aOptions: not nullable MarkdownOptions;
      aFootnotes: nullable MarkdownFootnotes): not nullable String;
    begin
      var lOutput := new StringBuilder;
      var i := 0;
      while i < aText.Length do begin
        if (aText[i] = Char(92)) and (i + 1 < aText.Length) and
           (aText[i + 1] in [#33..#47, #58..#64, #91..#96, #123..#126]) then begin
          AppendEscapedCharacter(lOutput, aText[i + 1]); inc(i, 2); continue;
        end;
        if aOptions.AllowRawHtml and (i + 3 < aText.Length) and (aText.Substring(i, 4) = "<!--") then begin
          var lEnd := aText.IndexOf("-->", i + 4);
          if lEnd >= 0 then begin
            lOutput.Append(aText.Substring(i, lEnd - i + 3));
            i := lEnd + 3;
            continue;
          end;
        end;
        if aOptions.AllowRawHtml and (aText[i] = '<') then begin
          var lEnd := RawHtmlEnd(aText, i);
          if lEnd >= 0 then begin lOutput.Append(aText.Substring(i, lEnd - i + 1)); i := lEnd + 1; continue; end;
        end;
        if aOptions.EnableAutolinks and (aText[i] = '<') then begin
          var lEnd := aText.IndexOf('>', i + 1);
          if lEnd >= 0 then begin
            var lUrl := aText.Substring(i + 1, lEnd - i - 1);
            if IsAutolinkUrl(lUrl) then begin
              lOutput.Append("<a href=""" + EscapeAttribute(RewriteDestination(lUrl, aOptions)) + """>");
              lOutput.Append(EscapeText(lUrl));
              lOutput.Append("</a>");
              i := lEnd + 1;
              continue;
            end;
          end;
        end;
        if (aText[i] = '`') then begin
          var lEnd := aText.IndexOf('`', i + 1);
          if lEnd >= 0 then begin lOutput.Append("<code>"); lOutput.Append(EscapeText(aText.Substring(i + 1, lEnd - i - 1))); lOutput.Append("</code>"); i := lEnd + 1; continue; end;
        end;
        if aOptions.EnableStrikethrough and (i + 1 < aText.Length) and (aText.Substring(i, 2) = "~~") then begin
          var lEnd := aText.IndexOf("~~", i + 2);
          if lEnd >= 0 then begin lOutput.Append("<del>"); lOutput.Append(&Inline(aText.Substring(i + 2, lEnd - i - 2), aOptions, aFootnotes)); lOutput.Append("</del>"); i := lEnd + 2; continue; end;
        end;
        var lMarker := if (i + 1 < aText.Length) and ((aText.Substring(i, 2) = "**") or (aText.Substring(i, 2) = "__")) then aText.Substring(i, 2) else aText[i].ToString;
        if (lMarker = "*") or (lMarker = "_") or (lMarker = "**") or (lMarker = "__") then begin
          var lEnd := aText.IndexOf(lMarker, i + lMarker.Length);
          if lEnd >= 0 then begin
            lOutput.Append(if lMarker.Length = 2 then "<strong>" else "<em>");
            lOutput.Append(&Inline(aText.Substring(i + lMarker.Length, lEnd - i - lMarker.Length), aOptions, aFootnotes));
            lOutput.Append(if lMarker.Length = 2 then "</strong>" else "</em>");
            i := lEnd + lMarker.Length; continue;
          end;
        end;
        if (aText[i] = '!') and (i + 1 < aText.Length) and (aText[i + 1] = '[') then begin
          var lBracket := aText.IndexOf(']', i + 2);
          if (lBracket >= 0) and (lBracket + 1 < aText.Length) and (aText[lBracket + 1] = '(') then begin
            var lEnd: Integer;
            var lDestination := ReadDestination(aText, lBracket + 2, out lEnd);
            if assigned(lDestination) then begin
              var lUrl := RewriteDestination(lDestination, aOptions);
              lOutput.Append("<img src=""");
              lOutput.Append(EscapeAttribute(lUrl));
              lOutput.Append(""" alt=""");
              lOutput.Append(EscapeAttribute(aText.Substring(i + 2, lBracket - i - 2)));
              lOutput.Append(""" />");
              i := lEnd + 1;
              continue;
            end;
          end;
        end;
        if aText[i] = '[' then begin
          var lBracket := aText.IndexOf(']', i + 1);
          if (lBracket > i + 1) and (lBracket + 1 < aText.Length) and (aText[lBracket + 1] = '(') then begin
            var lEnd: Integer;
            var lDestination := ReadDestination(aText, lBracket + 2, out lEnd);
            if assigned(lDestination) then begin
              var lUrl := RewriteDestination(lDestination, aOptions);
              lOutput.Append("<a href=""");
              lOutput.Append(EscapeAttribute(lUrl));
              lOutput.Append(""">");
              lOutput.Append(&Inline(aText.Substring(i + 1, lBracket - i - 1), aOptions, nil));
              lOutput.Append("</a>");
              i := lEnd + 1;
              continue;
            end;
          end;
        end;
        if assigned(aFootnotes) and (aText[i] = '[') then begin
          var lEnd := aText.IndexOf(']', i + 1);
          var lLabel := FootnoteLabel(aText, i, lEnd);
          var lNote := if assigned(lLabel) then aFootnotes.Definitions[lLabel] else nil;
          if assigned(lNote) then begin
            if lNote.Number = 0 then begin
              aFootnotes.Ordered.Add(lNote);
              lNote.Number := aFootnotes.Ordered.Count;
            end;
            lNote.ReferenceCount := lNote.ReferenceCount + 1;
            lOutput.Append("<sup id=""" + lNote.ReferenceId(lNote.ReferenceCount) + """><a href=""#fn:" +
              lNote.LabelName + """ rel=""footnote"">" + lNote.Number.ToString + "</a></sup>");
            i := lEnd + 1;
            continue;
          end;
        end;
        AppendEscapedCharacter(lOutput, aText[i]); inc(i);
      end;
      result := lOutput.ToString as not nullable;
    end;

    class method BulletItem(aLine: not nullable String; out aIndent: Integer; out aText: String): Boolean;
    begin
      aIndent := 0;
      aText := "";
      var lIndex := 0;
      while (lIndex < aLine.Length) and (aLine[lIndex] in [' ', #9]) do begin
        if aLine[lIndex] = #9 then
          aIndent := aIndent + 4 - (aIndent mod 4)
        else
          inc(aIndent);
        inc(lIndex);
      end;
      if (lIndex + 1 >= aLine.Length) or not (aLine[lIndex] in ['-', '*']) or (aLine[lIndex + 1] <> ' ') then
        exit false;
      aText := aLine.Substring(lIndex + 2):TrimEnd;
      result := true;
    end;

    class method RenderBulletList(aLines: not nullable List<String>; var aIndex: Integer;
      aIndent: Integer; aOutput: not nullable StringBuilder; aOptions: not nullable MarkdownOptions; aFootnotes: nullable MarkdownFootnotes);
    begin
      aOutput.Append("<ul>" + #10);
      var lIndent: Integer;
      var lItem: String;
      while (aIndex < aLines.Count) and BulletItem(aLines[aIndex], out lIndent, out lItem) and (lIndent >= aIndent) do begin
        var lContentIndent := lIndent + 2;
        if aOptions.EnableTaskLists and (lItem.StartsWith("[ ] ") or lItem.StartsWith("[x] ") or lItem.StartsWith("[X] ")) then begin
          var lChecked := lItem[1] in ['x', 'X'];
          lItem := lItem.Substring(4);
          aOutput.Append("<li class=""task-list-item""><input type=""checkbox"" disabled" + (if lChecked then " checked" else "") + " /> ");
        end
        else begin
          aOutput.Append("<li>");
        end;
        aOutput.Append(&Inline(lItem, aOptions, aFootnotes));
        inc(aIndex);

        while (aIndex < aLines.Count) and BulletItem(aLines[aIndex], out lIndent, out lItem) and (lIndent >= lContentIndent) do begin
          aOutput.Append(#10);
          RenderBulletList(aLines, var aIndex, lContentIndent, aOutput, aOptions, aFootnotes);
        end;
        aOutput.Append("</li>" + #10);
      end;
      aOutput.Append("</ul>" + #10);
    end;

    class method RenderBlocks(lLines: not nullable List<String>; lOutput: not nullable StringBuilder;
      aOptions: not nullable MarkdownOptions; aFootnotes: nullable MarkdownFootnotes;
      lHeadings: not nullable Dictionary<String, Integer>; var lContainsMermaid: Boolean);
    begin
      var i := 0;
      while i < lLines.Count do begin
        if IsBlank(lLines[i]) then begin
          inc(i);
          continue;
        end;

        if aOptions.AllowRawHtml and lLines[i]:TrimStart.StartsWith("<!--") then begin
          while i < lLines.Count do begin
            lOutput.Append(lLines[i]);
            lOutput.Append(#10);
            var lFinished := lLines[i].Contains("-->");
            inc(i);
            if lFinished then
              break;
          end;
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
        var lLevel := HeadingLevel(lLines[i], out lHeadingText, aOptions.UseLegacyHeadingIds);
        if (lLevel = 0) and aOptions.UseLegacyHeadingIds and (i + 1 < lLines.Count) and
           not IsThematicBreak(lLines[i]) and not lLines[i][0].IsWhitespace and not (lLines[i][0] in ['<', '>']) then begin
          var lIndent: Integer;
          var lItem: String;
          if not BulletItem(lLines[i], out lIndent, out lItem) then begin
            lLevel := SetextHeadingLevel(lLines[i + 1]);
            if lLevel > 0 then begin
              lHeadingText := lLines[i].TrimEnd;
              inc(i);
            end;
          end;
        end;
        if lLevel > 0 then begin
          lOutput.Append("<h" + lLevel.ToString);
          if aOptions.GenerateHeadingIds then begin
            var lId := if aOptions.UseLegacyHeadingIds then LegacyHeadingId(lHeadingText, lHeadings) else Slug(lHeadingText, lHeadings);
            lOutput.Append(" id=""" + EscapeAttribute(lId) + """");
          end;
          lOutput.Append(">" + &Inline(lHeadingText, aOptions, aFootnotes) + "</h" + lLevel.ToString + ">" + #10); inc(i); continue;
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
            lOutput.Append("<p>" + &Inline(lQuoteLines.JoinedString(#10), aOptions, aFootnotes).Replace(String(#10), "<br />" + #10) + "</p>" + #10);
          lOutput.Append("</blockquote>" + #10);
          continue;
        end;
        if aOptions.EnableTables and (i + 1 < lLines.Count) and lLines[i].Contains("|") and IsTableDelimiter(lLines[i + 1]) then begin
          var lHeaders := TableCells(lLines[i]); var lAlignments := TableAlignments(lLines[i + 1]); lOutput.Append("<table><thead><tr>");
          for each lCell in lHeaders index lCellIndex do lOutput.Append("<th" + TableAlignmentAttribute(lAlignments, lCellIndex) + ">" + &Inline(lCell, aOptions, aFootnotes) + "</th>");
          lOutput.Append("</tr></thead><tbody>" + #10); i := i + 2;
          while (i < lLines.Count) and lLines[i].Contains("|") and not IsBlank(lLines[i]) do begin var lCells := TableCells(lLines[i]); lOutput.Append("<tr>"); for each lCell in lCells index lCellIndex do lOutput.Append("<td" + TableAlignmentAttribute(lAlignments, lCellIndex) + ">" + &Inline(lCell, aOptions, aFootnotes) + "</td>"); lOutput.Append("</tr>" + #10); inc(i); end;
          lOutput.Append("</tbody></table>" + #10); continue;
        end;
        var lBulletIndent: Integer;
        var lBulletText: String;
        if BulletItem(lLines[i], out lBulletIndent, out lBulletText) then begin
          RenderBulletList(lLines, var i, 0, lOutput, aOptions, aFootnotes);
          continue;
        end;
        var lParagraph := new StringBuilder;
        while (i < lLines.Count) and not IsBlank(lLines[i]) do begin
          if lParagraph.Length > 0 then begin
            var lInterruptHeadingText: String;
            if HeadingLevel(lLines[i], out lInterruptHeadingText, aOptions.UseLegacyHeadingIds) > 0 then
              break;
            if aOptions.AllowRawHtml and lLines[i]:TrimStart.StartsWith("<!--") then
              break;
            if aOptions.UseLegacyHeadingIds and FenceInfo(lLines[i], out lFenceMarker, out lFenceInfo) then
              break;
          end;
          if lParagraph.Length > 0 then
            lParagraph.Append(#10);
          lParagraph.Append(lLines[i]);
          inc(i);
        end;
        lOutput.Append("<p>" + &Inline(lParagraph.ToString, aOptions, aFootnotes).Replace(String(#10), "<br />" + #10) + "</p>" + #10);
      end;
    end;

  public
    class method Render(aSource: not nullable String; aOptions: not nullable MarkdownOptions): not nullable String;
    begin
      var lLines := Lines(aSource);
      var lFootnotes := if aOptions.EnableFootnotes then new MarkdownFootnotes else nil;
      if assigned(lFootnotes) then
        lLines := CollectFootnotes(lLines, aOptions, lFootnotes);

      var lOutput := new StringBuilder;
      var lHeadings := new Dictionary<String, Integer>;
      var lContainsMermaid := false;
      RenderBlocks(lLines, lOutput, aOptions, lFootnotes, lHeadings, var lContainsMermaid);

      if assigned(lFootnotes) and (lFootnotes.Ordered.Count > 0) then begin
        var lBodies := new List<String>;
        // Rendering a note may discover references to other notes.
        while lBodies.Count < lFootnotes.Ordered.Count do begin
          var lBody := new StringBuilder;
          RenderBlocks(lFootnotes.Ordered[lBodies.Count].Lines, lBody, aOptions, lFootnotes, lHeadings, var lContainsMermaid);
          lBodies.Add(lBody.ToString);
        end;

        lOutput.Append("<div class=""footnotes"">" + #10 + "<hr />" + #10 + "<ol>" + #10);
        for each lNote in lFootnotes.Ordered index lIndex do begin
          lOutput.Append("<li id=""fn:" + lNote.LabelName + """>" + #10);
          var lBody := lBodies[lIndex];
          var lEndsInParagraph := lBody.EndsWith("</p>" + #10);
          if lEndsInParagraph then
            lOutput.Append(lBody.Substring(0, lBody.Length - 5))
          else begin
            lOutput.Append(lBody);
            lOutput.Append("<p>");
          end;

          for lOccurrence := 1 to lNote.ReferenceCount do begin
            if lEndsInParagraph or (lOccurrence > 1) then
              lOutput.Append("&nbsp;");
            lOutput.Append("<a href=""#" + lNote.ReferenceId(lOccurrence) + """ rev=""footnote"" aria-label=""Back to reference " +
              lNote.Number.ToString + (if lOccurrence > 1 then ", occurrence " + lOccurrence.ToString else "") + """>&#8617;</a>");
          end;
          lOutput.Append("</p>" + #10 + "</li>" + #10);
        end;
        lOutput.Append("</ol>" + #10 + "</div>" + #10);
      end;

      if aOptions.IncludeMermaidRuntime and lContainsMermaid then begin
        lOutput.Append("<script>");
        lOutput.Append(Markdown.MermaidRuntimeJavaScript);
        lOutput.Append("</script>" + #10 + "<script>");
        lOutput.Append(Markdown.MermaidBootstrapJavaScript);
        lOutput.Append("</script>" + #10);
      end;

      result := lOutput.ToString as not nullable;
    end;
  end;

end.
