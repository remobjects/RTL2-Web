namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  ApplicationTests = public class(Test)
  public

    method StoresAndClearsValues;
    begin
      Application.RemoveAll;
      Assert.AreEqual(Application.Keys.Count, 0);

      Application["cache-key"] := "cached";

      Assert.AreEqual(Application["cache-key"], "cached");
      Assert.AreEqual(Application.Keys.Count, 1);

      Application.RemoveAll;

      Assert.IsNil(Application["cache-key"]);
      Assert.AreEqual(Application.Keys.Count, 0);
    end;

  end;

end.
