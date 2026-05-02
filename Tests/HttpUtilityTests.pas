namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  HttpUtilityTests = public class(Test)
  public

    method UrlDecodeTreatsPlusAsSpace;
    begin
      Assert.AreEqual(HttpUtility.UrlDecode("one+two%2Fthree"), "one two/three");
    end;

    method HtmlEncodeEscapesCommonMarkupCharacters;
    begin
      Assert.AreEqual(HttpUtility.HtmlEncode("<a href=""/"">A&B</a>"), "&lt;a href=&quot;/&quot;&gt;A&amp;B&lt;/a&gt;");
    end;

    method HtmlDecodeRestoresCommonMarkupCharacters;
    begin
      Assert.AreEqual(HttpUtility.HtmlDecode("&lt;a href=&quot;/&quot;&gt;A&amp;B&lt;/a&gt;"), "<a href=""/"">A&B</a>");
    end;

  end;

end.
