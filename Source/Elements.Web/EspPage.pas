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

    method AutoEventWireup;
    begin
      //Log($"AutoEventWireup for {typeOf(self).Name}");

      for each m in typeOf(self).Methods do begin
        //var p := m.Name.LastIndexOf("_");
        //if p > 0 then begin
          //var lName := m.Name.Substring(p+1);
          case caseInsensitive(m.Name) of
            //"Page_PreInit": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_Init": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_InitComplete": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_PreLoad": Load += (s, e) -> m.Invoke(self, [s,e]);
            "Page_Load": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_LoadComplete": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_PreRender": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_PreRenderComplete": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_SaveStateComplete": Load += (s, e) -> m.Invoke(self, [s,e]);
            //"Page_Render": Load += (s, e) -> m.Invoke(self, [s,e]);
            "Page_UnLoad": UnLoad += (s, e) -> m.Invoke(self, [s,e]);
          end;
        //end;
      end;

      //var lMethod := typeOf(self).GetMethod("Page_Load", System.Reflection.BindingFlags.NonPublic or System.Reflection.BindingFlags.IgnoreCase or System.Reflection.BindingFlags.FlattenHierarchy);
        //if assigned(lMethod) and (lMethod.GetParameters.Count = 2) then begin
          //Log($"lMethod {lMethod}");
          //lMethod.Invoke(self, [self, e]);
        //end
        //else begin
          //Log($"No Page_Load found {lMethod}");
        //end;
      //end;

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

  WebContext = public class
  public
    constructor(aRequest: WebRequest; aResponse: WebResponse);
    begin
      Request := aRequest;
      Response := aResponse;
      Session := WebSessionState.FinfOrCreateSession(self);
    end;

    property Page: Page read Request.Page;
    property Request: WebRequest; readonly;
    property Response: WebResponse; readonly;
    property Session: WebSessionState;
    property Server: WebServerForContext;

  private



  end;

  WebSessionState = public class
  public

    property Expires: not nullable DateTime read private write := DateTime.UtcNow.AddMinutes(ESP_SESSION_EXPIRATION_MINUTES);
    property IsExpired: Boolean read Expires < DateTime.UtcNow;
    property Item[aName: not nullable String]: nullable Object read fSessionState[aName] write SetSessionState; default;

    method Abandon;
    begin

    end;

    method Clear;
    begin
      fSessionState.RemoveAll;
    end;

  assembly

    constructor(aSessionID: String; aContext: WebContext);
    begin
    end;

    method ExtendSession;
    begin
      Expires := DateTime.UtcNow.AddMinutes(ESP_SESSION_EXPIRATION_MINUTES);
    end;

    class var fActiveSessions := new Dictionary<String,WebSessionState>; readonly;

    class method FinfOrCreateSession(aContext: not nullable WebContext): not nullable WebSessionState;
    begin
      var lSessionID := aContext.Request.Cookies[ESP_SESSION_ID_COOKIE_NAME]:Values["ID"];
      if assigned(lSessionID) then begin
        Log($"Looking for session with id {lSessionID}");
        var lSession := locking fActiveSessions do fActiveSessions[lSessionID];
        if assigned(lSession) then begin
          if not lSession:IsExpired then begin
            lSession.ExtendSession;
            result := lSession;
          end
          else begin
            locking fActiveSessions do
              fActiveSessions[lSessionID] := nil;
          end;
        end;
      end;

      if not assigned(result) then begin
        lSessionID := Guid.NewGuid.ToString(GuidFormat.Default);
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME]["ID"] := lSessionID;
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME].Expires := DateTime.UtcNow.AddMinutes(ESP_SESSION_EXPIRATION_MINUTES);
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME].Domain := aContext.Request.Url.Host;
        result := new WebSessionState(lSessionID, aContext);
        locking fActiveSessions do
          fActiveSessions[lSessionID] := result;
        Log($"Created new session for id {lSessionID}");
      end;
    end;

    class method ExpireSessions;
    begin
      for each k in fActiveSessions.Keys.UniqueCopy do
        if fActiveSessions[k].IsExpired then
          locking fActiveSessions do
            fActiveSessions[k] := nil;
    end;

  private

    fSessionState := new Dictionary<String,Object>;

    method SetSessionState(aName: not nullable String; aValue: nullable Object);
    begin
      fSessionState[aName] := aValue;
      // todo: persist?
    end;

    const ESP_SESSION_EXPIRATION_MINUTES = 10;
    const ESP_SESSION_ID_COOKIE_NAME = "ESP_SessionID";

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
    property Values[aName: String]: Object read nil write nil; default;
    property Keys: sequence of String read nil;

    method RemoveAll;
    begin

    end;
  end;


  BuildTemplateMethod = public block(aContainer: Control);

end.