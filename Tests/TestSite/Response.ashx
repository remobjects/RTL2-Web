<%@ WebHandler Language="Oxygene" Class="ResponseHandler" %>

namespace RemObjects.Elements.Web.Tests.TestSite;

uses
  System.Web;

type
  ResponseHandler = public class(System.Web.IHttpHandler)
  public

    method ProcessRequest(Context: HttpContext);
    begin
      var lAction := Context.Request.QueryString["action"];

      case lAction of
        "write": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.Write("alpha");
          Context.Response.Write("-");
          Context.Response.Write(42);
        end;

        "redirect": begin
          Context.Response.Redirect("/Ping.ashx?value=redirected", false);
          Context.Response.Write("after-redirect");
        end;

        "redirect-end": begin
          Context.Response.Redirect("/Ping.ashx?value=redirected");
          Context.Response.Write("after-end");
        end;

        "transfer-handler": begin
          Context.Server.Transfer("/Ping.ashx?value=transferred-handler");
          Context.Response.Write("after-transfer-handler");
        end;

        "transfer-page": begin
          Context.Server.Transfer("/?q=transferred-page");
          Context.Response.Write("after-transfer-page");
        end;

        "rawurl": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.Write(Context.Request.RawUrl);
        end;

        "permanent": begin
          Context.Response.RedirectPermanent("/Ping.ashx?value=permanent", false);
        end;

        "clear": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.AddHeader("X-Test-Clear", "before");
          Context.Response.Write("before");
          Context.Response.Clear;
          Context.Response.ContentType := "text/plain";
          Context.Response.Write("after");
        end;

        "headers": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.AddHeader("X-Test-Header", "one");
          Context.Response.AppendHeader("X-Test-Header", "two");
          Context.Response.SetHeader("X-Test-Replace", "old");
          Context.Response.SetHeader("X-Test-Replace", "new");
          Context.Response.Write(Context.Response.Headers["X-Test-Replace"]);
        end;

        "status": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.StatusCode := 404;
          Context.Response.Write(Context.Response.StatusDescription);
        end;

        "runtime": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.Charset := "utf-8";
          Context.Response.CacheControl := "no-cache";
          Context.Response.BufferOutput := false;
          Context.Response.SubStatusCode := 7;
          Context.Response.Status := "202 Accepted";

          var lAppendCookie := new HttpCookie("append-cookie");
          lAppendCookie.Value := "one";
          Context.Response.AppendCookie(lAppendCookie);

          var lSetCookie := new HttpCookie("set-cookie");
          lSetCookie.Value := "two";
          Context.Response.SetCookie(lSetCookie);

          Context.Response.Write("status="+Context.Response.Status);
          Context.Response.Write(";code="+Context.Response.StatusCode);
          Context.Response.Write(";description="+Context.Response.StatusDescription);
          Context.Response.Write(";substatus="+Context.Response.SubStatusCode);
          Context.Response.Write(";buffer="+Context.Response.BufferOutput);
          Context.Response.Write(";suppress="+Context.Response.SuppressContent);
          Context.Response.Write(";cache="+Context.Response.CacheControl);
          Context.Response.Write(";charset="+Context.Response.Charset);
          Context.Response.Write(";content-type="+Context.Response.ContentType);
        end;

        "suppress": begin
          Context.Response.ContentType := "text/plain";
          Context.Response.SuppressContent := true;
          Context.Response.Write("hidden");
        end;

        else begin
          Context.Response.ContentType := "text/plain";
          Context.Response.Write("unknown");
        end;
      end;
    end;

    property IsReusable: Boolean read false;

  end;

end.
