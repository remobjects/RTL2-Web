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

    method ParsesSimpleAndMultiValueRequestCookies;
    begin
      var lCookies := new ImmutableWebCookieCollection("Seen=yes; Flavor=kind=chocolate&size=large; Encoded=a%20b");

      Assert.AreEqual(lCookies["Seen"].Value, "yes");
      Assert.AreEqual(lCookies["Flavor"]["kind"], "chocolate");
      Assert.AreEqual(lCookies["Flavor"]["size"], "large");
      Assert.AreEqual(lCookies["Encoded"].Value, "a b");
    end;

    method SerializesSimpleAndMultiValueResponseCookiesSeparately;
    begin
      var lCookies := new WebCookieCollection;
      lCookies["Seen"].Value := "yes";
      lCookies["Flavor"]["kind"] := "chocolate";
      lCookies["Flavor"]["size"] := "large";

      var lHeaderStrings := lCookies.GetCookieHeaderStrings.ToList;

      Assert.AreEqual(lHeaderStrings.Count, 2);
      Assert.IsTrue(lHeaderStrings.Contains("Seen=yes; path=/"));
      Assert.IsTrue(lHeaderStrings.Contains("Flavor=kind=chocolate&size=large; path=/"));
    end;

  end;

end.
