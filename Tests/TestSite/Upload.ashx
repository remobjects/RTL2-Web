<%@ WebHandler Language="Oxygene" Class="UploadHandler" %>

namespace RemObjects.Elements.Web.Tests.TestSite;

uses
  System.Web;

type
  UploadHandler = public class(System.Web.IHttpHandler)
  public

    method ProcessRequest(Context: HttpContext);
    begin
      Context.Response.ContentType := "text/plain";

      var lFile := Context.Request.Files["sample"];
      if not assigned(lFile) then begin
        Context.Response.Write("missing");
        exit;
      end;

      var lSavedPath := Path.Combine(Environment.TempFolder.FullPath, "rtl2-web-upload-test.txt");
      lFile.SaveAs(lSavedPath);

      Context.Response.Write("form-title="+Context.Request.Form["title"]);
      Context.Response.Write(";files="+Context.Request.Files.Count);
      Context.Response.Write(";key="+Context.Request.Files.AllKeys[0]);
      Context.Response.Write(";name="+lFile.FileName);
      Context.Response.Write(";type="+lFile.ContentType);
      Context.Response.Write(";length="+lFile.ContentLength);
      Context.Response.Write(";stream="+lFile.InputStream.Length);
      Context.Response.Write(";saved="+File.ReadText(lSavedPath));
    end;

    property IsReusable: Boolean read false;

  end;

end.
