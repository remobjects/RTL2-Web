namespace RemObjects.Elements.Web;

uses
  System.Net,
  RemObjects.Elements.RTL.Reflection;

type
  WebServer = public class
  public

    method Start(aPort: Integer := 8001);
    begin
      fServer := new HttpServer();
      fServer.Port := aPort;
      fServer.KeepAlive := true;
      fServer.CloseConnectionsOnShutdown := true;
      fServer.HttpRequest += HandleEspRequest;
      fServer.Open();
    end;

    method HandleEspRequest(aSender: Object; aEventArgs: HttpRequestEventArgs);
    begin
      try
        var lRequestPath := aEventArgs.Request.Path;
        var lRequestQuery := aEventArgs.Request.QueryString.ToString;
        var lTransferCount := 0;

        if caseInsensitive(aEventArgs.Request.Header.RequestType) in ["get", "head"] then begin
          var lRedirect := PageFactory:FindRedirectForPath(lRequestPath);
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
          var lObject := PageFactory:DoFindClassForPath(lRequestPath);
          if assigned(lObject) then begin

            //Log($"{lRequestPath} served via {lObject}");
            var lHost := String(aEventArgs.Request.Header["Host"]:Value):SubstringToFirstOccurrenceOf(":");
            var lPort := aEventArgs.Connection.Binding.Port;
            with matching lLocalEndPoint := IPEndPoint(aEventArgs.Connection.LocalEndPoint) do
              lPort := lLocalEndPoint.Port;
            var lScheme := "http";
            var lForwardedScheme := aEventArgs.Request.Header["X-Forwarded-Proto"]:Value:SubstringToFirstOccurrenceOf(","):Trim;
            if caseInsensitive(lForwardedScheme) in ["http", "https"] then
              lScheme := lForwardedScheme as not nullable;
            var lUrl := Url.UrlWithComponents(lScheme, lHost, lPort, lRequestPath, lRequestQuery, nil, nil);
            var lContext := new WebContext(new RemObjects.Elements.Web.WebRequest(aEventArgs.Request, lUrl, aEventArgs.Connection.RemoteEndPoint, aEventArgs.Connection.LocalEndPoint), new WebResponse(aEventArgs.Response));
            lContext.Server := new WebServerForContext(self, lContext);

            var lPreviousContext := WebContext.Current;
            var lTransferPath: nullable String := nil;
            WebContext.Current := lContext;
            try

              try

                if lObject is Page then begin
                  var lPage := lObject as Page;
                  lPage.Context := lContext;
                  lContext.Request.Page := lPage;
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

                var lCookieIndex := 0;
                for each lCookieHeader in lContext.Response.Cookies.GetCookieHeaderStrings do begin
                  if lCookieIndex = 0 then
                    lContext.Response.HttpServerResponse.Header.SetHeaderValue("Set-Cookie", lCookieHeader)
                  else
                    lContext.Response.HttpServerResponse.Header["Set-Cookie"].Add(lCookieHeader);
                  inc(lCookieIndex);
                end;
                aEventArgs.Response.ContentStream.Seek(0, SeekOrigin.Begin);

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
            var lRedirect := PageFactory:FindRedirectForPath(lRequestPath);
            if assigned(lRedirect) then begin

              Log($"{lRequestPath} redirected to {lRedirect}");
              aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.MovedPermanently;
              aEventArgs.Response.Header.SetHeaderValue("Location", lRedirect);
              aEventArgs.Response.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a hrwf=""{lRedirect}"">here</a>.</p></body>";

            end
            else begin
              var lResourceName := PageFactory:FindResourcesForPath(lRequestPath);
              if assigned(lResourceName) then begin

                if defined("ECHOES") then begin
                  var lAssembly := PageFactory.GetType.Assembly;

                  var lStream := lAssembly.GetManifestResourceStream(lResourceName);
                  if assigned(lStream) then begin
                    //Log($"{lRequestPath} served as resource {lResourceName}");
                    aEventArgs.Response.ContentStream := new WrappedPlatformStream(lStream);
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

                if not TryServeStaticFile(lRequestPath, aEventArgs) then begin
                  Log($"{lRequestPath} unknown path 404");
                  if not RunError(aEventArgs, 404) then begin
                    aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
                    //aEventArgs.Response.Header["Content-Type"] := "text/html";
                    aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
                    aEventArgs.Response.ContentString := RenderErrorPage(404, "Page Not Found", lRequestPath, "No page or static resource matches this URL.");
                  end;
                end;

              end;
            end;
          end;
          break;
        end;

      except
        on E: Exception do begin
          Log($"Unhandled ESP request exception for '{aEventArgs.Request.Path}': {E}");
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
      var lPath := ErrorPaths[aCode];
      if assigned(lPath) then begin
        var lUrl := Url.UrlWithComponents("http", "localhost", 8000, lPath, nil, nil, nil);
        with matching lPage := Page(PageFactory:DoFindClassForPath(e.Request.Path)) do begin
          Log($"{e.Request.Path} error {aCode} served via {lPage}");
          lPage.Context := new WebContext(new RemObjects.Elements.Web.WebRequest(e.Request, lUrl, e.Connection.RemoteEndPoint, e.Connection.LocalEndPoint), new WebResponse(e.Response));
          lPage.Context.Server := new WebServerForContext(self, lPage.Context);
          lPage.Context.Request.Page := lPage;
          var lPreviousContext := WebContext.Current;
          WebContext.Current := lPage.Context;
          try
            lPage.RenderControl(nil);
            e.Response.ContentStream.Seek(0, SeekOrigin.Begin);
          finally
            WebContext.Current := lPreviousContext;
          end;
          exit true;
        end;
      end;
    end;

    method RenderException(aException: System.Exception): String;
    begin
      var lException := aException;
      var lIndex := 0;
      var lResult := new StringBuilder;

      while assigned(lException) do begin
        var lLabel := if lIndex = 0 then "Exception" else "Caused by";
        lResult.Append(##"""
          <section class="exception">
            <div class="exception-label">{{lLabel}}</div>
            <h2>{{HtmlLandingPage.EscapeHtml(lException.Message)}}</h2>
            <div class="exception-type"><code>{{HtmlLandingPage.EscapeHtml(lException.GetType.Name)}}</code></div>
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
    end;

    method OpenFile(aVirtualPath: not nullable String): nullable Stream; assembly;
    begin
      var lPath := aVirtualPath.Replace("\", "/");
      if lPath.StartsWith("~/") then
        lPath := lPath.Substring(1);
      if not lPath.StartsWith("/") then
        lPath := "/"+lPath;

      if length(PhysicalRootFolder) > 0 then begin
        var lFileName := PhysicalRootFolder as not nullable;
        for each lPart in lPath.Split("/") do begin
          if length(lPart) = 0 then
            continue;
          if (lPart = ".") or (lPart = "..") then
            exit;
          lFileName := Path.Combine(lFileName, lPart);
        end;
        if lFileName.FileExists then
          exit new FileStream(lFileName, FileOpenMode.ReadOnly);
      end;

      var lResourceName := PageFactory:FindEmbeddedResourceForPath(lPath);
      if not assigned(lResourceName) then
        exit;

      {$IF ECHOES}
      var lStream := PageFactory.GetType.Assembly.GetManifestResourceStream(lResourceName);
      if assigned(lStream) then
        result := new WrappedPlatformStream(lStream);
      {$ELSE}
      raise new NotImplementedException("Reading embedded web resources is not yet implemented for this platform.");
      {$ENDIF}
    end;

    property PageFactory: WebPageFactory;
    property PhysicalRootFolder: nullable String;
    property PhysicalBinFolder: nullable String;
    property DebugMode: Boolean;
    property ErrorPaths := new Dictionary<Integer,String>;

    property Port: Integer read fServer.Port;

  private

    fServer: HttpServer;

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

        var lLocationText := lFileName+(if assigned(lLineNumber) then $":{lLineNumber}" else "");
        if DebugMode and File.Exists(lFileName) then begin
          var lFileUrl := new System.Uri(lFileName).AbsoluteUri;
          if assigned(lLineNumber) then
            lFileUrl := lFileUrl+$"#L{lLineNumber}";
          lLocationHtml := $"<a href=""{HtmlLandingPage.EscapeHtml(lFileUrl)}"" title=""Open local source file"">{HtmlLandingPage.EscapeHtml(lLocationText)}</a>";
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
      var lDetails := if assigned(aException) then RenderException(aException) else "";
      var lMessage := if length(aMessage) > 0 then $"<p class=""message"">{HtmlLandingPage.EscapeHtml(aMessage)}</p>" else "";
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
          <img class="product-logo" src="https://www.remobjects.com/images/product-logos/Elements-1024.png" width="88" height="88" alt="Elements" />
        </a>
        <div class="status">HTTP {{aCode}}</div>
        <h1>{{HtmlLandingPage.EscapeHtml(aTitle)}}</h1>
        <code class="request-path">{{HtmlLandingPage.EscapeHtml(aPath)}}</code>
        {{lMessage}}
        {{lDetails}}
        """;

      result := HtmlLandingPage.RenderCardPage($"{aCode} {aTitle}", lBody);
    end;

    method TryServeStaticFile(aRequestPath: not nullable String; aEventArgs: not nullable HttpRequestEventArgs): Boolean;
    begin
      if length(PhysicalRootFolder) = 0 then
        exit;

      var lParts := HttpUtility.UrlDecode(aRequestPath).Replace("\", "/").Split("/");
      var lFileName := PhysicalRootFolder as not nullable;
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

      if caseInsensitive(lFirstPart) in ["bin", "app_code", "app_data", ".esp"] then
        exit;
      if IsFileInFolder(lFileName, PhysicalBinFolder) then
        exit;
      if caseInsensitive(lFileName.LastPathComponent) = "web.config" then
        exit;
      if caseInsensitive(lFileName.PathExtension) in [".aspx", ".ascx", ".master", ".ashx", ".asmx", ".pas", ".cs", ".swift", ".java", ".vb", ".go"] then
        exit;
      if not lFileName.FileExists then
        exit;

      aEventArgs.Response.Header.SetHeaderValue("Content-Type", ContentTypeForFileName(lFileName));
      aEventArgs.Response.ContentStream := new FileStream(lFileName, FileOpenMode.ReadOnly);
      result := true;
    end;

    class method IsFileInFolder(aFileName: not nullable String; aFolder: nullable String): Boolean;
    begin
      if length(aFolder) = 0 then
        exit false;

      var lFileName := Path.GetFullPath(aFileName);
      var lFolder := Path.GetFullPath(aFolder as not nullable).TrimEnd(Path.DirectorySeparatorChar);
      result := (lFileName.ToLowerInvariant = lFolder.ToLowerInvariant) or
                lFileName.ToLowerInvariant.StartsWith((lFolder+Path.DirectorySeparatorChar).ToLowerInvariant);
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

    method OpenFile(aVirtualPath: not nullable String): nullable Stream;
    begin
      result := WebServer.OpenFile(aVirtualPath);
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
        exit Path.GetFullPath(Path.Combine(lApplicationRoot, lPath.Substring(2)));

      if lPath.StartsWith("/") then
        exit Path.GetFullPath(Path.Combine(lApplicationRoot, lPath.Substring(1)));

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

      result := Path.GetFullPath(Path.Combine(lBasePath, lPath));
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
      if not assigned(Context:Page) then
        exit;

      {$IF ECHOES}
      var lFlags := System.Reflection.BindingFlags.Instance or
                    System.Reflection.BindingFlags.Public or
                    System.Reflection.BindingFlags.NonPublic;
      for each lProperty in Context.Page.GetType.GetProperties(lFlags) do begin
        if lProperty.Name = aName then begin
          with matching lValue := String(lProperty.GetValue(Context.Page, nil)) do
            if length(lValue) > 0 then
              exit lValue;
        end;
      end;
      {$ELSE}
      for each lProperty in typeOf(Context.Page).Properties do begin
        if lProperty.Name = aName then begin
          with matching lValue := String(lProperty.GetValue(Context.Page, [])) do
            if length(lValue) > 0 then
              exit lValue;
        end;
      end;
      {$ENDIF}
    end;

  end;

  WebPageFactory = public abstract class
  public
    method FindClassForPath(aPath: not nullable String): nullable Object; abstract;
    method FindRedirectForPath(aPath: not nullable String): nullable String; abstract;
    method FindResourcesForPath(aPath: not nullable String): nullable String; virtual; empty;
    method FindEmbeddedResourceForPath(aPath: not nullable String): nullable String; virtual; empty;

    method DoFindClassForPath(aPath: not nullable String): nullable Object;
    begin
      result := coalesce(FindClassForPath(aPath+".aspx"),
                         FindClassForPath(aPath+".ashx"),
                         FindClassForPath(aPath+".asmx"),
                         FindClassForPath(aPath));
    end;
  end;

end.
