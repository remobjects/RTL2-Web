namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  ResponseTests = public class(Test)
  public

    method DefaultsToUtf8Html;
    begin
      var lResponse := new WebResponse(new HttpServerResponse);

      Assert.AreEqual(lResponse.ContentType, "text/html; charset=utf-8");
      Assert.AreEqual(lResponse.Charset, "utf-8");
    end;

  end;

end.
