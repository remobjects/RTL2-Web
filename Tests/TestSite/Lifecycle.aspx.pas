namespace;

uses
  System,
  System.Web.UI;

type
  LifecyclePage = public partial class(Page)
  private

    fSteps: String;

    method AppendStep(aStep: not nullable String);
    begin
      if length(fSteps) > 0 then
        fSteps := fSteps+",";
      fSteps := fSteps+aStep;
    end;

  protected

    method OnInit(e: EventArgs); override;
    begin
      AppendStep("override-before");
      inherited OnInit(e);
      AppendStep("override-after");
    end;

    method Page_Init(aSender: Object; aEventArgs: EventArgs);
    begin
      AppendStep("event-init");
    end;

    method Page_Load(aSender: Object; aEventArgs: EventArgs);
    begin
      AppendStep("load");
    end;

  public

    method RenderStep: String;
    begin
      AppendStep("render");
      result := fSteps;
    end;

  end;

end.
