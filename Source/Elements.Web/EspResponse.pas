namespace RemObjects.Elements.Web;

type
  HttpCacheability = public enum (
    NoCache,
    &Private,
    Server,
    ServerAndNoCache,
    ServerAndPrivate,
    &Public
  );

  HttpCacheRevalidation = public enum (
    AllCaches,
    ProxyCaches,
    None
  );

  WebCachePolicy = public class
  public
    constructor(aResponse: not nullable WebResponse);
    begin
      fResponse := aResponse;
    end;

    method SetCacheability(aCacheability: HttpCacheability);
    begin
      case aCacheability of
        HttpCacheability.NoCache: fResponse.CacheControl := "no-cache";
        HttpCacheability.&Private: fResponse.CacheControl := "private";
        HttpCacheability.Server: fResponse.CacheControl := "no-cache";
        HttpCacheability.ServerAndNoCache: fResponse.CacheControl := "no-cache";
        HttpCacheability.ServerAndPrivate: fResponse.CacheControl := "private";
        HttpCacheability.&Public: fResponse.CacheControl := "public";
      end;
    end;

    method SetNoStore;
    begin
      var lCacheControl := coalesce(fResponse.CacheControl, "");
      if length(lCacheControl) = 0 then
        lCacheControl := "no-store"
      else if not lCacheControl.ToLowerInvariant.Split(",").Any(v -> v.Trim = "no-store") then
        lCacheControl := lCacheControl+", no-store";

      fResponse.CacheControl := lCacheControl;
      fResponse.Headers["Pragma"] := "no-cache";
    end;

    method SetRevalidation(aRevalidation: HttpCacheRevalidation);
    begin
      case aRevalidation of
        HttpCacheRevalidation.AllCaches:
          fResponse.CacheControl := AppendCacheControlDirective("must-revalidate, proxy-revalidate");
        HttpCacheRevalidation.ProxyCaches:
          fResponse.CacheControl := AppendCacheControlDirective("proxy-revalidate");
        HttpCacheRevalidation.None:
          ;
      end;
    end;

  private
    fResponse: not nullable WebResponse;

    method AppendCacheControlDirective(aDirective: not nullable String): String;
    begin
      var lCacheControl := coalesce(fResponse.CacheControl, "");
      if length(lCacheControl) = 0 then
        exit aDirective;

      if lCacheControl.ToLowerInvariant.Split(",").Any(v -> v.Trim = aDirective.ToLowerInvariant) then
        exit lCacheControl;

      result := lCacheControl+", "+aDirective;
    end;
  end;


  WebResponseTextWriter = public class({$IF ECHOES}System.IO.TextWriter{$ENDIF})
  public

    constructor(aResponse: not nullable WebResponse);
    begin
      fResponse := aResponse;
    end;

    property Encoding: Encoding read fResponse.ContentEncoding; {$IF ECHOES}override;{$ENDIF}

    method Flush; {$IF ECHOES}override;{$ENDIF}
    begin
      fResponse.Flush;
    end;

    method &Write(aValue: Char); {$IF ECHOES}override;{$ENDIF}
    begin
      fResponse.Write(aValue);
    end;

    method &Write(aBuffer: array of Char; aIndex: Integer; aCount: Integer); {$IF ECHOES}override;{$ENDIF}
    begin
      fResponse.Write(aBuffer, aIndex, aCount);
    end;

    method &Write(aValue: nullable String); {$IF ECHOES}override;{$ENDIF}
    begin
      fResponse.Write(aValue);
    end;

  private
    fResponse: not nullable WebResponse;
  end;

  WebResponse = public class;

  WebResponseOutputStream = public class(Stream)
  public
    constructor(aResponse: not nullable WebResponse);
    begin
      fResponse := aResponse;
    end;

    method Seek(aOffset: Int64; aOrigin: SeekOrigin): Int64; override;
    begin
      raise new NotSupportedException("The HTTP response output stream cannot be seeked.");
    end;

    method Close; override; empty;

    method Flush; override;
    begin
      fResponse.Flush;
    end;

    method &Read(aBuffer: array of Byte; aOffset: Int32; aCount: Int32): Int32; override;
    begin
      raise new NotSupportedException("The HTTP response output stream cannot be read.");
    end;

    method &Write(aBuffer: array of Byte; aOffset: Int32; aCount: Int32): Int32; override;
    begin
      fResponse.WriteBytes(aBuffer, aOffset, aCount);
      result := aCount;
    end;

    property CanRead: Boolean read false; override;
    property CanSeek: Boolean read false; override;
    property CanWrite: Boolean read true; override;

  private
    fResponse: not nullable WebResponse;
  end;

  WebResponse = public class
  public
    constructor(aResponse: HttpServerResponse);
    begin
      HttpServerResponse := aResponse;
      fBufferedContent := new MemoryStream;
      Cookies := new WebCookieCollection;
      BufferOutput := true;
      ContentEncoding := Encoding;
      ContentType := "text/html";
      Charset := "utf-8";
    end;

    property HttpServerResponse: HttpServerResponse; readonly;
    property Encoding: Encoding := Encoding.UTF8;
    property TrySkipIisCustomErrors: Boolean;

    //
    // Writing content
    //

    method &Write(aString: nullable String);
    begin
      if SuppressContent then
        exit;

      if assigned(aString) then begin
        var lBytes := ContentEncoding.GetBytes(aString) includeBOM(false);
        WriteBytes(lBytes, 0, length(lBytes));
      end;
    end;

    method &Write(aChars: array of Char; aIndex: Integer; aCount: Integer);
    begin
      &Write(new String(aChars, aIndex, aCount));
    end;

    method &Write(aChar: Char); public;
    begin
      Write(aChar.ToString);
    end;

    method &Write(aObject: Object);
    begin
      if assigned(aObject) then
        &Write(aObject.ToString);
    end;

    //method WriteSubstitution(callback: System.Web.HttpResponseSubstitutionCallback); public;
    //method WriteFile(fileHandle: IntPtr; offset: Int64; size: Int64); public;
    method WriteFile(aFileName: String; aOffset: Int64; aSize: Int64);
    begin
      if SuppressContent then
        exit;

      var lBytes := File.ReadBytes(aFileName);
      WriteBytes(lBytes, aOffset, aSize);
    end;

    method WriteFile(aFileName: not nullable String; aShouldReadIntoMemory: Boolean); public;
    begin
      if SuppressContent then
        exit;

      //if aShouldReadIntoMemory then begin
        var lBytes := File.ReadBytes(aFileName);
        WriteBytes(lBytes, 0, length(lBytes));
      //end
      //else begin
        //using lStream := new FileStream(aFileName, FileOpenMode.ReadOnly) do
          //HttpServerResponse.ContentStream.Write(lStream); // H3 parameter 1 is "FileStream" should be "array of Byte"
      //end;
    end;

    method WriteFile(aFileName: String); public;
    begin
      WriteFile(aFileName, false);
    end;

    //method TransmitFile(aFileName: String; aOffset: Int64; aLength: Int64); public;
    //begin
      //raise new CleanlyEndResponseException
    //end;

    method TransmitFile(aFileName: String); public;
    begin
      EnsureNotStreaming("transmit a file");
      if SuppressContent then begin
        fBufferedContent.Clear;
        fTransmittedContent := nil;
        raise new CleanlyEndResponseException;
      end;

      fTransmittedContent := new FileStream(aFileName, FileOpenMode.ReadOnly);
      raise new CleanlyEndResponseException;
    end;

    //
    //
    //

    //constructor(writer: System.IO.TextWriter); public;
    //method BeginFlush(callback: AsyncCallback; state: Object): IAsyncResult; public;
    //method EndFlush(asyncResult: IAsyncResult); public;
    //method DisableKernelCache; public;
    //method DisableUserCache; public;
    //method AddFileDependency(filename: String); public;
    //method AddFileDependencies(filenames: array of String); public;
    //method AddFileDependencies(filenames: System.Collections.ArrayList); public;
    //method AddCacheItemDependency(cacheKey: String); public;
    //method AddCacheItemDependencies(cacheKeys: array of String); public;
    //method AddCacheItemDependencies(cacheKeys: System.Collections.ArrayList); public;
    //method AddCacheDependency(dependencies: array of System.Web.Caching.CacheDependency); public;
    //class method RemoveOutputCacheItem(path: String; providerName: String); public;
    //class method RemoveOutputCacheItem(path: String); public;
    //method Close; public;

    method BinaryWrite(buffer: array of Byte); public;
    begin
      if SuppressContent then
        exit;

      WriteBytes(buffer, 0, length(buffer));
    end;

    //method Pics(value: String); public;
    method AppendHeader(aName: String; aValue: String);
    begin
      var lHeader := HttpServerResponse.Header[aName];
      if assigned(lHeader) then begin
        lHeader.Add(aValue);
      end
      else begin
        HttpServerResponse.Header.SetHeaderValue(aName, aValue);
      end;
    end;

    method AppendCookie(aCookie: WebCookie); public;
    begin
      Cookies.Add(aCookie);
    end;

    method SetCookie(aCookie: WebCookie); public;
    begin
      Cookies.Add(aCookie);
    end;

    method ClearHeaders;
    begin
      EnsureNotStreaming("clear response headers");
      HttpServerResponse.Header := new HttpHeaders;
      fCacheControl := nil;
      fCharset := nil;
    end;

    method ClearContent;
    begin
      EnsureNotStreaming("clear response content");
      fBufferedContent.Clear;
      fTransmittedContent := nil;
    end;

    method Clear;
    begin
      // Clear the body only; callers use ClearHeaders explicitly for headers.
      ClearContent;
    end;

    method Flush;
    begin
      if fCompleted then
        exit;

      if not fStreaming then begin
        CommitCookies;
        HttpServerResponse.BeginChunkedResponse;
        fStreaming := true;
        var lBytes := fBufferedContent.ToArray;
        fBufferedContent.Clear;
        if length(lBytes) > 0 then
          HttpServerResponse.WriteChunk(lBytes);
      end;
      HttpServerResponse.FlushChunkedResponse;
    end;
    //method AppendToLog(&param: String); public;
    method Redirect(aUrl: String; aShouldEndResponse: Boolean);
    begin
      Log($"Redirecting to {aUrl}");
      IsRequestBeingRedirected := true;
      RedirectLocation := aUrl;
      HttpServerResponse.HttpCode := HttpStatusCode.Found;
      HttpServerResponse.Header.SetHeaderValue("Location", aUrl);
      ClearContent;
      Write($"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a href=""{aUrl}"">here</a>.</p></body>");
      if aShouldEndResponse then
        raise new CleanlyEndResponseException;
    end;

    method Redirect(aUrl: String);
    begin
      Redirect(aUrl, true);
    end;

    method RedirectPermanent(aUrl: String; aShouldEndResponse: Boolean);
    begin
      Log($"Redirecting to {aUrl}");
      IsRequestBeingRedirected := true;
      RedirectLocation := aUrl;
      HttpServerResponse.HttpCode := HttpStatusCode.MovedPermanently;
      HttpServerResponse.Header.SetHeaderValue("Location", aUrl);
      ClearContent;
      Write($"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a href=""{aUrl}"">here</a>.</p></body>");
      if aShouldEndResponse then
        raise new CleanlyEndResponseException;
    end;

    method RedirectPermanent(aUrl: String);
    begin
      RedirectPermanent(aUrl, true);
    end;

    //method RedirectToRoute(routeName: String; routeValues: System.Web.Routing.RouteValueDictionary); public;
    //method RedirectToRoute(routeName: String; routeValues: Object); public;
    //method RedirectToRoute(routeValues: System.Web.Routing.RouteValueDictionary); public;
    //method RedirectToRoute(routeName: String); public;
    //method RedirectToRoute(routeValues: Object); public;
    //method RedirectToRoutePermanent(routeName: String; routeValues: System.Web.Routing.RouteValueDictionary); public;
    //method RedirectToRoutePermanent(routeName: String; routeValues: Object); public;
    //method RedirectToRoutePermanent(routeValues: System.Web.Routing.RouteValueDictionary); public;
    //method RedirectToRoutePermanent(routeName: String); public;
    //method RedirectToRoutePermanent(routeValues: Object); public;

    method AddHeader(aName: String; aValue: String);
    begin
      AppendHeader(aName, aValue);
    end;

    method SetHeader(aName: String; aValue: String);
    begin
      HttpServerResponse.Header.SetHeaderValue(aName, aValue);
    end;

    method &End; public;
    begin
      raise new CleanlyEndResponseException;
    end;

    //method ApplyAppPathModifier(virtualPath: String): String; public;
    //property SupportsAsyncFlush: Boolean; readonly; public;
    property Cookies: WebCookieCollection; readonly; public;
    property Headers[aName: String]: nullable String read GetHeader write SetHeader;
    property StatusCode: Integer read Integer(HttpServerResponse.HttpCode) write SetStatusCode;
    property SubStatusCode: Integer; public;
    property StatusDescription: String read GetStatusDescription write fStatusDescription; public;
    //property TrySkipIisCustomErrors: Boolean; public;
    //property SuppressFormsAuthenticationRedirect: Boolean; public;
    property BufferOutput: Boolean; public;
    property ContentType: nullable String read HttpServerResponse.Header.ContentType write SetContentType;
    property Charset: nullable String read fCharset write SetCharset; public;
    property ContentEncoding: Encoding read fContentEncoding write SetContentEncoding; public;
    //property HeaderEncoding: System.Text.Encoding; public;
    property Cache: WebCachePolicy := new WebCachePolicy(self); readonly; lazy;
    //property IsClientConnected: Boolean; readonly; public;
    //property ClientDisconnectedToken: System.Threading.CancellationToken; readonly; public;
    property IsRequestBeingRedirected: Boolean read assembly write; public;
    property RedirectLocation: nullable String; public;
    property Output: WebResponseTextWriter := new WebResponseTextWriter(self); readonly; lazy;
    {$IF ROSDK}
    {$ELSE}
    property OutputStream: Stream := new WebResponseOutputStream(self); readonly; lazy;
    {$ENDIF}
    //property Filter: System.IO.Stream; public;
    property SuppressContent: Boolean; public;
    property Status: String read GetStatus write SetStatus; public;
    //property Buffer: Boolean; public;
    //property Expires: Integer; public;
    //property ExpiresAbsolute: System.DateTime; public;
    property CacheControl: nullable String read fCacheControl write SetCacheControl; public;

  private

    fBufferedContent: not nullable MemoryStream;
    fTransmittedContent: nullable Stream;
    fStreaming: Boolean;
    fCompleted: Boolean;
    fCookiesCommitted: Boolean;
    fCacheControl: nullable String;
    fCharset: nullable String;
    fContentEncoding: Encoding;
    fStatusDescription: nullable String;

  assembly

    method WriteBytes(aBuffer: array of Byte; aOffset: Int32; aCount: Int32);
    begin
      if fCompleted then
        raise new InvalidOperationException("The HTTP response has already completed.");
      if fStreaming then
        HttpServerResponse.WriteChunk(aBuffer, aOffset, aCount)
      else
        fBufferedContent.Write(aBuffer, aOffset, aCount);
    end;

    method Complete;
    begin
      if fCompleted then
        exit;

      CommitCookies;
      if fStreaming then
        HttpServerResponse.EndChunkedResponse
      else begin
        HttpServerResponse.ContentStream := coalesce(fTransmittedContent, fBufferedContent);
        HttpServerResponse.ContentStream.Seek(0, SeekOrigin.Begin);
      end;
      fCompleted := true;
    end;

  private

    method CommitCookies;
    begin
      if fCookiesCommitted then
        exit;

      var lCookieIndex := 0;
      for each lCookieHeader in Cookies.GetCookieHeaderStrings do begin
        if lCookieIndex = 0 then
          HttpServerResponse.Header.SetHeaderValue("Set-Cookie", lCookieHeader)
        else
          HttpServerResponse.Header["Set-Cookie"].Add(lCookieHeader);
        inc(lCookieIndex);
      end;
      fCookiesCommitted := true;
    end;

    method EnsureNotStreaming(aOperation: not nullable String);
    begin
      if fStreaming then
        raise new InvalidOperationException($"Cannot {aOperation} after the HTTP response has started streaming.");
    end;

    method GetHeader(aName: String): nullable String;
    begin
      result := HttpServerResponse.Header.GetHeaderValue(aName);
    end;

    method SetStatusCode(aValue: Integer);
    begin
      HttpServerResponse.HttpCode := HttpStatusCode(aValue);
    end;

    method SetCharset(aValue: nullable String);
    begin
      fCharset := aValue;
      UpdateContentTypeHeader;
    end;

    method SetContentEncoding(aValue: Encoding);
    begin
      fContentEncoding := coalesce(aValue, Encoding.UTF8);
    end;

    method SetContentType(aValue: nullable String);
    begin
      HttpServerResponse.Header.ContentType := aValue;
      UpdateContentTypeHeader;
    end;

    method SetCacheControl(aValue: nullable String);
    begin
      fCacheControl := aValue;
      if assigned(aValue) then
        HttpServerResponse.Header.SetHeaderValue("Cache-Control", aValue);
    end;

    method GetStatus: String;
    begin
      result := $"{StatusCode} {StatusDescription}";
    end;

    method SetStatus(aValue: String);
    begin
      if length(aValue) = 0 then
        exit;

      var lSplit := aValue.SplitAtFirstOccurrenceOf(" ");
      if lSplit.Count > 0 then begin
        with matching lStatusCode := Convert.TryToInt32(lSplit[0]) do
          StatusCode := lStatusCode;
      end;
      if lSplit.Count = 2 then
        StatusDescription := lSplit[1];
    end;

    method GetStatusDescription: String;
    begin
      result := coalesce(fStatusDescription, HttpServerResponse.ResponseText);
    end;

    method UpdateContentTypeHeader;
    begin
      var lContentType := HttpServerResponse.Header.ContentType;
      if length(lContentType) = 0 then
        exit;

      var lBaseType := lContentType.SplitAtFirstOccurrenceOf(";")[0].Trim;
      if length(Charset) > 0 then
        HttpServerResponse.Header.ContentType := $"{lBaseType}; charset={Charset}"
      else
        HttpServerResponse.Header.ContentType := lBaseType;
    end;

  end;

end.
