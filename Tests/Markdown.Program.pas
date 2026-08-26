namespace RTL2.Markdown.Tests;

uses
  RemObjects.Elements.EUnit;

type
  Program = public static class
  public
    method Main(aArguments: array of String): Integer;
    begin
      var lTests := Discovery.DiscoverTests;
      var lResult := Runner.RunTests(lTests) withListener(Runner.DefaultListener);
      result := if lResult.State = TestState.Succeeded then 0 else 1;
    end;
  end;

end.
