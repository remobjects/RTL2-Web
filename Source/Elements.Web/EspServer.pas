namespace RemObjects.Elements.Web;

uses
  {$IF ECHOES}
  System.Net,
  {$ENDIF}
  RemObjects.Elements.RTL.Reflection;

type
  WebServer = public partial class
  public

    method Start(aPort: Integer := 8001);
    begin
      if not assigned(PageFactory) and not RequireUpdateTrigger then
        fStartupStaticFiles := new WebStaticFiles(PhysicalRootFolder, nil);
      fServer := new HttpServer();
      fServer.ServerName := "RemObjectts Elements ESP HTTP Server";
      fServer.Port := aPort;
      fServer.KeepAlive := true;
      fServer.CloseConnectionsOnShutdown := true;
      fServer.HttpRequest += HandleEspRequest;
      fServer.Open();
    end;

    method HandleEspRequest(aSender: Object; aEventArgs: HttpRequestEventArgs);
    begin
      var lFactory: nullable WebPageFactory;
      locking fFactoryMonitor do begin
        lFactory := fPageFactory;
        lFactory:Acquire;
      end;
      var lFailure := new WebRequestError;
      locking fDiagnosticMonitor do
        lFailure.Generation := coalesce(fHostStatus:ActiveGeneration, 0);
      try
        HandleEspRequestWithFactory(aSender, aEventArgs, lFactory, nil, nil, 0, lFailure);
      finally
        try
          RecordRequestError(aEventArgs, lFactory, lFailure);
        finally
          lFactory:Release;
        end;
      end;
    end;

    method HandleEspRequestWithFactory(aSender: Object; aEventArgs: HttpRequestEventArgs; aFactory: nullable WebPageFactory;
                                      aErrorPath: nullable String := nil; aErrorQuery: nullable String := nil;
                                      aErrorCode: Integer := 0; aFailure: nullable WebRequestError := nil); private;
    begin
      var lRequestPath := coalesce(aErrorPath, aEventArgs.Request.Path);
      var lContext: nullable WebContext;
      try
        // Reject null bytes before routing or filesystem access, without invoking site error handlers.
        if HttpUtility.UrlDecode(lRequestPath).Contains(#0) then begin
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/plain; charset=utf-8");
          aEventArgs.Response.ContentString := if caseInsensitive(aEventArgs.Request.Header.RequestType) = "head" then "" else "Not Found";
          exit;
        end;
        {$IF ECHOES}
        if (lRequestPath = "/__esp/logo.png") and (caseInsensitive(aEventArgs.Request.Header.RequestType) in ["get", "head"]) then begin
          var lLogo := (typeOf(WebServer) as System.Type).Assembly.GetManifestResourceStream("RemObjects.Elements.Web.Logo.png");
          if assigned(lLogo) then begin
            aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.OK;
            aEventArgs.Response.Header.SetHeaderValue("Content-Type", "image/png");
            aEventArgs.Response.Header.SetHeaderValue("Cache-Control", "public, max-age=86400");
            aEventArgs.Response.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
            aEventArgs.Response.ContentStream := new WrappedPlatformStream(lLogo);
            exit;
          end;
        end;
        {$ENDIF}
        if not assigned(aErrorPath) and HandleManagementRequest(aEventArgs, aFailure) then
          exit;
        if ((lRequestPath = "/__esp/status") and not RequireUpdateTrigger) or lRequestPath.StartsWith("/__esp/source/") then begin
          var lSourceHtml: nullable String;
          if DebugMode and (caseInsensitive(aEventArgs.Request.Header.RequestType) in ["get", "head"]) then
            lSourceHtml := if lRequestPath = "/__esp/status" then RenderHostStatus else RenderDiagnosticSource(lRequestPath.Substring(length("/__esp/source/")));
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
          aEventArgs.Response.Header.SetHeaderValue("Cache-Control", "no-store");
          aEventArgs.Response.Header.SetHeaderValue("Referrer-Policy", "no-referrer");
          aEventArgs.Response.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
          aEventArgs.Response.HttpCode := if assigned(lSourceHtml) then RemObjects.InternetPack.Http.HttpStatusCode.OK else RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
          aEventArgs.Response.ContentString := coalesce(lSourceHtml, "Diagnostic page unavailable.");
          exit;
        end;
        if lRequestPath.StartsWith("/__esp/") then begin
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
          aEventArgs.Response.ContentString := "Management endpoint unavailable.";
          exit;
        end;
        if RequireUpdateTrigger and not assigned(aFactory) then begin
          aFailure:Message := "Requested before site was ready";
          if TryServeStartupError(aEventArgs, 503) then
            exit;
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.ServiceUnavailable;
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
          aEventArgs.Response.Header.SetHeaderValue("Cache-Control", "no-store");
          aEventArgs.Response.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
          aEventArgs.Response.ContentString := RenderErrorPage(503, "Website not published yet", lRequestPath,
            "This website is waiting for its first publication. Please check back soon.");
          exit;
        end;
        if HostStarting and not assigned(aFactory) then begin
          if TryServeStaticFile(lRequestPath, aEventArgs, nil) then
            exit;
          var lFailure := HostFailure;
          var lCode := if assigned(lFailure) then 500 else 503;
          if assigned(lFailure) then
            aFailure:CaptureException(lFailure)
          else
            aFailure:Message := "Requested before site was ready";
          if TryServeStartupError(aEventArgs, lCode) then
            exit;
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(lCode);
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
          aEventArgs.Response.Header.SetHeaderValue("Cache-Control", "no-store");
          aEventArgs.Response.ContentString := RenderErrorPage(lCode,
            if assigned(lFailure) then "Compilation Error" else "Website is building", lRequestPath,
            if assigned(lFailure) then "The website could not be built." else "Waiting for the first website generation.",
            if DebugMode then lFailure else nil);
          exit;
        end;
        var lRequestQuery := if assigned(aErrorPath) then aErrorQuery else aEventArgs.Request.QueryString.ToString;
        var lTransferCount := 0;

        if not assigned(aErrorPath) and (caseInsensitive(aEventArgs.Request.Header.RequestType) in ["get", "head"]) then begin
          var lRedirect := aFactory:FindRedirectForPath(lRequestPath);
          if assigned(lRedirect) and (lRedirect ≠ lRequestPath) then begin
            if length(lRequestQuery) > 0 then
              lRedirect := lRedirect+"?"+lRequestQuery;

            Log($"{lRequestPath} redirected to {lRedirect}");
            aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.MovedPermanently;
            aEventArgs.Response.Header.SetHeaderValue("Location", lRedirect);
            aEventArgs.Response.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a href=""{lRedirect}"">here</a>.</p></body>";
            exit;
          end;
        end;

        while true do begin
          lContext := CreateRequestContext(aEventArgs, lRequestPath, lRequestQuery, aFactory);
          var lPreviousContext := WebContext.Current;
          var lObject: nullable Object;
          WebContext.Current := lContext;
          try
            lContext.Lifetime.EnsureStarted(aFactory, lContext);
            lObject := aFactory:DoFindClassForPath(lRequestPath);
          finally
            WebContext.Current := lPreviousContext;
          end;
          if assigned(lObject) then begin

            //Log($"{lRequestPath} served via {lObject}");
            var lTransferPath: nullable String := nil;
            WebContext.Current := lContext;
            try

              try

                if lObject is Page then begin
                  var lPage := lObject as Page;
                  lPage.Context := lContext;
                  lContext.Request.Page := lPage;
                  lPage.Initialize(new EventArgs);
                  lPage.OnLoad(new EventArgs);
                  lPage.RenderControl(nil);
                  lPage.OnUnLoad(new EventArgs);
                end
                else if lObject is IHttpHandler then begin
                  (lObject as IHttpHandler).ProcessRequest(lContext)
                end
                else begin
                  aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
                  aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.InternalServerError;
                  aEventArgs.Response.ContentString := RenderErrorPage(
                    Integer(aEventArgs.Response.HttpCode),
                    "Internal Server Error",
                    lRequestPath,
                    $"Unexpected or unsupported class {typeOf(lObject)}.");
                end;

              except
                on E: TransferToNewPathException do begin
                  inc(lTransferCount);
                  if lTransferCount > 8 then
                    raise new Exception("Too many Server.Transfer requests.");
                  lTransferPath := E.Path;
                end;
                on E: CleanlyEndResponseException do
                  begin
                  end;
                {$IF ECHOES}
                on E: System.Reflection.TargetInvocationException do begin
                  if E.InnerException is TransferToNewPathException then begin
                    inc(lTransferCount);
                    if lTransferCount > 8 then
                      raise new Exception("Too many Server.Transfer requests.");
                    lTransferPath := (E.InnerException as TransferToNewPathException).Path;
                  end
                  else if E.InnerException is CleanlyEndResponseException then begin
                  end
                  else begin
                    raise;
                  end;
                end;
                {$ENDIF}
              end;

              // Redirect and End finish the response by throwing. Finalize their
              // cookies and body just like a normally completed page or handler.
              if not assigned(lTransferPath) then
                lContext.Response.Complete;

            finally
              WebContext.Current := lPreviousContext;
            end;

            if assigned(lTransferPath) then begin
              var lQuestionMark := lTransferPath.IndexOf("?");
              if lQuestionMark ≥ 0 then begin
                lRequestPath := lTransferPath.Substring(0, lQuestionMark);
                lRequestQuery := lTransferPath.Substring(lQuestionMark+1);
              end
              else begin
                lRequestPath := lTransferPath;
                lRequestQuery := "";
              end;
              continue;
            end;

            break;

          end
          else begin
            var lRedirect := aFactory:FindRedirectForPath(lRequestPath);
            if assigned(lRedirect) then begin

              Log($"{lRequestPath} redirected to {lRedirect}");
              aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.MovedPermanently;
              aEventArgs.Response.Header.SetHeaderValue("Location", lRedirect);
              aEventArgs.Response.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a hrwf=""{lRedirect}"">here</a>.</p></body>";

            end
            else begin
              var lResourceName := aFactory:FindResourcesForPath(lRequestPath);
              if assigned(lResourceName) then begin

                if defined("ECHOES") then begin
                  var lStream := aFactory.OpenResource(lRequestPath, true);
                  if assigned(lStream) then begin
                    //Log($"{lRequestPath} served as resource {lResourceName}");
                    ServeStaticContent(lRequestPath, lStream, aEventArgs, aFactory);
                  end
                  else begin
                    Log($"{lRequestPath} resource 404");
                    aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
                    //aEventArgs.Response.Header["Content-Type"] := "text/html";
                    aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
                    aEventArgs.Response.ContentString := RenderErrorPage(404, "Resource Not Found", lRequestPath, "The embedded resource could not be found.");
                  end;
                end
                else begin
                  raise new NotImplementedException("Serving static resources is not yet implemented for this platform.");
                end;

              end
              else begin

                if not TryServeStaticFile(lRequestPath, aEventArgs, aFactory) then begin
                  Log($"{lRequestPath} unknown path 404");
                  aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
                  var lCode := if assigned(aErrorPath) then aErrorCode else 404;
                  aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(lCode);
                  aEventArgs.Response.ContentString := RenderErrorPage(lCode, if lCode = 404 then "Page Not Found" else "Request Failed", lRequestPath,
                    if assigned(aErrorPath) then "The configured error page could not be found." else "No page or static resource matches this URL.");
                end;

              end;
            end;
          end;
          break;
        end;

        if not assigned(aErrorPath) and (Integer(aEventArgs.Response.HttpCode) >= 400) and
           not coalesce(lContext:Response:TrySkipIisCustomErrors, false) then
          RunError(aEventArgs, Integer(aEventArgs.Response.HttpCode), aFactory, aFailure);

      except
        on E: Exception do begin
          if RequireUpdateTrigger then begin
            try
              PublicationError(self, new WebPublicationErrorEventArgs(Revision := aFactory:PublicationRevision,
                Path := aEventArgs.Request.Path, Message := E.Message));
            except
              on lReportingError: Exception do begin
                // Reporting must never replace the original request failure.
              end;
            end;
          end;
          aFailure:CaptureException(E);
          if not assigned(aErrorPath) then
            NotifyApplicationError(aEventArgs, aFactory, lContext, lRequestPath, E);
          Log($"Unhandled ESP request exception for '{aEventArgs.Request.Path}': {E}");
          if not assigned(aErrorPath) then begin
            try
              if RunError(aEventArgs, 500, aFactory, aFailure) then
                exit;
            except
              on lHandlerException: Exception do
                Log($"Custom ESP error handler failed: {lHandlerException}");
            end;
          end;
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
          //aEventArgs.Response.Header["Content-Type"] := "text/html";
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.InternalServerError;
          try
            aEventArgs.Response.ContentString := RenderErrorPage(
              Integer(aEventArgs.Response.HttpCode),
              "Internal Server Error",
              aEventArgs.Request.Path,
              nil,
              E);
          except
            on lRenderException: Exception do begin
              Log($"Could not render the ESP error page: {lRenderException}");
              aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/plain; charset=utf-8");
              aEventArgs.Response.ContentString := $"500 Internal Server Error\n\n{E}";
            end;
          end;
        end;
      end;
    end;

    method RunError(e: HttpRequestEventArgs; aCode: Integer): Boolean;
    begin
      var lFactory: nullable WebPageFactory;
      locking fFactoryMonitor do begin
        lFactory := fPageFactory;
        lFactory:Acquire;
      end;
      try
        result := RunError(e, aCode, lFactory);
      finally
        lFactory:Release;
      end;
    end;

    method RunError(e: HttpRequestEventArgs; aCode: Integer; aFactory: nullable WebPageFactory): Boolean;
    begin
      result := RunError(e, aCode, aFactory, nil);
    end;

    method RunError(e: HttpRequestEventArgs; aCode: Integer; aFactory: nullable WebPageFactory; aFailure: nullable WebRequestError): Boolean; private;
    begin
      aFailure:CaptureStatus(aCode);
      var lRule := aFactory:FindErrorPage(aCode);
      if assigned(ErrorPaths[aCode]) then
        lRule := new WebErrorPage(ErrorPaths[aCode], false, false, false);
      if not assigned(lRule) then
        exit false;
      var lOriginal := CreateRequestContext(e, e.Request.Path, e.Request.QueryString.ToString, aFactory);
      if lRule.RemoteOnly and (lOriginal.Request.ServerVariables["REMOTE_ADDR"] in ["127.0.0.1", "::1"]) then
        exit false;
      if lRule.StaticFile then begin
        var lContent := ReadStaticErrorFile(lRule.Path, coalesce(aFactory:PhysicalRootFolder, PhysicalRootFolder),
          coalesce(aFactory:PhysicalBinFolder, PhysicalBinFolder));
        if assigned(lContent) then
          ServeStaticError(e, aCode, lContent)
        else begin
          e.Response.Header := new HttpHeaders;
          e.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(aCode);
          e.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
          e.Response.Header.SetHeaderValue("Cache-Control", "no-store");
          e.Response.ContentString := if caseInsensitive(e.Request.Header.RequestType) = "head" then ""
            else RenderErrorPage(aCode, "Request Failed", e.Request.Path, "The configured error page could not be found.");
        end;
        exit true;
      end;
      var lPath := lRule.Path;
      if lPath.StartsWith("~/") then
        lPath := lPath.Substring(1);
      var lQuery := if lRule.IisQuery then HttpUtility.UrlEncode($"{aCode};{lOriginal.Request.Url.ToAbsoluteString}")
                    else "aspxerrorpath="+HttpUtility.UrlEncode(e.Request.Path);
      if lRule.Redirect then begin
        e.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.Found;
        e.Response.Header.SetHeaderValue("Location", lPath+(if lPath.Contains("?") then "&" else "?")+lQuery);
        e.Response.ContentString := "";
        exit true;
      end;
      // Execute only site-local routes, and never dispatch errors recursively.
      if lPath.Contains(":") or lPath.StartsWith("//") then
        exit false;
      if not lPath.StartsWith("/") then
        lPath := "/"+lPath;
      if lPath.StartsWith("/__esp/") then
        exit false;
      var lQuestionMark := lPath.IndexOf("?");
      if lQuestionMark >= 0 then begin
        lQuery := lPath.Substring(lQuestionMark+1)+"&"+lQuery;
        lPath := lPath.Substring(0, lQuestionMark);
      end;
      e.Response.ContentStream := new MemoryStream;
      e.Response.Header := new HttpHeaders;
      e.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(aCode);
      HandleEspRequestWithFactory(self, e, aFactory, lPath, lQuery, aCode, aFailure);
      result := true;
    end;

    // Called by the host before compilation, using only an accepted publication in trigger mode.
    method LoadStaticErrorPages(aRoot: not nullable String);
    begin
      var lPages := new Dictionary<Integer, WebStaticErrorContent>;
      try
        var lConfig := Path.Combine(aRoot, "Web.config");
        if lConfig.FileExists then begin
          var lRules := new Dictionary<Integer, String>;
          var lXml := XmlDocument.FromFile(lConfig);
          var lBinFolder := PhysicalBinFolder;
          if length(lBinFolder) = 0 then
            for each lSection in lXml.Root.ElementsWithName("esp.projectSettings") do
              for each lSetting in lSection.Elements do
                if caseInsensitive(lSetting.LocalName) = "BinFolder" then begin
                  lBinFolder := lSetting.Value:ToPlatformPathFromWindowsPath;
                  if (length(lBinFolder) > 0) and not lBinFolder.IsAbsolutePath then
                    lBinFolder := Path.Combine(aRoot, lBinFolder);
                end;
          for each w in lXml.Root.ElementsWithName("system.webServer") do
            for each c in w.ElementsWithName("httpErrors") do begin
              if caseInsensitive(c.Attribute["errorMode"]:Value) = "Detailed" then
                continue;
              for each e in c.Elements do begin
                if e.LocalName = "clear" then begin
                  lRules.RemoveAll;
                  continue;
                end;
                var lCode := Convert.TryToInt32(e.Attribute["statusCode"]:Value);
                if not assigned(lCode) then
                  continue;
                if e.LocalName = "remove" then
                  lRules[lCode] := nil
                else if e.LocalName = "error" then begin
                  var lMode := e.Attribute["responseMode"]:Value;
                  if caseInsensitive(lMode) = "File" then
                    lRules[lCode] := e.Attribute["path"]:Value
                  else if caseInsensitive(lMode) in ["ExecuteURL", "Redirect"] then
                    lRules[lCode] := nil;
                end;
              end;
            end;
          for each lCode in lRules.Keys do
            lPages[lCode] := ReadStaticErrorFile(lRules[lCode], aRoot, lBinFolder);
        end;
      except
        on E: Exception do
          Log("Could not load static ESP error pages: "+E.Message);
      end;
      // Publish complete, immutable contents; requests never parse config or retain a retired root.
      locking fStaticErrorMonitor do
        fStartupErrorPages := lPages;
    end;

    method TryServeStartupError(aEvent: not nullable HttpRequestEventArgs; aCode: Integer): Boolean; private;
    begin
      var lContent: nullable WebStaticErrorContent;
      locking fStaticErrorMonitor do
        lContent := fStartupErrorPages[aCode];
      if not assigned(lContent) then
        exit;
      ServeStaticError(aEvent, aCode, lContent);
      result := true;
    end;

    method ReadStaticErrorFile(aPath: not nullable String; aRoot: nullable String; aBinFolder: nullable String): nullable WebStaticErrorContent; private;
    begin
      try
        aPath := HttpUtility.UrlDecode(aPath).Replace("\", "/");
        if aPath.StartsWith("~/") then
          aPath := aPath.Substring(1);
        if aPath.Contains(":") or aPath.Contains("?") or aPath.Contains("#") or aPath.StartsWith("//") or aPath.StartsWith("/__esp/") then
          exit;
        var lFileName := ResolvePublicStaticFile(aPath, aRoot, aBinFolder);
        if not assigned(lFileName) then
          exit;
        {$IF ECHOES}
        // Reject links at every component, including directories, before reading file contents.
        var lCheck := Path.GetFullPath(lFileName);
        var lRoot := Path.GetFullPath(aRoot as not nullable).TrimEnd(Path.DirectorySeparatorChar);
        if not IsFileInFolder(lCheck, lRoot) then
          exit;
        loop begin
          if (System.IO.File.GetAttributes(lCheck) and System.IO.FileAttributes.ReparsePoint) ≠ 0 then
            exit;
          if lCheck = lRoot then
            break;
          var lParent := Path.GetParentDirectory(lCheck);
          if (length(lParent) = 0) or (lParent = lCheck) then
            exit;
          lCheck := lParent;
        end;
        {$ELSE}
        // Fail closed on backends without a link-safe filesystem implementation.
        exit;
        {$ENDIF}
        result := new WebStaticErrorContent(File.ReadBytes(lFileName), ContentTypeForFileName(lFileName));
      except
        on E: Exception do begin
          // Missing or unreadable placeholders must not replace the original failure.
        end;
      end;
    end;

    method ServeStaticError(aEvent: not nullable HttpRequestEventArgs; aCode: Integer; aContent: not nullable WebStaticErrorContent); private;
    begin
      aEvent.Response.Header := new HttpHeaders;
      aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(aCode);
      aEvent.Response.Header.SetHeaderValue("Content-Type", aContent.ContentType);
      aEvent.Response.Header.SetHeaderValue("Cache-Control", "no-store");
      aEvent.Response.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
      aEvent.Response.ContentStream := if caseInsensitive(aEvent.Request.Header.RequestType) = "head" then new MemoryStream else new MemoryStream(aContent.Body);
    end;

    field fStaticErrorMonitor: Monitor := new Monitor; private;
    field fStartupErrorPages := new Dictionary<Integer, WebStaticErrorContent>; private;

    method RenderException(aException: Exception): String;
    begin
      var lCompilation := FindCompilationFailure(aException);
      if assigned(lCompilation) then
        exit RenderCompilationErrors(lCompilation);
      var lException := aException;
      var lIndex := 0;
      var lResult := new StringBuilder;

      while assigned(lException) do begin
        var lLabel := if lIndex = 0 then "Exception" else "Caused by";
        lResult.Append(##"""
          <section class="exception">
            <div class="exception-label">{{lLabel}}</div>
            <h2>{{HtmlLandingPage.EscapeHtml(lException.Message)}}</h2>
            <div class="exception-type"><code>{{HtmlLandingPage.EscapeHtml(typeOf(lException).Name)}}</code></div>
          </section>
          """);

        {$IF ECHOES}
        lException := lException.InnerException;
        {$ELSE}
        lException := nil;
        {$ENDIF}
        inc(lIndex);
      end;

      {$IF ECHOES}
      if aException.CallStack.Any then
        lResult.Append(##"""
          <details open>
            <summary>Stack trace</summary>
            <div class="stack-trace">{{RenderStackTrace(aException.CallStack)}}</div>
          </details>
          """);
      {$ENDIF}

      result := lResult.ToString;
    end;

    method Stop;
    begin
      fServer.Close();
      PageFactory := nil;
    end;

    method OpenFile(aVirtualPath: not nullable String; aFactory: nullable WebPageFactory := nil): nullable Stream; assembly;
    begin
      var lPath := aVirtualPath.Replace("\", "/");
      if lPath.StartsWith("~/") then
        lPath := lPath.Substring(1);
      if not lPath.StartsWith("/") then
        lPath := "/"+lPath;

      var lFactory := coalesce(aFactory, PageFactory);
      var lRoot := coalesce(lFactory:PhysicalRootFolder, PhysicalRootFolder);
      if length(lRoot) > 0 then begin
        var lFileName := lRoot as not nullable;
        for each lPart in lPath.Split("/") do begin
          if length(lPart) = 0 then
            continue;
          if (lPart = ".") or (lPart = "..") then
            exit;
          lFileName := Path.Combine(lFileName, lPart);
        end;
        if lFileName.FileExists then
          exit LeaseFile(lFileName, lFactory);
      end;

      result := coalesce(aFactory, PageFactory):OpenResource(lPath, false);
    end;

    property PageFactory: WebPageFactory read locking fFactoryMonitor do fPageFactory write SetPageFactory;
    property PhysicalRootFolder: nullable String;
    property PhysicalBinFolder: nullable String;
    property DebugMode: Boolean;
    property ShowCompilerErrorSource: Boolean;
    property HostStatus: nullable WebHostStatus read locking fDiagnosticMonitor do fHostStatus write SetHostStatus;
    property HostStarting: Boolean;
    property HostFailure: nullable Exception read locking fDiagnosticMonitor do fHostFailure write SetHostFailure;

    method SetHostFailure(aValue: nullable Exception); private;
    begin
      locking fDiagnosticMonitor do
        fHostFailure := aValue;
    end;
    property ErrorPaths := new Dictionary<Integer,String>;

    property Port: Integer read fServer.Port;

    // Hosts register their captured/generated roots explicitly. Never infer
    // ownership from filenames or from arbitrary temporary-directory names.
    method RegisterDiagnosticSourceFolder(aFolder: not nullable String; aDisplayFolder: not nullable String);
    begin
      locking fDiagnosticMonitor do
        fDiagnosticFolders[aFolder.Replace("\", "/").TrimEnd('/')+"/"] := aDisplayFolder.TrimEnd('/')+"/";
    end;

    method RenderDiagnosticSource(aToken: not nullable String): nullable String;
    begin
      if not DebugMode then
        exit;
      var lSource: nullable WebCompilerDiagnostic;
      locking fDiagnosticMonitor do
        lSource := fDiagnosticSources[aToken];
      if not assigned(lSource) then
        exit;
      var lLines := RenderSourceLines(lSource, 20);
      if length(lLines) = 0 then
        exit;
      var lTitle := coalesce(DiagnosticDisplayPath(lSource.FileName), "Source")+$":{lSource.Line}";
      result := HtmlLandingPage.RenderCardPage(lTitle, ##"""
        <style>
          h1 { overflow-wrap: anywhere; }
          pre { overflow: auto; padding: 0.75rem 0; background: #111827; color: #e5e7eb; font: 0.85rem/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; border-radius: 8px; }
          .source-line { display: block; padding-right: 1rem; min-width: max-content; }
          .line-number { display: inline-block; width: 4rem; padding-right: 1rem; text-align: right; color: #94a3b8; user-select: none; }
          .source-error { background: #7f1d1d; }
        </style>
        <h1>{{HtmlLandingPage.EscapeHtml(lTitle)}}</h1>
        <p>Source context · Debug mode</p>
        <pre>{{lLines}}</pre>
        """);
    end;

    method RenderHostStatus: nullable String;
    begin
      if not DebugMode then
        exit;
      result := RenderHostStatusPage(nil);
    end;

    method RenderHostStatusPage(aToken: nullable String): not nullable String; private;
    begin
      var lQuery := if (length(AuthorizationToken) > 0) and (length(aToken) > 0) then "?token="+HttpUtility.UrlEncode(aToken) else "";
      var lJsonQuery := "?format=json"+(if length(lQuery) > 0 then "&"+lQuery.Substring(1) else "");
      var lStatus: nullable WebHostStatus;
      var lErrors := new StringBuilder;
      locking fDiagnosticMonitor do begin
        lStatus := fHostStatus;
        for each lError in fRecentErrors do
          lErrors.Append($"<li>{HtmlLandingPage.EscapeHtml(lError.Path+": "+lError.Message)}</li>");
      end;
      var lRows := new StringBuilder;
      if assigned(lStatus) then
        for each lUnit in lStatus.Units do
          lRows.Append(##"""
            <tr><td>{{HtmlLandingPage.EscapeHtml(lUnit.Name)}}</td><td>{{HtmlLandingPage.EscapeHtml(lUnit.State)}}</td>
            <td><code>{{HtmlLandingPage.EscapeHtml(lUnit.Artifact)}}</code></td><td>{{HtmlLandingPage.EscapeHtml(lUnit.Error)}}</td></tr>
            """);
      var lCompilerErrors := if lStatus:Failure is WebCompilationException then RenderCompilationErrors(lStatus.Failure as WebCompilationException, aToken) else "";
      result := HtmlLandingPage.RenderCardPage("ESP Status", ##"""
        <style>
          .wrap { max-width: 90rem; }
          .table-scroll { overflow-x: auto; }
          table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
          th, td { padding: 0.65rem; text-align: left; vertical-align: top; border-bottom: 1px solid #94a3b844; overflow-wrap: anywhere; }
          td:first-child { min-width: 14rem; }
          td code { font-size: 0.75rem; }
          .build-error { white-space: pre-wrap; color: #dc2626; }
          li { white-space: pre-wrap; overflow-wrap: anywhere; margin-bottom: 0.5rem; }
        </style>
        <h1>ESP Status</h1>
        <nav><a href="/__esp/status{{HtmlLandingPage.EscapeHtml(lQuery)}}">Refresh status</a> · <a href="/__esp/diagnostics{{HtmlLandingPage.EscapeHtml(lQuery)}}">Diagnostics</a> · <a href="/__esp/errors{{HtmlLandingPage.EscapeHtml(lQuery)}}">Request errors</a> · <a href="/__esp/status{{HtmlLandingPage.EscapeHtml(lJsonQuery)}}">JSON</a> · ESPDebugMode {{if DebugMode then "enabled" else "disabled"}}</nav>
        <p>{{HtmlLandingPage.EscapeHtml(coalesce(lStatus:Summary, "This server has not supplied compilation status."))}}</p>
        <p>Active generation: <strong>{{lStatus:ActiveGeneration}}</strong> · Latest attempt: <strong>{{lStatus:Generation}}</strong></p>
        <p>Retained generations: {{HtmlLandingPage.EscapeHtml(lStatus:RetainedGenerations)}}</p>
        <p class="build-error">{{HtmlLandingPage.EscapeHtml(lStatus:Error)}}</p>
        {{lCompilerErrors}}
        <div class="table-scroll"><table><thead><tr><th>Unit</th><th>State</th><th>Artifact</th><th>Error</th></tr></thead><tbody>{{lRows}}</tbody></table></div>
        <h2>Recent request errors</h2><ul>{{lErrors}}</ul>
        """);
    end;

    method UpdateRetainedGenerations(aGenerations: nullable String);
    begin
      locking fDiagnosticMonitor do
        if assigned(fHostStatus) then
          fHostStatus.RetainedGenerations := aGenerations;
    end;

  private

    fServer: HttpServer;
    fPageFactory: nullable WebPageFactory;
    fFactoryMonitor := new Monitor;
    fDiagnosticMonitor := new Monitor;
    fDiagnosticFolders := new Dictionary<String,String>;
    fDiagnosticSources := new Dictionary<String,WebCompilerDiagnostic>;
    fDiagnosticSourceOrder := new Queue<String>;
    fHostStatus: nullable WebHostStatus;
    fHostFailure: nullable Exception;
    fRecentErrors := new Queue<WebRequestError>;
    fRequestErrorSequence: Int64;

    method SetHostStatus(aValue: nullable WebHostStatus);
    begin
      locking fDiagnosticMonitor do
        fHostStatus := aValue;
    end;

    method DiagnosticSourceLink(aFileName: nullable String; aSourceFileName: nullable String; aLine: Integer): nullable String;
    begin
      if not DebugMode or (length(aSourceFileName) = 0) or not File.Exists(aSourceFileName) then
        exit;
      var lToken := Guid.NewGuid.ToString(GuidFormat.Default);
      locking fDiagnosticMonitor do begin
        // Bound retained links; expired links return 404, never fall back to
        // treating URL input as a filesystem path.
        while fDiagnosticSourceOrder.Count ≥ 512 do
          fDiagnosticSources.Remove(fDiagnosticSourceOrder.Dequeue);
        fDiagnosticSources[lToken] := new WebCompilerDiagnostic(FileName := aFileName, SourceFileName := aSourceFileName, Line := Math.Max(1, aLine));
        fDiagnosticSourceOrder.Enqueue(lToken);
      end;
      result := "/__esp/source/"+lToken;
    end;

    method FindCompilationFailure(aException: nullable Exception): nullable WebCompilationException;
    begin
      while assigned(aException) do begin
        if aException is WebCompilationException then
          exit aException as WebCompilationException;
        {$IF ECHOES}
        aException := aException.InnerException;
        {$ELSE}
        exit;
        {$ENDIF}
      end;
    end;

    method DiagnosticDisplayPath(aPath: nullable String): nullable String;
    begin
      if length(aPath) = 0 then
        exit;
      var lPath := aPath.Replace("\", "/");
      if length(PhysicalRootFolder) > 0 then begin
        var lRoot := PhysicalRootFolder.Replace("\", "/").TrimEnd('/')+"/";
        if lPath.StartsWith(lRoot) then
          exit "./"+lPath.Substring(length(lRoot));
      end;
      locking fDiagnosticMonitor do begin
        var lMatch: nullable String;
        for each lRoot in fDiagnosticFolders.Keys do
          if lPath.StartsWith(lRoot) and (length(lRoot) > length(lMatch)) then
            lMatch := lRoot;
        if assigned(lMatch) then
          exit fDiagnosticFolders[lMatch]+lPath.Substring(length(lMatch));
      end;
      result := "<unknown>/"+lPath.Substring(lPath.LastIndexOf("/")+1);
    end;

    method RenderCompilationErrors(aFailure: not nullable WebCompilationException; aToken: nullable String := nil): not nullable String;
    begin
      var lResult := new StringBuilder;
      lResult.Append($"<p class=""message"">{HtmlLandingPage.EscapeHtml(aFailure.Message)}</p>");
      for each lDiagnostic in aFailure.Diagnostics do begin
        var lLocation := DiagnosticDisplayPath(lDiagnostic.FileName);
        if lDiagnostic.Line > 0 then begin
          lLocation := lLocation+$":{lDiagnostic.Line}";
          if lDiagnostic.Column > 0 then
            lLocation := lLocation+$":{lDiagnostic.Column}";
        end;
        var lLocationHtml := HtmlLandingPage.EscapeHtml(lLocation);
        var lUrl := DiagnosticSourceLink(lDiagnostic.FileName, coalesce(lDiagnostic.SourceFileName, lDiagnostic.FileName), lDiagnostic.Line);
        if assigned(lUrl) then begin
          if (length(AuthorizationToken) > 0) and (length(aToken) > 0) then
            lUrl := lUrl+"?token="+HttpUtility.UrlEncode(aToken);
          lLocationHtml := $"<a href=""{HtmlLandingPage.EscapeHtml(lUrl)}"">{lLocationHtml}</a>";
        end;
        var lCode := if length(lDiagnostic.Code) > 0 then $" <code>{HtmlLandingPage.EscapeHtml(lDiagnostic.Code)}</code>" else "";
        lResult.Append(##"""
          <section class="exception compiler-diagnostic">
            <div class="exception-label">{{HtmlLandingPage.EscapeHtml(lDiagnostic.Severity)}}{{lCode}}</div>
            <h2>{{HtmlLandingPage.EscapeHtml(lDiagnostic.Message)}}</h2>
            <div class="diagnostic-location">{{lLocationHtml}}</div>
            {{RenderCompilerSource(lDiagnostic)}}
          </section>
          """);
      end;
      result := lResult.ToString;
    end;

    method RenderCompilerSource(aDiagnostic: not nullable WebCompilerDiagnostic): not nullable String;
    begin
      result := "";
      if not DebugMode or not ShowCompilerErrorSource or (aDiagnostic.Line ≤ 0) or
          (length(aDiagnostic.SourceFileName) = 0) then
        exit;
      var lLines := RenderSourceLines(aDiagnostic, 3);
      if length(lLines) > 0 then
        result := $"<details class=""compiler-source""><summary>Source</summary><pre>{lLines}</pre></details>";
    end;

    method RenderSourceLines(aDiagnostic: not nullable WebCompilerDiagnostic; aContextLines: Integer): not nullable String;
    begin
      result := "";
      try
        if not File.Exists(aDiagnostic.SourceFileName) then
          exit;
        var lLines := File.ReadLines(aDiagnostic.SourceFileName);
        if aDiagnostic.Line > lLines.Count then
          exit;
        var lResult := new StringBuilder;
        for i := Math.Max(1, aDiagnostic.Line-aContextLines) to Math.Min(lLines.Count, aDiagnostic.Line+aContextLines) do begin
          var lLine := lLines[i-1];
          if length(lLine) > 2000 then
            lLine := lLine.Substring(0, 2000)+"…";
          var lClass := if i = aDiagnostic.Line then "source-line source-error" else "source-line";
          lResult.Append($"<span class=""{lClass}""><span class=""line-number"">{i}</span>{HtmlLandingPage.EscapeHtml(lLine)}</span>");
        end;
        result := lResult.ToString;
      except
        // Unreadable source must never replace the compiler diagnostic.
        result := "";
      end;
    end;

    method CreateRequestContext(aEventArgs: HttpRequestEventArgs; aPath: String; aQuery: String; aFactory: nullable WebPageFactory): WebContext;
    begin
      var lScheme := "http";
      var lForwardedScheme := aEventArgs.Request.Header["X-Forwarded-Proto"]:Value:SubstringToFirstOccurrenceOf(","):Trim:ToLowerInvariant;
      if lForwardedScheme in ["http", "https"] then
        lScheme := lForwardedScheme as not nullable;

      // Use the same public authority for host and port. The listening socket
      // belongs to the upstream connection, not necessarily the public URL.
      var lAuthority := ParseRequestAuthority(lScheme,
        aEventArgs.Request.Header["X-Forwarded-Host"]:Value:SubstringToFirstOccurrenceOf(","):Trim);
      if not assigned(lAuthority) then
        lAuthority := ParseRequestAuthority(lScheme, aEventArgs.Request.Header["Host"]:Value:Trim);
      var lDefaultPort := if lScheme = "https" then 443 else 80;
      var lHost: String;
      var lPort: Integer;
      if assigned(lAuthority) then begin
        lHost := lAuthority.Host;
        lPort := coalesce(lAuthority.Port, lDefaultPort);
      end
      else begin
        lPort := aEventArgs.Connection.Binding.Port;
        lHost := "localhost";
        with matching lLocalEndPoint := IPEndPoint(aEventArgs.Connection.LocalEndPoint) do begin
          lPort := lLocalEndPoint.Port;
          lHost := lLocalEndPoint.Address.ToString;
        end;
      end;
      with matching lForwardedPort := Convert.TryToInt32(aEventArgs.Request.Header["X-Forwarded-Port"]:Value:SubstringToFirstOccurrenceOf(","):Trim) do
        if (lForwardedPort > 0) and (lForwardedPort ≤ 65535) then
          lPort := lForwardedPort;
      var lPublicAuthority := if lHost.Contains(":") then "["+lHost+"]" else lHost;
      if lPort ≠ lDefaultPort then
        lPublicAuthority := lPublicAuthority+":"+lPort.ToString;
      var lUrl := Url.UrlWithString(lScheme+"://"+lPublicAuthority+aPath+
        (if length(aQuery) > 0 then "?"+aQuery else ""));
      result := new WebContext(new RemObjects.Elements.Web.WebRequest(aEventArgs.Request, lUrl, aEventArgs.Connection.RemoteEndPoint, aEventArgs.Connection.LocalEndPoint), new WebResponse(aEventArgs.Response), aFactory);
      result.Server := new WebServerForContext(self, result);
    end;

    method ParseRequestAuthority(aScheme: not nullable String; aAuthority: nullable String): nullable Url; private;
    begin
      if length(aAuthority) = 0 then
        exit;
      for each c in aAuthority do
        if c in ['/', '\', '?', '#', '@', ' ', #9, #10, #13] then
          exit;
      result := Url.TryUrlWithString(aScheme+"://"+aAuthority);
      if assigned(result) and ((length(result.Host) = 0) or
          (assigned(result.Port) and ((result.Port < 1) or (result.Port > 65535)))) then
        result := nil;
    end;

    method SetPageFactory(aFactory: nullable WebPageFactory);
    begin
      aFactory:InitializeStaticFiles(coalesce(aFactory:PhysicalRootFolder, PhysicalRootFolder));
      aFactory:Seal;
      var lPrevious: nullable WebPageFactory;
      locking fFactoryMonitor do begin
        if fPageFactory = aFactory then
          exit;
        lPrevious := fPageFactory;
        fPageFactory := aFactory;
      end;
      lPrevious:Retire;
    end;

    {$IF ECHOES}
    method RenderStackTrace(aCallStack: not nullable sequence of String): not nullable String;
    begin
      var lResult := new StringBuilder;
      for each lFrame in aCallStack do
        lResult.Append(RenderStackFrame(lFrame));
      result := lResult.ToString;
    end;

    method RenderStackFrame(aFrame: nullable String): not nullable String;
    begin
      var lFrame := coalesce(aFrame, ""):Trim;
      var lMethod := lFrame;
      var lLocation: nullable String;
      var lLocationMarker := lFrame.LastIndexOf(" in ");
      if lLocationMarker ≥ 0 then begin
        lMethod := lFrame.Substring(0, lLocationMarker);
        lLocation := lFrame.Substring(lLocationMarker+4);
      end;

      var lLocationHtml := "";
      if length(lLocation) > 0 then begin
        var lFileName := lLocation as not nullable;
        var lLineNumber: nullable Integer;
        var lLineMarker := lFileName.LastIndexOf(":line ");
        var lLineMarkerLength := 6;
        if lLineMarker < 0 then begin
          lLineMarker := lFileName.LastIndexOf(":");
          lLineMarkerLength := 1;
        end;

        if lLineMarker ≥ 0 then begin
          var lCandidateLineNumber := Convert.TryToInt32(lFileName.Substring(lLineMarker+lLineMarkerLength));
          if assigned(lCandidateLineNumber) then begin
            lLineNumber := lCandidateLineNumber;
            lFileName := lFileName.Substring(0, lLineMarker);
          end;
        end;

        var lLocationText := DiagnosticDisplayPath(lFileName)+(if assigned(lLineNumber) then $":{lLineNumber}" else "");
        var lSourceUrl := DiagnosticSourceLink(lFileName, lFileName, coalesce(lLineNumber, 1));
        if assigned(lSourceUrl) then begin
          lLocationHtml := $"<a href=""{HtmlLandingPage.EscapeHtml(lSourceUrl)}"" title=""View source context"">{HtmlLandingPage.EscapeHtml(lLocationText)}</a>";
        end
        else
          lLocationHtml := HtmlLandingPage.EscapeHtml(lLocationText);
      end;

      var lLocationElement := if length(lLocationHtml) > 0 then $"<div class=""stack-location"">{lLocationHtml}</div>" else "";
      result := ##"""
        <div class="stack-frame">
          <div class="stack-method">{{HtmlLandingPage.EscapeHtml(lMethod)}}</div>
          {{lLocationElement}}
        </div>
        """;
    end;
    {$ENDIF}

    method RenderErrorPage(aCode: Integer; aTitle: not nullable String; aPath: nullable String; aMessage: nullable String; aException: nullable Exception := nil): not nullable String;
    begin
      if assigned(FindCompilationFailure(aException)) then
        aTitle := "Compilation Error";
      var lDetails := if assigned(aException) then RenderException(aException) else "";
      var lMessage := if length(aMessage) > 0 then $"<p class=""message"">{HtmlLandingPage.EscapeHtml(aMessage)}</p>" else "";
      {$IF ECHOES}
      var lLogoUrl := "/__esp/logo.png";
      {$ELSE}
      var lLogoUrl := "https://www.remobjects.com/images/product-logos/Elements-1024.png";
      {$ENDIF}
      var lBody := ##"""
        <style>
          .product-logo {
            display: block;
            width: 88px;
            height: 88px;
            margin: 0 0 1.25rem;
          }
          .status {
            margin-bottom: 0.4rem;
            color: #dc2626;
            font-size: 0.78rem;
            font-weight: 750;
            letter-spacing: 0.09em;
            text-transform: uppercase;
          }
          .request-path {
            display: inline-block;
            max-width: 100%;
            margin: 0.15rem 0 1rem;
            overflow-wrap: anywhere;
          }
          .message { color: #4b5563; }
          .exception {
            margin-top: 1.35rem;
            padding-top: 1.25rem;
            border-top: 1px solid #e5e7eb;
          }
          .exception-label {
            margin-bottom: 0.35rem;
            color: #6b7280;
            font-size: 0.72rem;
            font-weight: 700;
            letter-spacing: 0.08em;
            text-transform: uppercase;
          }
          .exception h2 {
            margin: 0 0 0.6rem;
            font-size: 1.05rem;
            line-height: 1.45;
            overflow-wrap: anywhere;
          }
          .exception-type { color: #6b7280; }
          .diagnostic-location { overflow-wrap: anywhere; font: 0.85rem/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
          .compiler-source pre { margin: 0; padding: 0.65rem 0; overflow: auto; background: #111827; color: #e5e7eb; font: 0.8rem/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
          .source-line { display: block; padding-right: 1rem; min-width: max-content; }
          .line-number { display: inline-block; width: 4rem; padding-right: 1rem; text-align: right; color: #94a3b8; user-select: none; }
          .source-error { background: #7f1d1d; }
          details {
            margin-top: 1.35rem;
            border: 1px solid #e5e7eb;
            border-radius: 10px;
            overflow: hidden;
          }
          summary {
            padding: 0.75rem 0.9rem;
            background: #f9fafb;
            cursor: pointer;
            font-weight: 650;
          }
          .stack-trace {
            max-height: 24rem;
            overflow: auto;
            background: #111827;
            color: #e5e7eb;
            font: 0.78rem/1.55 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          }
          .stack-frame {
            padding: 0.75rem 1rem;
            border-top: 1px solid #273244;
          }
          .stack-frame:first-child { border-top: 0; }
          .stack-method, .stack-location { overflow-wrap: anywhere; }
          .stack-location {
            margin-top: 0.2rem;
            color: #94a3b8;
            font-size: 0.72rem;
          }
          .stack-location a {
            color: #a5b4fc;
            text-decoration: none;
          }
          .stack-location a:hover { text-decoration: underline; }
          .stack-location a::before {
            content: "↗ ";
            color: #64748b;
          }
          @media (prefers-color-scheme: dark) {
            .status { color: #fca5a5; }
            .message, .exception-type, .exception-label { color: #9ca3af; }
            .exception, details { border-color: #374151; }
            summary { background: #111827; }
            .stack-trace {
              background: #0b1020;
              color: #d1d5db;
            }
          }
        </style>
        <a href="https://www.remobjects.com/elements" target="_blank" rel="noreferrer">
          <img class="product-logo" src="{{lLogoUrl}}" width="88" height="88" alt="Elements" />
        </a>
        <div class="status">HTTP {{aCode}}</div>
        <h1>{{HtmlLandingPage.EscapeHtml(aTitle)}}</h1>
        <code class="request-path">{{HtmlLandingPage.EscapeHtml(aPath)}}</code>
        {{lMessage}}
        {{lDetails}}
        """;

      result := HtmlLandingPage.RenderCardPage($"{aCode} {aTitle}", lBody);
    end;

    method TryServeStaticFile(aRequestPath: not nullable String; aEventArgs: not nullable HttpRequestEventArgs; aFactory: nullable WebPageFactory): Boolean;
    begin
      var lFileName := ResolvePublicStaticFile(aRequestPath, coalesce(aFactory:PhysicalRootFolder, PhysicalRootFolder),
        coalesce(aFactory:PhysicalBinFolder, PhysicalBinFolder));
      if not assigned(lFileName) then
        exit;
      ServeStaticContent(aRequestPath, LeaseFile(lFileName, aFactory), aEventArgs, aFactory, lFileName);
      result := true;
    end;

    method ResolvePublicStaticFile(aRequestPath: not nullable String; aRoot: nullable String; aBinFolder: nullable String): nullable String;
    begin
      if length(aRoot) = 0 then
        exit;

      var lParts := HttpUtility.UrlDecode(aRequestPath).Replace("\", "/").Split("/");
      var lFileName := aRoot as not nullable;
      var lFirstPart: nullable String;
      for each lPart in lParts do begin
        if length(lPart) = 0 then
          continue;
        if (lPart = ".") or (lPart = "..") then
          exit;
        if not assigned(lFirstPart) then
          lFirstPart := lPart;
        lFileName := Path.Combine(lFileName, lPart);
      end;

      if caseInsensitive(lFirstPart) in ["bin", "app_code", "app_private", "app_data", ".esp"] then
        exit;
      if IsFileInFolder(lFileName, aBinFolder) then
        exit;
      if caseInsensitive(lFileName.LastPathComponent) = "web.config" then
        exit;
      if caseInsensitive(lFileName.PathExtension) in [".aspx", ".ascx", ".master", ".ashx", ".asmx", ".asax", ".pas", ".cs", ".swift", ".java", ".vb", ".go"] then
        exit;
      if not lFileName.FileExists then begin
        var lResolved := ResolveStaticFile(aRequestPath, aRoot);
        if not assigned(lResolved) then
          exit;
        lFileName := lResolved as not nullable;
      end;

      result := lFileName;
    end;

    method ResolveStaticFile(aRequestPath: not nullable String; aRoot: nullable String): nullable String;
    begin
      if length(aRoot) = 0 then
        exit;
      var lParts := HttpUtility.UrlDecode(aRequestPath).Replace("\", "/").Split("/").Where(p -> length(p) > 0).ToList;
      var lFolder := aRoot as not nullable;
      for each lPart in lParts index i do begin
        if (lPart = ".") or (lPart = "..") then
          exit;
        var lPath := Path.Combine(lFolder, lPart);
        var lIsFile := i = lParts.Count-1;
        if (lIsFile and File.Exists(lPath)) or (not lIsFile and Folder.Exists(lPath)) then begin
          lFolder := lPath as not nullable;
          continue;
        end;
        var lCandidates := if lIsFile then Folder.GetFiles(lFolder) else Folder.GetSubfolders(lFolder);
        var lMatches := lCandidates.Where(p -> caseInsensitive(p.LastPathComponent) = lPart).ToList;
        if lMatches.Count ≠ 1 then
          exit;
        lFolder := lMatches.First as not nullable;
      end;
      if lParts.Count > 0 then
        result := lFolder;
    end;

    class method IsFileInFolder(aFileName: not nullable String; aFolder: nullable String): Boolean;
    begin
      if length(aFolder) = 0 then
        exit false;

      var lFileName := Path.GetFullPath(aFileName);
      var lFolder := Path.GetFullPath(aFolder as not nullable).TrimEnd(Path.DirectorySeparatorChar);
      var lFolderPrefix: String := lFolder+Path.DirectorySeparatorChar.ToString;
      result := (lFileName.ToLowerInvariant = lFolder.ToLowerInvariant) or
                lFileName.ToLowerInvariant.StartsWith(lFolderPrefix.ToLowerInvariant);
    end;

    class method ContentTypeForFileName(aFileName: not nullable String): not nullable String;
    begin
      result := case caseInsensitive(aFileName.PathExtension) of
        ".html", ".htm": "text/html; charset=utf-8";
        ".css": "text/css; charset=utf-8";
        ".js", ".mjs": "text/javascript; charset=utf-8";
        ".json", ".map": "application/json; charset=utf-8";
        ".txt": "text/plain; charset=utf-8";
        ".xml": "application/xml; charset=utf-8";
        ".svg": "image/svg+xml";
        ".png": "image/png";
        ".gif": "image/gif";
        ".jpg", ".jpeg": "image/jpeg";
        ".webp": "image/webp";
        ".ico": "image/x-icon";
        ".woff": "font/woff";
        ".woff2": "font/woff2";
        ".ttf": "font/ttf";
        ".otf": "font/otf";
        ".pdf": "application/pdf";
        else "application/octet-stream";
      end;
    end;

  end;

  WebServerForContext = public class
  public

    method GetLastError: nullable Exception;
    begin
      result := Context.Error;
    end;

    method OpenFile(aVirtualPath: not nullable String): nullable Stream;
    begin
      result := WebServer.OpenFile(aVirtualPath, Context.PageFactory);
    end;

    method MapPath(aPath: nullable String): nullable String;
    begin
      if not assigned(aPath) then
        exit;

      var lPath := aPath.Replace("\", "/");
      var lApplicationRoot := PhysicalApplicationPath;
      if length(lApplicationRoot) = 0 then
        exit aPath;

      if lPath.StartsWith("~/") then
        exit ResolveMapPath(lApplicationRoot, lPath.Substring(2));

      if lPath.StartsWith("/") then
        exit ResolveMapPath(lApplicationRoot, lPath.Substring(1));

      var lBasePath := lApplicationRoot;
      var lRequestDirectory := Context:Request:Path;
      if length(lRequestDirectory) > 0 then begin
        lRequestDirectory := lRequestDirectory.Replace("\", "/");
        if not lRequestDirectory.EndsWith("/") then begin
          var lSlash := lRequestDirectory.LastIndexOf("/");
          lRequestDirectory := if lSlash ≥ 0 then lRequestDirectory.Substring(0, lSlash+1) else "";
        end;
        lRequestDirectory := lRequestDirectory.TrimStart('/');
        if length(lRequestDirectory) > 0 then
          lBasePath := Path.Combine(lApplicationRoot, lRequestDirectory);
      end;

      result := ResolveMapPath(lBasePath, lPath);
    end;

    method ResolveMapPath(aBase: String; aPath: String): String; private;
    begin
      result := Path.GetFullPath(Path.Combine(aBase, aPath));
      var lRoot := Context.PageFactory:PhysicalRootFolder;
      if length(lRoot) > 0 then begin
        lRoot := Path.GetFullPath(lRoot).Replace("\", "/").TrimEnd('/');
        var lResolved := result.Replace("\", "/");
        if (lResolved ≠ lRoot) and not lResolved.StartsWith(lRoot+"/") then
          raise new ArgumentException("The virtual path escapes the website publication root.");
      end;
    end;

    method MapPath(aPath: nullable String; aBaseVirtualDir: nullable String; aAllowCrossAppMapping: Boolean): nullable String;
    begin
      if (length(aBaseVirtualDir) = 0) or (assigned(aPath) and (aPath.StartsWith("/") or aPath.StartsWith("~/"))) then
        exit MapPath(aPath);

      result := MapPath(coalesce(aBaseVirtualDir, "").TrimEnd('/')+"/"+coalesce(aPath, ""));
    end;

    method Transfer(aPath: String);
    begin
      raise new TransferToNewPathException(aPath);
    end;

    method UrlEncode(aString: nullable String): nullable String;
    begin
      result := HttpUtility.UrlEncode(aString);
    end;

    method UrlDecode(aString: nullable String): nullable String;
    begin
      result := HttpUtility.UrlDecode(aString);
    end;

    method UrlPathEncode(aString: nullable String): nullable String;
    begin
      result := HttpUtility.UrlEncode(aString);
    end;

    method HtmlEncode(aString: nullable String): nullable String;
    begin
      result := HttpUtility.HtmlEncode(aString);
    end;

    method HtmlDecode(aString: nullable String): nullable String;
    begin
      result := HttpUtility.HtmlDecode(aString);
    end;

    property ScriptTimeout: Integer;
    property Context: WebContext; readonly;
    property ApplicationPath: String read "/";
    property PhysicalApplicationPath: String read GetPhysicalApplicationPath;

  assembly

    constructor(aWebServer: WebServer; aContext: WebContext);
    begin
      WebServer := aWebServer;
      Context := aContext;
    end;

  private

    property WebServer: WebServer; readonly;

    method GetPhysicalApplicationPath: String;
    begin
      if length(Context.PageFactory:PhysicalRootFolder) > 0 then
        exit Context.PageFactory.PhysicalRootFolder;
      if length(WebServer.PhysicalRootFolder) > 0 then
        exit WebServer.PhysicalRootFolder;
      var lPageAbsolutePath := GetPageStringProperty("AbsolutePath");
      if length(lPageAbsolutePath) = 0 then
        exit Environment.CurrentDirectory;

      var lRelativePath := GetPageStringProperty("RelativePath");
      if length(lRelativePath) > 0 then begin
        lRelativePath := lRelativePath.Replace("\", "/");
        if lRelativePath.StartsWith("~/") then begin
          var lRelativeFilePath := lRelativePath.Substring(2).Replace("/", Path.DirectorySeparatorChar.ToString);
          if lPageAbsolutePath.EndsWith(lRelativeFilePath) then
            exit lPageAbsolutePath.Substring(0, length(lPageAbsolutePath)-length(lRelativeFilePath)).TrimEnd(Path.DirectorySeparatorChar);
        end;
      end;

      result := Path.GetParentDirectory(lPageAbsolutePath);
    end;

    method GetPageStringProperty(aName: not nullable String): nullable String;
    begin
      result := WebPageReflection.GetStringProperty(Context:Page, aName);
    end;

  end;

  WebStaticErrorContent = assembly class
  public

    constructor(aBody: array of Byte; aContentType: not nullable String);
    begin
      Body := aBody;
      ContentType := aContentType;
    end;

    property Body: array of Byte; readonly;
    property ContentType: not nullable String; readonly;

  end;

  WebErrorPage = public class
  public

    constructor(aPath: not nullable String; aRedirect: Boolean; aIisQuery: Boolean; aRemoteOnly: Boolean);
    begin
      Path := aPath;
      Redirect := aRedirect;
      IisQuery := aIisQuery;
      RemoteOnly := aRemoteOnly;
    end;

    constructor(aPath: not nullable String; aRedirect: Boolean; aIisQuery: Boolean; aRemoteOnly: Boolean; aStaticFile: Boolean);
    begin
      Path := aPath;
      Redirect := aRedirect;
      IisQuery := aIisQuery;
      RemoteOnly := aRemoteOnly;
      StaticFile := aStaticFile;
    end;

    property StaticFile: Boolean; readonly;
    property Path: not nullable String; readonly;
    property Redirect: Boolean; readonly;
    property IisQuery: Boolean; readonly;
    property RemoteOnly: Boolean; readonly;

  end;

  WebPageFactory = public abstract class
  public
    property PhysicalRootFolder: nullable String read nil; virtual;
    property PhysicalBinFolder: nullable String read nil; virtual;
    property PublicationRevision: nullable String read nil; virtual;
    property Lifetime: not nullable WebApplicationLifetime read fLifetime; virtual;
    method Acquire; virtual;
    begin
      locking fLifecycleMonitor do begin
        if fRetired and (fRequests = 0) then
          raise new InvalidOperationException("Cannot acquire a retired ESP factory.");
        inc(fRequests);
      end;
    end;
    method Seal; virtual; empty;
    method Release; virtual;
    begin
      var lEnd := false;
      locking fLifecycleMonitor do begin
        if fRequests = 0 then
          raise new InvalidOperationException("ESP factory has no active request to release.");
        dec(fRequests);
        lEnd := fRetired and (fRequests = 0);
      end;
      if lEnd then
        fLifetime.EndApplication;
    end;

    method Retire; virtual;
    begin
      var lEnd := false;
      locking fLifecycleMonitor do begin
        if fRetired then
          exit;
        fRetired := true;
        lEnd := fRequests = 0;
      end;
      if lEnd then
        fLifetime.EndApplication;
    end;

    method OpenResource(aPath: not nullable String; aPublicOnly: Boolean): nullable Stream; virtual;
    begin
      var lName := if aPublicOnly then FindResourcesForPath(aPath) else FindEmbeddedResourceForPath(aPath);
      if not assigned(lName) then
        exit;
      {$IF ECHOES}
      var lStream := GetType.Assembly.GetManifestResourceStream(lName);
      if assigned(lStream) then
        result := new WrappedPlatformStream(lStream);
      {$ELSE}
      raise new NotImplementedException("Reading embedded web resources is not yet implemented for this platform.");
      {$ENDIF}
    end;

    // Hosts can override registration; .NET ESP also discovers an application
    // class in the factory assembly (App_Code for incremental generations).
    method CreateApplication: nullable WebApplication; virtual;
    begin
      {$IF ECHOES}
      locking fApplicationMonitor do begin
        if not fApplicationResolved then begin
          var lApplicationType: nullable System.Type;
          var lTypes := GetType.Assembly.GetTypes;
          for each lType in lTypes do
            if not lType.IsAbstract and not lType.ContainsGenericParameters and lType.IsSubclassOf(typeOf(WebApplication)) and
               not lTypes.Any(t -> not t.IsAbstract and not t.ContainsGenericParameters and t.IsSubclassOf(lType)) then begin
              if assigned(lApplicationType) then
                raise new InvalidOperationException("An ESP application assembly must contain only one concrete WebApplication class.");
              lApplicationType := lType;
            end;
          fApplicationType := lApplicationType;
          fApplicationResolved := true;
        end;
      end;
      if assigned(fApplicationType) then
        result := System.Activator.CreateInstance(fApplicationType) as WebApplication;
      {$ENDIF}
    end;

    method FindClassForPath(aPath: not nullable String): nullable Object; abstract;
    method FindRedirectForPath(aPath: not nullable String): nullable String; abstract;
    method FindResourcesForPath(aPath: not nullable String): nullable String; virtual; empty;
    method FindEmbeddedResourceForPath(aPath: not nullable String): nullable String; virtual; empty;
    method FindErrorPage(aCode: Integer): nullable WebErrorPage; virtual; empty;

    method DoFindClassForPath(aPath: not nullable String): nullable Object;
    begin
      result := coalesce(FindClassForPath(aPath+".aspx"),
                         FindClassForPath(aPath+".ashx"),
                         FindClassForPath(aPath+".asmx"),
                         FindClassForPath(aPath));
    end;
  private

    fStaticFiles: nullable WebStaticFiles;

    property StaticFiles: nullable WebStaticFiles read fStaticFiles; assembly;

    method InitializeStaticFiles(aRoot: nullable String); assembly;
    begin
      locking fLifecycleMonitor do
        if not assigned(fStaticFiles) then
          fStaticFiles := new WebStaticFiles(aRoot, self);
    end;

    fLifetime := new WebApplicationLifetime;
    fLifecycleMonitor := new Monitor;
    fRequests: Integer;
    fRetired: Boolean;

    {$IF ECHOES}
    fApplicationType: nullable System.Type;
    fApplicationResolved: Boolean;
    fApplicationMonitor := new Monitor;
    {$ENDIF}

  end;

  WebResolvePageEventArgs = public class(EventArgs)
  public

    constructor(aPath: not nullable String);
    begin
      Path := aPath;
      PublicationRevision := WebContext.Current:PageFactory:PublicationRevision;
    end;

    property Path: not nullable String; readonly;
    property PublicationRevision: nullable String; readonly;
    property Factory: nullable WebPageFactory;

  end;

  // Routes are immutable after publication. Resolution only materializes code
  // from the generation's captured inputs; it never changes its route graph.
  WebDeferredPageFactory = public class(WebCompositePageFactory)
  public

    method AddRoute(aPath: not nullable String);
    begin
      if fSealed then
        raise new InvalidOperationException("A published ESP route table is immutable.");
      fRoutes.Add(aPath.ToLowerInvariant);
    end;

    method AddRedirect(aPath: not nullable String; aDestination: not nullable String);
    begin
      if fSealed then
        raise new InvalidOperationException("A published ESP route table is immutable.");
      fRedirects[aPath.ToLowerInvariant] := aDestination;
    end;

    method Seal; override;
    begin
      fSealed := true;
      inherited Seal;
    end;

    event ResolvePage: EventHandler;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if not fRoutes.Contains(aPath.ToLowerInvariant) then
        exit;
      var lArgs := new WebResolvePageEventArgs(aPath);
      ResolvePage(self, lArgs);
      result := lArgs.Factory:FindClassForPath(aPath);
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override;
    begin
      result := fRedirects[aPath.ToLowerInvariant];
    end;

  private

    fRoutes := new HashSet<String>;
    fRedirects := new Dictionary<String,String>;
    fSealed: Boolean;

  end;

  // Construct completely before publishing through WebServer.PageFactory.
  WebCompositePageFactory = public class(WebPageFactory)
  public

    constructor(aLifetime: not nullable WebApplicationLifetime);
    begin
      fLifetime := aLifetime;
      fLifetime.Retain;
      Retired += ReleaseLifetime;
    end;

    method AddFactory(aFactory: not nullable WebPageFactory);
    begin
      if fPublished then
        raise new InvalidOperationException("A published ESP snapshot is immutable.");
      fFactories.Add(aFactory);
    end;

    method AddFailure(aPath: not nullable String; aMessage: not nullable String);
    begin
      AddFailureException(aPath, new Exception(aMessage));
    end;

    method AddFailureException(aPath: not nullable String; aException: not nullable Exception);
    begin
      if fPublished then
        raise new InvalidOperationException("A published ESP snapshot is immutable.");
      fFailures[aPath.ToLowerInvariant] := aException;
    end;

    property Lifetime: not nullable WebApplicationLifetime read fLifetime; override;
    event Retired: EventHandler;

    method Seal; override;
    begin
      locking fMonitor do
        fPublished := true;
    end;

    method Acquire; override;
    begin
      locking fMonitor do begin
        if fRetired and (fRequests = 0) then
          raise new InvalidOperationException("Cannot acquire a retired ESP snapshot.");
        fPublished := true;
        inc(fRequests);
      end;
    end;

    method Release; override;
    begin
      var lNotify := false;
      locking fMonitor do begin
        if fRequests = 0 then
          raise new InvalidOperationException("ESP snapshot has no active request to release.");
        dec(fRequests);
        lNotify := fRetired and (fRequests = 0);
      end;
      if lNotify then
        Retired(self, new EventArgs);
    end;

    method Retire; override;
    begin
      var lNotify := false;
      locking fMonitor do begin
        if fRetired then
          exit;
        fRetired := true;
        fPublished := true;
        lNotify := fRequests = 0;
      end;
      if lNotify then
        Retired(self, new EventArgs);
    end;

    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      CheckFailure(aPath);
      for each lFactory in fFactories do begin
        result := lFactory.FindClassForPath(aPath);
        if assigned(result) then
          exit;
      end;
    end;

    method FindRedirectForPath(aPath: not nullable String): nullable String; override;
    begin
      CheckFailure(aPath);
      for each lFactory in fFactories do begin
        result := lFactory.FindRedirectForPath(aPath);
        if assigned(result) then
          exit;
      end;
    end;

    method FindResourcesForPath(aPath: not nullable String): nullable String; override;
    begin
      for each lFactory in fFactories do begin
        result := lFactory.FindResourcesForPath(aPath);
        if assigned(result) then
          exit;
      end;
    end;

    method OpenResource(aPath: not nullable String; aPublicOnly: Boolean): nullable Stream; override;
    begin
      for each lFactory in fFactories do begin
        result := lFactory.OpenResource(aPath, aPublicOnly);
        if assigned(result) then
          exit;
      end;
    end;

    method CreateApplication: nullable WebApplication; override;
    begin
      for each lFactory in fFactories do begin
        result := lFactory.CreateApplication;
        if assigned(result) then
          exit;
      end;
    end;

    method FindErrorPage(aCode: Integer): nullable WebErrorPage; override;
    begin
      for each lFactory in fFactories do begin
        result := lFactory.FindErrorPage(aCode);
        if assigned(result) then
          exit;
      end;
    end;

  private

    fLifetime: not nullable WebApplicationLifetime;
    fFactories := new List<WebPageFactory>;
    fFailures := new Dictionary<String,Exception>;
    fMonitor := new Monitor;
    fRequests: Integer;
    fRetired: Boolean;
    fPublished: Boolean;

    method ReleaseLifetime(aSender: Object; aArgs: EventArgs);
    begin
      fLifetime.Release;
    end;

    method CheckFailure(aPath: not nullable String);
    begin
      var lError := fFailures[aPath.ToLowerInvariant];
      if assigned(lError) then
        raise lError;
    end;

  end;

end.
