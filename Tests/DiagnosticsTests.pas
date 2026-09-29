namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  DiagnosticsTests = public class(Test)
  public

    method NullBytePathsReturnSilent404;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new Redirect404TestFactory);
      lServer.Start(lPort);
      try
        using lHandler := new System.Net.Http.HttpClientHandler(AllowAutoRedirect := false) do
        using lClient := new System.Net.Http.HttpClient(lHandler) do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          for each lStarting in [false, true] do begin
            if lStarting then begin
              lServer.PageFactory := nil;
              lServer.RequireUpdateTrigger := true;
            end;
            for each lPath in ["/.env.development%00", "/%00/file.txt", "/__esp/source/%00"] do
              for each lMethod in [System.Net.Http.HttpMethod.Get, System.Net.Http.HttpMethod.Head] do
                using lRequest := new System.Net.Http.HttpRequestMessage(lMethod, lPath) do
                  using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
                    Assert.AreEqual(Integer(lResponse.StatusCode), 404);
                    Assert.IsFalse(assigned(lResponse.Headers.Location));
                    Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult,
                      if lMethod = System.Net.Http.HttpMethod.Head then "" else "Not Found");
                  end;
          end;
          var lJson := JsonObject.FromString(lClient.GetStringAsync("/__esp/errors?format=json").GetAwaiter.GetResult);
          Assert.AreEqual((lJson["errors"] as JsonArray).Count, 0);
        end;
      finally
        lServer.Stop;
      end;
    end;

    method StatusFormatDoesNotDependOnPublicationOrAuthentication;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(HostStatus := new WebHostStatus(Summary := "Ready <test>", ActiveGeneration := 7, Generation := 8));
      lServer.ManagementRequest += (s, e) -> begin
        var lArgs := e as WebManagementEventArgs;
        Assert.IsTrue(lArgs.Json, "HTML status must use the shared renderer.");
        lArgs.Body := '{"publication":"preserved"}';
      end;
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          for each lTrigger in [false, true] do
            for each lToken in ["", "test-token"] do
              for each lDebug in [false, true] do begin
                lServer.RequireUpdateTrigger := lTrigger;
                lServer.AuthorizationToken := lToken;
                lServer.DebugMode := lDebug;
                for each lFormat in ["", "&format=html", "&format=json"] do
                  using lResponse := lClient.GetAsync("/__esp/status?token="+lToken+lFormat).GetAwaiter.GetResult do begin
                    if not lTrigger and not lDebug and (length(lToken) = 0) then begin
                      Assert.AreEqual(Integer(lResponse.StatusCode), 404);
                      continue;
                    end;
                    Assert.AreEqual(Integer(lResponse.StatusCode), 200);
                    var lBody := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
                    if lFormat = "&format=json" then begin
                      Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "application/json");
                      Assert.AreEqual(lBody, '{"publication":"preserved"}');
                    end
                    else begin
                      Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "text/html");
                      Assert.IsTrue(lBody.Contains("<h1>ESP Status</h1>"));
                      Assert.IsTrue(lBody.Contains("Ready &lt;test&gt;"));
                      Assert.IsTrue(lBody.Contains("<strong>7</strong>"));
                      Assert.IsFalse(lBody.Contains("publication"));
                      Assert.IsTrue(lBody.Contains("ESPDebugMode "+(if lDebug then "enabled" else "disabled")));
                      if length(lToken) > 0 then
                        Assert.IsTrue(lBody.Contains('/__esp/diagnostics?token=test-token'));
                    end;
                  end;
                if length(lToken) > 0 then
                  using lDenied := lClient.GetAsync("/__esp/status?format=html").GetAwaiter.GetResult do
                    Assert.AreEqual(Integer(lDenied.StatusCode), 401);
              end;
          using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Head, "/__esp/status") do begin
            lRequest.Headers.Authorization := new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", "test-token");
            using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 200);
              Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "text/html");
              Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "");
            end;
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;

    method StaticErrorFilesWorkBeforeCompilationAndForNormalErrors;
    begin
      var lRoot := Path.Combine(System.IO.Path.GetTempPath, "esp-static-errors-"+Guid.NewGuid.ToString);
      Folder.Create(lRoot);
      var lConfig := Path.Combine(lRoot, "Web.config");
      var lHtml := "<html>We'll be right back.</html>";
      File.WriteText(Path.Combine(lRoot, "503.html"), lHtml);
      var lXml := '<configuration><system.webServer><httpErrors errorMode="Custom"><error statusCode="503" path="/503.html" responseMode="File"/></httpErrors></system.webServer></configuration>';
      File.WriteText(lConfig, lXml);
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(HostStarting := true, PhysicalRootFolder := lRoot);
      lServer.LoadStaticErrorPages(lRoot);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          for each lTrigger in [false, true] do begin
            lServer.RequireUpdateTrigger := lTrigger;
            for each lMethod in [System.Net.Http.HttpMethod.Get, System.Net.Http.HttpMethod.Head] do
              using lRequest := new System.Net.Http.HttpRequestMessage(lMethod, "/not-built") do
                using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
                  Assert.AreEqual(Integer(lResponse.StatusCode), 503);
                  Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, if lMethod = System.Net.Http.HttpMethod.Head then "" else lHtml);
                  Assert.AreEqual(lResponse.Content.Headers.ContentType.MediaType, "text/html");
                  Assert.IsTrue(lResponse.Headers.CacheControl.NoStore);
                end;
          end;
          // Cached startup contents do not change while publication is being restored.
          File.WriteText(Path.Combine(lRoot, "503.html"), "unaccepted replacement");
          using lResponse := lClient.GetAsync("/not-built").GetAwaiter.GetResult do
            Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, lHtml);
          File.WriteText(Path.Combine(lRoot, "503.html"), lHtml);
          using lResponse := lClient.GetAsync("/__esp/health").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          for each lRules in [
            '<clear/>', '<remove statusCode="503"/>',
            '<error statusCode="503" path="/dynamic.aspx" responseMode="ExecuteURL"/>',
            '<error statusCode="503" path="/other" responseMode="Redirect"/>'] do begin
            File.WriteText(lConfig, lXml.Replace('</httpErrors>', lRules+'</httpErrors>'));
            lServer.LoadStaticErrorPages(lRoot);
            using lResponse := lClient.GetAsync("/not-built").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 503);
              Assert.IsFalse(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult.Contains(lHtml));
            end;
          end;
          for each lConfigText in [lXml.Replace('errorMode="Custom"', 'errorMode="Detailed"'), '<configuration>'] do begin
            File.WriteText(lConfig, lConfigText);
            lServer.LoadStaticErrorPages(lRoot);
            using lResponse := lClient.GetAsync("/not-built").GetAwaiter.GetResult do
              Assert.IsFalse(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult.Contains(lHtml));
          end;
          File.WriteText(lConfig, lXml);
          lServer.LoadStaticErrorPages(lRoot);
          lServer.RequireUpdateTrigger := false;
          lServer.HostStarting := false;
          var lFactory := new StaticErrorTestFactory(Root := lRoot, ErrorFile := "/503.html");
          lServer.PageFactory := lFactory;
          for each lCode in [404, 500, 503] do
            for each lMethod in [System.Net.Http.HttpMethod.Get, System.Net.Http.HttpMethod.Head] do
              using lRequest := new System.Net.Http.HttpRequestMessage(lMethod, $"/status?code={lCode}") do
                using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
                  Assert.AreEqual(Integer(lResponse.StatusCode), lCode);
                  Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, if lMethod = System.Net.Http.HttpMethod.Head then "" else lHtml);
                  Assert.IsTrue(lResponse.Headers.CacheControl.NoStore);
                end;
          Folder.Create(Path.Combine(lRoot, "App_Private"));
          File.WriteText(Path.Combine(lRoot, "App_Private/secret.html"), "private-content");
          File.WriteText(Path.Combine(lRoot, "source.aspx"), "private-content");
          System.IO.File.CreateSymbolicLink(Path.Combine(lRoot, "linked.html"), Path.Combine(lRoot, "App_Private/secret.html"));
          System.IO.Directory.CreateSymbolicLink(Path.Combine(lRoot, "linked-folder"), Path.Combine(lRoot, "App_Private"));
          for each lPath in ["/missing.html", "/../503.html", "/%2e%2e/503.html", "/App_Private/secret.html", "/source.aspx", "/Web.config", "/linked.html", "/linked-folder/secret.html", "https://example.com/503.html"] do begin
            lFactory.ErrorFile := lPath;
            using lResponse := lClient.GetAsync("/status?code=503").GetAwaiter.GetResult do begin
              var lBody := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
              Assert.AreEqual(Integer(lResponse.StatusCode), 503, lPath);
              Assert.IsTrue(lBody.Contains("The configured error page could not be found."), lPath);
              Assert.IsFalse(lBody.Contains("private-content"), lPath);
            end;
          end;
        end;
      finally
        lServer.Stop;
        System.IO.Directory.Delete(lRoot, true);
      end;
    end;

    method ConfiguredErrorPagesHandleEveryErrorStatusInBothDebugModes;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lFactory := new ErrorPageTestFactory;
      var lServer := new WebServer(PageFactory := lFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          for each lDebug in [false, true] do begin
            lServer.DebugMode := lDebug;
            for lCode := 400 to 599 do begin
              using lResponse := lClient.GetAsync($"/status?code={lCode}").GetAwaiter.GetResult do begin
                Assert.AreEqual(Integer(lResponse.StatusCode), lCode);
                Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, $"handled:{lCode}");
              end;
            end;
            for each lPath in ["/throw", "/compile", "/missing"] do
              using lResponse := lClient.GetAsync(lPath).GetAwaiter.GetResult do begin
                var lCode := if lPath = "/missing" then 404 else 500;
                Assert.AreEqual(Integer(lResponse.StatusCode), lCode);
                Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, $"handled:{lCode}");
              end;
          end;
          lFactory.FailErrorPage := true;
          using lResponse := lClient.GetAsync("/throw").GetAwaiter.GetResult do begin
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
            Assert.IsTrue(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult.Contains("error page failed"));
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;

    method ApplicationErrorSignaturesAndRequestIsolation;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lFactory := new NotificationTestFactory;
      var lComposite := new WebCompositePageFactory(new WebApplicationLifetime);
      lComposite.AddFactory(lFactory);
      var lServer := new WebServer(PageFactory := lComposite);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          for each lLegacy in [false, true] do begin
            if lLegacy then begin
              lFactory := new NotificationTestFactory(Legacy := true);
              var lNext := new WebCompositePageFactory(new WebApplicationLifetime);
              lNext.AddFactory(lFactory);
              lServer.PageFactory := lNext;
            end;
            NotificationApplication.Errors.Clear;
            LegacyNotificationApplication.Calls := 0;
            using lResponse := lClient.GetAsync("/throw?original=yes").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 500);
              Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "notified:True");
            end;
            Assert.AreEqual(NotificationApplication.Errors.Count, 1);
            Assert.AreEqual(LegacyNotificationApplication.Calls, if lLegacy then 1 else 0);
            var lError := NotificationApplication.Errors["original=yes"];
            Assert.AreEqual(lError.Exception.Message, "original error");
            Assert.AreEqual(lError.RequestMethod, "GET");
            Assert.AreEqual(lError.PagePath, "/throw");
            Assert.AreEqual(lError.StatusCode, 500);
            Assert.IsTrue(lError.RequestUrl.EndsWith("/throw?original=yes"));
            Assert.AreEqual(length(lError.CompilationDiagnostics), 0);
            using lResponse := lClient.GetAsync("/status?code=500").GetAwaiter.GetResult do
              Assert.AreEqual(Integer(lResponse.StatusCode), 500);
            Assert.AreEqual(NotificationApplication.Errors.Count, 1);
          end;
          lFactory := new NotificationTestFactory;
          var lTyped := new WebCompositePageFactory(new WebApplicationLifetime);
          lTyped.AddFactory(lFactory);
          lServer.PageFactory := lTyped;
          using lResponse := lClient.GetAsync("/compile?compiler=yes").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
          var lCompiler := NotificationApplication.Errors["compiler=yes"];
          Assert.AreEqual(lCompiler.CompilationDiagnostics[0].Code, "E42");
          Assert.AreEqual(lCompiler.CompilationDiagnostics[0].Line, 13);
          (lCompiler.Exception as WebCompilationException).Diagnostics[0].Message := "changed";
          var lCopy := lCompiler.CompilationDiagnostics;
          lCopy[0] := nil;
          Assert.AreEqual(lCompiler.CompilationDiagnostics[0].Message, "broken page");
          var lRequests := new List<System.Threading.Tasks.Task<System.Net.Http.HttpResponseMessage>>;
          for i := 0 to 9 do
            lRequests.Add(lClient.GetAsync($"/throw?parallel={i}"));
          for each lRequest in lRequests do
            using lResponse := lRequest.GetAwaiter.GetResult do
              Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "notified:True");
          for i := 0 to 9 do
            Assert.IsTrue(NotificationApplication.Errors[$"parallel={i}"].RequestUrl.EndsWith($"/throw?parallel={i}"));
          // A notification failure still allows the custom page to run.
          using lResponse := lClient.GetAsync("/throw?fail=yes").GetAwaiter.GetResult do
            Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "notified:True");
          lFactory.BuiltIn := true;
          using lResponse := lClient.GetAsync("/throw?builtin=yes").GetAwaiter.GetResult do begin
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
            Assert.IsTrue(NotificationApplication.Errors.ContainsKey("builtin=yes"));
          end;
          lFactory.BuiltIn := false;
          using lResponse := lClient.GetAsync("/transfer?incoming=yes").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
          var lTransferred := NotificationApplication.Errors["transferred=yes"];
          Assert.AreEqual(lTransferred.PagePath, "/throw");
          Assert.IsTrue(lTransferred.RequestUrl.EndsWith("/transfer?incoming=yes"));
          // A failure in the error page must not recursively notify.
          var lCount := NotificationApplication.Errors.Count;
          lFactory.FailErrorPage := true;
          using lResponse := lClient.GetAsync("/throw?secondary=yes").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
          Assert.AreEqual(NotificationApplication.Errors.Count, lCount+1);
        end;
      finally
        lServer.Stop;
      end;
    end;

    method Custom404PreservesOriginalUrlAcrossRedirect;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new Redirect404TestFactory);
      lServer.Start(lPort);
      try
        using lHandler := new System.Net.Http.HttpClientHandler(AllowAutoRedirect := false) do
        using lClient := new System.Net.Http.HttpClient(lHandler) do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          var lPath := "/oxygene/whatsnew?ref=blogs.remobjects.com&value=a%2Bb%20c&next=https%3A%2F%2Fexample.com%2Fa%3Bx";
          using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, lPath) do begin
            lRequest.Headers.Host := "remobjects.com";
            lRequest.Headers.Add("X-Forwarded-Proto", "https");
            using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 301);
              var lLocation := lResponse.Headers.Location;
              Assert.AreEqual(lLocation.Host, "www.remobjects.com");
              Assert.AreEqual(lLocation.AbsolutePath, "/404.ashx");
              // A query value must escape the nested URL's scheme and slashes.
              Assert.IsTrue(lLocation.Query.ToLowerInvariant.Contains("https%3a%2f%2fremobjects.com%2f"));
              // Replay locally with the redirected public host; never contact the website.
              using lRedirect := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, lLocation.PathAndQuery) do begin
                lRedirect.Headers.Host := "www.remobjects.com";
                lRedirect.Headers.Add("X-Forwarded-Proto", "https");
                using lFinal := lClient.SendAsync(lRedirect).GetAwaiter.GetResult do begin
                  Assert.AreEqual(Integer(lFinal.StatusCode), 200);
                  Assert.AreEqual(lFinal.Content.ReadAsStringAsync.GetAwaiter.GetResult, "https://remobjects.com"+lPath);
                end;
              end;
            end;
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;

    method UrlEncodeUsesQueryValueEncoding;
    begin
      Assert.IsNil(HttpUtility.UrlEncode(nil));
      Assert.AreEqual(HttpUtility.UrlEncode(""), "");
      Assert.AreEqual(HttpUtility.UrlEncode("https://example.com/a b+c?x=1&y=2;#é"),
        "https%3A%2F%2Fexample.com%2Fa+b%2Bc%3Fx%3D1%26y%3D2%3B%23%C3%A9");
      Assert.AreEqual(HttpUtility.UrlDecode(HttpUtility.UrlEncode("https://example.com/a b+c?x=%2F&y=é")),
        "https://example.com/a b+c?x=%2F&y=é");
    end;

    method PublicRequestUrlsUseProxyAuthority;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new NotificationTestFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          // Host, forwarded proto, forwarded host, forwarded port, public origin, port.
          var lCases: array of array of String := [
            [$"localhost:{lPort}", "", "", "", $"http://localhost:{lPort}", lPort.ToString],
            ["staging.remobjects.com", "https", "", "", "https://staging.remobjects.com", "443"],
            ["staging.remobjects.com:9443", "https", "", "", "https://staging.remobjects.com:9443", "9443"],
            ["public.example", "", "", "", "http://public.example", "80"],
            ["internal:5002", "https", "public.example", "", "https://public.example", "443"],
            ["internal:5002", "HTTPS, http", "public.example:8443, internal:5002", "9443, 5002", "https://public.example:9443", "9443"],
            ["internal:5002", "https", "public.example:8443", "443", "https://public.example", "443"],
            ["public.example", "https", "https://invalid.example/path", "invalid", "https://public.example", "443"],
            ["public.example:8443", "https", "", "70000", "https://public.example:8443", "8443"],
            ["[::1]:8001", "", "", "", "http://[::1]:8001", "8001"],
            ["internal:5002", "https", "[2001:db8::1]:8443", "", "https://[2001:db8::1]:8443", "8443"]
          ];
          for each lCase in lCases do begin
            for each lPath in ["/url", "/throw"] do
              using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, lPath+"?proxy=yes") do begin
                lRequest.Headers.Host := lCase[0];
                if length(lCase[1]) > 0 then
                  lRequest.Headers.Add("X-Forwarded-Proto", lCase[1]);
                if length(lCase[2]) > 0 then
                  lRequest.Headers.Add("X-Forwarded-Host", lCase[2]);
                if length(lCase[3]) > 0 then
                  lRequest.Headers.Add("X-Forwarded-Port", lCase[3]);
                using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
                  if lPath = "/url" then begin
                    Assert.AreEqual(Integer(lResponse.StatusCode), 200);
                    Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult,
                      lCase[4]+"/url?proxy=yes|"+lCase[5], lCase[4]);
                  end
                  else begin
                    Assert.AreEqual(Integer(lResponse.StatusCode), 500);
                    Assert.AreEqual(NotificationApplication.Errors["proxy=yes"].RequestUrl,
                      lCase[4]+"/throw?proxy=yes", lCase[4]);
                  end;
                end;
              end;
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;

    method RequestHistoryCopiesCompilerDiagnostics;
    begin
      var lFailure := new WebCompilationException("Compilation failed");
      lFailure.AddDiagnostic("Error", "E100", "Original error", "Test.aspx", nil, 13, 4);
      var lRecord := new WebRequestError;
      lRecord.CaptureException(lFailure);
      lFailure.Diagnostics[0].Message := "Changed after request";
      lFailure.Diagnostics.RemoveAt(0);
      Assert.AreEqual(lRecord.Diagnostics.Count, 1);
      Assert.AreEqual(lRecord.Diagnostics[0].Message, "Original error");
      var lPlainFailure := new WebRequestError;
      lPlainFailure.CaptureException(new Exception("Compilation failed"));
      Assert.AreEqual(lPlainFailure.Diagnostics.Count, 0);
      Assert.IsTrue(lPlainFailure.ExceptionDetails.Contains("Compilation failed"));
    end;

    method DiagnosticsAndRequestHistoryOverHttp;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lSourceFile := System.IO.Path.GetTempFileName;
      var lSourceText := new StringBuilder;
      for i := 1 to 15 do
        lSourceText.AppendLine("source <line>");
      File.WriteText(lSourceFile, lSourceText.ToString);
      var lServer := new WebServer(PageFactory := new DiagnosticsFactory(SourceFileName := lSourceFile));
      var lStatus := new WebHostStatus(Generation := 2, ActiveGeneration := 1);
      var lBuild := new WebCompilationException("Compilation failed");
      lBuild.AddDiagnostic("Error", "E123", "broken <script>", "Bad.aspx", nil, 3, 4);
      lBuild.AddDiagnostic("Warning", "W123", "a warning", "Good.aspx", nil, 5, 6);
      lStatus.AddDiagnostics("Page", lBuild);
      lServer.HostStatus := lStatus;
      lServer.Start(lPort);
      try
        using lHandler := new System.Net.Http.HttpClientHandler(AllowAutoRedirect := false) do
        using lClient := new System.Net.Http.HttpClient(lHandler) do begin
          lClient.BaseAddress := new System.Uri($"http://127.0.0.1:{lPort}");
          var lJson := JsonObject.FromString(lClient.GetStringAsync("/__esp/diagnostics?format=json").GetAwaiter.GetResult);
          Assert.AreEqual((lJson["diagnostics"] as JsonArray).Count, 2);
          var lHtml := lClient.GetStringAsync("/__esp/diagnostics").GetAwaiter.GetResult;
          Assert.IsTrue(lHtml.Contains("broken &lt;script&gt;"));
          Assert.IsFalse(lHtml.Contains("broken <script>"));
          // Replacing current diagnostics must remove fixed errors, while retaining warnings.
          var lFixed := new WebHostStatus;
          lFixed.AddProjectDiagnostic("Warning", "remaining warning");
          lServer.HostStatus := lFixed;
          lJson := JsonObject.FromString(lClient.GetStringAsync("/__esp/diagnostics?format=json").GetAwaiter.GetResult);
          Assert.AreEqual((lJson["diagnostics"] as JsonArray).Count, 1);
          Assert.IsFalse(lJson.ToJsonString.Contains("E123"));

          for each lPath in ["/throw", "/explicit", "/compile"] do
            using lResponse := lClient.GetAsync(lPath+"?secret=do-not-log").GetAwaiter.GetResult do
              Assert.AreEqual(Integer(lResponse.StatusCode), if lPath = "/explicit" then 503 else 500, lPath);
          lServer.ErrorPaths[500] := "/custom";
          using lResponse := lClient.GetAsync("/throw").GetAwaiter.GetResult do
            Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "custom");
          lServer.RequireUpdateTrigger := true;
          lServer.PageFactory := nil;
          using lResponse := lClient.GetAsync("/unpublished").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 503);
          lServer.RequireUpdateTrigger := false;
          lServer.HostStarting := true;
          using lResponse := lClient.GetAsync("/building").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 503);
          lServer.HostFailure := new Exception("Build failed");
          using lResponse := lClient.GetAsync("/build-failed").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 500);
          lJson := JsonObject.FromString(lClient.GetStringAsync("/__esp/errors?format=json").GetAwaiter.GetResult);
          var lErrors := lJson["errors"] as JsonArray;
          Assert.AreEqual(lErrors.Count, 7, "Each failed request must be logged exactly once.");
          for each lPath in ["/unpublished", "/building"] do
            Assert.AreEqual(lErrors.FirstOrDefault(e -> e["path"]:StringValue = lPath)["message"].StringValue,
              "Requested before site was ready");
          Assert.AreEqual(lErrors.FirstOrDefault(e -> e["path"]:StringValue = "/explicit")["message"].StringValue, "HTTP 503");
          Assert.AreEqual(lErrors.FirstOrDefault(e -> e["path"]:StringValue = "/build-failed")["message"].StringValue, "Build failed");
          Assert.IsTrue(lClient.GetStringAsync("/__esp/errors").GetAwaiter.GetResult.Contains("Requested before site was ready"));
          Assert.IsFalse(lJson.ToJsonString.Contains("do-not-log"));
          Assert.IsTrue(lJson.ToJsonString.Contains("test exception"));
          Assert.IsTrue(lJson.ToJsonString.Contains("Compilation failed"));
          var lCompilation := lErrors.FirstOrDefault(e -> e["path"]:StringValue = "/compile");
          var lCompilationDiagnostics := lCompilation["diagnostics"] as JsonArray;
          Assert.AreEqual(lCompilationDiagnostics.Count, 2);
          Assert.AreEqual(lCompilationDiagnostics[0]["code"].StringValue, "E100");
          var lErrorHtml := lClient.GetStringAsync("/__esp/errors").GetAwaiter.GetResult;
          Assert.IsTrue(lErrorHtml.Contains("Test.aspx:13:4 Error E100: Unknown identifier &lt;missing&gt;"));
          Assert.IsTrue(lErrorHtml.Contains("Test.aspx:14:2 Error E101: Second compiler error"));
          Assert.IsTrue(lClient.GetStringAsync("/__esp/errors").GetAwaiter.GetResult.Contains("/unpublished"));
          // Diagnostics remain reachable before publication and outside debug mode.
          lServer.AuthorizationToken := "test-token";
          for each lPage in ["diagnostics", "errors"] do begin
            using lResponse := lClient.GetAsync("/__esp/"+lPage).GetAwaiter.GetResult do
              Assert.AreEqual(Integer(lResponse.StatusCode), 401);
            using lResponse := lClient.GetAsync("/__esp/"+lPage+"?token=wrong").GetAwaiter.GetResult do
              Assert.AreEqual(Integer(lResponse.StatusCode), 401);
            using lResponse := lClient.GetAsync("/__esp/"+lPage+"?token=test-token&format=json").GetAwaiter.GetResult do begin
              Assert.AreEqual(Integer(lResponse.StatusCode), 200);
              Assert.IsTrue(lResponse.Content.Headers.ContentType.ToString.Contains("application/json"));
              Assert.IsFalse(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult.Contains("test-token"));
            end;
          end;
          lServer.DebugMode := true;
          lJson := JsonObject.FromString(lClient.GetStringAsync("/__esp/errors?format=json&token=test-token").GetAwaiter.GetResult);
          lCompilation := (lJson["errors"] as JsonArray).FirstOrDefault(e -> e["path"]:StringValue = "/compile");
          var lSourceUrl := lCompilation["diagnostics"][0]["sourceUrl"].StringValue;
          Assert.IsTrue(lSourceUrl.StartsWith("/__esp/source/"));
          using lResponse := lClient.GetAsync(lSourceUrl).GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 401);
          var lSourceHtml := lClient.GetStringAsync(lSourceUrl+"?token=test-token").GetAwaiter.GetResult;
          Assert.IsTrue(lSourceHtml.Contains("source &lt;line&gt;"));
          lErrorHtml := lClient.GetStringAsync("/__esp/errors?token=test-token").GetAwaiter.GetResult;
          Assert.IsTrue(lErrorHtml.Contains('?token=test-token">&lt;unknown&gt;/Test.aspx:13:4</a> Error E100: Unknown identifier &lt;missing&gt;'));
          lClient.DefaultRequestHeaders.Authorization := new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", "test-token");
          using lResponse := lClient.GetAsync("/__esp/errors?format=json").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 200);
          using lRequest := new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Head, "/__esp/errors") do
          using lResponse := lClient.SendAsync(lRequest).GetAwaiter.GetResult do begin
            Assert.AreEqual(Integer(lResponse.StatusCode), 200);
            Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult, "");
          end;
          using lResponse := lClient.PostAsync("/__esp/errors", new System.Net.Http.StringContent("")).GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 405);
        end;
      finally
        lServer.Stop;
        File.Delete(lSourceFile);
      end;
    end;

  end;

  Redirect404TestFactory = class(WebPageFactory)
  public
    method CreateApplication: nullable WebApplication; override; empty;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/404.ashx" then
        result := new Redirect404TestHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      if aCode = 404 then
        result := new WebErrorPage("/404.ashx", false, true, false);
    end;
  end;

  Redirect404TestHandler = class(IHttpHandler)
  public
    method ProcessRequest(aContext: WebContext);
    begin
      if aContext.Request.ServerVariables["HTTP_HOST"] = "remobjects.com" then
        aContext.Response.RedirectPermanent("https://www.remobjects.com"+
          aContext.Request.ServerVariables["PATH_INFO"]+"?"+aContext.Request.QueryString.ToString);
      var lPayload := HttpUtility.UrlDecode(aContext.Request.QueryString.ToString);
      var lOriginal := Url.UrlWithString(lPayload.Substring(lPayload.IndexOf(";")+1));
      aContext.Response.Write(lOriginal.ToAbsoluteString);
    end;
  end;

  ErrorPageTestFactory = class(WebPageFactory)
  public

    property FailErrorPage: Boolean;

    method CreateApplication: nullable WebApplication; override; empty;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/compile" then
        raise new WebCompilationException("Compilation failed");
      if aPath in ["/status", "/throw", "/custom"] then
        result := new ErrorPageTestHandler(FailErrorPage := FailErrorPage);
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      if (aCode ≥ 400) and (aCode ≤ 599) then
        result := new WebErrorPage("/custom", false, true, false);
    end;

  end;

  StaticErrorTestFactory = class(ErrorPageTestFactory)
  public

    property Root: nullable String;
    property ErrorFile: not nullable String := "/503.html";
    property PhysicalRootFolder: nullable String read Root; override;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      result := new WebErrorPage(ErrorFile, false, false, false, true);
    end;

  end;

  ErrorPageTestHandler = class(IHttpHandler)
  public

    property FailErrorPage: Boolean;

    method ProcessRequest(aContext: WebContext);
    begin
      case aContext.Request.Url.Path of
        "/throw": raise new Exception("original error");
        "/status": aContext.Response.StatusCode := Convert.ToInt32(aContext.Request.QueryString["code"]);
        "/custom": begin
          if FailErrorPage then
            raise new Exception("error page failed");
          aContext.Response.Write($"handled:{aContext.Response.StatusCode}");
        end;
      end;
    end;

  end;

  DiagnosticsFactory = class(WebPageFactory)
  public

    property SourceFileName: nullable String;

    method CreateApplication: nullable WebApplication; override; empty;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/compile" then begin
        var lFailure := new WebCompilationException("Compilation failed");
        lFailure.AddDiagnostic("Error", "E100", "Unknown identifier <missing>", "Test.aspx", SourceFileName, 13, 4);
        lFailure.AddDiagnostic("Error", "E101", "Second compiler error", "Test.aspx", SourceFileName, 14, 2);
        raise new System.Reflection.TargetInvocationException(lFailure);
      end;
      if aPath in ["/throw", "/explicit", "/custom"] then
        result := new DiagnosticsHandler;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;

  end;

  DiagnosticsHandler = class(IHttpHandler)
  public

    method ProcessRequest(aContext: WebContext);
    begin
      case aContext.Request.Url.Path of
        "/throw": raise new Exception("test exception");
        "/explicit": aContext.Response.StatusCode := 503;
        "/custom": aContext.Response.Write("custom");
      end;
    end;

  end;

  NotificationTestFactory = class(ErrorPageTestFactory)
  public

    property Legacy: Boolean;
    property BuiltIn: Boolean;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      if not BuiltIn then
        result := inherited FindErrorPage(aCode);
    end;

    method CreateApplication: nullable WebApplication; override;
    begin
      result := if Legacy then new LegacyNotificationApplication else new NotificationApplication;
    end;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/compile" then begin
        var lError := new WebCompilationException("Compilation failed");
        lError.AddDiagnostic("Error", "E42", "broken page", "Test.aspx", nil, 13, 4);
        raise new System.Reflection.TargetInvocationException(lError);
      end;
      if aPath = "/url" then
        exit new NotificationUrlPage;
      if aPath = "/transfer" then
        exit new NotificationTransferPage;
      if (aPath = "/custom") and not FailErrorPage then
        exit new NotificationErrorPage;
      result := inherited FindClassForPath(aPath);
    end;

  end;

  NotificationUrlPage = class(IHttpHandler)
  public

    method ProcessRequest(aContext: WebContext);
    begin
      aContext.Response.Write(aContext.Request.Url.ToAbsoluteString+"|"+aContext.Request.ServerVariables["SERVER_PORT"]);
    end;

  end;

  NotificationTransferPage = class(IHttpHandler)
  public

    method ProcessRequest(aContext: WebContext);
    begin
      aContext.Server.Transfer("/throw?transferred=yes");
    end;

  end;

  NotificationErrorPage = class(IHttpHandler)
  public

    method ProcessRequest(aContext: WebContext);
    begin
      var lQuery := HttpUtility.UrlDecode(aContext.Request.Url.QueryString);
      // The notification must have run before custom error page execution.
      aContext.Response.Write("notified:"+NotificationApplication.Errors.ContainsKey(lQuery.Substring(lQuery.IndexOf("?")+1)).ToString);
    end;

  end;

  LegacyNotificationApplication = class(WebApplication)
  public

    class property Calls: Integer;

  protected

    method Application_Error(aSender: Object; aArgs: EventArgs);
    begin
      inc(Calls);
      Assert.IsTrue(aSender = self);
      Assert.IsTrue(WebContext.Current = Context);
      NotificationApplication.Errors[Request.QueryString.ToString] := new WebErrorContext(Server.GetLastError,
        Request.Url.ToAbsoluteString, "GET", Request.Path);
    end;

  end;

  NotificationApplication = class(LegacyNotificationApplication)
  public

    class property Errors := new System.Collections.Concurrent.ConcurrentDictionary<String, WebErrorContext>; readonly;

  protected

    method Application_Error(aError: WebErrorContext);
    begin
      Assert.IsTrue(Server.GetLastError = aError.Exception);
      Assert.IsTrue(WebContext.Current = Context);
      Errors[Request.QueryString.ToString] := aError;
      if Request.QueryString["fail"] = "yes" then
        raise new Exception("notification failed");
    end;

  end;

end.
