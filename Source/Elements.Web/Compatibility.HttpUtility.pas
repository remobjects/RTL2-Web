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

  end;

end.