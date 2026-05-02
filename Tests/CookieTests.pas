namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  CookieTests = public class(Test)
  public

    method MutableCollectionCreatesNamedCookies;
    begin
      var lResponse := new WebResponse(new HttpServerResponse);
      var lCookies := lResponse.Cookies;
      var lCookie := lCookies["Shop"];

      Assert.IsNotNil(lCookie);

      (lCookie as not nullable)["Cart"] := "abc123";

      Assert.AreEqual(lCookies.Count, 1);
      Assert.AreEqual(lCookies["Shop"]["Cart"], "abc123");
    end;

  end;

end.
