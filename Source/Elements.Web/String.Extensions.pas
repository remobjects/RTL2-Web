namespace RemObjects.Elements.Web;

type
  WebStringExtensions = public extension class(String)
  public

    // HTML text and quoted text attributes.
    method HtmlEncoded: nullable String;
    begin
      result := HttpUtility.HtmlEncode(self);
    end;

    // A single URL query/form value.
    method UrlEncoded: nullable String;
    begin
      result := HttpUtility.UrlEncode(self);
    end;

    // Remove individual characters, preserving all remaining text.
    method HtmlStripped: nullable String;
    begin
      result := self:Replace("<", ""):Replace(">", ""):Replace("'", ""):Replace("""", ""):Replace("/", ""):Replace("&", "");
    end;

    method TryAsInteger: nullable Integer;
    begin
      result := Convert.TryToInt32(self);
    end;

    method TryAsInt64: nullable Int64;
    begin
      result := Convert.TryToInt64(self);
    end;

    method TryAsDoubleInvariant: nullable Double;
    begin
      var lValue := Convert.TryToDoubleInvariant(self);
      if assigned(lValue) and not Consts.IsNaN(lValue) and not Consts.IsInfinity(lValue) then
        result := lValue;
    end;

    method TryAsBoolean: nullable Boolean;
    begin
      case self:ToLowerInvariant of
        "true": result := true;
        "false": result := false;
      end;
    end;

    // Extended ISO calendar dates or timestamps, with optional fractions and timezone.
    method TryAsISO8601DateTime: nullable DateTime;
    begin
      if not assigned(self) then
        exit;
      if (self.Length < 10) or (self.Length > 33) or self.StartsWith("0000-") then
        exit;

      var lPattern := new Regex withPattern(
        "^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?(Z|[+-][0-9]{2}:[0-9]{2})?)?$");
      if not lPattern.IsMatch(self) then
        exit;

      var lValue := self;
      var lOffsetMinutes := 0;
      if lValue.EndsWith("Z") then begin
        lValue := lValue.Substring(0, lValue.Length-1);
      end
      else if (lValue.Length >= 25) and (lValue[lValue.Length-6] in ['+', '-']) then begin
        var lHours := Convert.ToInt32(lValue.Substring(lValue.Length-5, 2));
        var lMinutes := Convert.ToInt32(lValue.Substring(lValue.Length-2));
        if (lHours > 23) or (lMinutes > 59) then
          exit;
        lOffsetMinutes := lHours*60+lMinutes;
        if lValue[lValue.Length-6] = '+' then
          lOffsetMinutes := -lOffsetMinutes;
        lValue := lValue.Substring(0, lValue.Length-6);
      end;

      var lBaseFormat := if lValue.Length = 10 then "yyyy-MM-dd" else "yyyy-MM-ddTHH:mm:ss";
      var lFormat := lBaseFormat;
      if lValue.Length > 19 then
        lFormat := lFormat+"."+new String('f', lValue.Length-20);
      try
        // Exact format avoids the ISO parser's fallback to a date-only result.
        var lParsed := DateTime.TryParse(lValue, lFormat);
        if not assigned(lParsed) then
          exit;
        if lParsed.ToString(lBaseFormat, TimeZone.Utc) ≠ lValue.Substring(0, lBaseFormat.Length) then
          exit;
        result := lParsed.Add(RemObjects.Elements.RTL.Units.Minutes(lOffsetMinutes));
      except
        on E: ArgumentException do
          exit;
      end;
    end;

    // Contents of a quoted JavaScript string, including inside an inline script.
    method JavaScriptStringEncoded: nullable String;
    begin
      if not assigned(self) then
        exit;

      var lJson := JsonStringValue.RenderString(self);
      result := lJson.Substring(1, lJson.Length-2).Replace("'", "\u0027").
        Replace("<", "\u003c").Replace(">", "\u003e").Replace("&", "\u0026");
    end;

    method TryAsGuid: nullable Guid;
    begin
      var lValue := self;
      if not assigned(lValue) then
        exit;
      if lValue.Length = 38 then begin
        if not (((lValue[0] = '{') and (lValue[37] = '}')) or
                ((lValue[0] = '(') and (lValue[37] = ')'))) then
          exit;
        lValue := lValue.Substring(1, 36);
      end;
      if lValue.Length ≠ 36 then
        exit;

      // Some platform Guid.TryParse implementations throw or accept abbreviated groups.
      for i: Integer := 0 to 35 do begin
        if i in [8, 13, 18, 23] then begin
          if lValue[i] ≠ '-' then
            exit;
        end
        else if not (lValue[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then begin
          exit;
        end;
      end;
      result := Guid.TryParse(lValue);
    end;

    method TryAsValidEmail(aAllowQuotedLocalPart: Boolean := false; aMaximumLength: Integer := 200): nullable String;
    begin
      if EmailValidation.IsValid(self, aAllowQuotedLocalPart, aMaximumLength) then
        result := self;
    end;

  end;

end.
