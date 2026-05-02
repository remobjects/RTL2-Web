namespace RemObjects.Elements.Web;

uses
  RemObjects.Elements.RTL;

type
  ImmutableWebCookie = public class
  public
    property Value: nullable String read Values[""]; virtual;
    property Values: ImmutableDictionary<String,String> read fValues;
    property Values[aName: not nullable String]: nullable String read fValues[aName]; virtual; default;
    property Count: Integer read fValues.Count;
    property Keys: sequence of String read fValues.Keys;
  protected
    fValues := new Dictionary<String,String>;
  end;

  WebCookie = public class(ImmutableWebCookie)
  public
    property Name: nullable String read assembly write;
    property Domain: nullable String;
    property Path: nullable String;
    property Secure: Boolean;
    property HttpOnly: Boolean;
    property Expires: DateTime;
    property Value: nullable String read Values[""] write Values[""]; override;
    property Values[aName: not nullable String]: nullable String read fValues[aName] write fValues[aName]; override; default;
  end;

  //
  //
  //

  ImmutableWebCookieCollection = public class
  public

    constructor;
    begin
    end;

    constructor(aCookieHeader: nullable String);
    begin
      LoadCookieHeader(aCookieHeader);
    end;

    property Cookies[aName: String]: nullable WebCookie read GetCookie; virtual; default;
    property Count: Integer read fCookies.Count;
    property Keys: sequence of String read fCookies.Keys;

  protected

    var fCookies := new Dictionary<String, WebCookie>;

    method GetCookie(aName: not nullable String): nullable WebCookie; virtual;
    begin
      result := fCookies[aName];
    end;

    method LoadCookieHeader(aCookieHeader: nullable String);
    begin
      //Log($" reading CookieHeader {aCookieHeader}");
      for each c in aCookieHeader.Split(";") do begin
        var lSplit := c.SplitAtFirstOccurrenceOf("=");
        if lSplit.Count = 2 then begin
          var lCookie := new WebCookie;
          lCookie.Name := WebNameValueCollection.DecodeFormValue(lSplit[0].Trim);
          fCookies[lCookie.Name] := lCookie;
          //Log($"got cookie '{lSplit[0].Trim}'");

          var lValues := lSplit[1].Trim.Split("&");
          if (lValues.Count = 1) and not lSplit[1].Contains("=") then begin
            lCookie[""] := WebNameValueCollection.DecodeFormValue(lSplit[1].Trim);
            //Log($"got single cookie value '{lSplit[1].Trim}'");
          end
          else begin
            for each v in lValues do begin
              var lSplitValue := v.SplitAtFirstOccurrenceOf("=");
              if lSplitValue.Count = 2 then begin
                lCookie[WebNameValueCollection.DecodeFormValue(lSplitValue[0].Trim)] := WebNameValueCollection.DecodeFormValue(lSplitValue[1].Trim);
                //Log($"got cookie named value '{lSplitValue[0].Trim}'='{lSplitValue[1].Trim}'");
              end;
            end;
          end;
        end;
      end;
    end;

  public

    method GetCookieHeaderString: String;
    begin
      var lString := new StringBuilder;
      for each k in fCookies.Keys index i do begin
        if i > 0 then
          lString.Append(Environment.LineBreak);
        lString.Append(GetCookieHeaderString(fCookies[k]));
      end;

      result := lString.ToString;
      //Log($"set-cookie: {result}");
    end;

    method GetCookieHeaderStrings: sequence of String;
    begin
      result := fCookies.Keys.Select(k -> GetCookieHeaderString(fCookies[k]));
    end;

    method GetCookieHeaderString(aCookie: not nullable WebCookie): String;
    begin
      var lString := new StringBuilder;
      lString.Append(aCookie.Name);
      lString.Append("=");

      for each v in aCookie.Values.Keys index j do begin
        if j > 0 then
          lString.Append("&");
        if (v = "") and (aCookie.Values.Count = 1)  then begin
          lString.Append(Url.AddPercentEncodingsToPath(aCookie.Values[v])) // review this
        end
        else begin
          lString.Append(Url.AddPercentEncodingsToPath(v));
          lString.Append("=");
          lString.Append(Url.AddPercentEncodingsToPath(aCookie.Values[v]))
        end;
      end;

      if assigned(aCookie.Domain) then begin
        lString.Append("; ");
        lString.Append("domain=");
        lString.Append(aCookie.Domain.ToLowerInvariant);
      end;

      lString.Append("; ");
      lString.Append("path=");
      lString.Append(coalesce(aCookie.Path, "/"));

      if assigned(aCookie.Expires) then begin
        lString.Append("; ");
        lString.Append("expires=");
        lString.Append(aCookie.Expires.ToString("ddd, dd-MMM-yyyy HH:mm:ss UTC"));
      end;

      if aCookie.Secure then
        lString.Append("; Secure");

      if aCookie.HttpOnly then
        lString.Append("; HttpOnly");

      result := lString.ToString;
    end;

  end;

  //
  //
  //

  WebCookieCollection = public class(ImmutableWebCookieCollection)
  public

    constructor;
    begin
    end;

    //property Cookies[aName: String]: nullable WebCookie read GetCookie write SetCookie; override; default;

    method &Add(aCookie: WebCookie);
    begin
      if assigned(aCookie) and assigned(aCookie.Name) then
        fCookies[aCookie.Name] := aCookie;
    end;

  protected

    method GetCookie(aName: not nullable String): nullable WebCookie; override;
    begin
      result := inherited;
      if not assigned(result) then begin
        result := new WebCookie;
        result.Name := aName;
        fCookies[aName] := result;
      end;
    end;

    //method SetCookie(aName: not nullable String

  end;
end.