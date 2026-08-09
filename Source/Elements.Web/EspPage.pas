namespace RemObjects.Elements.Web;

uses
  RemObjects.Elements.RTL.Reflection;

type
  //Control = public System.Web.UI.Control;
  //Page = public System.Web.UI.Page;
  //MasterPage = public System.Web.UI.MasterPage;

  //HtmlTextWriter = public System.Web.UI.HtmlTextWriter;
  //CompiledTemplateBuilder = public System.Web.UI.CompiledTemplateBuilder;
  //BuildTemplateMethod = public System.Web.UI.BuildTemplateMethod;

  IHttpHandler = public interface
    method ProcessRequest(Context: WebContext);
    property IsReusable: Boolean read false;
  end;

  Control = public class
  public

    property Context: WebContext;
    property Request: WebRequest read Context.Request;
    property Response: WebResponse read Context.Response;
    property Session: WebSessionState read Context.Session;

    property ID: String;
    property Visible: Boolean;
    property Page: Page read Context.Page;
    property Parent: Control; // todo
    property Server: WebServerForContext read Context.Server;

    property ContentTemplates: ImmutableDictionary<String, CompiledTemplateBuilder> read fContentTemplates; readonly;
    method AddContentTemplate(aName: String; aBuilder: CompiledTemplateBuilder);
    begin
      fContentTemplates[aName] := aBuilder;
    end;

    method RenderControl(__Container: RemObjects.Elements.Web.Control); virtual;
    begin

    end;

    event Load: EventHandler;
    event UnLoad: EventHandler;

    method OnLoad(e: EventArgs); public; virtual;
    begin
      if assigned(Load) then
        Load(self, e);
    end;

    method OnUnLoad(e: EventArgs); public; virtual;
    begin
      if assigned(UnLoad) then
        UnLoad(self, e);
    end;

  protected

    method CreateDelegate(aInstance: not nullable Object; aMethod: not nullable &Method): not nullable EventHandler;
    begin
      {$IF ECHOES}
      result := &Delegate.CreateDelegate(EventHandler, self, aMethod) as EventHandler;
      {$ELSEIF ISLAND}
      result := Utilities.NewDelegate(System.Type(typeOf(aInstance)).RTTI, self, System.MethodInfo(aMethod).Pointer) as RemObjects.InternetPack.EventHandler;
      {$ENDIF}
    end;

    method AutoEventWireup;
    begin
      with matching lMethod := FindAutoEventHandler("Page_Load") do
        Load += CreateDelegate(self, lMethod);
      with matching lMethod := FindAutoEventHandler("Page_UnLoad") do
        UnLoad += CreateDelegate(self, lMethod);
    end;

    method FindAutoEventHandler(aName: not nullable String): nullable &Method;
    begin
      {$IF ECHOES}
      var lType := System.Type(typeOf(self));
      while assigned(lType) do begin
        var lFlags := System.Reflection.BindingFlags.Instance or
                      System.Reflection.BindingFlags.Public or
                      System.Reflection.BindingFlags.NonPublic or
                      System.Reflection.BindingFlags.DeclaredOnly;
        for each lMethod in lType.GetMethods(lFlags) do begin
          if caseInsensitive(lMethod.Name) = caseInsensitive(aName) then
            exit &Method(lMethod);
        end;
        lType := lType.BaseType;
      end;
      {$ELSEIF ISLAND}
      var lType := typeOf(self);
      while assigned(lType) do begin
        for each lMethod in lType.Methods do begin
          if caseInsensitive(lMethod.Name) = caseInsensitive(aName) then
            exit lMethod;
        end;
        lType := lType.BaseType;
      end;
      {$ENDIF}
    end;

  private
    fContentTemplates := new Dictionary<String, CompiledTemplateBuilder>;
  end;

  UserControl = public class(Control)
  end;

  Page = public class(UserControl)
  public
    property Header: WebPageHeader :=  new WebPageHeader(); readonly; lazy;

    property Title: String read Header:Title write Header:Title;
    property Master: MasterPage;

    property Head: WebPageHeader read Header; {$HINT really?}
  end;

  Master = public class(Page)  // ??
  public

  end;

  MasterPage = public class(Page)
  public

  end;

  WebPageHeader = public class
  public
    property Title: String;
  end;




  //WebSessionState = public System.Web.SessionState.HttpSessionState;
  //HttpContext = public System.Web.HttpContext;
  //HtmlTextWriter = public System.Web.UI.HtmlTextWriter;

  WebContextItems = public class
  public
    property Item[aName: not nullable Object]: nullable Object read fValues[aName] write SetValue; default;
    property Keys: sequence of Object read fValues.Keys;
    property Count: Integer read fValues.Count;

    method Clear;
    begin
      fValues.RemoveAll;
    end;

    method Remove(aName: not nullable Object);
    begin
      fValues[aName] := nil;
    end;

  private
    fValues := new Dictionary<Object,Object>;

    method SetValue(aName: not nullable Object; aValue: nullable Object);
    begin
      fValues[aName] := aValue;
    end;
  end;

  WebContext = public class
  public
    constructor(aRequest: WebRequest; aResponse: WebResponse);
    begin
      Request := aRequest;
      Response := aResponse;
      Session := SessionManager.FindOrCreateSession(self);
    end;

    property Page: Page read Request.Page;
    property Request: WebRequest; readonly;
    property Response: WebResponse; readonly;
    property Session: WebSessionState;
    property Items: WebContextItems := new WebContextItems; readonly; lazy;
    property Server: WebServerForContext;

    class property Current: nullable WebContext read GetCurrent write SetCurrent;

  private

    {$IF ECHOES}
    [System.ThreadStatic]
    {$ENDIF}
    class var fCurrent: nullable WebContext;

    class method GetCurrent: nullable WebContext;
    begin
      result := fCurrent;
    end;

    class method SetCurrent(aValue: nullable WebContext);
    begin
      fCurrent := aValue;
    end;
  end;

  WebRuntime = public static class
  public

    class property AppDomainAppPath: nullable String read GetAppDomainAppPath;
    class property AppDomainAppVirtualPath: String read GetAppDomainAppVirtualPath;

  private

    class method GetAppDomainAppPath: nullable String;
    begin
      result := WebContext.Current:Server:PhysicalApplicationPath;
    end;

    class method GetAppDomainAppVirtualPath: String;
    begin
      result := coalesce(WebContext.Current:Server:ApplicationPath, "/");
    end;
  end;

  CompiledTemplateBuilder = public class
  public
    constructor(aBuildTemplateMethod: BuildTemplateMethod);
    begin
      fBuildTemplateMethod := aBuildTemplateMethod;
    end;

    method RenderControl(aContainer: Control);
    begin
      fBuildTemplateMethod(aContainer);
    end;

    property Context: WebContext; assembly;

  private
    fBuildTemplateMethod: BuildTemplateMethod;
  end;

  Application = public static class
  public

    property Values[aName: String]: nullable Object read locking fMonitor do fValues[aName] write SetValue; default;
    property Keys: sequence of String read locking fMonitor do fValues.Keys.UniqueCopy;

    method RemoveAll;
    begin
      locking fMonitor do
        fValues.RemoveAll;
    end;

  private

    class var fValues := new Dictionary<String,Object>; readonly;
    class var fMonitor := new Monitor; readonly;

    class method SetValue(aName: String; aValue: nullable Object);
    begin
      locking fMonitor do
        fValues[aName] := aValue;
    end;
  end;


  BuildTemplateMethod = public block(aContainer: Control);

end.
