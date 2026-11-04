namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  HttpUtilityTests = public class(Test)
  public

    method UrlDecodeTreatsPlusAsSpace;
    begin
      Assert.AreEqual(HttpUtility.UrlDecode("one+two%2Fthree"), "one two/three");
    end;

    method HtmlEncodeEscapesCommonMarkupCharacters;
    begin
      Assert.AreEqual(HttpUtility.HtmlEncode("<a href=""/"">A&B</a>"), "&lt;a href=&quot;/&quot;&gt;A&amp;B&lt;/a&gt;");
    end;

    method HtmlEncodeEscapesApostrophesForSingleQuotedAttributes;
    begin
      Assert.AreEqual(HttpUtility.HtmlEncode("it's <safe> &"), "it&#39;s &lt;safe&gt; &amp;");
      Assert.AreEqual(HttpUtility.HtmlDecode("it&#39;s &amp;#39;"), "it's &#39;");
    end;

    method HtmlDecodeRestoresCommonMarkupCharacters;
    begin
      Assert.AreEqual(HttpUtility.HtmlDecode("&lt;a href=&quot;/&quot;&gt;A&amp;B&lt;/a&gt;"), "<a href=""/"">A&B</a>");
    end;

    method HtmlAttributeEncodeEscapesAttributeSensitiveCharacters;
    begin
      Assert.AreEqual(HttpUtility.HtmlAttributeEncode("x""&<>"), "x&quot;&amp;&lt;&gt;");
    end;

    method WebStringExtensionsPreserveValuesAndNulls;
    begin
      var lValue := "<a href=""/"">O'Reilly & café</a>";
      Assert.AreEqual(lValue:HtmlEncoded, "&lt;a href=&quot;/&quot;&gt;O&#39;Reilly &amp; café&lt;/a&gt;");
      Assert.AreEqual(lValue:HtmlStripped, "a href=OReilly  caféa");
      Assert.AreEqual("a+b /&?=é":UrlEncoded, "a%2Bb+%2F%26%3F%3D%C3%A9");
      Assert.AreEqual("&lt;":HtmlEncoded, "&amp;lt;");
      Assert.AreEqual(lValue, "<a href=""/"">O'Reilly & café</a>");
      Assert.AreEqual("":HtmlEncoded, "");
      Assert.AreEqual("":UrlEncoded, "");
      Assert.AreEqual("":HtmlStripped, "");

      var lMissing: nullable String;
      Assert.IsNil(lMissing:HtmlEncoded);
      Assert.IsNil(lMissing:UrlEncoded);
      Assert.IsNil(lMissing:HtmlStripped);
      Assert.IsNil(lMissing:TryAsInteger);
      Assert.IsNil(lMissing:TryAsGuid);
      Assert.IsNil(lMissing:TryAsInt64);
      Assert.IsNil(lMissing:TryAsDoubleInvariant);
      Assert.IsNil(lMissing:TryAsBoolean);
      Assert.IsNil(lMissing:TryAsISO8601DateTime);
      Assert.IsNil(lMissing:JavaScriptStringEncoded);
      Assert.IsNil(lMissing:TryAsValidEmail);
    end;

    method WebStringIntegerConversionRejectsInvalidInputAndOverflow;
    begin
      Assert.AreEqual("0":TryAsInteger, 0);
      Assert.AreEqual("-2147483648":TryAsInteger, -2147483648);
      Assert.AreEqual("+2147483647":TryAsInteger, 2147483647);
      for each lValue in ["", "2147483648", "-2147483649", "1.5", "12px", " 12", "12 ", "<12>"] do
        Assert.IsNil(lValue:TryAsInteger);
    end;

    method WebStringInt64ConversionRejectsInvalidInputAndOverflow;
    begin
      Assert.AreEqual("9223372036854775807":TryAsInt64, Consts.MaxInt64);
      Assert.AreEqual("-9223372036854775808":TryAsInt64, Consts.MinInt64);
      Assert.AreEqual("2147483648":TryAsInt64, Int64(2147483648));
      for each lValue in ["", "9223372036854775808", "-9223372036854775809", "1.5", "12px"] do
        Assert.IsNil(lValue:TryAsInt64);
    end;

    method WebStringDoubleConversionUsesInvariantNumbersAndRejectsNonFiniteValues;
    begin
      Assert.AreEqual("1.5":TryAsDoubleInvariant, 1.5);
      Assert.AreEqual("-2.5e2":TryAsDoubleInvariant, -250.0);
      for each lValue in ["", "invalid", "12px", "NaN", "Infinity", "-Infinity", "1e9999"] do
        Assert.IsNil(lValue:TryAsDoubleInvariant);
    end;

    method WebStringBooleanConversionAcceptsOnlyTrueAndFalse;
    begin
      for each lValue in ["true", "True", "TRUE"] do
        Assert.AreEqual(lValue:TryAsBoolean, true);
      for each lValue in ["false", "False", "FALSE"] do
        Assert.AreEqual(lValue:TryAsBoolean, false);
      for each lValue in ["", "1", "0", "yes", "no", "on", " true", "false "] do
        Assert.IsNil(lValue:TryAsBoolean);
    end;

    method WebStringISO8601ConversionRejectsMalformedAndImpossibleDates;
    begin
      var lDate := "2024-02-29":TryAsISO8601DateTime;
      Assert.IsNotNil(lDate);
      Assert.AreEqual(lDate.Year, 2024);
      Assert.AreEqual(lDate.Month, 2);
      Assert.AreEqual(lDate.Day, 29);
      Assert.IsNotNil("2026-11-04T12:34:56Z":TryAsISO8601DateTime);
      Assert.IsNotNil("2026-11-04T12:34:56.1234567Z":TryAsISO8601DateTime);
      Assert.AreEqual("2026-11-04T12:34:56Z":TryAsISO8601DateTime:Hour, 12);
      Assert.AreEqual("2026-11-04T12:34:56.1234567Z":TryAsISO8601DateTime:Millisecond, 123);
      Assert.AreEqual("2026-11-04T12:34:56+05:30":TryAsISO8601DateTime:Ticks,
        "2026-11-04T07:04:56Z":TryAsISO8601DateTime:Ticks);
      Assert.AreEqual("2026-11-04T00:15:00-00:30":TryAsISO8601DateTime:Ticks,
        "2026-11-04T00:45:00Z":TryAsISO8601DateTime:Ticks);
      for each lValue in ["0000-01-01", "2026-00-04", "2026-11-00", "2026-11-04junk",
        "2026-11-04T12:34:56Zjunk", "2026-11-04T12:34:56+24:00", "2026-11-04T12:34:56+01:60"] do
        Assert.IsNil(lValue:TryAsISO8601DateTime, lValue);
      for each lValue in ["", "invalid", "04/11/2026", "2026-13-04", "2026-02-30", "2026-11-04T25:00:00Z"] do
        Assert.IsNil(lValue:TryAsISO8601DateTime, lValue);
    end;

    method WebJavaScriptStringEncodingPreservesDataAndPreventsScriptTermination;
    begin
      var lValue := "</script><script>alert('x')</script> & "+'"'+'\'+#13#10+Char(8232)+Char(8233)+"café";
      var lEncoded := lValue:JavaScriptStringEncoded;
      Assert.IsFalse(lEncoded.Contains("<"));
      Assert.IsFalse(lEncoded.Contains(">"));
      Assert.IsFalse(lEncoded.Contains("&"));
      Assert.IsFalse(lEncoded.Contains("'"));
      Assert.IsFalse(lEncoded.Contains(#10));
      Assert.IsFalse(lEncoded.Contains(Char(8232).ToString));
      Assert.IsFalse(lEncoded.Contains(Char(8233).ToString));
      Assert.IsTrue(lEncoded.Contains("\u003c/script\u003e"));
      Assert.AreEqual(JsonDocument.FromString('"'+lEncoded+'"').StringValue, lValue);
      Assert.AreEqual("":JavaScriptStringEncoded, "");
      for i: Integer := 0 to 31 do begin
        var lControl := "a"+Char(i)+"b";
        Assert.AreEqual(JsonDocument.FromString('"'+lControl:JavaScriptStringEncoded+'"').StringValue, lControl);
      end;
    end;

    method WebStringGuidConversionAcceptsStandardFormsAndRejectsMalformedInput;
    begin
      var lGuid := "01234567-89ab-cdef-0123-456789abcdef";
      for each lValue in [lGuid, lGuid.ToUpper, "{"+lGuid+"}", "("+lGuid+")"] do
        Assert.AreEqual(lValue:TryAsGuid:ToString:ToLower, lGuid);
      Assert.AreEqual("00000000-0000-0000-0000-000000000000":TryAsGuid, Guid.Empty);

      for each lValue in ["", "not-a-guid", new String('z', 36), "{"+new String('a', 35),
        "("+lGuid+"}", "{"+lGuid+")", " "+lGuid, lGuid+" ", lGuid.Replace("-", ""),
        "1-2-3-4-5", "01234567-89ab-cdef-0123-456789abcdeg"] do
        Assert.IsNil(lValue:TryAsGuid);
    end;

    method WebStringEmailValidationPreservesValidAddresses;
    begin
      for each lValue in ["person@example.com", "First.Last+Tag@Example.co.uk", "o'reilly@example.com",
        "user@xn--bcher-kva.example", new String('a', 64)+"@example.com", "a@"+new String('b', 63)+".com"] do
        Assert.AreEqual(lValue:TryAsValidEmail, lValue);

      for each lValue in ["", "missing-at", "a@@example.com", "a..b@example.com", ".a@example.com",
        "a.@example.com", "a@localhost", "a@-example.com", "a@example-.com", "a@exam_ple.com",
        "a@example..com", "Person <a@example.com>", " a@example.com", "a@example.com ", "a@example.com"+#10,
        "a"+#13#10+"b@example.com", "a"+Char(8203)+"b@example.com", new String('a', 65)+"@example.com",
        "a@"+new String('b', 64)+".com", "a@"+new String('b', 63)+"."+new String('c', 63)+"."+new String('d', 63)+"."+new String('e', 63)] do
        Assert.IsNil(lValue:TryAsValidEmail);
    end;

    method WebEmailValidationRetainsWebsitePolicies;
    begin
      for each lAllowQuoted in [false, true] do begin
        for each lValue in ["person@example.com", "first.last+tag@example.co.uk", "PERSON@EXAMPLE.COM"] do
          Assert.IsTrue(EmailValidation.IsValid(lValue, lAllowQuoted));
        for each lValue in ["missing-at", "a@@example.com", "a..b@example.com", " person@example.com", "person@example.com ", "a@localhost"] do
          Assert.IsFalse(EmailValidation.IsValid(lValue, lAllowQuoted));
        for i: Integer := 0 to 159 do
          if (i < 32) or (i >= 127) then
            for each lValue in ["a"+Char(i)+"b@example.com", """a"+Char(i)+"b""@example.com", "a@example.com"+Char(i)] do
              Assert.IsFalse(EmailValidation.IsValid(lValue, lAllowQuoted));
        for each lCode in [8203, 8232, 8233, 8238, 65279] do
          Assert.IsFalse(EmailValidation.IsValid("""a"+Char(lCode)+"b""@example.com", lAllowQuoted));
      end;

      var lQuoted := """first last""@example.com";
      Assert.IsNil(lQuoted:TryAsValidEmail);
      Assert.AreEqual(lQuoted:TryAsValidEmail(true), lQuoted);
      for each lValue in ['"a@b"@example.com', '"a\"b"@example.com', '"a\\"@example.com'] do
        Assert.AreEqual(lValue:TryAsValidEmail(true), lValue);
      for each lValue in ['"a"b"@example.com', '"a\"@example.com', '"unclosed@example.com', "a@[127.0.0.1]", "a(comment)@example.com"] do
        Assert.IsNil(lValue:TryAsValidEmail(true));

      Assert.IsTrue(EmailValidation.IsValid("a@example.com", true, 13));
      Assert.IsFalse(EmailValidation.IsValid("a@example.com", true, 12));
      Assert.IsTrue(EmailValidation.IsValid("+tag@example.com"));
      Assert.AreEqual("o'reilly@example.com":TryAsValidEmail:HtmlEncoded, "o&#39;reilly@example.com");
      var lMaximum := new String('a', 64)+"@"+new String('b', 63)+"."+new String('c', 63)+"."+new String('d', 61);
      Assert.AreEqual(length(lMaximum), 254);
      Assert.IsTrue(EmailValidation.IsValid(lMaximum, false, 254));
      Assert.IsFalse(EmailValidation.IsValid(lMaximum+"d", false, 255));
    end;

  end;

end.
