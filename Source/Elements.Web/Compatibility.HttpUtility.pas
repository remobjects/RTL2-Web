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
      result := Url.RemovePercentEncodingsFromPath(aString);
    end;

    method HtmlEncode(aString: nullable String): nullable String;
    begin
      {$WARNING Not implemented}
    end;

    method HtmlDecode(aString: nullable String): nullable String;
    begin
      {$WARNING Not implemented}
    end;

  end;

end.