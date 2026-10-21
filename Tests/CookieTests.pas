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

    method RepeatedRequestCookieNamesKeepLastValue;
    begin
      // Negative guard: response scope storage must preserve existing request name lookup semantics.
      var lCookies := new ImmutableWebCookieCollection("same=root; same=nested");
      Assert.AreEqual(lCookies.Count, 1);
      Assert.AreEqual(lCookies["same"].Value, "nested");
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

    method SameNameCookiesRetainDistinctScopes;
    begin
      // Positive guard: AppendCookie preserves distinct path/domain scopes and last-added name lookup.
      var lResponse := new WebResponse(new HttpServerResponse);
      lResponse.AppendCookie(new WebCookie("same", Value := "root", Path := "/"));
      lResponse.AppendCookie(new WebCookie("same", Value := "nested", Path := "/scope"));
      lResponse.AppendCookie(new WebCookie("same", Value := "domain", Path := "/", Domain := "Example.Test"));
      Assert.AreEqual(lResponse.Cookies.Count, 3);
      Assert.AreEqual(lResponse.Cookies["same"].Value, "domain");
      var lHeaders := lResponse.Cookies.GetCookieHeaderStrings.ToList;
      Assert.AreEqual(lHeaders.Count, 3);
      Assert.IsTrue(lHeaders.Contains("same=root; path=/"));
      Assert.IsTrue(lHeaders.Contains("same=nested; path=/scope"));
      Assert.IsTrue(lHeaders.Contains("same=domain; domain=example.test; path=/"));
    end;

    method SameScopeCookiesStillReplace;
    begin
      // Negative guard: default path and domain casing must not create duplicate cookie identities.
      var lResponse := new WebResponse(new HttpServerResponse);
      lResponse.AppendCookie(new WebCookie("same", Value := "old"));
      lResponse.SetCookie(new WebCookie("same", Value := "root", Path := "/"));
      lResponse.AppendCookie(new WebCookie("same", Value := "old-domain", Domain := "Example.Test"));
      lResponse.SetCookie(new WebCookie("same", Value := "domain", Path := "/", Domain := "example.test"));
      lResponse.AppendCookie(new WebCookie("Same", Value := "case-sensitive"));
      var lHeaders := lResponse.Cookies.GetCookieHeaderStrings.ToList;
      Assert.AreEqual(lResponse.Cookies.Count, 3);
      Assert.AreEqual(lHeaders.Count, 3);
      Assert.IsTrue(lHeaders.Contains("same=root; path=/"));
      Assert.IsTrue(lHeaders.Contains("same=domain; domain=example.test; path=/"));
      Assert.IsTrue(lHeaders.Contains("Same=case-sensitive; path=/"));
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
