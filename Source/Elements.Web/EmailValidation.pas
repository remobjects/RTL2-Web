namespace RemObjects.Elements.Web;

type
  // Adapted from the website's EmailValidation helper.
  EmailValidation = public static class
  public

    // A single ASCII mailbox with a dotted DNS domain.
    // RFC 5321 sections 4.1.2 and 4.5.3.1, with the website's opt-in quoted-local-part policy.
    method IsValid(aEmail: nullable String; aAllowQuotedLocalPart: Boolean := false; aMaximumLength: Integer := 200): Boolean;
    begin
      if (length(aEmail) = 0) or (length(aEmail) > aMaximumLength) or (length(aEmail) > 254) then
        exit false;

      // ASCII also makes the SMTP byte limits equal to character counts.
      for each lCharacter in aEmail do
        if (ord(lCharacter) < 32) or (ord(lCharacter) > 126) then
          exit false;

      var lAt := aEmail.LastIndexOf("@");
      if (lAt < 1) or (lAt > 64) then
        exit false;

      var lLocalPart := aEmail.Substring(0, lAt);
      var lDomain := aEmail.Substring(lAt+1);
      var lDomainPattern := new Regex withPattern(
        "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");
      if not lDomainPattern.IsMatch(lDomain) then
        exit false;

      if lLocalPart.StartsWith("""") then
        exit aAllowQuotedLocalPart and IsValidQuotedLocalPart(lLocalPart);

      var lLocalPattern := new Regex withPattern("^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*$");
      result := lLocalPattern.IsMatch(lLocalPart);
    end;

  private

    method IsValidQuotedLocalPart(aLocalPart: String): Boolean;
    begin
      if (length(aLocalPart) < 2) or not aLocalPart.EndsWith("""") then
        exit false;

      var lEscaped := false;
      for i: Integer := 1 to length(aLocalPart)-2 do begin
        if lEscaped then begin
          lEscaped := false;
        end
        else if aLocalPart[i] = '\' then begin
          lEscaped := true;
        end
        else if aLocalPart[i] = '"' then begin
          exit false;
        end;
      end;
      result := not lEscaped;
    end;

  end;

end.
