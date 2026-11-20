namespace RemObjects.Elements.Slides;

uses
  RemObjects.Elements.RTL.Markdown,
  RemObjects.InternetPack,
  RemObjects.InternetPack.Http;

type
  SlidePreview = public class
  assembly
    property ID: not nullable String; readonly;
    property Root: not nullable String; readonly;
    property State := new JsonObject;
    constructor(aRoot: not nullable String; aPath: not nullable String; aOrigin: not nullable String);
    begin
      Root := aRoot;
      Path := aPath;
      ID := NSUUID.UUID.UUIDString as not nullable String;
      URL := aOrigin + "/d/" + ID + "/";
    end;
  public
    property Path: not nullable String; readonly;
    property URL: not nullable String; readonly;
  end;

  SlideHost = public class
  private

    field fResources: not nullable String;
    field fBackgrounds: not nullable String;
    field fPort: Integer;
    field fServer: nullable HttpServer;
    field fPreviews := new Dictionary<String, SlidePreview>;

    method EnsureStarted;
    begin
      if assigned(fServer) then
        exit;
      var lServer := new HttpServer;
      lServer.BindV4 := true;
      lServer.BindV6 := false;
      var lLoopback := IPAddress.Parse("127.0.0.1");
      lServer.BindAddressV4 := lLoopback;
      lServer.Port := fPort;
      lServer.CloseConnectionsOnShutdown := true;
      lServer.HttpRequest += HandleRequest;
      lServer.Open;
      if lServer.BindingV4.EndPoint.Address.Address <> lLoopback.Address then begin
        lServer.Close;
        raise new Exception("The Slides listener did not bind to IPv4 loopback.");
      end;
      if lServer.Port <= 0 then begin
        lServer.Close;
        raise new Exception("InternetPack did not report the assigned Slides port.");
      end;
      fServer := lServer;
    end;

    class method WriteText(aResponse: not nullable HttpServerResponse; aText: not nullable String;
      aContentType: not nullable String := "text/plain; charset=utf-8"; aCode: Integer := 200);
    begin
      aResponse.HttpCode := HttpStatusCode(aCode);
      aResponse.Header.ContentType := aContentType;
      aResponse.ContentBytes := Encoding.UTF8.GetBytes(aText);
    end;

    class method WriteFile(aResponse: not nullable HttpServerResponse; aPath: not nullable String; aType: not nullable String);
    begin
      aResponse.Header.ContentType := aType;
      aResponse.ContentBytes := File.ReadBytes(aPath);
    end;

    method DeckRequest(aRequest: not nullable HttpServerRequest; aResponse: not nullable HttpServerResponse; aPreview: not nullable SlidePreview);
    begin
      var lQuery := aRequest.QueryString;
      if assigned(lQuery) and (lQuery["asset"] = "mermaid") then begin
        WriteText(aResponse, Markdown.MermaidRuntimeJavaScript, "text/javascript; charset=utf-8");
        exit;
      end;
      if assigned(lQuery) and assigned(lQuery["file"]) then begin
        var lFile := SlideFiles.Resolve(aPreview.Root, aPreview.Root, lQuery["file"]);
        var lType := if assigned(lFile) then SlideFiles.ContentType(lFile) else nil;
        if not assigned(lFile) or not assigned(lType) then
          WriteText(aResponse, "Asset not found.", "text/plain; charset=utf-8", 404)
        else begin
          aResponse.Header.SetHeaderValue("Content-Security-Policy", "sandbox; default-src 'none'");
          WriteFile(aResponse, lFile, lType);
        end;
        exit;
      end;
      var lDeckPath := SlideFiles.CanonicalPath(aPreview.Path);
      if not SlideFiles.IsWithin(aPreview.Root, lDeckPath) or not File.Exists(lDeckPath) then begin
        WriteText(aResponse, "Deck not found.", "text/plain; charset=utf-8", 404);
        exit;
      end;
      var lDeck := new SlideDeck(File.ReadText(lDeckPath) as not nullable);
      var lRendered := lDeck.Render(aPreview.Root, Path.GetParentDirectory(lDeckPath) as not nullable, assigned(lQuery) and (lQuery["presenter"] = "1"));
      if assigned(lQuery) and (lQuery["revision"] = "1") then
        WriteText(aResponse, lRendered["revision"].StringValue as not nullable)
      else
        WriteText(aResponse, lRendered.ToJsonString, "application/json; charset=utf-8");
    end;

    method StateRequest(aRequest: not nullable HttpServerRequest; aResponse: not nullable HttpServerResponse;
      aPreview: not nullable SlidePreview; aAuthority: not nullable String);
    begin
      locking aPreview do begin
        if aRequest.Header.RequestType = "POST" then begin
          if aRequest.Header.GetHeaderValue("Origin") <> "http://" + aAuthority then begin
            WriteText(aResponse, "Invalid source.", "text/plain; charset=utf-8", 403);
            exit;
          end;
          var lSlide := Convert.TryToInt32(aRequest.QueryString["slide"]);
          var lStep := Convert.TryToInt32(aRequest.QueryString["step"]);
          if not assigned(lSlide) or not assigned(lStep) or (lSlide < 1) or (lStep < 0) then begin
            WriteText(aResponse, "Invalid slide position.", "text/plain; charset=utf-8", 400);
            exit;
          end;
          var lVersion := coalesce(aPreview.State["version"]:IntegerValue, 0);
          aPreview.State["slide"] := lSlide as not nullable;
          aPreview.State["step"] := lStep as not nullable;
          aPreview.State["version"] := lVersion + 1;
        end
        else if aRequest.Header.RequestType <> "GET" then begin
          WriteText(aResponse, "Method not allowed.", "text/plain; charset=utf-8", 405);
          exit;
        end;
        WriteText(aResponse, aPreview.State.ToJsonString, "application/json; charset=utf-8");
      end;
    end;

    method HandleRequest(aSender: Object; aEvent: HttpRequestEventArgs);
    begin
      var lResponse := aEvent.Response as not nullable;
      var lRequest := aEvent.Request as not nullable;
      lResponse.Header.SetHeaderValue("Cache-Control", "no-store");
      lResponse.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
      lResponse.Header.SetHeaderValue("Referrer-Policy", "no-referrer");
      var lAuthority := lRequest.Header.GetHeaderValue("Host");
      var lPort := Port.ToString;
      if not (lAuthority in ["127.0.0.1:" + lPort, "localhost:" + lPort]) then begin
        WriteText(lResponse, "Invalid host.", "text/plain; charset=utf-8", 403);
        exit;
      end;

      var lParts := lRequest.Path.Split('/');
      var lPreview: nullable SlidePreview;
      if (length(lParts) >= 4) and (lParts[1] = "d") then
        locking self do
          lPreview := fPreviews[lParts[2]];
      if not assigned(lPreview) then begin
        WriteText(lResponse, "Preview not found.", "text/plain; charset=utf-8", 404);
        exit;
      end;

      try
        var lRoute := lParts.Skip(3).JoinedString("/") as not nullable;
        if lRoute = "state" then begin
          StateRequest(lRequest, lResponse, lPreview, lAuthority as not nullable);
          exit;
        end;
        if lRequest.Header.RequestType <> "GET" then begin
          WriteText(lResponse, "Method not allowed.", "text/plain; charset=utf-8", 405);
          exit;
        end;
        case lRoute of
          "": WriteFile(lResponse, Path.Combine(fResources, "presenter.html"), "text/html; charset=utf-8");
          "deck": DeckRequest(lRequest, lResponse, lPreview);
          "slides.js", "highlight.pack.js": WriteFile(lResponse, Path.Combine(fResources, lRoute), "text/javascript; charset=utf-8");
          "slides.css", "highlight-vs.css": WriteFile(lResponse, Path.Combine(fResources, lRoute), "text/css; charset=utf-8");
          "assets/background-light.png", "assets/background-dark.png":
            WriteFile(lResponse, Path.Combine(fBackgrounds, lParts[4]), "image/png");
          else WriteText(lResponse, "Resource not found.", "text/plain; charset=utf-8", 404);
        end;
      except
        on E: Exception do WriteText(lResponse, "Could not load the slide resource.", "text/plain; charset=utf-8", 500);
      end;
    end;

  public

    constructor(aResources: not nullable String; aBackgrounds: not nullable String; aPort: Integer := 0);
    begin
      fResources := aResources;
      fBackgrounds := aBackgrounds;
      fPort := aPort;
    end;

    property Port: Integer read coalesce(fServer:Port, 0);

    method ExportAudienceHtml(aRoot: not nullable String; aPath: not nullable String): not nullable String;
    begin
      var lRoot := SlideFiles.CanonicalPath(aRoot);
      var lPath := SlideFiles.CanonicalPath(aPath);
      if not SlideFiles.IsWithin(lRoot, lPath) or not File.Exists(lPath) then
        raise new Exception("Deck is missing or outside the workspace.");

      var lDeck := new SlideDeck(File.ReadText(lPath) as not nullable);
      if (lDeck.Count = 0) or (lDeck.Diagnostics.Count > 0) then
        raise new Exception("The deck must contain at least one slide and have balanced code fences and comments.");
      var lAssets := new Dictionary<String, String>;
      var lEncode: SlideAssetEncoder := (aFile, aType) -> begin
        var lUrl := lAssets[aFile];
        if not assigned(lUrl) then begin
          lUrl := "data:" + aType + ";base64," + Convert.ToBase64String(File.ReadBytes(aFile));
          lAssets[aFile] := lUrl;
        end;
        exit lUrl as not nullable;
      end;
      var lData := lDeck.Render(lRoot, Path.GetParentDirectory(lPath) as not nullable, false, lEncode);
      if assigned(lData["styleError"]) then
        raise new Exception(lData["styleError"].StringValue);

      var lNonce := NSUUID.UUID.UUIDString as not nullable String;
      var lTemplate := File.ReadText(Path.Combine(fResources, "presenter.html")) as not nullable;
      var lStyle := File.ReadText(Path.Combine(fResources, "slides.css")) as not nullable;
      for each lName in ["background-light.png", "background-dark.png"] do
        lStyle := lStyle.Replace('url("assets/' + lName + '")', 'url("' + lEncode(Path.Combine(fBackgrounds, lName), "image/png") + '")');

      var lPayload := lData.ToJsonString.Replace("<", "\u003c");
      var lScripts := '<script type="application/json" id="exported-deck">' + lPayload + '</script>'
        + ExportScript(File.ReadText(Path.Combine(fResources, "highlight.pack.js")) as not nullable, lNonce);
      if lPayload.Contains("elements-markdown-mermaid") then
        lScripts := lScripts + ExportScript(Markdown.MermaidRuntimeJavaScript, lNonce);
      lScripts := lScripts + ExportScript(File.ReadText(Path.Combine(fResources, "slides.js")) as not nullable, lNonce);

      const Policy = 'default-src ''none''; base-uri ''none''; style-src ''unsafe-inline''; img-src data: https: http:; media-src data: https: http:;';
      var lPolicy := '<meta http-equiv="Content-Security-Policy" content="' + Policy + ' script-src ''nonce-' + lNonce + '''">';
      result := lTemplate.Replace("<head>", "<head>" + lPolicy)
        .Replace('<link rel="stylesheet" href="https://use.typekit.net/nbz6fkz.css">', '')
        .Replace('<link rel="stylesheet" href="highlight-vs.css">', '<style>' +
          File.ReadText(Path.Combine(fResources, "highlight-vs.css")) + '</style>')
        .Replace('<link rel="stylesheet" href="slides.css">', '<style>' + lStyle + '</style>')
        .Replace('<script src="highlight.pack.js"></script>', '')
        .Replace('<script type="module" src="slides.js"></script>', '')
        .Replace("</body>", lScripts + #10 + "</body>");
    end;

    class method ExportScript(aScript: not nullable String; aNonce: not nullable String): not nullable String; private;
    begin
      var lData := Convert.ToBase64String(Encoding.UTF8.GetBytes(aScript));
      // Transport source as data so script text cannot terminate the HTML tag.
      result := '<script nonce="' + aNonce + '">(()=>{const s=document.createElement("script");s.nonce=document.currentScript.nonce;'
        + 's.textContent=new TextDecoder().decode(Uint8Array.from(atob("' + lData
        + '"),c=>c.charCodeAt(0)));document.head.append(s);})();</script>';
    end;

    method OpenDeck(aRoot: not nullable String; aPath: not nullable String): not nullable SlidePreview;
    begin
      var lRoot := SlideFiles.CanonicalPath(aRoot);
      var lPath := SlideFiles.CanonicalPath(aPath);
      if not SlideFiles.IsWithin(lRoot, lPath) or not File.Exists(lPath) then
        raise new Exception("Deck is missing or outside the workspace.");
      locking self do begin
        for each lEntry in fPreviews do begin
          if (lEntry.Value.Root = lRoot) and (lEntry.Value.Path = lPath) then
            exit lEntry.Value;
        end;
        EnsureStarted;
        result := new SlidePreview(lRoot, lPath, "http://127.0.0.1:" + Port.ToString);
        fPreviews[result.ID] := result;
      end;
    end;

    method ListPreviews(aRoot: not nullable String): not nullable JsonArray;
    begin
      var lRoot := SlideFiles.CanonicalPath(aRoot);
      result := new JsonArray;
      locking self do begin
        for each lEntry in fPreviews do begin
          if lEntry.Value.Root = lRoot then begin
            var lValue := new JsonObject;
            lValue["path"] := lEntry.Value.Path;
            lValue["url"] := lEntry.Value.URL;
            result.Add(lValue);
          end;
        end;
      end;
    end;

    method CloseDeck(aRoot: not nullable String; aPath: not nullable String): Boolean;
    begin
      var lRoot := SlideFiles.CanonicalPath(aRoot);
      var lPath := SlideFiles.CanonicalPath(aPath);
      locking self do begin
        var lID: nullable String;
        for each lEntry in fPreviews do begin
          if (lEntry.Value.Root = lRoot) and (lEntry.Value.Path = lPath) then begin
            lID := lEntry.Key;
            break;
          end;
        end;
        if assigned(lID) then begin
          fPreviews.Remove(lID);
          exit true;
        end;
      end;
    end;

    method IsAudienceURL(aURL: nullable String): Boolean;
    begin
      if not assigned(aURL) then
        exit;
      locking self do begin
        for each lEntry in fPreviews do begin
          var lPrefix := lEntry.Value.URL + "?presentation=1";
          if (aURL = lPrefix) or aURL.StartsWith(lPrefix + "#") then
            exit true;
        end;
      end;
    end;

    method Stop;
    begin
      var lServer: nullable HttpServer;
      locking self do begin
        lServer := fServer;
        fServer := nil;
        fPreviews.RemoveAll;
      end;
      lServer:Close;
    end;

  end;

end.
