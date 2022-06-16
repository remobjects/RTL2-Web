namespace RemObjects.Elements.Web;

uses
  RemObjects.InternetPack,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

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
        var lPage := PageFactory:FindClassForPath(aEventArgs.Request.Path);
        if assigned(lPage) then begin
          var lUrl := Url.UrlWithComponents("http", "localhost", 8000, aEventArgs.Request.Path, nil, nil, nil);
          Log($"{aEventArgs.Request.Path} served via {lPage}");
          lPage.Context := new WebContext(new RemObjects.Elements.Web.WebRequest(aEventArgs.Request, lPage, lUrl), new WebResponse(aEventArgs.Response));
          lPage.OnLoad(new EventArgs);
          lPage.RenderControl(nil);
          lPage.OnUnLoad(new EventArgs);
          aEventArgs.Response.ContentStream.Seek(0, SeekOrigin.Begin);
        end
        else begin
          var lRedirect := PageFactory:FindRedirectForPath(aEventArgs.Request.Path);
          if assigned(lRedirect) then begin
            Log($"{aEventArgs.Request.Path} redirected to {lRedirect}");
            aEventArgs.Response.HttpCode := HttpStatusCode.MovedPermanently;
            aEventArgs.Response.Header.SetHeaderValue("Location", lRedirect);
            aEventArgs.Response.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a HREF=""{lRedirect}"">here</a>.</p></body>";
          end
          else begin
            var lResourceName := PageFactory:FindResourcesForPath(aEventArgs.Request.Path);
            if assigned(lResourceName) then begin
              if defined("ECHOES") then begin
                var lAssembly := System.Reflection.Assembly.GetEntryAssembly;

                var lStream := lAssembly.GetManifestResourceStream(lResourceName);
                if assigned(lStream) then begin
                  Log($"{aEventArgs.Request.Path} served as resource {lResourceName}");
                  aEventArgs.Response.ContentStream := new WrappedPlatformStream(lStream);
                end
                else begin
                  Log($"{aEventArgs.Request.Path} resource 404. avilable resources are:");
                  aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
                  //aEventArgs.Response.Header["Content-Type"] := "text/html";
                  aEventArgs.Response.HttpCode := HttpStatusCode.NotFound;
                  aEventArgs.Response.ContentString := $"<h1>404 Embedded resource Not found.</h1> <tt>{aEventArgs.Request.Path}</tt>";
                end;
              end;

            end
            else begin
              Log($"{aEventArgs.Request.Path} unknown path 404");
              if not RunError(aEventArgs, 404) then begin
                aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
                //aEventArgs.Response.Header["Content-Type"] := "text/html";
                aEventArgs.Response.HttpCode := HttpStatusCode.NotFound;
                aEventArgs.Response.ContentString := $"<h1>404 Not found.</h1> <tt>{aEventArgs.Request.Path}</tt>";
              end;
            end;
          end;
        end;
      except
        on E: Exception do begin
          aEventArgs.Response.Header.SetHeaderValue("Content-Type", "text/html");
          //aEventArgs.Response.Header["Content-Type"] := "text/html";
          aEventArgs.Response.HttpCode := HttpStatusCode.InternalServerError;
          aEventArgs.Response.ContentString := $"<h1>{Integer(aEventArgs.Response.HttpCode)} Internal Error.</h1> <tt>{aEventArgs.Request.Path}</tt>"+RenderException(E);
        end;
      end;
    end;

    method RunError(e: HttpRequestEventArgs; aCode: Integer): Boolean;
    begin
      var lPath := ErrorPaths[aCode];
      if assigned(lPath) then begin
        var lUrl := Url.UrlWithComponents("http", "localhost", 8000, lPath, nil, nil, nil);
        var lPage := PageFactory:FindClassForPath(e.Request.Path);
        if assigned(lPage) then begin
          Log($"{e.Request.Path} error {aCode} served via {lPage}");
          lPage.Context := new WebContext(new RemObjects.Elements.Web.WebRequest(e.Request, lPage, lUrl), new WebResponse(e.Response));
          lPage.RenderControl(nil);
          e.Response.ContentStream.Seek(0, SeekOrigin.Begin);
          exit true;
        end;
      end;
    end;

    method RenderException(aException: Exception): String;
    begin
      result := $"{EXCEPTION_STYLES}<h2>{aException.Message}</h2><p><pre>{aException.GetType.Name}
{aException.CallStack.JoinedString("<br>")}</pre></p>";
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

    method Transfer(aPath: String);
    begin

    end;

    method HtmlEncode(aString: nullable String): nullable String;
    begin
      {$WARNING Not implemented}
    end;

    method HtmlDecode(aString: nullable String): nullable String;
    begin
      {$WARNING Not implemented}
    end;

    property ScriptTimeout: Integer;

  assembly

    constructor(aWebServer: WebServer);
    begin

    end;

  end;

  WebPageFactory = public abstract class
  public
    method FindClassForPath(aPath: not nullable String): nullable Page; abstract;
    method FindRedirectForPath(aPath: not nullable String): nullable String; abstract;
    method FindResourcesForPath(aPath: not nullable String): nullable String; virtual; empty;
  end;

end.