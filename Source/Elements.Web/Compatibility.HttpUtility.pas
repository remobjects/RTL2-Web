namespace RemObjects.Elements.Web;

type
  HttpUtility = public static class
  public

    method UrlEncode(aString: nullable String): nullable String;
    begin
      result := Url.AddPercentEncodingsToPath(aString);
    end;

    method UrlDecode(aString: nullable String): nullable String;
    begin
      result := Url.RemovePercentEncodingsFromPath(aString, true);
    end;

    method HtmlEncode(aString: nullable String): nullable String;
    begin
      if not assigned(aString) then
        exit;

      result := aString.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("""", "&quot;");
    end;

    method HtmlDecode(aString: nullable String): nullable String;
    begin
      if not assigned(aString) then
        exit;

      result := aString.Replace("&quot;", """").Replace("&gt;", ">").Replace("&lt;", "<").Replace("&amp;", "&");
    end;

    method HtmlAttributeEncode(aString: nullable String): nullable String;
    begin
      if not assigned(aString) then
        exit;

      result := aString.Replace("&", "&amp;").Replace("""", "&quot;").Replace("<", "&lt;").Replace(">", "&gt;");
    end;

  end;

end.
