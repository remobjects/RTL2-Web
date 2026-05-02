namespace RemObjects.Elements.Web;

type
  WebNameValueCollection = public class
  public

    constructor;
    begin
    end;

    constructor(aCaseInsensitive: Boolean);
    begin
      fCaseInsensitive := aCaseInsensitive;
    end;

    constructor(aEncodedValues: nullable String);
    begin
      ParseUrlEncodedValues(aEncodedValues);
    end;

    constructor(aEncodedValues: nullable String; aCaseInsensitive: Boolean);
    begin
      fCaseInsensitive := aCaseInsensitive;
      ParseUrlEncodedValues(aEncodedValues);
    end;

    method Add(aName: nullable String; aValue: nullable String);
    begin
      var lName := NormalizeName(aName);
      if fValues.ContainsKey(lName) then begin
        if assigned(aValue) then
          fValues[lName] := coalesce(fValues[lName], "")+","+aValue;
      end
      else begin
        fValues[lName] := aValue;
      end;
    end;

    method &Set(aName: nullable String; aValue: nullable String);
    begin
      fValues[NormalizeName(aName)] := aValue;
    end;

    method Clear;
    begin
      fValues.RemoveAll;
      fRawValue := nil;
    end;

    property Item[aName: not nullable String]: nullable String read GetValue(aName); default;
    property Count: Integer read fValues.Count;
    property Keys: sequence of String read fValues.Keys;
    property Values: ImmutableDictionary<String,String> read fValues;

    [ToString]
    method ToString: String; override;
    begin
      result := coalesce(fRawValue, "");
    end;

  private

    fValues := new Dictionary<String,String>;
    fRawValue: nullable String;
    fCaseInsensitive: Boolean;

    method NormalizeName(aName: nullable String): String;
    begin
      result := coalesce(aName, "");
      if fCaseInsensitive then
        result := result.ToUpperInvariant;
    end;

    method GetValue(aName: not nullable String): nullable String;
    begin
      result := fValues[NormalizeName(aName)];
    end;

    method ParseUrlEncodedValues(aEncodedValues: nullable String);
    begin
      fRawValue := aEncodedValues;

      if length(aEncodedValues) = 0 then
        exit;

      for each s in aEncodedValues.Split("&") do begin
        var lSplit := s.SplitAtFirstOccurrenceOf("=");
        if lSplit.Count = 2 then
          Add(DecodeFormValue(lSplit[0]), DecodeFormValue(lSplit[1]))
        else
          Add(DecodeFormValue(s), nil);
      end;
    end;

  assembly

    class method DecodeFormValue(aValue: nullable String): nullable String;
    begin
      if not assigned(aValue) then
        exit;

      result := Url.RemovePercentEncodingsFromPath(aValue, true);
    end;

  end;

end.
