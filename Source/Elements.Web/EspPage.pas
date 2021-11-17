namespace RemObjects.Elements.Web;

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

    property Visible: Boolean;
    property Page: Page;

    property ContentTemplates: ImmutableDictionary<String, CompiledTemplateBuilder> read fContentTemplates; readonly;
    method AddContentTemplate(aName: String; aBuilder: CompiledTemplateBuilder);
    begin
      fContentTemplates[aName] := aBuilder;
    end;

    method RenderControl(__Container: RemObjects.Elements.Web.Control); virtual;
    begin

    end;

  private
    fContentTemplates := new Dictionary<String, CompiledTemplateBuilder>;
  end;

  UserControl = public class(Control)
  end;

  Page = public class(UserControl)
  public
    property Title: String;
    property Master: MasterPage;

    property Head: PageHead;
  end;

  Master = public class(Page)  // ??
  public

  end;

  MasterPage = public class(Page)
  public

  end;

  PageHead = public class
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
    end;

    property Request: WebRequest; readonly;
    property Response: WebResponse; readonly;
    property Session: WebSessionState;
    property Server: WebServer;
  end;

  WebSessionState = public class
  public
    property Values[aName: String]: Object read nil write nil; default; {$HINT TODO}
    method Abandon;
    begin

    end;
  end;

  WebCookie = public class
  public
    property Domain: String;
    property Secure: Boolean;
    property Expires: DateTime;
    property Values[aName: String]: String read nil write nil; default;
  end;

  ImmutableWebCookieCollection = public class
  public

    property Cookies[aName: String]: WebCookie read nil; default;

  end;

  WebCookieCollection = public class(ImmutableWebCookieCollection)
  public

    //property Cookies[aName: String]: String read nil; default;

    method &Add(aCookie: WebCookie);
    begin

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
    property Values[aName: String]: Object read nil write nil; default;
    property Keys: sequence of String read nil;

    method RemoveAll;
    begin

    end;
  end;


  BuildTemplateMethod = public block(aContainer: Control);

end.