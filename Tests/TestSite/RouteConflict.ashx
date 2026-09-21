<%@ WebHandler Language="Oxygene" Class="RouteConflictHandler" %>

namespace RemObjects.Elements.Web.Tests.TestSite;

uses
  System.Web;

type
  RouteConflictHandler = public class(System.Web.IHttpHandler)
  public

    method ProcessRequest(Context: HttpContext);
    begin
      Context.Response.ContentType := "text/plain";
      Context.Response.Write("handler");
    end;

    property IsReusable: Boolean read false;

  end;

end.
