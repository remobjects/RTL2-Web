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

    method PersistentCookiesUseEnglishGmtExpiry;
    begin
      var lPreviousCulture := System.Globalization.CultureInfo.CurrentCulture;
      try
        System.Globalization.CultureInfo.CurrentCulture := new System.Globalization.CultureInfo("de-DE");
        var lCookies := new WebCookieCollection;
        lCookies["Access"].Value := "granted";
        lCookies["Access"].Expires := new DateTime(2030, 1, 2, 3, 4, 5);
        var lHeader := lCookies.GetCookieHeaderStrings.First;
        Assert.IsTrue(lHeader.Contains("expires=Wed, 02 Jan 2030 03:04:05 GMT"));
        var lContainer := new System.Net.CookieContainer;
        var lUrl := new System.Uri("https://example.test/");
        lContainer.SetCookies(lUrl, lHeader);
        Assert.AreEqual(lContainer.GetCookieHeader(lUrl), "Access=granted");
      finally
        System.Globalization.CultureInfo.CurrentCulture := lPreviousCulture;
      end;
    end;

  end;

end.
