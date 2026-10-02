namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  StaticFileTests = public class(Test)
  public

    method PhysicalFilesValidateAndHeadHasNoBody;
    begin
      using lSite := new StaticCacheFixture do begin
        File.WriteText(Path.Combine(lSite.Root, "asset.txt"), "first");
        lSite.Publish;
        var lTag: String;
        var lModified: String;
        using lResponse := lSite.Get("/asset.txt") do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "first");
          Assert.AreEqual(lResponse.Headers.CacheControl.ToString, "no-cache");
          lTag := lResponse.Headers.ETag.ToString;
          Assert.IsTrue(lTag.StartsWith('"'));
          lModified := lResponse.Content.Headers.GetValues("Last-Modified").First;
        end;
        for each lMethod in ["GET", "HEAD"] do begin
          using lHead := lSite.Send(lMethod, "/asset.txt") do begin
            Assert.AreEqual(Integer(lHead.StatusCode), 200);
            Assert.AreEqual(lHead.Content.Headers.ContentLength, 5);
            Assert.AreEqual(lHead.Headers.ETag.ToString, lTag);
            Assert.AreEqual(lHead.Content.ReadAsStringAsync.GetAwaiter.GetResult, if lMethod = "HEAD" then "" else "first");
          end;
          for each lMatch in [lTag, "W/"+lTag, '"different,tag", W/'+lTag, "*"] do
            using lResponse := lSite.Send(lMethod, "/asset.txt?version=anything", "If-None-Match", lMatch) do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 304);
              Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "");
              Assert.AreEqual(lResponse.Content.Headers.ContentLength, 5);
              Assert.AreEqual(lResponse.Headers.ETag.ToString, lTag);
              Assert.AreEqual(lResponse.Headers.CacheControl.ToString, "no-cache");
            end;
        end;
        using lResponse := lSite.Send("GET", "/asset.txt", "If-Modified-Since", lModified) do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
        using lResponse := lSite.Send("GET", "/asset.txt", "If-Modified-Since", "not a date") do
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
        using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, "/asset.txt") do begin
          lRequest.Headers.TryAddWithoutValidation("If-None-Match", '"different"');
          lRequest.Headers.TryAddWithoutValidation("If-Modified-Since", lModified);
          using lResponse := lSite.Client.SendAsync(lRequest).GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 200);
        end;
        // Reusing a connection after HEAD/304 must not leave body bytes behind.
        using lResponse := lSite.Get("/asset.txt") do
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "first");
        // A live development file may be replaced with the same length and timestamp.
        var lTimestamp := System.IO.File.GetLastWriteTimeUtc(Path.Combine(lSite.Root, "asset.txt"));
        File.WriteText(Path.Combine(lSite.Root, "asset.txt"), "other");
        System.IO.File.SetLastWriteTimeUtc(Path.Combine(lSite.Root, "asset.txt"), lTimestamp);
        using lResponse := lSite.Send("GET", "/asset.txt", "If-None-Match", lTag) do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "other");
          Assert.AreNotEqual(lResponse.Headers.ETag.ToString, lTag);
        end;
      end;
    end;

    method PoliciesInheritByPathAndAreCapturedAtPublication;
    begin
      using lSite := new StaticCacheFixture do begin
        Folder.Create(Path.Combine(lSite.Root, "images"));
        Folder.Create(Path.Combine(lSite.Root, "images", "versioned"));
        for each lPath in ["asset.txt", "images/photo.txt", "images/versioned/hash.txt", "images-other.txt"] do
          File.WriteText(Path.Combine(lSite.Root, lPath), "asset");
        lSite.Config := '<configuration>'+CacheSection('cacheControlMode="DisableCache"')+
          '<location path="images/versioned">'+CacheSection('cacheControlMaxAge="365.00:00:00" cacheControlCustom="public, immutable"')+'</location>'+
          '<location path="images">'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="01:00:00"')+'</location></configuration>';
        lSite.Publish;
        for each lPath in ["/asset.txt", "/images-other.txt"] do
          using lResponse := lSite.Get(lPath) do
            Assert.AreEqual(lResponse.Headers.CacheControl.ToString, "no-cache");
        for each lPath in ["/images/photo.txt", "/images//photo.txt", "/images/photo%2Etxt"] do
          using lResponse := lSite.Get(lPath) do begin
            Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 3600.0);
            Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "text/plain");
          end;
        using lResponse := lSite.Get("/images/versioned/hash.txt") do begin
          Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 31536000.0);
          Assert.IsTrue(lResponse.Headers.CacheControl.ToString.Contains("immutable"));
        end;
        lSite.Config := '<configuration>'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="00:02:00" setEtag="false"')+'</configuration>';
        using lResponse := lSite.Get("/images/photo.txt") do
          Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 3600.0);
        lSite.Publish;
        using lResponse := lSite.Get("/images/photo.txt") do begin
          Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 120.0);
          Assert.IsNil(lResponse.Headers.ETag);
          Assert.IsTrue(assigned(lResponse.Content.Headers.LastModified));
        end;
        using lResponse := lSite.Send("GET", "/asset.txt", "If-None-Match", "*") do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
      end;
    end;

    method EmbeddedResourcesUseCapturedConfigAndStableContentTags;
    begin
      using lSite := new StaticCacheFixture do begin
        var lConfig := '<configuration>'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="00:05:00"')+'</configuration>';
        lSite.Server.PageFactory := new StaticCacheTestFactory(EmbeddedConfig := lConfig, EmbeddedBody := "embedded");
        var lTag: String;
        using lResponse := lSite.Get("/embedded.txt") do begin
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "embedded");
          Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 300.0);
          Assert.IsNil(lResponse.Content.Headers.LastModified);
          lTag := lResponse.Headers.ETag.ToString;
        end;
        using lResponse := lSite.Send("GET", "/embedded.txt", "If-None-Match", lTag) do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
        lSite.Server.PageFactory := new StaticCacheTestFactory(EmbeddedConfig := lConfig, EmbeddedBody := "embedded");
        using lResponse := lSite.Send("GET", "/embedded.txt", "If-None-Match", lTag) do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
        lSite.Server.PageFactory := new StaticCacheTestFactory(EmbeddedConfig := lConfig, EmbeddedBody := "replaced");
        using lResponse := lSite.Send("GET", "/embedded.txt", "If-None-Match", lTag) do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "replaced");
        end;
      end;
    end;

    method PublishedRootsKeepIndependentPoliciesAndTags;
    begin
      using lSite := new StaticCacheFixture do begin
        var lFirst := Path.Combine(lSite.Root, "accepted-1");
        var lNext := Path.Combine(lSite.Root, "accepted-2");
        Folder.Create(lFirst);
        Folder.Create(lNext);
        File.WriteText(Path.Combine(lFirst, "asset.txt"), "first");
        File.WriteText(Path.Combine(lNext, "asset.txt"), "other");
        File.WriteText(Path.Combine(lFirst, "Web.config"), '<configuration>'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="01:00:00"')+'</configuration>');
        var lInner := new StaticCacheTestFactory(EmbeddedConfig := '<configuration>'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="02:00:00"')+'</configuration>');
        lSite.Server.PageFactory := new WebPublicationPageFactory(lInner, lFirst, nil, "v1");
        var lTag: String;
        using lResponse := lSite.Get("/asset.txt") do begin
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "first");
          Assert.AreEqual(lResponse.Headers.CacheControl.MaxAge.TotalSeconds, 3600.0);
          lTag := lResponse.Headers.ETag.ToString;
        end;
        using lResponse := lSite.Send("GET", "/asset.txt", "If-None-Match", lTag) do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
        // The next physical publication deliberately has no Web.config. Do not
        // resurrect a configuration embedded in its retained code factory.
        lSite.Server.PageFactory := new WebPublicationPageFactory(lInner, lNext, nil, "v2");
        using lResponse := lSite.Send("GET", "/asset.txt", "If-None-Match", lTag) do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "other");
          Assert.AreEqual(lResponse.Headers.CacheControl.ToString, "no-cache");
          lTag := lResponse.Headers.ETag.ToString;
        end;
        lSite.Server.PageFactory := new WebPublicationPageFactory(lInner, lNext, nil, "v3");
        using lResponse := lSite.Send("GET", "/asset.txt", "If-None-Match", lTag) do
          Assert.AreEqual(Integer(lResponse.StatusCode), 304);
      end;
    end;

    method ExplicitModesAndInvalidConfig;
    begin
      using lSite := new StaticCacheFixture do begin
        File.WriteText(Path.Combine(lSite.Root, "asset.txt"), "asset");
        lSite.Config := '<configuration>'+CacheSection('cacheControlMode="NoControl"')+'</configuration>';
        lSite.Publish;
        using lResponse := lSite.Get("/asset.txt") do begin
          Assert.IsNil(lResponse.Headers.CacheControl);
          Assert.IsTrue(assigned(lResponse.Headers.ETag));
        end;
        lSite.Config := '<configuration>'+CacheSection('cacheControlMode="UseExpires" httpExpires="Fri, 01 Jan 2027 00:00:00 GMT"')+'</configuration>';
        lSite.Publish;
        using lResponse := lSite.Get("/asset.txt") do
          Assert.AreEqual(lResponse.Content.Headers.GetValues("Expires").First, "Fri, 01 Jan 2027 00:00:00 GMT");
        for each lAttributes in ['cacheControlMode="bogus"', 'cacheControlMaxAge="-1:00:00"', 'cacheControlMaxAge="999999999.00:00:00"',
            'setEtag="maybe"', 'cacheControlMode="UseExpires"', 'cacheControlCustom="public&#13;&#10;X-Injected: yes"'] do begin
          var lOld := lSite.Server.PageFactory;
          lSite.Config := '<configuration>'+CacheSection(lAttributes)+'</configuration>';
          var lFailed := false;
          try
            lSite.Publish;
          except
            on E: Exception do
              lFailed := true;
          end;
          Assert.IsTrue(lFailed, lAttributes);
          Assert.AreEqual(lSite.Server.PageFactory, lOld);
          using lResponse := lSite.Get("/asset.txt") do
            Assert.AreEqual(Integer(lResponse.StatusCode), 200);
        end;
      end;
    end;

    method ErrorResponsesDynamicHandlersAndNonGetRequestsKeepTheirSemantics;
    begin
      using lSite := new StaticCacheFixture do begin
        File.WriteText(Path.Combine(lSite.Root, "asset.txt"), "asset");
        lSite.Config := '<configuration>'+CacheSection('cacheControlMode="UseMaxAge" cacheControlMaxAge="01:00:00"')+'</configuration>';
        lSite.Publish;
        using lResponse := lSite.Get("/dynamic.ashx") do begin
          Assert.IsTrue(lResponse.Headers.CacheControl.Private);
          Assert.IsTrue(lResponse.Headers.CacheControl.NoStore);
          Assert.IsNil(lResponse.Headers.ETag);
        end;
        using lResponse := lSite.Send("POST", "/asset.txt", "If-None-Match", "*") do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.IsTrue(lResponse.Headers.CacheControl.NoStore);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "asset");
        end;
        lSite.Server.PageFactory := new StaticCacheTestFactory(Root := lSite.Root, ErrorPath := "/asset.txt");
        using lResponse := lSite.Send("GET", "/missing", "If-None-Match", "*") do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 404);
          Assert.IsTrue(lResponse.Headers.CacheControl.NoStore);
          Assert.IsNil(lResponse.Headers.ETag);
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "asset");
        end;
      end;
    end;

  private

    class method CacheSection(aAttributes: String): String;
    begin
      result := '<system.webServer><staticContent><clientCache '+aAttributes+'/></staticContent></system.webServer>';
    end;

  end;

  StaticCacheFixture = assembly class(System.IDisposable)
  public

    constructor;
    begin
      Root := Path.Combine(System.IO.Path.GetTempPath, "esp-static-cache-"+Guid.NewGuid.ToString);
      Folder.Create(Root);
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      Server := new WebServer;
      Server.Start(lPort);
      Client := new System.Net.Http.HttpClient(BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}"), Timeout := System.TimeSpan.FromSeconds(10));
    end;

    property Root: String;
    property Server: WebServer;
    property Client: System.Net.Http.HttpClient;
    property Config: String write begin File.WriteText(Path.Combine(Root, "Web.config"), value); end;

    method Publish;
    begin
      Server.PageFactory := new StaticCacheTestFactory(Root := Root);
    end;

    method Get(aPath: String): System.Net.Http.HttpResponseMessage;
    begin
      result := Send("GET", aPath);
    end;

    method Send(aMethod: String; aPath: String; aHeader: nullable String := nil; aValue: nullable String := nil): System.Net.Http.HttpResponseMessage;
    begin
      using lRequest := new System.Net.Http.HttpRequestMessage(new System.Net.Http.HttpMethod(aMethod), aPath) do begin
        if assigned(aHeader) then
          lRequest.Headers.TryAddWithoutValidation(aHeader, aValue);
        result := Client.SendAsync(lRequest).GetAwaiter.GetResult;
      end;
    end;

    method Dispose;
    begin
      Client.Dispose;
      Server.Stop;
      System.IO.Directory.Delete(Root, true);
    end;

  end;

  StaticCacheTestFactory = assembly class(WebPageFactory)
  public

    property Root: nullable String;
    property EmbeddedConfig: nullable String;
    property EmbeddedBody: nullable String;
    property ErrorPath: nullable String;
    property PhysicalRootFolder: nullable String read Root; override;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/dynamic.ashx" then
        result := new StaticCacheTestHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

    method FindResourcesForPath(aPath: not nullable String): nullable String; override;
    begin
      if (aPath = "/embedded.txt") and assigned(EmbeddedBody) then
        result := "embedded.txt";
    end;

    method OpenResource(aPath: not nullable String; aPublicOnly: Boolean): nullable Stream; override;
    begin
      if (aPath = "/Web.config") and not aPublicOnly and assigned(EmbeddedConfig) then
        result := new MemoryStream(Encoding.UTF8.GetBytes(EmbeddedConfig))
      else if (aPath = "/embedded.txt") and assigned(EmbeddedBody) then
        result := new MemoryStream(Encoding.UTF8.GetBytes(EmbeddedBody));
    end;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      if assigned(ErrorPath) then
        result := new WebErrorPage(ErrorPath, false, false, false);
    end;

  end;

  StaticCacheTestHandler = assembly class(IHttpHandler)
  public

    property IsReusable: Boolean read false;

    method ProcessRequest(aContext: WebContext);
    begin
      aContext.Response.CacheControl := "private, no-store";
      aContext.Response.Write("dynamic");
    end;

  end;

end.
