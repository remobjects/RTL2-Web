namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  NameValueCollectionTests = public class(Test)
  public

    method DecodesUrlEncodedValues;
    begin
      var lValues := new WebNameValueCollection("name=Marc+Hoffman&product=Elements%20Web&empty=&flag");

      Assert.AreEqual(lValues["name"], "Marc Hoffman");
      Assert.AreEqual(lValues["product"], "Elements Web");
      Assert.AreEqual(lValues["empty"], "");
      Assert.IsNil(lValues["flag"]);
      Assert.AreEqual(lValues.ToString, "name=Marc+Hoffman&product=Elements%20Web&empty=&flag");
    end;

    method JoinsRepeatedValues;
    begin
      var lValues := new WebNameValueCollection("id=1&id=2&id=3");

      Assert.AreEqual(lValues["id"], "1,2,3");
      Assert.AreEqual(lValues.Count, 1);
    end;

    method SupportsCaseInsensitiveLookupWhenRequested;
    begin
      var lValues := new WebNameValueCollection(true);

      lValues.Add("User-Agent", "Elements");
      Assert.AreEqual(lValues["user-agent"], "Elements");

      lValues.Set("SERVER_NAME", "localhost");
      Assert.AreEqual(lValues["server_name"], "localhost");
    end;

  end;

end.
