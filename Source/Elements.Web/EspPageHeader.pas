namespace RemObjects.Elements.Web;

type
  WebPageHeader = public class(Control)
  public

    constructor;
    begin
      Visible := true;
    end;

    property Title: String;
    property Attributes: WebNameValueCollection := new WebNameValueCollection(true); readonly;
    property Controls: List<Control> := new List<Control>; readonly;

    method RegisterTemplate(aOwner: not nullable Control);
    begin
      if assigned(fOwner) and (fOwner <> aOwner) then
        raise new InvalidOperationException("A page can contain only one server head.");
      fOwner := aOwner;
      Parent := aOwner;
    end;

    method SetDefaultTitle(aTitle: String);
    begin
      if not assigned(Title) then
        Title := HttpUtility.HtmlDecode(aTitle);
    end;

    method SetDefaultAttribute(aName: String; aValue: String);
    begin
      case aName.ToLowerInvariant of
        "id": begin
          if not assigned(ID) then
            ID := HttpUtility.HtmlDecode(aValue);
        end;
        "visible": Visible := Convert.ToBoolean(aValue);
        "runat": ;
        else begin
          if not assigned(Attributes[aName]) then
            Attributes[aName] := HttpUtility.HtmlDecode(aValue);
        end;
      end;
    end;

    method RenderBegin;
    begin
      Response.Write("<head");
      if length(ID) > 0 then
        Response.Write(' id="'+HttpUtility.HtmlEncode(ID)+'"');
      for each lName in Attributes.Keys do
        if not (lName.ToLowerInvariant in ["runat", "id", "visible"]) then
          Response.Write(' '+lName.ToLowerInvariant+'="'+HttpUtility.HtmlEncode(Attributes[lName])+'"');
      Response.Write(">");
    end;

    method RenderTitle;
    begin
      Response.Write("<title>"+HttpUtility.HtmlEncode(Title)+"</title>");
    end;

    method RenderEnd;
    begin
      for each lControl in Controls do begin
        lControl.Context := Context;
        lControl.Parent := self;
        lControl.Initialize(new EventArgs);
        lControl.OnLoad(new EventArgs);
        if lControl.Visible then
          lControl.RenderControl(self);
        lControl.OnUnLoad(new EventArgs);
      end;
      Response.Write("</head>");
    end;

  private

    fOwner: nullable Control;

  end;

end.
