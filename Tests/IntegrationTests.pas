namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit;

type
  IntegrationTests = public class(Test)
  private

    const BaseUrl = "http://127.0.0.1:8001";
    const TestSiteAssembly = "Tests/TestSite/Bin/Debug/Elements.Web.TestSite.dll";

    method StartTestSite: System.Diagnostics.Process;
    begin
      Assert.IsTrue(File.Exists(TestSiteAssembly), "Build Tests/TestSite/TestSite.elements before running integration tests.");

      var lStartInfo := new System.Diagnostics.ProcessStartInfo("dotnet", TestSiteAssembly);
      lStartInfo.WorkingDirectory := Environment.CurrentDirectory;
      lStartInfo.UseShellExecute := false;
      lStartInfo.RedirectStandardOutput := true;
      lStartInfo.RedirectStandardError := true;

      result := System.Diagnostics.Process.Start(lStartInfo);
      Assert.IsNotNil(result);
      Assert.IsTrue(WaitForServer(result), "Test site did not start on http://127.0.0.1:8001.");
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

        using lResponse := aClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
          var lResult := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
          Assert.IsNotNil(lResult);
          result := lResult as not nullable;
        end;
      end;
    end;

    method StopTestSite(aProcess: nullable System.Diagnostics.Process);
    begin
      if assigned(aProcess) and not aProcess.HasExited then begin
        aProcess.Kill(true);
        aProcess.WaitForExit(5000);
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
        Assert.IsTrue(lPage.Contains("session=1"));
        Assert.IsTrue(lPage.Contains("application=hello world"));
        Assert.IsTrue(lPage.Contains("control=from-control"));
        Assert.IsTrue(lPage.Contains("master-end"));

        var lPost := PostString("/?q=post", "name=Form+Value");
        Assert.IsTrue(lPost.Contains("query=post"));
        Assert.IsTrue(lPost.Contains("form=Form Value"));

        Assert.AreEqual(GetString("/Ping.ashx?value=ok"), "handler=ok");
        Assert.IsTrue(GetString("/Static/hello.txt").StartsWith("hello from embedded resource"));
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
        end;
      finally
        StopTestSite(lProcess);
      end;
    end;

  end;

end.
