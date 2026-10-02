namespace RemObjects.Elements.Web;

type
  // Owned by a single published factory; never reads live configuration during requests.
  WebStaticFiles = assembly class
  public

    constructor(aRoot: nullable String; aFactory: nullable WebPageFactory);
    begin
      var lXml: nullable XmlDocument;
      var lConfig := if length(aRoot) > 0 then Path.Combine(aRoot, "Web.config") else nil;
      if assigned(lConfig) then begin
        // A physical publication is authoritative, including removal of Web.config.
        if lConfig.FileExists then
          lXml := XmlDocument.FromFile(lConfig);
      end
      else if assigned(aFactory) then begin
        var lStream := aFactory.OpenResource("/Web.config", false);
        if assigned(lStream) then
          try
            var lBytes := new MemoryStream;
            lStream.CopyTo(lBytes);
            lXml := XmlDocument.FromBinary(new Binary(lBytes.ToArray));
          finally
            lStream.Close;
          end;
      end;
      if not assigned(lXml) then
        exit;
      fDefault := WebStaticCachePolicy.FromSection(lXml.Root, fDefault);
      var lLocations := new Dictionary<String, XmlElement>;
      for each lLocation in lXml.Root.ElementsWithName("location") do begin
        var lPath := NormalizePath(coalesce(lLocation.Attribute["path"]:Value, ""), true);
        if lPath = "/" then
          fDefault := WebStaticCachePolicy.FromSection(lLocation, fDefault)
        else
          lLocations[lPath] := lLocation;
      end;
      for each lPath in lLocations.Keys.OrderBy(p -> length(p)) do
        fRules[lPath] := WebStaticCachePolicy.FromSection(lLocations[lPath], PolicyForPath(lPath));
    end;

    method PolicyForPath(aPath: not nullable String): not nullable WebStaticCachePolicy;
    begin
      var lPath := NormalizePath(HttpUtility.UrlDecode(aPath));
      result := fDefault;
      var lLength := 0;
      for each lRule in fRules.Keys do
        if (length(lRule) > lLength) and ((lPath = lRule) or lPath.StartsWith(lRule+"/")) then begin
          result := fRules[lRule] as not nullable;
          lLength := length(lRule);
        end;
    end;

    method EntityTag(aKey: not nullable String; aStream: not nullable Stream; aImmutable: Boolean): nullable String;
    begin
      // Mutable development files can change without changing their length or timestamp.
      // Only accepted snapshots and embedded resources are safe to memoize.
      if not aImmutable then
        exit HashStream(aStream);
      locking fMonitor do begin
        result := fTags[aKey];
        if assigned(result) then
          exit;
        result := HashStream(aStream);
        if fTags.Count ≥ 4096 then
          fTags.RemoveAll;
        fTags[aKey] := result;
      end;
    end;

    class method HttpDate(aDate: not nullable DateTime): not nullable String;
    begin
      result := aDate.ToString("ddd, dd MMM yyyy HH:mm:ss 'GMT'", "en-US", TimeZone.Utc);
    end;

    class method ParseHttpDate(aValue: nullable String): nullable DateTime;
    begin
      if length(aValue) = 0 then
        exit;
      {$IF ECHOES}
      var lDate: System.DateTime;
      if System.DateTime.TryParseExact(aValue,
          ["ddd, dd MMM yyyy HH:mm:ss 'GMT'", "dddd, dd-MMM-yy HH:mm:ss 'GMT'", "ddd MMM d HH:mm:ss yyyy"],
          System.Globalization.CultureInfo.InvariantCulture,
          System.Globalization.DateTimeStyles.AssumeUniversal or System.Globalization.DateTimeStyles.AdjustToUniversal,
          out lDate) then
        result := new DateTime(lDate);
      {$ELSE}
      result := DateTime.TryParse(aValue, "ddd, dd MMM yyyy HH:mm:ss 'GMT'");
      {$ENDIF}
    end;

    class method MatchesTag(aHeader: nullable String; aTag: nullable String): Boolean;
    begin
      if aHeader:Trim = "*" then
        exit true;
      if not assigned(aTag) or not assigned(aHeader) then
        exit;
      // Commas inside a quoted opaque tag are not list separators.
      var lQuoted := false;
      var lStart := 0;
      for i := 0 to length(aHeader) do begin
        if (i < length(aHeader)) and (aHeader[i] = '"') then
          lQuoted := not lQuoted;
        if (i = length(aHeader)) or ((aHeader[i] = ',') and not lQuoted) then begin
          var lTag := aHeader.Substring(lStart, i-lStart).Trim;
          if lTag.StartsWith("W/") then
            lTag := lTag.Substring(2);
          if lTag = aTag then
            exit true;
          lStart := i+1;
        end;
      end;
    end;

  private

    fDefault: not nullable WebStaticCachePolicy := new WebStaticCachePolicy;
    fRules := new Dictionary<String, WebStaticCachePolicy>;
    fTags := new Dictionary<String, String>;
    fMonitor := new Monitor;

    class method NormalizePath(aPath: not nullable String; aValidate: Boolean := false): not nullable String;
    begin
      result := aPath.Replace("\", "/").Trim('/');
      if result.StartsWith("~/") then
        result := result.Substring(2);
      if result = "." then
        result := "";
      if aValidate and (result.Contains("?") or result.Contains("#") or result.Contains("*") or result.Contains(":") or
          result.Split("/").Any(p -> (p = "..") or (p = "."))) then
        raise new Exception("Invalid static cache location path: "+aPath);
      result := "/"+result.Split("/").Where(p -> length(p) > 0).ToList.JoinedString("/").ToLowerInvariant;
    end;

    class method HashStream(aStream: not nullable Stream): nullable String;
    begin
      {$IF ECHOES}
      using lHash := System.Security.Cryptography.SHA256.Create do begin
        var lPosition := aStream.Position;
        try
          var lBuffer := new Byte[65536];
          loop begin
            var lRead := aStream.Read(lBuffer, 0, length(lBuffer));
            if lRead = 0 then
              break;
            lHash.TransformBlock(lBuffer, 0, lRead, lBuffer, 0);
          end;
          lHash.TransformFinalBlock(new Byte[0], 0, 0);
          result := '"'+Convert.ToHexString(lHash.Hash)+'"';
        finally
          aStream.Position := lPosition;
        end;
      end;
      {$ELSE}
      // Backends without a streaming digest still support date validators.
      {$ENDIF}
    end;

  end;

  WebStaticCachePolicy = assembly class
  public

    property SetEtag: Boolean := true;
    property CacheControl: nullable String read GetCacheControl;
    property Expires: nullable String read if fMode = "useexpires" then fExpires;

    class method FromSection(aSection: not nullable XmlElement; aParent: not nullable WebStaticCachePolicy): not nullable WebStaticCachePolicy;
    begin
      result := aParent;
      for each lWeb in aSection.ElementsWithName("system.webServer") do
        for each lStatic in lWeb.ElementsWithName("staticContent") do
          for each lCache in lStatic.ElementsWithName("clientCache") do begin
            result := new WebStaticCachePolicy;
            result.fMode := coalesce(lCache.Attribute["cacheControlMode"]:Value:ToLowerInvariant, aParent.fMode);
            result.fSeconds := aParent.fSeconds;
            result.fCustom := coalesce(lCache.Attribute["cacheControlCustom"]:Value, aParent.fCustom);
            result.fExpires := coalesce(lCache.Attribute["httpExpires"]:Value, aParent.fExpires);
            result.SetEtag := aParent.SetEtag;
            if not (result.fMode in ["nocontrol", "disablecache", "usemaxage", "useexpires"]) then
              raise new Exception("Invalid staticContent/clientCache cacheControlMode.");
            var lEtag := lCache.Attribute["setEtag"]:Value:ToLowerInvariant;
            if assigned(lEtag) then begin
              if not (lEtag in ["true", "false"]) then
                raise new Exception("Invalid staticContent/clientCache setEtag; expected true or false.");
              result.SetEtag := lEtag = "true";
            end;
            var lAge := lCache.Attribute["cacheControlMaxAge"]:Value;
            if assigned(lAge) then
              result.fSeconds := ParseMaxAge(lAge);
            if result.fCustom:Contains(#13) or result.fCustom:Contains(#10) then
              raise new Exception("Invalid staticContent/clientCache cacheControlCustom.");
            if assigned(result.fExpires) then begin
              var lDate := WebStaticFiles.ParseHttpDate(result.fExpires);
              if not assigned(lDate) then
                raise new Exception("Invalid staticContent/clientCache httpExpires; expected an HTTP date.");
              result.fExpires := WebStaticFiles.HttpDate(lDate);
            end;
            if (result.fMode = "useexpires") and not assigned(result.fExpires) then
              raise new Exception("staticContent/clientCache UseExpires requires httpExpires.");
          end;
    end;

  private

    fMode: not nullable String := "disablecache";
    fSeconds: Int64 := 86400;
    fCustom: nullable String;
    fExpires: nullable String;

    method GetCacheControl: nullable String;
    begin
      case fMode of
        "disablecache": result := "no-cache";
        "usemaxage": result := "max-age="+fSeconds.ToString;
      end;
      if length(fCustom) > 0 then
        result := if assigned(result) then fCustom+", "+result else fCustom;
    end;

    class method ParseMaxAge(aValue: not nullable String): Int64;
    begin
      // IIS TimeSpan syntax: [days.]hh:mm:ss, whole seconds only.
      var lParts := aValue.Split(":");
      if lParts.Count ≠ 3 then
        raise new Exception("Invalid staticContent/clientCache cacheControlMaxAge; expected [days.]hh:mm:ss.");
      var lDayHour := lParts[0].Split(".");
      var lDays := if lDayHour.Count = 2 then Convert.TryToInt64(lDayHour[0]) else nullable Int64(0);
      var lHours := Convert.TryToInt64(lDayHour.Last);
      var lMinutes := Convert.TryToInt64(lParts[1]);
      var lSeconds := Convert.TryToInt64(lParts[2]);
      if (lDayHour.Count > 2) or not assigned(lDays) or not assigned(lHours) or not assigned(lMinutes) or not assigned(lSeconds) or
          (lDays < 0) or (lDays > 24855) or (lHours < 0) or (lHours > 23) or (lMinutes < 0) or (lMinutes > 59) or (lSeconds < 0) or (lSeconds > 59) then
        raise new Exception("Invalid staticContent/clientCache cacheControlMaxAge; expected a nonnegative duration below 2^31 seconds.");
      result := lDays*86400+lHours*3600+lMinutes*60+lSeconds;
      if result > 2147483647 then
        raise new Exception("staticContent/clientCache cacheControlMaxAge exceeds 2^31-1 seconds.");
    end;

  end;

  // InternetPack derives Content-Length from the stream, then reads its body.
  // HEAD and 304 describe the selected representation but transmit no body.
  WebStaticHeadersStream = assembly class(MemoryStream)
  public

    constructor(aLength: Int64);
    begin
      inherited constructor;
      fLength := aLength;
    end;

    method GetLength: Int64; override;
    begin
      result := fLength;
    end;

  private

    fLength: Int64;

  end;

  WebServer = public partial class
  private

    fStartupStaticFiles := new WebStaticFiles(nil, nil);

    method ServeStaticContent(aPath: not nullable String; aStream: not nullable Stream; aEvent: not nullable HttpRequestEventArgs;
                             aFactory: nullable WebPageFactory; aFileName: nullable String := nil);
    begin
      var lOwned := true;
      try
        aEvent.Response.Header.SetHeaderValue("Content-Type", ContentTypeForFileName(coalesce(aFileName, aPath)));
        var lNow := DateTime.UtcNow;
        aEvent.Response.Header.SetHeaderValue("Date", WebStaticFiles.HttpDate(lNow));
        var lMethod := aEvent.Request.Header.RequestType:ToLowerInvariant;
        // An error-page transfer must keep its status and must never become a 304.
        if (Integer(aEvent.Response.HttpCode) ≠ 200) or not (lMethod in ["get", "head"]) then begin
          aEvent.Response.Header.SetHeaderValue("Cache-Control", "no-store");
        end
        else begin
          var lCache := coalesce(aFactory:StaticFiles, fStartupStaticFiles);
          var lPolicy := lCache.PolicyForPath(aPath);
          if assigned(lPolicy.CacheControl) then
            aEvent.Response.Header.SetHeaderValue("Cache-Control", lPolicy.CacheControl);
          if assigned(lPolicy.Expires) then
            aEvent.Response.Header.SetHeaderValue("Expires", lPolicy.Expires);
          var lTag := if lPolicy.SetEtag then lCache.EntityTag(if assigned(aFileName) then "file:"+aFileName else "resource:"+aPath, aStream,
            not assigned(aFileName) or (length(aFactory:PublicationRevision) > 0)) else nil;
          if assigned(lTag) then
            aEvent.Response.Header.SetHeaderValue("ETag", lTag);
          var lModified: nullable DateTime;
          if assigned(aFileName) then begin
            lModified := File.DateModified(aFileName);
            if lModified > lNow then
              lModified := lNow;
            lModified := new DateTime(lModified.Ticks div 10000000 * 10000000);
            aEvent.Response.Header.SetHeaderValue("Last-Modified", WebStaticFiles.HttpDate(lModified));
          end;
          var lIfNoneMatch := aEvent.Request.Header.GetHeaderValue("If-None-Match");
          var lNotModified := false;
          if assigned(lIfNoneMatch) then begin
            lNotModified := WebStaticFiles.MatchesTag(lIfNoneMatch, lTag);
          end
          else if assigned(lModified) then begin
            var lSince := WebStaticFiles.ParseHttpDate(aEvent.Request.Header.GetHeaderValue("If-Modified-Since"));
            lNotModified := assigned(lSince) and (lModified ≤ lSince);
          end;
          if lNotModified then
            aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotModified;
        end;
        if (lMethod = "head") or (Integer(aEvent.Response.HttpCode) = 304) then begin
          aEvent.Response.ContentStream := new WebStaticHeadersStream(aStream.Length);
        end
        else begin
          aEvent.Response.ContentStream := aStream;
          lOwned := false;
        end;
      finally
        if lOwned then
          aStream.Close;
      end;
    end;

  end;

end.
