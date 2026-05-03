namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit;

type
  IntegrationTests = public class(Test)
  private

    const BaseUrl = "http://127.0.0.1:8001";

    method StartTestSite: System.Diagnostics.Process;
    begin
      var lTestSiteAssembly := GetTestSiteAssemblyPath;
      Assert.IsTrue(File.Exists(lTestSiteAssembly), "Build Tests/TestSite/TestSite.elements before running integration tests.");

      var lStartInfo := new System.Diagnostics.ProcessStartInfo("dotnet", lTestSiteAssembly);
      lStartInfo.WorkingDirectory := Path.GetParentDirectory(lTestSiteAssembly);
      lStartInfo.UseShellExecute := false;
      lStartInfo.RedirectStandardOutput := true;
      lStartInfo.RedirectStandardError := true;

      result := System.Diagnostics.Process.Start(lStartInfo);
      Assert.IsNotNil(result);
      Assert.IsTrue(WaitForServer(result), "Test site did not start on http://127.0.0.1:8001.");
    end;

    method GetTestSiteAssemblyPath: not nullable String;
    begin
      {$IF ECHOES}
      var lBasePath := Path.GetParentDirectory(System.Reflection.Assembly.GetExecutingAssembly.Location);
      {$ELSE}
      var lBasePath := Environment.CurrentDirectory;
      {$ENDIF}

      result := Path.GetFullPath(Path.Combine(lBasePath, "..", "..", "TestSite", "Bin", "Debug", "Elements.Web.TestSite.dll"));
    end;

    method WaitForServer(aProcess: not nullable System.Diagnostics.Process): Boolean;
    begin
      for i: Integer := 0 to 49 do begin
        if aProcess.HasExited then
          exit false;

        try
          Http.GetString(nil, new HttpRequest(BaseUrl+"/Ping.ashx?value=ready"));
          exit true;
        except
          on E: Exception do
            System.Threading.Thread.Sleep(100);
        end;
      end;
    end;

    method GetString(aPath: not nullable String): not nullable String;
    begin
      result := Http.GetString(nil, new HttpRequest(BaseUrl+aPath));
    end;

    method PostString(aPath: not nullable String; aBody: not nullable String): not nullable String;
    begin
      var lRequest := new HttpRequest(BaseUrl+aPath, HttpRequestMethod.Post);
      lRequest.Content := new HttpBinaryRequestContent(aBody, Encoding.UTF8, "application/x-www-form-urlencoded");
      result := Http.GetString(nil, lRequest);
    end;

    method PostMultipartString(aPath: not nullable String): not nullable String;
    begin
      var lBoundary := "----rtl2webtest";
      var lBody :=
        "--"+lBoundary+#13#10+
        "Content-Disposition: form-data; name=""title"""#13#10+
        #13#10+
        "Upload Title"#13#10+
        "--"+lBoundary+#13#10+
        "Content-Disposition: form-data; name=""sample""; filename=""hello.txt"""#13#10+
        "Content-Type: text/plain"#13#10+
        #13#10+
        "hello upload"#13#10+
        "--"+lBoundary+"--"#13#10;

      using lClient := new System.Net.Http.HttpClient do begin
        using lContent := new System.Net.Http.ByteArrayContent(Encoding.UTF8.GetBytes(lBody)) do begin
          lContent.Headers.TryAddWithoutValidation("Content-Type", "multipart/form-data; boundary="+lBoundary);

          using lResponse := lClient.PostAsync(BaseUrl+aPath, lContent).GetAwaiter.GetResult do begin
            var lResult := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
            Assert.IsNotNil(lResult);
            result := lResult as not nullable;
          end;
        end;
      end;
    end;

    method GetString(aClient: not nullable System.Net.Http.HttpClient; aPath: not nullable String): not nullable String;
    begin
      var lResult := aClient.GetStringAsync(BaseUrl+aPath).GetAwaiter.GetResult;
      Assert.IsNotNil(lResult);
      result := lResult as not nullable;
    end;

    method SendString(aClient: not nullable System.Net.Http.HttpClient; aPath: not nullable String): not nullable String;
    begin
      using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, BaseUrl+aPath) do begin
        lRequest.Headers.TryAddWithoutValidation("User-Agent", "RTL2WebTests/1.0");
        lRequest.Headers.TryAddWithoutValidation("X-Test-Header", "header-value");
        lRequest.Headers.TryAddWithoutValidation("Accept", "text/html, application/xhtml+xml");
        lRequest.Headers.TryAddWithoutValidation("Accept-Language", "en-US, en;q=0.9");
        lRequest.Headers.TryAddWithoutValidation("Referer", BaseUrl+"/referrer");

        using lResponse := aClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
          var lResult := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
          Assert.IsNotNil(lResult);
          result := lResult as not nullable;
        end;
      end;
    end;

    method StopTestSite(aProcess: nullable System.Diagnostics.Process);
    begin
      if not assigned(aProcess) then
        exit;

      try
        if aProcess.HasExited then
          exit;
      except
        on E: System.ComponentModel.Win32Exception do
          exit;
        on E: System.InvalidOperationException do
          exit;
      end;

      try
        aProcess.Kill(true);
        aProcess.WaitForExit(5000);
      except
        on E: System.ComponentModel.Win32Exception do begin
        end;
        on E: System.InvalidOperationException do begin
        end;
      end;
    end;

  public

    method BuiltAspxSiteServesPagesHandlersAndResources;
    begin
      var lProcess := StartTestSite;
      try
        var lPage := GetString("/?q=hello+world");
        Assert.IsTrue(lPage.Contains("master-start"));
        Assert.IsTrue(lPage.Contains("query=hello world"));
        Assert.IsTrue(lPage.Contains("params-query=hello world"));
        Assert.IsTrue(lPage.Contains("params-server=127.0.0.1"));
        Assert.IsTrue(lPage.Contains("params-default=hello world"));
        Assert.IsTrue(lPage.Contains("context-current-query=hello world"));
        Assert.IsTrue(lPage.Contains("server-html=&lt;server&gt;"));
        Assert.IsTrue(lPage.Contains("server-url=one%20two"));
        Assert.IsTrue(lPage.Contains("server-mappath="));
        Assert.IsTrue(lPage.Contains("Tests/TestSite/Static/hello.txt"));
        Assert.IsTrue(lPage.Contains("context-server-mappath="));
        Assert.IsTrue(lPage.Contains("request-physical-application-path="));
        Assert.IsTrue(lPage.Contains("request-mappath="));
        Assert.IsTrue(lPage.Contains("session=1"));
        Assert.IsTrue(lPage.Contains("application=hello world"));
        Assert.IsTrue(lPage.Contains("control=from-control"));
        Assert.IsTrue(lPage.Contains("master-end"));

        var lPost := PostString("/?q=post", "name=Form+Value");
        Assert.IsTrue(lPost.Contains("query=post"));
        Assert.IsTrue(lPost.Contains("form=Form Value"));
        Assert.IsTrue(lPost.Contains("params-query=post"));
        Assert.IsTrue(lPost.Contains("params-form=Form Value"));
        Assert.IsTrue(lPost.Contains("request-http-method=POST"));
        Assert.IsTrue(lPost.Contains("request-request-type=POST"));
        Assert.IsTrue(lPost.Contains("request-content-type=application/x-www-form-urlencoded"));
        Assert.IsTrue(lPost.Contains("request-content-length=15"));
        Assert.IsTrue(lPost.Contains("request-total-bytes=15"));

        Assert.AreEqual(GetString("/Ping.ashx?value=ok"), "handler=ok");
        Assert.AreEqual(GetString("/Ping.ashx?value=ok&current=1"), "current=ok");
        Assert.IsTrue(GetString("/Static/hello.txt").StartsWith("hello from embedded resource"));
        Assert.AreEqual(PostMultipartString("/Upload.ashx"), "form-title=Upload Title;files=1;key=sample;name=hello.txt;type=text/plain;length=12;stream=12;saved=hello upload");

        var lNestedPage := GetString("/Nested.aspx");
        Assert.IsTrue(lNestedPage.Contains("base-start"));
        Assert.IsTrue(lNestedPage.Contains("custom-header"));
        Assert.IsTrue(lNestedPage.Contains("child-start"));
        Assert.IsTrue(lNestedPage.Contains("page-content"));
        Assert.IsTrue(lNestedPage.Contains("child-end"));
        Assert.IsTrue(lNestedPage.Contains("base-end"));
        Assert.IsFalse(lNestedPage.Contains("default-header"));

        var lNestedFallbackPage := GetString("/NestedFallback.aspx");
        Assert.IsTrue(lNestedFallbackPage.Contains("base-start"));
        Assert.IsTrue(lNestedFallbackPage.Contains("default-header"));
        Assert.IsTrue(lNestedFallbackPage.Contains("fallback-body"));
        Assert.IsTrue(lNestedFallbackPage.Contains("base-end"));
      finally
        StopTestSite(lProcess);
      end;
    end;

    method SessionStateRoundTripsWithSessionCookie;
    begin
      var lProcess := StartTestSite;
      try
        using lHandler := new System.Net.Http.HttpClientHandler do begin
          lHandler.CookieContainer := new System.Net.CookieContainer;

          using lClient := new System.Net.Http.HttpClient(lHandler) do begin
            var lFirstPage := GetString(lClient, "/?q=session");
            var lSecondPage := GetString(lClient, "/?q=session");

            Assert.IsTrue(lFirstPage.Contains("session=1"));
            Assert.IsTrue(lSecondPage.Contains("session=2"));
          end;
        end;
      finally
        StopTestSite(lProcess);
      end;
    end;

    method RequestCookiesRoundTripFromResponseCookies;
    begin
      var lProcess := StartTestSite;
      try
        using lHandler := new System.Net.Http.HttpClientHandler do begin
          lHandler.CookieContainer := new System.Net.CookieContainer;

          using lClient := new System.Net.Http.HttpClient(lHandler) do begin
            var lFirstPage := GetString(lClient, "/?q=cookie");
            var lSecondPage := GetString(lClient, "/?q=cookie");

            Assert.IsTrue(lFirstPage.Contains("seen="));
            Assert.IsTrue(lFirstPage.Contains("flavor="));
            Assert.IsTrue(lSecondPage.Contains("seen=yes"));
            Assert.IsTrue(lSecondPage.Contains("flavor=chocolate"));
            Assert.IsTrue(lSecondPage.Contains("params-cookie=yes"));
          end;
        end;
      finally
        StopTestSite(lProcess);
      end;
    end;

    method RequestHeadersAndServerVariablesMatchClassicShape;
    begin
      var lProcess := StartTestSite;
      try
        using lClient := new System.Net.Http.HttpClient do begin
          var lPage := SendString(lClient, "/?q=headers");

          Assert.IsTrue(lPage.Contains("header-user-agent=RTL2WebTests/1.0"));
          Assert.IsTrue(lPage.Contains("header-user-agent-lower=RTL2WebTests/1.0"));
          Assert.IsTrue(lPage.Contains("header-custom=header-value"));
          Assert.IsTrue(lPage.Contains("server-http-host=127.0.0.1:8001"));
          Assert.IsTrue(lPage.Contains("server-name=127.0.0.1"));
          Assert.IsTrue(lPage.Contains("server-port=8001"));
          Assert.IsTrue(lPage.Contains("server-method=GET"));
          Assert.IsTrue(lPage.Contains("server-query=q=headers"));
          Assert.IsTrue(lPage.Contains("server-path=/"));
          Assert.IsTrue(lPage.Contains("server-script-name=/"));
          Assert.IsTrue(lPage.Contains("server-url=/"));
          Assert.IsTrue(lPage.Contains("server-user-agent=RTL2WebTests/1.0"));
          Assert.IsTrue(lPage.Contains("server-name-lower=127.0.0.1"));
          Assert.IsTrue(lPage.Contains("server-https=off"));
          Assert.IsTrue(lPage.Contains("server-remote-addr=127.0.0.1"));
          Assert.IsTrue(lPage.Contains("server-local-addr=127.0.0.1"));
          Assert.IsTrue(lPage.Contains("request-http-method=GET"));
          Assert.IsTrue(lPage.Contains("request-request-type=GET"));
          Assert.IsTrue(lPage.Contains("request-secure=False"));
          Assert.IsTrue(lPage.Contains("request-referrer=http://127.0.0.1:8001/referrer"));
          Assert.IsTrue(lPage.Contains("request-accept=text/html"));
          Assert.IsTrue(lPage.Contains("request-language=en-US"));
        end;
      finally
        StopTestSite(lProcess);
      end;
    end;

    method RequestPathPropertiesMatchClassicShape;
    begin
      var lProcess := StartTestSite;
      try
        var lPage := GetString("/?q=paths");

        Assert.IsTrue(lPage.Contains("request-application-path=/"));
        Assert.IsTrue(lPage.Contains("request-file-path=/Default.aspx"));
        Assert.IsTrue(lPage.Contains("request-current-execution-file-path=/Default.aspx"));
        Assert.IsTrue(lPage.Contains("request-current-execution-file-path-extension=.aspx"));
        Assert.IsTrue(lPage.Contains("request-app-relative-current-execution-file-path=~/Default.aspx"));
        Assert.IsTrue(lPage.Contains("request-path-info="));
        Assert.IsTrue(lPage.Contains("request-physical-path="));
        Assert.IsTrue(lPage.Contains("Tests/TestSite/Default.aspx"));
        Assert.IsTrue(lPage.Contains("request-physical-application-path="));
        Assert.IsTrue(lPage.Contains("Tests/TestSite"));
        Assert.IsTrue(lPage.Contains("runtime-app-domain-app-path="));
        Assert.IsTrue(lPage.Contains("runtime-app-domain-app-virtual-path=/"));
      finally
        StopTestSite(lProcess);
      end;
    end;

    method ResponseConvenienceMethodsMatchClassicShape;
    begin
      var lProcess := StartTestSite;
      try
        using lHandler := new System.Net.Http.HttpClientHandler do begin
          lHandler.AllowAutoRedirect := false;

          using lClient := new System.Net.Http.HttpClient(lHandler) do begin
            var lWrite := lClient.GetStringAsync(BaseUrl+"/Response.ashx?action=write").GetAwaiter.GetResult;
            Assert.AreEqual(lWrite, "alpha-42");

            using lRedirect := lClient.GetAsync(BaseUrl+"/Response.ashx?action=redirect").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lRedirect.StatusCode), 302);
              Assert.AreEqual(lRedirect.Headers.Location.ToString, "/Ping.ashx?value=redirected");
              var lBody := lRedirect.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.IsTrue(lBody.Contains("after-redirect"));
            end;

            using lRedirectEnd := lClient.GetAsync(BaseUrl+"/Response.ashx?action=redirect-end").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lRedirectEnd.StatusCode), 302);
              var lBody := lRedirectEnd.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.IsFalse(lBody.Contains("after-end"));
            end;

            var lRawUrl := lClient.GetStringAsync(BaseUrl+"/Response.ashx?action=rawurl&value=123").GetAwaiter.GetResult;
            Assert.AreEqual(lRawUrl, "/Response.ashx?action=rawurl&value=123");

            using lPermanent := lClient.GetAsync(BaseUrl+"/Response.ashx?action=permanent").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lPermanent.StatusCode), 301);
              Assert.AreEqual(lPermanent.Headers.Location.ToString, "/Ping.ashx?value=permanent");
            end;

            var lTransferHandler := lClient.GetStringAsync(BaseUrl+"/Response.ashx?action=transfer-handler").GetAwaiter.GetResult;
            Assert.AreEqual(lTransferHandler, "handler=transferred-handler");

            var lTransferPage := lClient.GetStringAsync(BaseUrl+"/Response.ashx?action=transfer-page").GetAwaiter.GetResult;
            Assert.IsTrue(lTransferPage.Contains("query=transferred-page"));
            Assert.IsFalse(lTransferPage.Contains("after-transfer-page"));

            using lClear := lClient.GetAsync(BaseUrl+"/Response.ashx?action=clear").GetAwaiter.GetResult do begin
              var lBody := lClear.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.AreEqual(lBody, "after");
              Assert.IsFalse(lClear.Headers.Contains("X-Test-Clear"));
            end;

            using lHeaders := lClient.GetAsync(BaseUrl+"/Response.ashx?action=headers").GetAwaiter.GetResult do begin
              var lBody := lHeaders.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.AreEqual(lBody, "new");
              var lHeaderText := lHeaders.Headers.ToString;
              Assert.IsTrue(lHeaderText.Contains("X-Test-Header"));
              Assert.IsTrue(lHeaderText.Contains("one"));
              Assert.IsTrue(lHeaderText.Contains("two"));
              Assert.IsTrue(lHeaderText.Contains("X-Test-Replace: new"));
            end;

            using lStatus := lClient.GetAsync(BaseUrl+"/Response.ashx?action=status").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lStatus.StatusCode), 404);
              var lBody := lStatus.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.AreEqual(lBody, "NotFound");
            end;
          end;
        end;
      finally
        StopTestSite(lProcess);
      end;
    end;

  end;

end.
