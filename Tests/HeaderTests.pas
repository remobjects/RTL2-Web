namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  HeaderTests = public class(Test)
  public

    method DefaultsPreserveExplicitEmptyTitle;
    begin
      var lHeader := new WebPageHeader;
      lHeader.SetDefaultTitle("A &amp; B");
      Assert.AreEqual(lHeader.Title, "A & B");
      lHeader.Title := "";
      lHeader.SetDefaultTitle("replacement");
      Assert.AreEqual(lHeader.Title, "");
      Assert.IsTrue(lHeader.Visible);
    end;

    method AttributesAreCaseInsensitive;
    begin
      var lHeader := new WebPageHeader;
      lHeader.SetDefaultAttribute("lang", "en");
      lHeader.Attributes["LANG"] := "nl";
      lHeader.SetDefaultAttribute("Lang", "de");
      Assert.AreEqual(lHeader.Attributes["lang"], "nl");
      Assert.AreEqual(lHeader.Attributes.Count, 1);
      lHeader.SetDefaultAttribute("visible", "false");
      Assert.IsFalse(lHeader.Visible);
      Assert.AreEqual(lHeader.Attributes.Count, 1);
    end;

    method TemplateInitializationPrecedesUserInitOnce;
    begin
      var lControl := new HeaderInitializationProbe;
      lControl.Initialize(new System.EventArgs);
      lControl.Initialize(new System.EventArgs);
      Assert.AreEqual(lControl.Trace, "template;user;");
    end;

    method RejectsDifferentHeadOwners;
    begin
      var lHeader := new WebPageHeader;
      var lOwner := new Page;
      lHeader.RegisterTemplate(lOwner);
      lHeader.RegisterTemplate(lOwner);
      var lRejected := false;
      try
        lHeader.RegisterTemplate(new Page);
      except
        on E: Exception do begin
          Assert.AreEqual(E.Message, "A page can contain only one server head.");
          lRejected := true;
        end;
      end;
      Assert.IsTrue(lRejected);
      Assert.AreEqual(lHeader.Parent, lOwner);
    end;

  end;

  HeaderInitializationProbe = class(Control)
  public

    property Trace: String := "";

  protected

    method InitializeTemplate(e: System.EventArgs); override;
    begin
      inherited;
      Trace := Trace+"template;";
    end;

    method OnInit(e: System.EventArgs); override;
    begin
      inherited;
      Trace := Trace+"user;";
    end;

  end;

end.
