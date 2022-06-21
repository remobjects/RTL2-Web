namespace RemObjects.Elements.Web;

uses
  RemObjects.InternetPack,
  RemObjects.InternetPack.Http;

type
  WebResponse = public class
  public
    constructor(aResponse: HttpServerResponse);
    begin
      HttpServerResponse := aResponse;
      HttpServerResponse.ContentStream := new MemoryStream;
      Cookies := new WebCookieCollection;
    end;

    property HttpServerResponse: HttpServerResponse; readonly;
    property Encoding: Encoding := Encoding.UTF8;

    //
    // Writing content
    //

    method &Write(aString: nullable String);
    begin
      if assigned(aString) then begin
        var lBytes := Encoding.GetBytes(aString) includeBOM(false);
        HttpServerResponse.ContentStream.Write(lBytes, length(lBytes));
      end;
      //HttpServerResponse.ContentStream.Flush;
      //HttpServerResponse.ContentString := HttpServerResponse.ContentString+aString;
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
      var lBytes := File.ReadBytes(aFileName);
      HttpServerResponse.ContentStream.Write(lBytes, aOffset, aSize);
    end;

    method WriteFile(aFileName: not nullable String; aShouldReadIntoMemory: Boolean); public;
    begin
      //if aShouldReadIntoMemory then begin
        var lBytes := File.ReadBytes(aFileName);
        HttpServerResponse.ContentStream.Write(lBytes);
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
      HttpServerResponse.ContentStream := new FileStream(aFileName, FileOpenMode.ReadOnly);
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
      HttpServerResponse.ContentStream.Write(buffer, length(buffer));
    end;

    //method Pics(value: String); public;
    method AppendHeader(aName: String; aValue: String);
    begin
      HttpServerResponse.Header.SetHeaderValue(aName, aValue);
    end;

    //method AppendCookie(cookie: System.Web.HttpCookie); public;
    //method SetCookie(cookie: System.Web.HttpCookie); public;
    //method ClearHeaders;
    //begin
      //HttpServerResponse.Header.
    //end;

    method ClearContent;
    begin
      HttpServerResponse.ContentStream := new MemoryStream;
    end;

    method Clear;
    begin
      // nedds to clear more? Cookies & co maybe?
      HttpServerResponse.ContentStream := new MemoryStream;
    end;

    method Flush;
    begin

    end;
    //method AppendToLog(&param: String); public;
    method Redirect(aUrl: String; aShouldEndResponse: Boolean);
    begin
      Log($"Redirecting to {aUrl}");
      HttpServerResponse.HttpCode := HttpStatusCode.MovedPermanently;
      HttpServerResponse.Header.SetHeaderValue("Location", aUrl);
      HttpServerResponse.ContentString := $"<head><title>Document PermanentlyMoved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a href=""{aUrl}"">here</a>.</p></body>";
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
      HttpServerResponse.HttpCode := HttpStatusCode.MovedPermanently;
      HttpServerResponse.Header.SetHeaderValue("Location", aUrl);
      HttpServerResponse.ContentString := $"<head><title>Document Moved</title></head><body><h1>Object Moved.</h1><p>This document may be found <a href=""{aUrl}"">here</a>.</p></body>";
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
      HttpServerResponse.Header.SetHeaderValue(aName, aValue);
    end;

    method &End; public;
    begin
      raise new CleanlyEndResponseException;
    end;

    //method ApplyAppPathModifier(virtualPath: String): String; public;
    //property SupportsAsyncFlush: Boolean; readonly; public;
    property Cookies: WebCookieCollection; readonly; public;
    //property Headers: System.Collections.Specialized.NameValueCollection; readonly; public;
    property StatusCode: Integer read HttpServerResponse.Code write HttpServerResponse.Code;
    //property SubStatusCode: Integer; public;
    //property StatusDescription: String; public;
    //property TrySkipIisCustomErrors: Boolean; public;
    //property SuppressFormsAuthenticationRedirect: Boolean; public;
    //property BufferOutput: Boolean; public;
    property ContentType: String read HttpServerResponse.Header["Content-Type"].Value write nil; {$HINT TODO}
    //property Charset: String; public;
    //property ContentEncoding: System.Text.Encoding; public;
    //property HeaderEncoding: System.Text.Encoding; public;
    //property Cache: System.Web.HttpCachePolicy; readonly; public;
    //property IsClientConnected: Boolean; readonly; public;
    //property ClientDisconnectedToken: System.Threading.CancellationToken; readonly; public;
    //property IsRequestBeingRedirected: Boolean read assembly write; public;
    //property RedirectLocation: String; public;
    //property Output: System.IO.TextWriter; public;
    property OutputStream: Stream read HttpServerResponse.ContentStream;
    //property Filter: System.IO.Stream; public;
    //property SuppressContent: Boolean; public;
    //property Status: String; public;
    //property Buffer: Boolean; public;
    //property Expires: Integer; public;
    //property ExpiresAbsolute: System.DateTime; public;
    //property CacheControl: String; public;

  end;

end.