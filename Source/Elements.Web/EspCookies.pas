namespace RemObjects.Elements.Web;

uses
  RemObjects.Elements.RTL;

type
  ImmutableWebCookie = public class
  public
    property Values: ImmutableDictionary<String,String> read fValues;
    property Values[aName: not nullable String]: nullable String read fValues[aName]; virtual; default;
    property Count: Integer read fValues.Count;
    property Keys: sequence of String read fValues.Keys;
  protected
    fValues := new Dictionary<String,String>;
  end;

  WebCookie = public class(ImmutableWebCookie)
  public
    property Domain: nullable String;
    property Path: nullable String;
    property Secure: Boolean;
    property Expires: DateTime;
    property Values[aName: not nullable String]: nullable String read fValues[aName] write fValues[aName]; override; default;
  end;

  //
  //
  //

  ImmutableWebCookieCollection = public class
  public

    property Cookies[aName: String]: nullable WebCookie read GetCookie; virtual; default;
    property Count: Integer read fCookies.Count;
    property Keys: sequence of String read fCookies.Keys;

  protected

    var fCookies := new Dictionary<String, WebCookie>;

    method GetCookie(aName: not nullable String): nullable WebCookie; virtual;
    begin
      result := fCookies[aName];
    end;

  assembly

    constructor;
    begin
    end;

    constructor(aCookieHeader: nullable String);
    begin
      //Login=UserName=mh&UserToken=$2a$11$7VcEQejDVl1WSNzTi8L3q.v4q5goR2Kut1XXXXXXXX;
      //ASP.NET_SessionId=lwmhjy3qq44wcfq0chl0obhk;
      //experimentation_subject_id=ImEzNzRlZTg3LWNhNDgtNGJjOC05NzMxLTYyMzAyZWY0N2Y1NyI%3D--7c3157660edd5faaffc522c4a09b280a108f84a0
      //Log($" reading CookieHeader {aCookieHeader}");
      for each c in aCookieHeader.Split(";") do begin
        var lSplit := c.SplitAtFirstOccurrenceOf("=");
        if lSplit.Count = 2 then begin
          var lCookie := new WebCookie;
          fCookies[lSplit[0].Trim] := lCookie;
          //Log($"got cookie '{lSplit[0].Trim}'");

          var lValues := lSplit[1].Trim.Split("&");
          if (lValues.Count = 1) and not lSplit[1].Contains("=") then begin
            lCookie[""] := lSplit[1].Trim;
            //Log($"got single cookie value '{lSplit[1].Trim}'");
          end
          else begin
            for each v in lValues do begin
              var lSplitValue := v.SplitAtFirstOccurrenceOf("=");
              if lSplitValue.Count = 2 then begin
                lCookie[lSplitValue[0].Trim] := lSplitValue[1].Trim;
                //Log($"got cookie named value '{lSplitValue[0].Trim}'='{lSplitValue[1].Trim}'");
              end;
            end;
          end;
        end;
      end;
    end;

    method GetCookieHeaderString: String;
    begin
      // Set-Cookie:

      // Login=UserName=mh&UserToken=$2a$11$7Sh46mgpvbN.bRUQpJGz3eoq9KwyjWfIg6PMtnIpRDR1fCqpOol52; domain=remobjects.com; expires=Sun, 17-Jul-2022 14:21:24 GMT; path=/; secure; HttpOnly

      var lString := new StringBuilder;
      for each k in fCookies.Keys index i do begin

        if i > 0 then
          lString.Append(", ");

        lString.Append(k);
        lString.Append("=");
        var lCookie := fCookies[k];
        for each v in lCookie.Values.Keys do begin
          if (v = "") and (lCookie.Values.Count = 1)  then begin
            lString.Append(lCookie.Values[v]) // review this
          end
          else begin
            lString.Append(v);
            lString.Append("=");
            lString.Append(lCookie.Values[v]) // encode?
          end;
        end;

        if assigned(lCookie.Domain) then begin
          lString.Append("; ");
          lString.Append("domain=");
          lString.Append(lCookie.Domain.ToLowerInvariant);
        end;

        if assigned(lCookie.Expires) then begin
          lString.Append("; ");
          lString.Append("expires=");
          lString.Append(lCookie.Expires.ToString("ddd, dd-mmm-yyyy hh:mm:ss UTC"));
        end;

        lString.Append("; ");
        lString.Append("path=");
        lString.Append(coalesce(lCookie.Path, "/"));
      end;

      result := lString.ToString;
      Log($"set-cookie: {result}");
    end;

  end;

  //
  //
  //

  WebCookieCollection = public class(ImmutableWebCookieCollection)
  public

    //property Cookies[aName: String]: nullable WebCookie read GetCookie write SetCookie; override; default;

    method &Add(aCookie: WebCookie);
    begin

    end;

  protected

    method GetCookie(aName: not nullable String): nullable WebCookie; override;
    begin
      result := inherited;
      if not assigned(result) then begin
        result := new WebCookie;
        fCookies[aName] := result;
      end;
    end;

    //method SetCookie(aName: not nullable String

  assembly


  end;
end.