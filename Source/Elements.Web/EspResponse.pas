namespace RemObjects.Elements.Web;

uses
  RemObjects.InternetPack.Http;

type
  WebResponse = public class
  public
    constructor(aResponse: HttpServerResponse);
    begin
      HttpServerResponse := aResponse;
      HttpServerResponse.ContentStream := new MemoryStream;
    end;

    property HttpServerResponse: HttpServerResponse; readonly;
    property Encoding: Encoding := Encoding.UTF8;

    //
    //
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

    //method &Write(aChar: Char);
    //begin
      //&Write(aChar.ToString);
      //HttpServerResponse.ContentStream.Write([aChar], 1);
    //end;

    method &Write(aObject: Object);
    begin
      &Write(aObject.ToString);
    end;

// System.Web, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a
// /Users/mh/Code/Fire Support/_NETFramework/v4.5/System.Web.dll

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
    //method Redirect(url: String; endResponse: Boolean); public;
    method Redirect(url: String);
    begin

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

    method RedirectPermanent(aUrl: String; aShouldEndResponse: Boolean);
    begin

    end;

    method RedirectPermanent(aUrl: String);
    begin
      RedirectPermanent(aUrl, true);
    end;

    //method &Write(buffer: array of Char; &index: Integer; count: Integer); public;
    //method &Write(ch: Char); public;
    //method &Write(obj: Object); public;
    //method &Write(s: String); public;
    //method WriteSubstitution(callback: System.Web.HttpResponseSubstitutionCallback); public;
    //method WriteFile(fileHandle: IntPtr; offset: Int64; size: Int64); public;
    //method WriteFile(filename: String; offset: Int64; size: Int64); public;
    //method WriteFile(filename: String; readIntoMemory: Boolean); public;
    //method WriteFile(filename: String); public;

    //method TransmitFile(aFileName: String; aOffset: Int64; aLength: Int64); public;
    //begin
      //using s := new FileStream(aFileName, FileOpenMode.ReadOnly) do
        //HttpServerResponse.ContentStream.Write(s, aOffset, aLength);
    //end;

    method TransmitFile(aFileName: String); public;
    begin
      var b := File.ReadBytes(aFileName);
      HttpServerResponse.ContentStream.Write(b, 0, length(b));
      //using s := new FileStream(aFileName, FileOpenMode.ReadOnly) do
        //HttpServerResponse.ContentStream.Write(s);
    end;

    method AddHeader(aName: String; aValue: String);
    begin
      HttpServerResponse.Header.SetHeaderValue(aName, aValue);
    end;

    method &End; public;
    begin

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