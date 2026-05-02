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

    property HttpMethodMode: HttpRequestMode read HttpServerRequest.Header.Mode;

    //
    // From System.Web.Request
    //

    //method BinaryRead(count: Integer): array of Byte; public;
    //method ValidateInput; public;
    //method MapImageCoordinates(imageFieldName: String): array of Integer; public;
    //method MapRawImageCoordinates(imageFieldName: String): array of Double; public;
    //method SaveAs(filename: String; includeHeaders: Boolean); public;
    method MapPath(aVirtualPath: nullable String; aBaseVirtualDir: nullable String; aAllowCrossAppMapping: Boolean): nullable String; public;
    begin
      result := Page:Context:Server:MapPath(aVirtualPath, aBaseVirtualDir, aAllowCrossAppMapping);
    end;

    method MapPath(aVirtualPath: nullable String): nullable String; public;
    begin
      result := Page:Context:Server:MapPath(aVirtualPath);
    end;

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
    property HttpMethod: nullable String read fServerVariables["REQUEST_METHOD"];
    property RequestType: nullable String read HttpMethod;
    property ContentType: nullable String read Headers["Content-Type"];
    property ContentLength: Integer read if HttpServerRequest.HasContentLength then HttpServerRequest.ContentLength else 0;
    //property ContentEncoding: System.Text.Encoding; public;
    property AcceptTypes: array of String read SplitHeaderValues(Headers["Accept"]);
    //property IsAuthenticated: Boolean; readonly; public;
    property IsSecureConnection: Boolean read fServerVariables["HTTPS"] = "on";
    property Path: String read HttpServerRequest.Path;
    //property AnonymousID: String read assembly write; public;
    //property FilePath: String; readonly; public;
    //property CurrentExecutionFilePath: String; readonly; public;
    //property CurrentExecutionFilePathExtension: String; readonly; public;
    //property AppRelativeCurrentExecutionFilePath: String; readonly; public;
    //property PathInfo: String read Page.Path;
    //property PhysicalPath: String read Page.AbsolutePath
    //property ApplicationPath: String; readonly; public;
    property PhysicalApplicationPath: nullable String read Page:Context:Server:PhysicalApplicationPath; public;
    property UserAgent: nullable String read fServerVariables["HTTP_USER_AGENT"];
    property UserLanguages: array of String read SplitHeaderValues(Headers["Accept-Language"]);
    property Browser: WebBrowserCapabilities; public;
    property UserHostName: nullable String read UserHostAddress; public;
    property UserHostAddress: nullable String read coalesce(fServerVariables["REMOTE_ADDR"], fServerVariables["HTTP_X_FORWARDED_FOR"]); public;
    property RawUrl: String read Url.ToAbsoluteString; public; // for now
    property Url: Url; readonly; public;
    property UrlReferrer: nullable Url read Url.TryUrlWithString(coalesce(Headers["Referer"], Headers["Referrer"])); public;
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
    property Files: WebFileCollection := LazyLoadFiles; readonly; lazy;
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
    fMultipartForm: WebNameValueCollection;
    fMultipartFiles: WebFileCollection;
    fParsedMultipart: Boolean;

    method GetFormValue(aValue: String): nullable String;
    begin
      result := Form.Item[aValue];
    end;

    method LazyLoadForm: WebNameValueCollection;
    begin
      if IsMultipartForm then begin
        ParseMultipartFormData;
        exit fMultipartForm;
      end;

      result := new WebNameValueCollection(if HttpServerRequest.HasContentLength then String(HttpServerRequest.ContentString));
    end;

    method LazyLoadFiles: WebFileCollection;
    begin
      if IsMultipartForm then begin
        ParseMultipartFormData;
        exit fMultipartFiles;
      end;

      result := new WebFileCollection;
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

    method SplitHeaderValues(aValue: nullable String): array of String;
    begin
      if length(aValue) = 0 then
        exit [];

      result := aValue.Split(",").Select(v -> v.Trim).Where(v -> length(v) > 0).ToArray;
    end;

    method IsMultipartForm: Boolean;
    begin
      result := coalesce(ContentType, "").ToLowerInvariant.StartsWith("multipart/form-data");
    end;

    method ParseMultipartFormData;
    begin
      if fParsedMultipart then
        exit;

      fParsedMultipart := true;
      fMultipartForm := new WebNameValueCollection;
      fMultipartFiles := new WebFileCollection;

      var lBoundary := GetContentTypeParameter("boundary");
      if length(lBoundary) = 0 then
        exit;

      var lBody := BodyAsBytes;
      if length(lBody) = 0 then
        exit;

      var lBoundaryBytes := Encoding.UTF8.GetBytes("--"+lBoundary);
      var lHeaderTerminator := [Byte(13), Byte(10), Byte(13), Byte(10)];
      var lPosition := FindBytes(lBody, lBoundaryBytes, 0);

      while lPosition ≥ 0 do begin
        lPosition := lPosition+length(lBoundaryBytes);

        if (lPosition+1 < length(lBody)) and (lBody[lPosition] = Byte(45)) and (lBody[lPosition+1] = Byte(45)) then
          break;

        if (lPosition+1 < length(lBody)) and (lBody[lPosition] = Byte(13)) and (lBody[lPosition+1] = Byte(10)) then
          inc(lPosition, 2);

        var lHeaderEnd := FindBytes(lBody, lHeaderTerminator, lPosition);
        if lHeaderEnd < 0 then
          break;

        var lHeaders := ParsePartHeaders(new String(CopyBytes(lBody, lPosition, lHeaderEnd-lPosition), Encoding.UTF8));
        var lContentStart := lHeaderEnd+length(lHeaderTerminator);
        var lNextBoundary := FindBytes(lBody, lBoundaryBytes, lContentStart);
        if lNextBoundary < 0 then
          break;

        var lContentEnd := lNextBoundary;
        if (lContentEnd ≥ 2) and (lBody[lContentEnd-2] = Byte(13)) and (lBody[lContentEnd-1] = Byte(10)) then
          dec(lContentEnd, 2);

        var lContent := CopyBytes(lBody, lContentStart, lContentEnd-lContentStart);
        var lDisposition := lHeaders["Content-Disposition"];
        var lName := GetHeaderParameter(lDisposition, "name");
        var lFileName := GetHeaderParameter(lDisposition, "filename");

        if assigned(lFileName) then begin
          fMultipartFiles.Add(lName, new WebPostedFile(lFileName, lHeaders["Content-Type"], lContent));
        end
        else begin
          fMultipartForm.Add(lName, new String(lContent, Encoding.UTF8));
        end;

        lPosition := lNextBoundary;
      end;
    end;

    method GetContentTypeParameter(aName: not nullable String): nullable String;
    begin
      result := GetHeaderParameter(ContentType, aName);
    end;

    method ParsePartHeaders(aHeaders: not nullable String): WebNameValueCollection;
    begin
      result := new WebNameValueCollection(true);

      for each lLine in aHeaders.Replace(#13#10, #10).Split(#10) do begin
        var lSplit := lLine.SplitAtFirstOccurrenceOf(":");
        if lSplit.Count = 2 then
          result.Set(lSplit[0].Trim, lSplit[1].Trim);
      end;
    end;

    method GetHeaderParameter(aHeader: nullable String; aName: not nullable String): nullable String;
    begin
      if length(aHeader) = 0 then
        exit;

      var lPrefix := aName.ToLowerInvariant+"=";
      for each lRawPart in aHeader.Split(";") do begin
        var lParameter := lRawPart.Trim;
        if lParameter.ToLowerInvariant.StartsWith(lPrefix) then begin
          result := lParameter.Substring(length(lPrefix));
          if (length(result) ≥ 2) and result.StartsWith("""") and result.EndsWith("""") then
            result := result.Substring(1, length(result)-2);
          exit;
        end;
      end;
    end;

    method FindBytes(aBytes: not nullable array of Byte; aNeedle: not nullable array of Byte; aStart: Integer): Integer;
    begin
      if (length(aNeedle) = 0) or (length(aBytes) < length(aNeedle)) then
        exit -1;

      for i: Integer := Math.Max(0, aStart) to length(aBytes)-length(aNeedle) do begin
        var lMatches := true;
        for j: Integer := 0 to length(aNeedle)-1 do begin
          if aBytes[i+j] ≠ aNeedle[j] then begin
            lMatches := false;
            break;
          end;
        end;

        if lMatches then
          exit i;
      end;

      result := -1;
    end;

    method CopyBytes(aBytes: not nullable array of Byte; aStart: Integer; aCount: Integer): array of Byte;
    begin
      if aCount ≤ 0 then
        exit [];

      result := new Byte[aCount];
      for i: Integer := 0 to aCount-1 do
        result[i] := aBytes[aStart+i];
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
