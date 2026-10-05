namespace RemObjects.Elements.Web;

type
  ILocalizationManager = public interface
    method GetText(aContext: WebContext; aKey: String): String;
  end;

  LocalizationFolderResolver = public block(aContext: WebContext): nullable String;

  JsonLocalizationManager = public class(ILocalizationManager)
  public

    constructor(aBaseFolder: String := "~/App_Private/Localization");
    begin
      if length(aBaseFolder:Trim) = 0 then
        raise new ArgumentException("A localization catalog folder is required.");
      BaseFolder := aBaseFolder;
    end;

    property BaseFolder: String; readonly;
    // Configure at startup. The resolver must not mutate shared request state.
    property FolderResolver: nullable LocalizationFolderResolver;

    method GetText(aContext: WebContext; aKey: String): String;
    begin
      if not assigned(aContext) then
        raise new ArgumentNullException("aContext");
      if length(aKey) = 0 then
        raise new ArgumentException("A localization key is required.");

      var lFolder := BaseFolder;
      var lResolver := FolderResolver;
      if assigned(lResolver) then begin
        var lResolved := lResolver(aContext);
        if length(lResolved:Trim) > 0 then
          lFolder := lResolved;
      end;
      lFolder := lFolder.Replace("\", "/").TrimEnd('/');
      if lFolder.StartsWith("~/") then
        lFolder := lFolder.Substring(1);
      if not lFolder.StartsWith("/") then
        lFolder := "/"+lFolder;

      var lLanguage := NormalizeLanguage(aContext.LocalizationLanguage);
      if lLanguage <> "en" then begin
        result := Lookup(ReadCatalog(aContext, lFolder+"/"+lLanguage+".json").Json, aKey);
        if length(result:Trim) > 0 then
          exit;
      end;
      var lEnglishPath := lFolder+"/en.json";
      var lEnglish := ReadCatalog(aContext, lEnglishPath);
      if not assigned(lEnglish.Json) then
        raise new InvalidOperationException($"Cannot load English localization catalog '{lEnglishPath}': {lEnglish.Error}");
      result := Lookup(lEnglish.Json, aKey);
      if length(result:Trim) = 0 then
        raise new InvalidOperationException($"English localization key '{aKey}' is missing, blank or not a string in '{lEnglishPath}'.");
    end;

  private

    // Only the cache key is shared; catalog data lives exclusively on the context.
    class var fCacheKey: Object := new Object; readonly;

    method ReadCatalog(aContext: WebContext; aPath: String): LocalizationCatalog;
    begin
      var lCache := aContext.Items[fCacheKey] as Dictionary<String, LocalizationCatalog>;
      if not assigned(lCache) then begin
        lCache := new Dictionary<String, LocalizationCatalog>;
        aContext.Items[fCacheKey] := lCache;
      end;
      result := lCache[aPath];
      if assigned(result) then
        exit;
      result := new LocalizationCatalog;
      try
        if not assigned(aContext.Server) then
          raise new InvalidOperationException("The supplied context has no server resource access.");
        using lStream := aContext.Server.OpenFile(aPath) do begin
          if not assigned(lStream) then begin
            result.Error := "File or embedded resource not found.";
          end
          else begin
            if lStream.Length > Consts.MaxInt32 then
              raise new IOException("Catalog is too large to read as text.");
            var lBytes := new Byte[Integer(lStream.Length)];
            var lOffset := 0;
            while lOffset < length(lBytes) do begin
              var lRead := lStream.Read(lBytes, lOffset, length(lBytes)-lOffset);
              if lRead = 0 then
                raise new IOException("Unexpected end of catalog stream.");
              inc(lOffset, lRead);
            end;
            var lText := Encoding.UTF8.GetString(lBytes);
            if lText.StartsWith(#$FEFF) then
              lText := lText.Substring(1);
            var lJson := JsonDocument.FromString(lText);
            if lJson is JsonObject then
              result.Json := lJson as JsonObject
            else
              result.Error := "The catalog must be a JSON object.";
          end;
        end;
      except
        on E: Exception do
          result.Error := E.Message;
      end;
      lCache[aPath] := result;
    end;

    method Lookup(aCatalog: nullable JsonObject; aKey: String): nullable String;
    begin
      var lNode: JsonNode := aCatalog;
      for each lPart in aKey.Split(".") do begin
        if (length(lPart) = 0) or not (lNode is JsonObject) then
          exit;
        lNode := (lNode as JsonObject)[lPart];
      end;
      if lNode is JsonStringValue then
        result := (lNode as JsonStringValue).Value;
    end;

    class method IsLetters(aValue: String): Boolean;
    begin
      result := length(aValue) > 0;
      for each c in aValue do
        if not (c in ['a'..'z']) then
          exit false;
    end;

    class method IsDigits(aValue: String): Boolean;
    begin
      result := length(aValue) > 0;
      for each c in aValue do
        if not (c in ['0'..'9']) then
          exit false;
    end;

    class method NormalizeLanguage(aLanguage: nullable String): String;
    begin
      if length(aLanguage) = 0 then
        exit "en";
      var lLanguage := aLanguage.ToLowerInvariant;
      var lParts := lLanguage.Split("-");
      if not (length(lParts[0]) in [2, 3]) or not IsLetters(lParts[0]) then
        exit "en";
      var i := 1;
      if (i < lParts.Count) and (length(lParts[i]) = 4) and IsLetters(lParts[i]) then
        inc(i); // optional script
      if (i < lParts.Count) and (((length(lParts[i]) = 2) and IsLetters(lParts[i])) or
                                ((length(lParts[i]) = 3) and IsDigits(lParts[i]))) then
        inc(i); // optional region
      while i < lParts.Count do begin
        var lPart := lParts[i];
        if not ((length(lPart) in [5..8]) or ((length(lPart) = 4) and (lPart[0] in ['0'..'9']))) then
          exit "en";
        for each c in lPart do
          if not (c in ['a'..'z', '0'..'9']) then
            exit "en";
        inc(i);
      end;
      result := lLanguage;
    end;

  end;

  LocalizationCatalog = assembly class
  public
    property Json: nullable JsonObject;
    property Error: nullable String;
  end;

end.
