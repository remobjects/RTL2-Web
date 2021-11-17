namespace RemObjects.Elements.Web;

uses
  RemObjects.InternetPack.Http;

type
  WebRequest = public class
  public
    constructor(aRequest: HttpServerRequest; aPage: Page; aUrl: Url);
    begin
      HttpServerRequest := aRequest;
      Page := aPage;
      Url := aUrl;
    end;

    property HttpServerRequest: HttpServerRequest; readonly;
    property Page: Page; readonly;




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
    //method GetBufferedInputStream: System.IO.Stream; public;
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
    //property UserAgent: String read HttpServerRequest.UserAgent;
    //property UserLanguages: array of String; readonly; public;
    //property Browser: System.Web.HttpBrowserCapabilities; public;
    property UserHostName: String; readonly; public;
    property UserHostAddress: String; readonly; public;
    //property RawUrl: String read assembly write; public;
    property Url: Url; readonly; public;
    property UrlReferrer: Url; readonly; public;
    //property &Params: System.Collections.Specialized.NameValueCollection; readonly; public;
    //property Item[key: String]: String; readonly; public; default;
    property QueryString[aValue: String]: String read HttpServerRequest.QueryString[aValue];
    property QueryString: String read HttpServerRequest.QueryString.ToString;
    property Form[aValue: String]: String read ""; {$HINT TODO}
    property Form: String read ""; {$HINT TODO}
    property Headers[aValue: String]: String read HttpServerRequest.Header[aValue].Value; {$HINT TODO}
    //property Unvalidated: System.Web.UnvalidatedRequestValues; readonly; public;
    property ServerVariables[aValue: String]: String read ""; {$HINT TODO}
    property Cookies: ImmutableWebCookieCollection; readonly; public;
    //property Files: System.Web.HttpFileCollection; readonly; public;
    property InputStream: Stream read HttpServerRequest.ContentStream;
    property TotalBytes: nullable Integer read if HttpServerRequest.HasContentLength then HttpServerRequest.ContentLength;
    //property Filter: System.IO.Stream; public;
    //property ClientCertificate: System.Web.HttpClientCertificate; readonly; public;
    //property LogonUserIdentity: System.Security.Principal.WindowsIdentity; readonly; public;
    //property HttpChannelBinding: System.Security.Authentication.ExtendedProtection.ChannelBinding; readonly; public;
    //property ReadEntityBodyMode: System.Web.ReadEntityBodyMode; readonly; public;
    //property TimedOutToken: System.Threading.CancellationToken; readonly; public;

  end;

end.