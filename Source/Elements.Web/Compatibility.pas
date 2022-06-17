namespace RemObjects.Elements.Web;

type
  System.Web.UI.Control = public Control;
  System.Web.UI.UserControl = public UserControl;
  System.Web.UI.Page = public Page;
  System.Web.UI.MasterPage = public MasterPage;

  System.Web.HttpUtility = public HttpUtility;

  System.Web.HttpContext = public WebContext;
  System.Web.HttpBrowserCapabilities = public WebBrowserCapabilities;

  System.Web.IHttpHandler = public IHttpHandler;

  System.Web.SessionState.IRequiresSessionState = public interface
  end;

  {$IF NOT ECHOES}
  RemObjects.Elements.System.EventArgs = public class
  end;
  {$ENDIF}

  System.Configuration.Dummy = public Int32;

  System.Web.Security.Dummy = public Int32;
  //System.Web.SessionState.Dummy = public Int32;
  //System.Web.UI.Dummy = public Int32;
  System.Web.UI.WebControls.Dummy = public Int32;
  System.Web.UI.WebControls.WebParts.Dummy = public Int32;
  System.Web.UI.HtmlControls.Dummy = public Int32;

  System.Web.UI.PersistChildrenAttribute = public class(Attribute)
  public
    constructor(aPersistChildren: Boolean); empty;
  end;

  System.Web.UI.ParseChildrenAttribute = public class(Attribute)
  public
    constructor(aParseChildren: Boolean); empty;
    constructor(aParseChildren: Boolean; aName: String); empty;
  end;

  System.Web.UI.PersistenceModeAttribute = public class(Attribute)
  public
    constructor(aMode: System.Web.UI.PersistenceMode); empty;
  end;

  System.Web.UI.PersistenceMode = public enum (Attribute = 0, InnerProperty = 1, InnerDefaultProperty = 2, EncodedInnerDefaultProperty = 3);

  //
  // System.Web.Services (not implemented, just to make them compile)
  //

  System.Web.Services.WebService = public class
  public
    constructor; empty;
  end;

  System.Web.Services.WebServiceAttribute = public class(Attribute)
  public
    property &Namespace: String;
  end;

  System.Web.Services.WebMethodAttribute = public class(Attribute)
  public
  end;

end.