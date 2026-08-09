<%@ WebHandler Language="Oxygene" Class="ErrorHandler" %>

namespace RemObjects.Elements.Web.Tests.TestSite;

uses
  System.Web;

type
  ErrorHandler = public class(System.Web.IHttpHandler)
  public

    method ProcessRequest(Context: HttpContext);
    begin
      raise new System.InvalidOperationException("The <sample> handler failed.", new System.Exception("Inner & specific cause."));
    end;

    property IsReusable: Boolean read false;

  end;

end.
