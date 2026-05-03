namespace RemObjects.Elements.Web;

uses
  System.Net,
  RemObjects.Elements.RTL.Reflection;

type
  WebServer = public class
  public

    method Start;
    begin
      fServer := new HttpServer();
      fServer.Port := 8001;
      fServer.KeepAlive := true;
      fServer.CloseConnectionsOnShutdown := true;
      fServer.HttpRequest += HandleEspRequest;
      fServer.Open();
    end;

    method HandleEspRequest(aSender: Object; aEventArgs: HttpRequestEventArgs);
    begin
      try

        var lObject := PageFactory:DoFindClassForPath(aEventArgs.Request.Path);
        if assigned(lObject) then begin

          //Log($"{aEventArgs.Request.Path} served via {lObject}");
          var lHost := String(aEventArgs.Request.Header["Host"]:Value):SubstringToFirstOccurrenceOf(":");
          var lPort := aEventArgs.Connection.Binding.Port;
          with matching lLocalEndPoint := IPEndPoint(aEventArgs.Connection.LocalEndPoint) do
            lPort := lLocalEndPoint.Port;
          var lScheme := "http"; // for now
          var lUrl := Url.UrlWithComponents(lScheme, lHost, lPort, aEventArgs.Request.Path, aEventArgs.Request.QueryString.ToString, nil, nil);
          var lContext := new WebContext(new RemObjects.Elements.Web.WebRequest(aEventArgs.Request, lUrl, aEventArgs.Connection.RemoteEndPoint, aEventArgs.Connection.LocalEndPoint), new WebResponse(aEventArgs.Response));
          lContext.Server := new WebServerForContext(self, lContext);

          var lPreviousContext := WebContext.Current;
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
                aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
                //aEventArgs.Response.Header["Content-Type"] := "text/html";
                aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.InternalServerError;
                aEventArgs.Response.ContentString := $"<h1>{Integer(aEventArgs.Response.HttpCode)} Internal Error.</h1><p>Unexpected/unsupported class {typeOf(lObject)} for path {aEventArgs.Request.Path}</p>";
              end;

            except
              on E: CleanlyEndResponseException do; // ignore these
              {$IF ECHOES}
              on E: System.Reflection.TargetInvocationException do
                if E.InnerException is not CleanlyEndResponseException then
                  raise;
              {$ENDIF}
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

          finally
            WebContext.Current := lPreviousContext;
          end;

        end
        else begin
          var lRedirect := PageFactory:FindRedirectForPath(aEventArgs.Request.Path);
          if assigned(lRedirect) then begin

            Log($"{aEventArgs.Request.Path} redirected to {lRedirect}");
            aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.MovedPermanently;
            aEventArgs.Response.Header.SetHeaderValue("Location", lRedirect);
            aEventArgs.Response.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a hrwf=""{lRedirect}"">here</a>.</p></body>";

          end
          else begin
            var lResourceName := PageFactory:FindResourcesForPath(aEventArgs.Request.Path);
            if assigned(lResourceName) then begin

              if defined("ECHOES") then begin
                var lAssembly := System.Reflection.Assembly.GetEntryAssembly;

                var lStream := lAssembly.GetManifestResourceStream(lResourceName);
                if assigned(lStream) then begin
                  //Log($"{aEventArgs.Request.Path} served as resource {lResourceName}");
                  aEventArgs.Response.ContentStream := new WrappedPlatformStream(lStream);
                end
                else begin
                  Log($"{aEventArgs.Request.Path} resource 404");
                  aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
                  //aEventArgs.Response.Header["Content-Type"] := "text/html";
                  aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
                  aEventArgs.Response.ContentString := $"<h1>404 Embedded resource Not found.</h1> <tt>{aEventArgs.Request.Path}</tt>";
                end;
              end
              else begin
                raise new NotImplementedException("Serving static resources is not yet implemented for this platform.");
              end;

            end
            else begin

              Log($"{aEventArgs.Request.Path} unknown path 404");
              if not RunError(aEventArgs, 404) then begin
                aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
                //aEventArgs.Response.Header["Content-Type"] := "text/html";
                aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.NotFound;
                aEventArgs.Response.ContentString := $"<h1>404 Not found.</h1> <tt>{aEventArgs.Request.Path}</tt>";
              end;

            end;
          end;
        end;

      except
        on E: Exception do begin
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
          //aEventArgs.Response.Header["Content-Type"] := "text/html";
          aEventArgs.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode.InternalServerError;
          aEventArgs.Response.ContentString := $"<h1>{Integer(aEventArgs.Response.HttpCode)} Internal Error.</h1> <tt>{aEventArgs.Request.Path}</tt>"+RenderException(E);
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
      {$IF ECHOES}
      result := $"{EXCEPTION_STYLES}<h2>{aException.Message}</h2><p><pre>{aException.GetType.Name}
{aException.CallStack.JoinedString("<br>")}</pre></p>";
      {$ELSE}
      result := $"{EXCEPTION_STYLES}<h2>{aException.Message}</h2><p><pre>{aException.GetType.Name}</pre></p>";
      {$ENDIF}
    end;

    const EXCEPTION_STYLES = "<style>
  pre {
    background-color: #ffffe0;
  }
</style>";

    method Stop;
    begin
      fServer.Close();
    end;

    property PageFactory: WebPageFactory;
    property ErrorPaths := new Dictionary<Integer,String>;

    property Port: Integer read fServer.Port;

  private

    fServer: HttpServer;

  end;

  WebServerForContext = public class
  public

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

    method DoFindClassForPath(aPath: not nullable String): nullable Object;
    begin
      result := coalesce(FindClassForPath(aPath+".aspx"),
                         FindClassForPath(aPath+".ashx"),
                         FindClassForPath(aPath+".asmx"),
                         FindClassForPath(aPath));
    end;
  end;

end.
