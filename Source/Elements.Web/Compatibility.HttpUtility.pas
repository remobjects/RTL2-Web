namespace RemObjects.Elements.Web;

type
  HttpUtility = public static class
  public

    method UrlEncode(aString: nullable String): nullable String;
    begin
      if not assigned(aString) then
        exit;

      // Encode a query/form value, not a path: slashes and colons are data.
      var lResult := new StringBuilder;
      for each b in Convert.ToUtf8Bytes(aString) do begin
        if (b in [48..57, 65..90, 97..122]) or (b in [45, 46, 95, 42]) then
          lResult.Append(Char(b))
        else if b = 32 then
          lResult.Append("+")
        else
          lResult.Append("%"+Convert.ToHexString(ord(b), 2));
      end;
      result := lResult.ToString;
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
