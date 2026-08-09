namespace;

uses
  System,
  System.Web.UI;

type
  AutoWireBasePage = public class(Page)
  protected

    method Page_Load(aSender: Object; aEventArgs: EventArgs);
    begin
      LoadMarker := "protected-inherited-load";
    end;

  public

    property LoadMarker: String;

  end;

  AutoWirePage = public partial class(AutoWireBasePage)
  end;

end.
