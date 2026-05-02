namespace RemObjects.Elements.Web;

uses
  System.Net;

type
  WebRequest = public class
  public

    constructor(aRequest: HttpServerRequest; aUrl: Url);
    begin
      constructor(aRequest, aUrl, nil, nil);
    end;

    constructor(aRequest: HttpServerRequest; aUrl: Url; aRemoteEndPoint: nullable EndPoint; aLocalEndPoint: nullable EndPoint);
    begin
      HttpServerRequest := aRequest;
      Url := aUrl;
      fQueryString := new WebNameValueCollection(aRequest.QueryString.ToString);

      fHeaders := new WebNameValueCollection(true);
      fServerVariables := new WebNameValueCollection(true);

      for each h in aRequest.Header do begin
        fHeaders.Add(h.Name, h.Value);
        fServerVariables.Set($"HTTP_{h.Name.ToUpperInvariant.Replace("-","_")}", h.Value);
      end;

      var lHostHeader := coalesce(fHeaders["Host"], aUrl.Host);
      fServerVariables.Set("HTTP_HOST", lHostHeader);
      fServerVariables.Set("HTTP_PORT", aUrl.Port.ToString);

      fServerVariables.Set("QUERY_STRING", QueryString.ToString);
      fServerVariables.Set("REQUEST_METHOD", aRequest.Header.RequestType);
      fServerVariables.Set("PATH_INFO", aUrl.Path);
      fServerVariables.Set("SCRIPT_NAME", aUrl.Path);
      fServerVariables.Set("URL", aUrl.Path);

      fServerVariables.Set("SERVER_NAME", aUrl.Host);
      fServerVariables.Set("SERVER_PORT", aUrl.Port.ToString);
      fServerVariables.Set("SERVER_PROTOCOL", "HTTP/1.1");
      fServerVariables.Set("SERVER_SOFTWARE", $"RemObjects Elements Server Pages (running on {Environment.Platform})");
      fServerVariables.Set("HTTPS", if aUrl.Scheme = "https" then "on" else "off");

      with matching lRemoteEndPoint := IPEndPoint(aRemoteEndPoint) do begin
        fServerVariables.Set("REMOTE_ADDR", lRemoteEndPoint.Address.ToString);
        fServerVariables.Set("REMOTE_HOST", lRemoteEndPoint.Address.ToString);
        fServerVariables.Set("REMOTE_PORT", lRemoteEndPoint.Port.ToString);
      end;

      with matching lLocalEndPoint := IPEndPoint(aLocalEndPoint) do begin
        fServerVariables.Set("LOCAL_ADDR", lLocalEndPoint.Address.ToString);
        fServerVariables.Set("LOCAL_PORT", lLocalEndPoint.Port.ToString);
      end;

      //for each k in fServerVariables.Keys do
        //Log($"{k} = {fServerVariables[k]}");

      Cookies := new ImmutableWebCookieCollection(aRequest.Header["Cookie"]:Value);
      Browser := new WebBrowserCapabilities(UserAgent);
    end;


    property HttpServerRequest: HttpServerRequest; readonly;
    property Page: Page read assembly write;

    property HttpMethod: RemObjects.Elements.RTL.HttpRequestMethod read HttpServerRequest.Header.Mode;

    //
    // From System.Web.Request
    //

    //method BinaryRead(count: Integer): array of Byte; public;
    //method ValidateInput; public;
    //method MapImageCoordinates(imageFieldName: String): array of Integer; public;
    //method MapRawImageCoordinates(imageFieldName: String): array of Double; public;
    //method SaveAs(filename: String; includeHeaders: Boolean); public;
    //method MapPath(virtualPath: String; baseVirtualDir: String; allowCrossAppMapping: Boolean): String; public;
    //method MapPath(virtualPath: String): String; public;
    //method InsertEntityBody; public;
    //method InsertEntityBody(buffer: array of Byte; offset: Integer; count: Integer); public;
    //method GetBufferlessInputStream(disableMaxRequestLength: Boolean): System.IO.Stream; public;
    //method GetBufferlessInputStream: System.IO.Stream; public;
    method GetBufferedInputStream: Stream; public;
    begin
      result := HttpServerRequest.ContentStream;
    end;

    method BodyAsString: String;
    begin
      result := HttpServerRequest.ContentString;
    end;

    method BodyAsBytes: array of Byte;
    begin
      result := HttpServerRequest.ContentBytes;
    end;

    //method Abort; public;
    //property RequestContext: System.Web.Routing.RequestContext; public;
    //property IsLocal: Boolean; readonly; public;
    //property HttpMethod: String read HttpServerRequest.Mode;
    //property RequestType: String read HttpServerRequest.Type;
    //property ContentType: String; public;
    //property ContentLength: Integer; readonly; public;
    //property ContentEncoding: System.Text.Encoding; public;
    //property AcceptTypes: array of String; readonly; public;
    //property IsAuthenticated: Boolean; readonly; public;
    //property IsSecureConnection: Boolean; readonly; public;
    property Path: String read HttpServerRequest.Path;
    //property AnonymousID: String read assembly write; public;
    //property FilePath: String; readonly; public;
    //property CurrentExecutionFilePath: String; readonly; public;
    //property CurrentExecutionFilePathExtension: String; readonly; public;
    //property AppRelativeCurrentExecutionFilePath: String; readonly; public;
    //property PathInfo: String read Page.Path;
    //property PhysicalPath: String read Page.AbsolutePath
    //property ApplicationPath: String; readonly; public;
    property PhysicalApplicationPath: String; readonly; public;
    property UserAgent: nullable String read fServerVariables["HTTP_USER_AGENT"];
    //property UserLanguages: array of String; readonly; public;
    property Browser: WebBrowserCapabilities; public;
    property UserHostName: nullable String read UserHostAddress; public;
    property UserHostAddress: nullable String read coalesce(fServerVariables["REMOTE_ADDR"], fServerVariables["HTTP_X_FORWARDED_FOR"]); public;
    property RawUrl: String read Url.ToAbsoluteString; public; // for now
    property Url: Url; readonly; public;
    property UrlReferrer: Url; readonly; public;
    property &Params: WebNameValueCollection := LazyLoadParams; readonly; lazy;
    property Item[key: String]: nullable String read &Params[key]; default;
    property QueryString[aValue: String]: nullable String read fQueryString[aValue];
    property QueryString: WebNameValueCollection read fQueryString;
    property Form[aValue: String]: nullable String read GetFormValue;
    property Form: WebNameValueCollection := LazyLoadForm; readonly; lazy;
    property Headers[aValue: String]: nullable String read fHeaders[aValue];
    property Headers: WebNameValueCollection read fHeaders;
    //property Unvalidated: System.Web.UnvalidatedRequestValues; readonly; public;
    property ServerVariables: WebNameValueCollection read fServerVariables;
    property Cookies: ImmutableWebCookieCollection; readonly; public;
    //property Files: System.Web.HttpFileCollection; readonly; public;
    {$IF ROSDK}
    {$ELSE}
    property InputStream: Stream read HttpServerRequest.ContentStream;
    {$ENDIF}

    property TotalBytes: nullable Integer read if HttpServerRequest.HasContentLength then HttpServerRequest.ContentLength;
    //property Filter: System.IO.Stream; public;
    //property ClientCertificate: System.Web.HttpClientCertificate; readonly; public;
    //property LogonUserIdentity: System.Security.Principal.WindowsIdentity; readonly; public;
    //property HttpChannelBinding: System.Security.Authentication.ExtendedProtection.ChannelBinding; readonly; public;
    //property ReadEntityBodyMode: System.Web.ReadEntityBodyMode; readonly; public;
    //property TimedOutToken: System.Threading.CancellationToken; readonly; public;

  private
    fHeaders: WebNameValueCollection;
    fServerVariables: WebNameValueCollection;
    fQueryString: WebNameValueCollection;

    method GetFormValue(aValue: String): nullable String;
    begin
      result := Form.Item[aValue];
    end;

    method LazyLoadForm: WebNameValueCollection;
    begin
      result := new WebNameValueCollection(if HttpServerRequest.HasContentLength then String(HttpServerRequest.ContentString));
    end;

    method LazyLoadParams: WebNameValueCollection;
    begin
      result := new WebNameValueCollection(true);

      AddValuesToParams(result, QueryString);
      AddValuesToParams(result, Form);

      for each lName in Cookies.Keys do begin
        var lCookie := Cookies[lName];
        if assigned(lCookie) then
          result.Add(lName, lCookie.Value);
      end;

      AddValuesToParams(result, ServerVariables);
    end;

    method AddValuesToParams(aParams: not nullable WebNameValueCollection; aValues: not nullable WebNameValueCollection);
    begin
      for each lName in aValues.Keys do
        aParams.Add(lName, aValues[lName]);
    end;
  end;

  WebBrowserCapabilities = public class
  public
    property Browser: String; readonly;
    property MajorVersion: Integer; readonly;

  assembly

    constructor(aUserAgent: nullable String);
    begin
      Browser := aUserAgent;

    end;

  end;

end.
