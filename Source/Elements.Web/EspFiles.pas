namespace RemObjects.Elements.Web;

type
  WebPostedFile = public class
  public

    constructor(aFileName: nullable String; aContentType: nullable String; aContent: not nullable array of Byte);
    begin
      FileName := aFileName;
      ContentType := aContentType;
      Content := aContent;
    end;

    method SaveAs(aFileName: not nullable String);
    begin
      File.WriteBytes(aFileName, Content);
    end;

    property FileName: nullable String; readonly;
    property ContentType: nullable String; readonly;
    property ContentLength: Integer read length(Content);
    property InputStream: Stream read new MemoryStream(Content, false);

  private

    property Content: array of Byte; readonly;

  end;

  WebFileCollection = public class
  public

    method Add(aName: nullable String; aFile: not nullable WebPostedFile);
    begin
      var lName := NormalizeName(aName);
      fFiles.Add(aFile);
      fNames.Add(lName);
      if not fNamedFiles.ContainsKey(lName) then
        fNamedFiles[lName] := aFile;
    end;

    property Item[aName: not nullable String]: nullable WebPostedFile read fNamedFiles[NormalizeName(aName)]; default;
    property Item[aIndex: Integer]: nullable WebPostedFile read if (aIndex >= 0) and (aIndex < fFiles.Count) then fFiles[aIndex]; default;
    property Count: Integer read fFiles.Count;
    property Keys: sequence of String read fNames.UniqueCopy;
    property AllKeys: array of String read fNames.UniqueCopy.ToArray;

  private

    fFiles := new List<WebPostedFile>;
    fNames := new List<String>;
    fNamedFiles := new Dictionary<String,WebPostedFile>;

    method NormalizeName(aName: nullable String): String;
    begin
      result := coalesce(aName, "");
    end;

  end;

end.
