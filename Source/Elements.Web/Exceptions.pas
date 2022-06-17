namespace RemObjects.Elements.Web;

type
  CleanlyEndResponseException = public class(Exception)
  public
    constructor;
    begin
      inherited constructor("Response has ended.")
    end;
  end;

  TransferToNewPathException = public class(Exception)
  public
    constructor(aPath: not nullable String);
    begin
      Path := aPath;
      inherited constructor($"Response has been transfered to {aPath}.")
    end;

    property Path: not nullable String read private write;
  end;

end.