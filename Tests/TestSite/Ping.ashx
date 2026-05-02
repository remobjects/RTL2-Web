<%@ WebHandler Language="Oxygene" Class="PingHandler" %>

namespace RemObjects.Elements.Web.Tests.TestSite;

uses
  System.Web;

type
  PingHandler = public class(System.Web.IHttpHandler)
  public

    method ProcessRequest(Context: HttpContext);
    begin
      Context.Response.ContentType := "text/plain";
      if Context.Request.QueryString["current"] = "1" then
        Context.Response.Write("current="+HttpContext.Current.Request.QueryString["value"])
      else
        Context.Response.Write("handler="+Context.Request.QueryString["value"]);
    end;

    property IsReusable: Boolean read false;

  end;

end.
