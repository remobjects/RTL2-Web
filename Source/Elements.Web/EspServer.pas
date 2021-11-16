namespace EspNetTest;

uses
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  EspServer = public class
  public

    method Start;
    begin
      fServer := new HttpServer();
      fServer.Port := 8000;
      fServer.KeepAlive := true;
      fServer.CloseConnectionsOnShutdown := true;

      fServer.HttpRequest += (sender, e) -> begin
        //var lPage := new EspNetTest_TextFile_aspx;
        //lPage.Context := new WebContext(new WebRequest(e.Request, lPage), new WebResponse(e.Response));
        var lUrl := Url.UrlWithComponents("http", "localhost", 80, e.Request.Path, e.Request.QueryString.ToString, nil, nil);
        nil := new WebContext(new WebRequest(e.Request, nil, lUrl), new WebResponse(e.Response));
        //lPage.RenderControl(nil);
        //e.Response.ContentStream.Seek(0, SeekOrigin.Begin);
      end;

      fServer.Open();
    end;

    method Stop;
    begin
      fServer.Close();
    end;

  private

    fServer: HttpServer;

  end;

end.