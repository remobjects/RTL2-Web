namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  ResponseTests = public class(Test)
  public

    method JsonErrorsAndFormContentTypes;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new JsonErrorFactory);
      lServer.ErrorPaths[404] := "/custom-error";
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          for each lPath in ["/skip", "/custom"] do
            using lBody := new System.Net.Http.StringContent('{"test":true}', System.Text.Encoding.UTF8, "application/json") do
            using lResponse := lClient.PostAsync($"http://127.0.0.1:{lPort}"+lPath, lBody).GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 404);
              Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult,
                if lPath = "/skip" then '{"error":"missing"}' else "custom error; form empty");
              if lPath = "/skip" then
                Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "application/json");
            end;
          using lBody := new System.Net.Http.StringContent("test=hello+world", System.Text.Encoding.UTF8, "application/x-www-form-urlencoded") do
          using lResponse := lClient.PostAsync($"http://127.0.0.1:{lPort}/form", lBody).GetAwaiter.GetResult do
            Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "hello world");
        end;
      finally
        lServer.Stop;
      end;
    end;

    method DefaultsToUtf8Html;
    begin
      var lResponse := new WebResponse(new HttpServerResponse);

      Assert.AreEqual(lResponse.ContentType, "text/html; charset=utf-8");
      Assert.AreEqual(lResponse.Charset, "utf-8");
    end;

    method AttachmentHeadersSurviveClearAndEnd;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new CookieCompletionFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do
        using lResponse := lClient.GetAsync($"http://127.0.0.1:{lPort}/download").GetAwaiter.GetResult do begin
          Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "text/text");
          Assert.AreEqual(lResponse.Content.Headers.ContentDisposition.DispositionType, "attachment");
          Assert.AreEqual(lResponse.Content.Headers.ContentDisposition.FileName, '"Your Elements Trial Extension.licenses"');
          Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "license data");
        end;
      finally
        lServer.Stop;
      end;
    end;

    method CookiesSurviveResponseCompletion;
    begin
      // Isolated loopback server: do not use the developer's website port.
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new CookieCompletionFactory);
      lServer.Start(lPort);
      try
        for each lMode in ["normal", "redirect", "permanent", "end", "reflected"] do begin
          var lCookies := new System.Net.CookieContainer;
          using lHandler := new System.Net.Http.HttpClientHandler(AllowAutoRedirect := false, CookieContainer := lCookies) do
          using lClient := new System.Net.Http.HttpClient(lHandler) do begin
            var lBaseUrl := $"http://127.0.0.1:{lPort}";
            using lResponse := lClient.GetAsync(lBaseUrl+"/"+lMode).GetAwaiter.GetResult do begin
              var lExpectedStatus := if lMode = "permanent" then 301 else if lMode in ["redirect", "reflected"] then 302 else 200;
              Assert.AreEqual(Integer(lResponse.StatusCode), lExpectedStatus, lMode);
              Assert.IsTrue(lResponse.Headers.Contains("Set-Cookie"), lMode+": response cookies missing");
              var lCookieHeaders := lResponse.Headers.GetValues("Set-Cookie").ToList;
              Assert.AreEqual(lCookieHeaders.Count, 3, lMode);
              var lHeaders := String.Join(#10, lCookieHeaders);
              Assert.IsTrue(lHeaders.Contains("StagingAccess=granted"), lMode);
              Assert.IsTrue(lHeaders.Contains("EspSessionId="), lMode);
              Assert.IsTrue(lHeaders.Contains("SecureOnly=yes"), lMode);
              Assert.IsTrue(lHeaders.ToLower.Contains("; secure"), lMode);
              Assert.IsTrue(lHeaders.ToLower.Contains("; httponly"), lMode);
              if lExpectedStatus in [301, 302] then
                Assert.AreEqual(lResponse.Headers.Location.ToString, "/read");
              var lBody := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.IsFalse(lBody.Contains("unreachable"), lMode);
              if lMode in ["normal", "end"] then
                Assert.AreEqual(lBody, "complete", lMode);
            end;
            var lResult := lClient.GetStringAsync(lBaseUrl+"/read").GetAwaiter.GetResult;
            Assert.AreEqual(lResult, "granted|preserved", lMode+": cookie/session round trip");
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;

    method FlushStreamsBeforeHandlerCompletion;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lFactory := new StreamingCompletionFactory;
      var lServer := new WebServer(PageFactory := lFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Sockets.TcpClient do begin
          lClient.ReceiveTimeout := 5000;
          lClient.Connect(System.Net.IPAddress.Loopback, lPort);
          using lStream := lClient.GetStream do begin
            var lRequest := System.Text.Encoding.ASCII.GetBytes("GET /stream HTTP/1.1"+#13#10+"Host: 127.0.0.1"+#13#10+"Connection: close"+#13#10#13#10);
            lStream.Write(lRequest, 0, length(lRequest));
            var lBuffer := new Byte[4096];
            var lFirstResponse := "";
            while not lFirstResponse.Contains("first") do begin
              var lCount := lStream.Read(lBuffer, 0, length(lBuffer));
              Assert.IsTrue(lCount > 0, "Stream ended before the flushed response bytes arrived.");
              lFirstResponse := lFirstResponse+System.Text.Encoding.UTF8.GetString(lBuffer, 0, lCount);
            end;
            Assert.IsTrue(lFirstResponse.ToLowerInvariant.Contains("transfer-encoding: chunked"));
            Assert.IsFalse(lFirstResponse.Contains("second"));
            lFactory.ContinueEvent.Set;
            var lRemainingResponse := "";
            while not lRemainingResponse.Contains("0"+#13#10#13#10) do begin
              var lCount := lStream.Read(lBuffer, 0, length(lBuffer));
              Assert.IsTrue(lCount > 0, "Stream ended before the chunked response terminator arrived.");
              lRemainingResponse := lRemainingResponse+System.Text.Encoding.UTF8.GetString(lBuffer, 0, lCount);
            end;
            Assert.IsTrue(lRemainingResponse.Contains("second"));
          end;
        end;
      finally
        lFactory.ContinueEvent.Set;
        lServer.Stop;
      end;
    end;

  end;

  JsonErrorFactory = class(WebPageFactory)
  public
    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath in ["/skip", "/custom", "/custom-error", "/form"] then
        result := new JsonErrorHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;
  end;

  JsonErrorHandler = class(IHttpHandler)
  public
    method ProcessRequest(aContext: WebContext);
    begin
      if aContext.Request.Url.Path = "/form" then begin
        aContext.Response.Write(aContext.Request.Form["test"]);
        exit;
      end;
      if aContext.Request.Url.Path = "/custom-error" then begin
        Assert.IsFalse(assigned(aContext.Request.Form["test"]));
        aContext.Response.Write("custom error; form empty");
        exit;
      end;
      var lBytes := new Byte[aContext.Request.ContentLength];
      var lOffset := 0;
      while lOffset < length(lBytes) do begin
        var lRead := aContext.Request.InputStream.Read(lBytes, lOffset, length(lBytes)-lOffset);
        Assert.IsTrue(lRead > 0);
        inc(lOffset, lRead);
      end;
      Assert.AreEqual(System.Text.Encoding.UTF8.GetString(lBytes), '{"test":true}');
      aContext.Response.TrySkipIisCustomErrors := aContext.Request.Url.Path = "/skip";
      aContext.Response.StatusCode := 404;
      aContext.Response.ContentType := "application/json";
      aContext.Response.Write('{"error":"missing"}');
    end;
  end;

  StreamingCompletionFactory = class(WebPageFactory)
  public

    property ContinueEvent := new System.Threading.ManualResetEventSlim(false); readonly;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/stream" then
        result := new StreamingCompletionHandler(ContinueEvent);
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

  end;

  StreamingCompletionHandler = class(IHttpHandler)
  public

    constructor(aContinueEvent: not nullable System.Threading.ManualResetEventSlim);
    begin
      fContinueEvent := aContinueEvent;
    end;

    method ProcessRequest(aContext: WebContext);
    begin
      aContext.Response.ContentType := "text/plain";
      aContext.Response.Write("first");
      aContext.Response.Flush;
      if not fContinueEvent.Wait(5000) then
        raise new TimeoutException("The streaming response test did not release the handler.");
      aContext.Response.Write("second");
    end;

  private
    fContinueEvent: not nullable System.Threading.ManualResetEventSlim;
  end;

  CookieCompletionFactory = class(WebPageFactory)
  public

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath in ["/normal", "/redirect", "/permanent", "/end", "/reflected", "/read", "/download"] then
        result := new CookieCompletionHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

  end;

  CookieCompletionHandler = class(IHttpHandler)
  public

    method ProcessRequest(Context: WebContext);
    begin
      var lMode := Context.Request.Url.Path;
      if lMode = "/download" then begin
        Context.Response.Write("discard me");
        Context.Response.ContentType := "text/text";
        Context.Response.AddHeader("Content-Disposition", 'attachment; filename="Your Elements Trial Extension.licenses"');
        Context.Response.Clear;
        Context.Response.BinaryWrite(System.Text.Encoding.UTF8.GetBytes("license data"));
        Context.Response.End;
      end;
      if lMode = "/read" then begin
        Context.Response.Write(Context.Request.Cookies["StagingAccess"].Value+"|"+Context.Session["marker"]);
        exit;
      end;
      Context.Session["marker"] := "preserved";
      Context.Response.Cookies["StagingAccess"].Value := "granted";
      Context.Response.Cookies["StagingAccess"].Domain := Context.Request.Url.Host;
      Context.Response.Cookies["StagingAccess"].Expires := DateTime.UtcNow.AddDays(1);
      Context.Response.Cookies["SecureOnly"].Value := "yes";
      Context.Response.Cookies["SecureOnly"].Domain := Context.Request.Url.Host;
      Context.Response.Cookies["SecureOnly"].Expires := DateTime.UtcNow.AddDays(1);
      Context.Response.Cookies["SecureOnly"].Secure := true;
      Context.Response.Cookies["SecureOnly"].HttpOnly := true;
      Context.Response.Write("complete");
      case lMode of
        "/redirect": Context.Response.Redirect("/read");
        "/permanent": Context.Response.RedirectPermanent("/read");
        "/end": Context.Response.End;
        "/reflected": begin
          try
            Context.Response.Redirect("/read");
          except
            on E: CleanlyEndResponseException do
              raise new System.Reflection.TargetInvocationException(E);
          end;
        end;
      end;
      if lMode ≠ "/normal" then
        Context.Response.Write("unreachable");
    end;

  end;

end.
