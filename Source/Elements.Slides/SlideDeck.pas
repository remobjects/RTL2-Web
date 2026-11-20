namespace RemObjects.Elements.Slides;

uses RemObjects.Elements.RTL.Markdown;

type
  SlideReveals = assembly class
  private

    field fPrefix := "ESPReveal" + (NSUUID.UUID.UUIDString as String).Replace("-", "");
    field fReplacements := new Dictionary<String, String>;
    field fOpen := new Stack<tuple of (String, String, String)>;

    method Marker(aBody: not nullable StringBuilder; aInitialHtml: not nullable String): not nullable String;
    begin
      result := fPrefix + fReplacements.Count.ToString;
      fReplacements[result] := aInitialHtml;
      // Keep the marker in its own paragraph so Markdown can parse the wrapped blocks normally.
      aBody.Append(#10).Append(result).Append(#10#10);
    end;

  public

    method Append(aBody: not nullable StringBuilder; aLine: not nullable String): Boolean;
    begin
      var lKind := "";
      var lClose := "";
      case aLine of
        "<v-click>": begin lKind := "click"; lClose := "</v-click>"; end;
        "<v-after>": begin lKind := "after"; lClose := "</v-after>"; end;
        "<v-clicks>": begin lKind := "list"; lClose := "</v-clicks>"; end;
        "<div v-click>": begin lKind := "click"; lClose := "</div>"; end;
        "<div v-after>": begin lKind := "after"; lClose := "</div>"; end;
      end;
      if length(lKind) > 0 then begin
        var lKey := Marker(aBody, "<p>"+aLine.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")+"</p>");
        fOpen.Push((lKey, lKind, lClose));
        exit true;
      end;
      if fOpen.Count > 0 then begin
        var lOpening := fOpen.Peek;
        if aLine = lOpening[2] then begin
          fOpen.Pop;
          fReplacements[lOpening[0]] := '<div data-reveal="'+lOpening[1]+'">';
          Marker(aBody, "</div>");
          exit true;
        end;
      end;
    end;

    method Restore(aHtml: not nullable String): not nullable String;
    begin
      result := aHtml;
      for each lReplacement in fReplacements do
        result := result.Replace("<p>"+lReplacement.Key+"</p>", lReplacement.Value);
    end;

  end;

  SlideBlock = assembly class
  public
    property Metadata := new Dictionary<String, String>;
    property Source: not nullable String := "";
  end;

  SlideDeck = public class
  private

    field fHeader := new Dictionary<String, String>;
    field fSlides := new List<SlideBlock>;
    field fDiagnostics := new JsonArray;
    field fRevision: not nullable String;

    class field fMetadataKey := Regex.FromPattern("^[A-Za-z][A-Za-z0-9_-]*$");
    class field fClock := Regex.FromPattern("^([0-9]+):([0-5][0-9])$");
    class field fDuration := Regex.FromPattern("^([0-9]+) *(s|m|min|h)?$");
    class field fColor := Regex.FromPattern("^#[0-9A-Fa-f]{6}$");

    class method ReadFrontmatter(aLines: not nullable ImmutableList<String>; aStart: Integer; aValues: not nullable Dictionary<String, String>): Integer;
    begin
      for i := aStart to aLines.Count - 1 do begin
        var lLine := aLines[i].TrimEnd;
        if lLine = "---" then
          exit if aValues.Count > 0 then i else -1;
        if (length(lLine.Trim) = 0) or lLine.TrimStart.StartsWith("#") or lLine.StartsWith(" ") then
          continue;
        var lColon := lLine.IndexOf(":");
        if (lColon < 1) or not fMetadataKey.IsMatch(lLine.Substring(0, lColon).Trim as not nullable) then
          exit -1;
        aValues[lLine.Substring(0, lColon).Trim] := lLine.Substring(lColon + 1).Trim.Trim('"', '''');
      end;
      exit -1;
    end;

    class method FenceWidth(aLine: not nullable String): Integer;
    begin
      if (length(aLine) = 0) or not (aLine[0] in ['`', '~']) then
        exit 0;
      for i := 0 to length(aLine) - 1 do begin
        if aLine[i] <> aLine[0] then
          break;
        inc(result);
      end;
      if result < 3 then
        result := 0;
    end;

    method AddBlock(aBlock: not nullable SlideBlock; aBody: not nullable StringBuilder);
    begin
      aBlock.Source := (aBody.ToString as String).TrimEnd as not nullable;
      if length(aBlock.Source) > 0 then
        fSlides.Add(aBlock);
    end;

    class method Duration(aValue: nullable String): nullable Integer;
    begin
      if not assigned(aValue) then
        exit;
      var lValue := aValue.ToLower as not nullable;
      var lMatch := fClock.Match(lValue);
      var lSeconds: Int64;
      if assigned(lMatch) then begin
        var lMinutes := Convert.TryToInt32(lMatch.Groups[1]);
        if not assigned(lMinutes) then
          exit;
        lSeconds := Int64(lMinutes as not nullable) * 60 + Convert.ToInt32(lMatch.Groups[2]);
      end
      else begin
        lMatch := fDuration.Match(lValue);
        if not assigned(lMatch) then
          exit;
        var lNumber := Convert.TryToInt32(lMatch.Groups[1]);
        if not assigned(lNumber) then
          exit;
        var lUnit := lMatch.Groups[2];
        var lMultiplier := if lUnit = "h" then 3600 else if lUnit in ["m", "min"] then 60 else 1;
        lSeconds := Int64(lNumber as not nullable) * lMultiplier;
      end;
      if (lSeconds > 0) and (lSeconds <= 2147483647) then
        result := Int32(lSeconds);
    end;

    class method MetadataText(aValues: not nullable Dictionary<String, String>): not nullable String;
    begin
      var lText := new StringBuilder;
      for each lValue in aValues do
        lText.Append(lValue.Key).Append(": ").Append(lValue.Value).Append(#10);
      exit lText.ToString as not nullable;
    end;

    class method ApplyMetadata(aValues: not nullable Dictionary<String, String>; aChanges: not nullable JsonObject);
    begin
      for each lKey in aChanges.Keys do begin
        if not fMetadataKey.IsMatch(lKey) then
          raise new Exception("Invalid front matter key: " + lKey);
        var lValue := aChanges[lKey];
        if not assigned(lValue) or (lValue.NodeKind = JsonNodeKind.Null) then begin
          aValues.Remove(lKey);
          continue;
        end;
        if not (lValue.NodeKind in [JsonNodeKind.String, JsonNodeKind.Boolean, JsonNodeKind.Integer]) then
          raise new Exception("Front matter values must be strings, booleans, integers, or null.");
        var lText := if lValue.NodeKind = JsonNodeKind.String then lValue.StringValue else lValue.ToJsonString;
        if lText.Contains(#10) or lText.Contains(#13) then
          raise new Exception("Front matter values must be on one line.");
        aValues[lKey] := lText;
      end;
    end;

    class method CheckedMarkdown(aValue: not nullable String): not nullable String;
    begin
      if length(aValue.Trim) = 0 then
        raise new Exception("Slide Markdown cannot be empty.");
      var lCheck := new SlideDeck(aValue);
      if (lCheck.fSlides.Count <> 1) or (lCheck.fHeader.Count <> 0) or (lCheck.fDiagnostics.Count <> 0) then
        raise new Exception("Supply one slide body without a separator or front matter.");
      exit aValue.TrimEnd as not nullable;
    end;

    class method RequiredString(aObject: not nullable JsonObject; aKey: not nullable String): not nullable String;
    begin
      var lValue := aObject[aKey];
      if lValue:NodeKind <> JsonNodeKind.String then
        raise new Exception("Expected a string for " + aKey);
      exit lValue.StringValue as not nullable;
    end;

    class method RequiredIndex(aObject: not nullable JsonObject; aKey: not nullable String; aCount: Integer): Integer;
    begin
      var lValue := aObject[aKey];
      if lValue:NodeKind <> JsonNodeKind.Integer then
        raise new Exception("Expected a one-based integer for " + aKey);
      var lIndex := lValue.IntegerValue;
      if (lIndex < 1) or (lIndex > aCount) then
        raise new Exception("Slide number out of range: " + lIndex.ToString);
      exit Int32(lIndex - 1);
    end;

    class method RenderBody(aSource: not nullable String; aOptions: not nullable MarkdownOptions; aIncludeNotes: Boolean): not nullable JsonObject;
    begin
      var lBody := new StringBuilder;
      var lNotes := new StringBuilder;
      var lReveals := new SlideReveals;
      var lFence := "";
      var lComment := false;
      for each lLine in aSource.Split(#10) do begin
        var lTrim := lLine.TrimStart as not nullable;
        var lWidth := if length(lLine) - length(lTrim) < 4 then FenceWidth(lTrim) else 0;
        if not lComment and (lWidth > 0) then begin
          if (length(lFence) = 0) and ((lTrim[0] <> '`') or not lTrim.Substring(lWidth).Contains("`")) then
            lFence := lTrim.Substring(0, lWidth)
          else if lTrim.StartsWith(lFence) and (length(lFence) > 0) and (length(lTrim.Substring(lWidth).Trim) = 0) then
            lFence := "";
        end;
        if lComment then begin
          var lEnd := lLine.IndexOf("-->");
          lComment := lEnd < 0;
          lNotes.Append(if lComment then lLine else lLine.Substring(0, lEnd)).Append(#10);
        end
        else if (length(lFence) = 0) and lTrim.StartsWith("<!--") and
          (not lTrim.Contains("-->") or lTrim.TrimEnd.EndsWith("-->")) then begin
          lNotes := new StringBuilder;
          var lEnd := lTrim.IndexOf("-->");
          lComment := lEnd < 0;
          lNotes.Append(if lComment then lTrim.Substring(4) else lTrim.Substring(4, lEnd - 4)).Append(#10);
        end
        else begin
          if length(lTrim) > 0 then
            lNotes := new StringBuilder;
          if (length(lFence) > 0) or (lLine <> lTrim) or not lReveals.Append(lBody, lTrim.TrimEnd as not nullable) then
            lBody.Append(lLine).Append(#10);
        end;
      end;
      result := new JsonObject;
      result["html"] := lReveals.Restore(Markdown.ToHtml(lBody.ToString, aOptions));
      if aIncludeNotes and not lComment and (length((lNotes.ToString as String).Trim) > 0) then
        result["notes"] := Markdown.ToHtml(lNotes.ToString, aOptions);
    end;

  public

    constructor(aSource: not nullable String);
    begin
      fRevision := SlideFiles.Revision(aSource);
      var lLines := aSource.TrimStart(#$FEFF).Replace(#13#10, #10).Replace(#13, #10).Split(#10);
      var lBlock := new SlideBlock;
      var lBody := new StringBuilder;
      var lFence := "";
      var lComment := false;
      var i := 0;
      if (lLines.Count > 0) and (lLines[0] = "---") then begin
        var lEnd := ReadFrontmatter(lLines, 1, fHeader);
        if lEnd >= 0 then begin
          i := lEnd + 1;
          lBlock.Metadata["layout"] := fHeader["layout"];
          lBlock.Metadata["duration"] := fHeader["slideDuration"];
          fHeader.Remove("layout");
          fHeader.Remove("slideDuration");
        end
        else
          fHeader.RemoveAll;
      end;
      while i < lLines.Count do begin
        var lLine := lLines[i];
        var lTrim := lLine.TrimStart as not nullable;
        var lWidth := if length(lLine) - length(lTrim) < 4 then FenceWidth(lTrim) else 0;
        if lComment then
          lComment := not lLine.Contains("-->")
        else if lWidth > 0 then begin
          if (length(lFence) = 0) and ((lTrim[0] <> '`') or not lTrim.Substring(lWidth).Contains("`")) then
            lFence := lTrim.Substring(0, lWidth)
          else if (length(lFence) > 0) and lTrim.StartsWith(lFence) and (length(lTrim.Substring(lWidth).Trim) = 0) then
            lFence := "";
        end
        else if (length(lFence) = 0) and lTrim.StartsWith("<!--") then
          lComment := not lTrim.Contains("-->")
        else if (length(lFence) = 0) and (lLine.TrimEnd = "---") then begin
          AddBlock(lBlock, lBody);
          lBlock := new SlideBlock;
          lBody := new StringBuilder;
          var lEnd := ReadFrontmatter(lLines, i+1, lBlock.Metadata);
          if lEnd >= 0 then
            i := lEnd
          else
            lBlock.Metadata.RemoveAll;
          inc(i);
          continue;
        end;
        lBody.Append(lLine).Append(#10);
        inc(i);
      end;
      AddBlock(lBlock, lBody);
      if length(lFence) > 0 then
        fDiagnostics.Add("Unclosed code fence.");
      if lComment then
        fDiagnostics.Add("Unclosed HTML comment.");
    end;

    property Revision: not nullable String read fRevision;
    property Diagnostics: not nullable JsonArray read fDiagnostics;
    property Count: Integer read fSlides.Count;

    method Outline: not nullable JsonArray;
    begin
      result := new JsonArray;
      for each lSlide in fSlides index i do begin
        var lItem := new JsonObject;
        lItem["slide"] := i+1;
        for each lLine in lSlide.Source.Split(#10) do begin
          if lLine.StartsWith("# ") then begin
            lItem["title"] := lLine.Substring(2).Trim;
            break;
          end;
        end;
        result.Add(lItem);
      end;
    end;

    method Apply(aChanges: not nullable JsonArray): not nullable String;
    begin
      var lDraft := new SlideDeck(Serialize);
      for each lChangeNode in aChanges do begin
        if not (lChangeNode is JsonObject) then
          raise new Exception("Each operation must be an object.");
        var lChange := lChangeNode as JsonObject;
        var lOperation := RequiredString(lChange, "op");
        if lOperation = "deck" then begin
          if not (lChange["frontMatter"] is JsonObject) then
            raise new Exception("Expected a frontMatter object.");
          ApplyMetadata(lDraft.fHeader, lChange["frontMatter"] as JsonObject);
          continue;
        end;
        if lOperation = "insert" then begin
          var lNew := new SlideBlock(Source := CheckedMarkdown(RequiredString(lChange, "markdown")));
          if assigned(lChange["notes"]) then
            lNew.Source := EditNotes(lNew.Source, RequiredString(lChange, "notes"));
          if assigned(lChange["frontMatter"]) then begin
            if not (lChange["frontMatter"] is JsonObject) then
              raise new Exception("Expected a frontMatter object.");
            ApplyMetadata(lNew.Metadata, lChange["frontMatter"] as JsonObject);
          end;
          lDraft.fSlides.Insert(RequiredIndex(lChange, "slide", lDraft.Count + 1), lNew);
          continue;
        end;

        var lIndex := RequiredIndex(lChange, "slide", lDraft.Count);
        var lSlide := lDraft.fSlides[lIndex];
        case lOperation of
          "delete": lDraft.fSlides.RemoveAt(lIndex);
          "move": begin
            var lDestination := RequiredIndex(lChange, "to", lDraft.Count);
            lDraft.fSlides.RemoveAt(lIndex);
            lDraft.fSlides.Insert(lDestination, lSlide);
          end;
          "update", "replace": begin
            if assigned(lChange["markdown"]) or (lOperation = "replace") then begin
              var lSource := CheckedMarkdown(RequiredString(lChange, "markdown"));
              if not assigned(lChange["notes"]) and (NotesIndex(lSource) < 0) then begin
                var lNotesIndex := NotesIndex(lSlide.Source);
                if lNotesIndex >= 0 then
                  lSource := lSource + #10#10 + lSlide.Source.Substring(lNotesIndex);
              end;
              lSlide.Source := lSource;
            end;
            if assigned(lChange["notes"]) then
              lSlide.Source := EditNotes(lSlide.Source, RequiredString(lChange, "notes"));
            if assigned(lChange["frontMatter"]) then begin
              if not (lChange["frontMatter"] is JsonObject) then
                raise new Exception("Expected a frontMatter object.");
              ApplyMetadata(lSlide.Metadata, lChange["frontMatter"] as JsonObject);
            end;
          end;
          else raise new Exception("Unknown slide operation: " + lOperation);
        end;
      end;
      if lDraft.Count = 0 then
        raise new Exception("A deck must have at least one slide.");
      exit lDraft.Serialize;
    end;

    method Serialize: not nullable String;
    begin
      var lText := new StringBuilder;
      if fHeader.Count > 0 then
        lText.Append("---").Append(#10).Append(MetadataText(fHeader)).Append("---").Append(#10#10)
      else if (fSlides.Count > 0) and (fSlides[0].Metadata.Count > 0) then
        lText.Append("---").Append(#10).Append("title: Slides").Append(#10).Append("---").Append(#10#10);
      for each lSlide in fSlides index i do begin
        if (i > 0) or (lSlide.Metadata.Count > 0) then
          lText.Append("---").Append(#10);
        if lSlide.Metadata.Count > 0 then
          lText.Append(MetadataText(lSlide.Metadata)).Append("---").Append(#10);
        if (i > 0) or (lSlide.Metadata.Count > 0) then
          lText.Append(#10);
        lText.Append(lSlide.Source.TrimStart(#10)).Append(#10);
        if i + 1 < fSlides.Count then
          lText.Append(#10);
      end;
      exit lText.ToString as not nullable;
    end;

    property StyleReference: nullable String read fHeader["style"];

    method Render(aRoot: not nullable String; aFolder: not nullable String; aIncludeNotes: Boolean;
      aEncodeAsset: nullable SlideAssetEncoder := nil): not nullable JsonObject;
    begin
      var lStyle: nullable JsonObject;
      var lStyleFolder := aFolder;
      var lStyleError: nullable String;
      var lRevision := fRevision;
      if assigned(StyleReference) then begin
        var lStylePath := SlideFiles.Resolve(aRoot, aFolder, StyleReference);
        if assigned(lStylePath) and (lStylePath.PathExtension.ToLower.TrimStart('.') = "json") then begin
          var lText := File.ReadText(lStylePath) as not nullable;
          lRevision := SlideFiles.Revision(fRevision + lText);
          try
            lStyle := ParseStyle(lText);
            lStyleFolder := Path.GetParentDirectory(lStylePath) as not nullable;
          except
            on E: Exception do lStyleError := E.Message;
          end;
        end
        else
          lStyleError := "Style file is missing or outside the workspace.";
      end;

      var lOptions := MarkdownOptions.GitHub;
      lOptions.RewriteUrl := aUrl -> coalesce(SlideFiles.ImageUrl(aRoot, aFolder, aUrl, aEncodeAsset),
        if assigned(SlideFiles.ContentType(aUrl)) then "" else nil);
      var lSlides := new JsonArray;
      for each lSlide in fSlides do begin
        var lRendered := RenderBody(lSlide.Source, lOptions, aIncludeNotes);
        var lLayout := coalesce(lSlide.Metadata["layout"], "default") as not nullable;
        var lTheme := coalesce(lSlide.Metadata["theme"], fHeader["theme"]);
        if not (lTheme in ["light", "dark"]) then
          lTheme := if lLayout in ["cover", "section"] then "dark" else "light";
        lRendered["layout"] := lLayout;
        lRendered["theme"] := lTheme as not nullable;
        var lVariant := if assigned(lStyle) then lStyle[lTheme] as nullable JsonObject else nil;
        if assigned(lVariant) then
          lRendered["style"] := lVariant;

        var lLogo := coalesce(lSlide.Metadata["logo"], fHeader["logo"]);
        var lLogoURL := if assigned(lLogo) then SlideFiles.ImageUrl(aRoot, aFolder, lLogo, aEncodeAsset)
          else SlideFiles.ImageUrl(aRoot, lStyleFolder, (if assigned(lVariant) then lVariant["logo"]:StringValue else nil), aEncodeAsset);
        if assigned(lLogoURL) then
          lRendered["logo"] := lLogoURL;
        var lBackground := coalesce(lSlide.Metadata["background"], fHeader["background"]);
        var lBackgroundURL := if assigned(lBackground) then SlideFiles.ImageUrl(aRoot, aFolder, lBackground, aEncodeAsset)
          else SlideFiles.ImageUrl(aRoot, lStyleFolder, (if assigned(lVariant) then lVariant["background"]:StringValue else nil), aEncodeAsset);
        if assigned(lBackgroundURL) then
          lRendered["background"] := lBackgroundURL
        else if (lBackground = "false") or (not assigned(lBackground) and ((if assigned(lVariant) then lVariant["background"]:StringValue else nil) = "false")) then
          lRendered["background"] := "false";

        var lDuration := Duration(lSlide.Metadata["duration"]);
        if assigned(lDuration) then
          lRendered["duration"] := lDuration as not nullable;
        lSlides.Add(lRendered);
      end;
      result := new JsonObject;
      result["revision"] := lRevision;
      result["title"] := coalesce(fHeader["title"], "Slides") as not nullable;
      result["slides"] := lSlides;
      var lDuration := Duration(fHeader["duration"]);
      if assigned(lDuration) then
        result["duration"] := lDuration as not nullable;
      if aIncludeNotes then begin
        if fHeader["presentationTimer"]:ToLowerInvariant = "false" then
          result["presentationTimer"] := false;
        if fHeader["slideTimer"]:ToLowerInvariant = "false" then
          result["slideTimer"] := false;
      end;
      if assigned(lStyleError) then
        result["styleError"] := lStyleError;
    end;

    class method ParseStyle(aSource: not nullable String): not nullable JsonObject;
    begin
      var lStyle := JsonObject.TryFromString(aSource);
      if not assigned(lStyle) or (lStyle["version"]:NodeKind <> JsonNodeKind.Integer) or (lStyle["version"].IntegerValue <> 1) then
        raise new Exception("Styles require a JSON object with version 1.");
      for each lKey in lStyle.Keys do begin
        if lKey in ["version", "name"] then begin
          if (lKey = "name") and (lStyle[lKey]:NodeKind <> JsonNodeKind.String) then
            raise new Exception("Style name must be a string.");
          continue;
        end;
        if not (lKey in ["light", "dark"]) or not (lStyle[lKey] is JsonObject) then
          raise new Exception("Unknown or invalid style variant: " + lKey);
        var lVariant := lStyle[lKey] as JsonObject;
        for each lField in lVariant.Keys do begin
          var lValue := lVariant[lField];
          if not assigned(lValue) then
            raise new Exception("Empty style field: " + lField);
          case lField of
            "backgroundColor", "textColor", "accentColor": begin
              if (lValue.NodeKind <> JsonNodeKind.String) or not fColor.IsMatch(lValue.StringValue as not nullable) then
                raise new Exception(lField + " must be a six-digit hex color.");
            end;
            "font", "headingFont": begin
              if (lValue.NodeKind <> JsonNodeKind.String) or not (lValue.StringValue in ["myriad", "system", "serif", "mono"]) then
                raise new Exception(lField + " must be myriad, system, serif, or mono.");
            end;
            "scale", "spacing": begin
              if (lValue.NodeKind <> JsonNodeKind.Integer) or (lValue.IntegerValue < 70) or (lValue.IntegerValue > 150) then
                raise new Exception(lField + " must be a percentage from 70 through 150.");
            end;
            "background", "logo": begin
              if lValue.NodeKind <> JsonNodeKind.String then
                raise new Exception(lField + " must be an image path or the string false.");
            end;
            else raise new Exception("Unknown style field: " + lField);
          end;
        end;
      end;
      exit lStyle;
    end;

  private

    class method NotesIndex(aSource: not nullable String): Integer;
    begin
      var lTrim := aSource.TrimEnd;
      if not lTrim.EndsWith("-->") then
        exit -1;
      var lIndex := lTrim.LastIndexOf("<!--");
      if (lIndex >= 0) and ((lIndex = 0) or (lTrim[lIndex - 1] = #10)) then
        exit lIndex;
      exit -1;
    end;

    class method EditNotes(aSource: not nullable String; aNotes: not nullable String): not nullable String;
    begin
      if aNotes.Contains("-->") then
        raise new Exception("Notes cannot contain a comment terminator.");
      var lIndex := NotesIndex(aSource);
      result := if lIndex >= 0 then aSource.Substring(0, lIndex).TrimEnd as not nullable else aSource;
      if length(aNotes.Trim) > 0 then
        result := result + #10#10 + "<!--" + #10 + aNotes + #10 + "-->";
    end;

  end;

end.
