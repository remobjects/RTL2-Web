namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  ResponseTests = public class(Test)
  public

    method DefaultsToUtf8Html;
    begin
      var lResponse := new WebResponse(new HttpServerResponse);

      Assert.AreEqual(lResponse.ContentType, "text/html; charset=utf-8");
      Assert.AreEqual(lResponse.Charset, "utf-8");
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

  end;

  CookieCompletionFactory = class(WebPageFactory)
  public

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath in ["/normal", "/redirect", "/permanent", "/end", "/reflected", "/read"] then
        result := new CookieCompletionHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

  end;

  CookieCompletionHandler = class(IHttpHandler)
  public

    method ProcessRequest(Context: WebContext);
    begin
      var lMode := Context.Request.Url.Path;
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
