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

    event Init: EventHandler;
    event Load: EventHandler;
    event UnLoad: EventHandler;

    method Initialize(e: EventArgs); assembly;
    begin
      OnInit(e);
    end;

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

    method OnInit(e: EventArgs); virtual;
    begin
      if assigned(Init) then
        Init(self, e);
    end;

    method CreateDelegate(aInstance: not nullable Object; aMethod: not nullable &Method): not nullable EventHandler;
    begin
      {$IF ECHOES}
      result := &Delegate.CreateDelegate(EventHandler, self, aMethod) as EventHandler;
      {$ELSEIF COOPER}
      var lJavaMethod := java.lang.reflect.Method(aMethod);
      lJavaMethod.setAccessible(true);
      result := (aSender, aEventArgs) -> begin
        lJavaMethod.invoke(aInstance, [aSender, aEventArgs]);
      end;
      {$ELSEIF ISLAND}
      result := Utilities.NewDelegate(System.Type(typeOf(aInstance)).RTTI, self, System.MethodInfo(aMethod).Pointer) as RemObjects.InternetPack.EventHandler;
      {$ELSE}
      {$ERROR Platform not supported}
      {$ENDIF}
    end;

    method AutoEventWireup;
    begin
      with matching lMethod := FindAutoEventHandler("Page_Init") do
        Init += CreateDelegate(self, lMethod);
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
      {$ELSEIF COOPER}
      var lType := java.lang.Class(typeOf(self));
      while assigned(lType) do begin
        for each lMethod in lType.getDeclaredMethods() do begin
          if caseInsensitive(String(lMethod.getName())) = caseInsensitive(aName) then
            exit &Method(lMethod);
        end;
        lType := lType.getSuperclass();
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

  Panel = public class(Control)
  public
    constructor;
    begin
      Visible := true;
    end;

    property CssClass: nullable String;

    method RenderBegin;
    begin
      if length(CssClass) > 0 then
        Response.Write(##"""<div id="{{HttpUtility.HtmlEncode(ID)}}" class="{{HttpUtility.HtmlEncode(CssClass)}}">""")
      else
        Response.Write(##"""<div id="{{HttpUtility.HtmlEncode(ID)}}">""");
    end;

    method RenderEnd;
    begin
      Response.Write(##"""</div>""");
    end;
  end;

  Page = public class(UserControl)
  public
    property Header: WebPageHeader read begin
      if assigned(Context:Page) and (Context.Page <> self) then
        exit Context.Page.Header;

      if not assigned(fHeader) then
        fHeader := new WebPageHeader;

      result := fHeader;
    end;

    property Title: String read Header:Title write Header:Title;
    property Master: MasterPage;
    property Items: WebContextItems read Context.Items;

    property Head: WebPageHeader read Header; {$HINT really?}

  private
    fHeader: WebPageHeader;

  end;

  WebPageReflection = assembly static class
  public

    class method GetStringProperty(aPage: nullable Page; aName: not nullable String): nullable String;
    begin
      if not assigned(aPage) then
        exit;

      {$IF ECHOES}
      var lFlags := System.Reflection.BindingFlags.Instance or
                    System.Reflection.BindingFlags.Public or
                    System.Reflection.BindingFlags.NonPublic;
      for each lProperty in aPage.GetType.GetProperties(lFlags) do begin
        if lProperty.Name = aName then begin
          with matching lValue := String(lProperty.GetValue(aPage, nil)) do
            if length(lValue) > 0 then
              exit lValue;
        end;
      end;
      {$ELSEIF COOPER}
      var lGetterName := "get_"+aName;
      var lJavaGetterName := "get"+aName;
      for each lMethod in typeOf(aPage).Methods do begin
        if (lMethod.Name = lGetterName) or (lMethod.Name = lJavaGetterName) then begin
          var lJavaMethod := java.lang.reflect.Method(lMethod);
          lJavaMethod.setAccessible(true);
          with matching lValue := String(lJavaMethod.invoke(aPage, [])) do
            if length(lValue) > 0 then
              exit lValue;
        end;
      end;
      {$ELSEIF ISLAND}
      for each lProperty in typeOf(aPage).Properties do begin
        if lProperty.Name = aName then begin
          with matching lValue := String(lProperty.GetValue(aPage, [])) do
            if length(lValue) > 0 then
              exit lValue;
        end;
      end;
      {$ELSE}
      {$ERROR Platform not supported}
      {$ENDIF}
    end;

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
      constructor(aRequest, aResponse, nil);
    end;

    constructor(aRequest: WebRequest; aResponse: WebResponse; aFactory: nullable WebPageFactory);
    begin
      Request := aRequest;
      aRequest.Context := self;
      Response := aResponse;
      PageFactory := aFactory;
      Lifetime := coalesce(aFactory:Lifetime, WebApplicationLifetime.Default);
    end;

    property Error: nullable Exception read assembly write;
    property Page: Page read Request.Page;
    property Request: WebRequest; readonly;
    property Response: WebResponse; readonly;
    property Session: WebSessionState read GetSession write fSession;
    property PageFactory: nullable WebPageFactory; readonly;
    property Lifetime: not nullable WebApplicationLifetime; readonly;
    property Items: WebContextItems := new WebContextItems; readonly; lazy;
    property Server: WebServerForContext;

    class property Current: nullable WebContext read GetCurrent write SetCurrent;

  private

    fSession: nullable WebSessionState;

    method GetSession: WebSessionState;
    begin
      if not assigned(fSession) then begin
        var lCreated: Boolean;
        fSession := Lifetime.Sessions.FindOrCreateSession(self, out lCreated);
        if lCreated then
          Lifetime.NotifySessionStart(self);
      end;
      result := fSession;
    end;

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

    class method OpenFile(aVirtualPath: not nullable String): nullable Stream;
    begin
      result := WebContext.Current:Server:OpenFile(aVirtualPath);
    end;

    class method ReadTextFile(aVirtualPath: not nullable String): nullable String;
    begin
      using lStream := OpenFile(aVirtualPath) do begin
        if not assigned(lStream) then
          exit;
        if lStream.Length > Consts.MaxInt32 then
          raise new IOException($"Web resource '{aVirtualPath}' is too large to read as text.");

        var lBytes := new Byte[Integer(lStream.Length)];
        var lOffset := 0;
        while lOffset < length(lBytes) do begin
          var lRead := lStream.Read(lBytes, lOffset, length(lBytes)-lOffset);
          if lRead = 0 then
            break;
          inc(lOffset, lRead);
        end;
        result := Encoding.UTF8.GetString(lBytes, 0, lOffset);
      end;
    end;

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

  WebApplicationLifetime = public class
  public

    class property Default: not nullable WebApplicationLifetime := new WebApplicationLifetime; readonly;
    class property Current: nullable WebApplicationLifetime read fCurrent write fCurrent; assembly;

    constructor;
    begin
      Sessions.Owner := self;
    end;

    method EnsureStarted(aFactory: nullable WebPageFactory; aContext: not nullable WebContext);
    begin
      locking fApplicationMonitor do begin
        if assigned(fStartFailure) then
          raise fStartFailure;
        if fStarted or fEnded then
          exit;
        fStarted := true;
        try
          fApplication := aFactory:CreateApplication;
          if assigned(fApplication) then begin
            var lPreviousLifetime := Current;
            Current := self;
            fApplication.Context := aContext;
            try
              fApplication.OnStart;
            finally
              fApplication.Context := nil;
              Current := lPreviousLifetime;
            end;
          end;
        except
          on E: Exception do begin
            fStartFailure := E;
            raise;
          end;
        end;
      end;
    end;

  assembly

    property Sessions := new SessionManager; readonly;
    property Values := new WebApplicationValues; readonly;

    method NotifySessionStart(aContext: not nullable WebContext);
    begin
      locking fApplicationMonitor do
        if assigned(fApplication) and not fEnded then begin
          var lPreviousLifetime := Current;
          var lPreviousContext := fApplication.Context;
          Current := self;
          fApplication.Context := aContext;
          try
            fApplication.OnSessionStart;
          finally
            fApplication.Context := lPreviousContext;
            Current := lPreviousLifetime;
          end;
        end;
    end;

    method NotifySessionEnd(aSession: not nullable WebSessionState);
    begin
      locking fApplicationMonitor do
        if assigned(fApplication) then begin
          var lPreviousLifetime := Current;
          var lPreviousContext := fApplication.Context;
          var lPreviousSession := fApplication.EventSession;
          Current := self;
          fApplication.Context := nil;
          fApplication.EventSession := aSession;
          try
            try
              fApplication.OnSessionEnd;
            except
              on E: Exception do
                Log($"ESP Session_End failed: {E}");
            end;
          finally
            fApplication.EventSession := lPreviousSession;
            fApplication.Context := lPreviousContext;
            Current := lPreviousLifetime;
          end;
        end;
    end;

    method NotifyError(aContext: not nullable WebContext; aError: not nullable WebErrorContext);
    begin
      locking fApplicationMonitor do
        if assigned(fApplication) then begin
          var lPreviousLifetime := Current;
          var lPreviousContext := fApplication.Context;
          Current := self;
          fApplication.Context := aContext;
          try
            fApplication.OnError(aError);
          finally
            fApplication.Context := lPreviousContext;
            Current := lPreviousLifetime;
          end;
        end;
    end;

    method EndApplication;
    begin
      locking fApplicationMonitor do begin
        if fEnded then
          exit;
        fEnded := true;
        Sessions.EndAll;
        if assigned(fApplication) then begin
          var lPreviousLifetime := Current;
          Current := self;
          fApplication.Context := nil;
          try
            try
              fApplication.OnEnd;
            except
              on E: Exception do
                Log($"ESP Application_End failed: {E}");
            end;
          finally
            Current := lPreviousLifetime;
          end;
        end;
        fApplication := nil;
      end;
    end;

    method Retain;
    begin
      locking fApplicationMonitor do
        inc(fUsers);
    end;

    method Release;
    begin
      var lEnd := false;
      locking fApplicationMonitor do begin
        dec(fUsers);
        lEnd := fUsers = 0;
      end;
      if lEnd then
        EndApplication;
    end;

  private

    fApplicationMonitor := new Monitor;
    fApplication: nullable WebApplication;
    fStartFailure: nullable Exception;
    fStarted: Boolean;
    fEnded: Boolean;
    fUsers: Integer;

    {$IF ECHOES}
    [System.ThreadStatic]
    {$ENDIF}
    class var fCurrent: nullable WebApplicationLifetime;

  end;

  Application = public static class
  public

    property Values[aName: String]: nullable Object read CurrentValues[aName] write CurrentValues[aName]; default;
    property Keys: sequence of String read CurrentValues.Keys;

    method RemoveAll;
    begin
      CurrentValues.RemoveAll;
    end;

  private

    class property CurrentValues: WebApplicationValues read coalesce(WebApplicationLifetime.Current, WebContext.Current:Lifetime,
      WebApplicationLifetime.Default).Values;

  end;

  WebApplicationValues = assembly class
  public

    property Values[aName: String]: nullable Object read locking fMonitor do fValues[aName] write SetValue; default;
    property Keys: sequence of String read locking fMonitor do fValues.Keys.UniqueCopy;

    method RemoveAll;
    begin
      locking fMonitor do
        fValues.RemoveAll;
    end;

  private

    var fValues := new Dictionary<String,Object>; readonly;
    var fMonitor := new Monitor; readonly;

    method SetValue(aName: String; aValue: nullable Object);
    begin
      locking fMonitor do
        fValues[aName] := aValue;
    end;
  end;


  BuildTemplateMethod = public block(aContainer: Control);

end.
