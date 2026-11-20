namespace RemObjects.Elements.Slides;

[System.Runtime.InteropServices.DllImport('/usr/lib/system/libcommonCrypto.dylib')]
method CC_SHA256(aBytes: array of Byte; aLength: UInt32; aDigest: array of Byte): IntPtr; external;

type
  SlideAssetEncoder = public block(aPath: not nullable String; aType: not nullable String): not nullable String;

  SlideFiles = public static class
  public

    class method CanonicalPath(aPath: not nullable String): not nullable String;
    begin
      var lPath := Path.GetFullPath(aPath) as not nullable String;
      var lMissing := new Stack<String>;
      while not File.Exists(lPath) and not Folder.Exists(lPath) do begin
        var lParent := Path.GetParentDirectory(lPath);
        if not assigned(lParent) or (lParent = lPath) then
          raise new Exception("Could not resolve slide path: " + aPath);
        lMissing.Push(lPath.LastPathComponent as not nullable);
        lPath := lParent;
      end;
      // Resolve an existing ancestor first so missing files use the same
      // spelling as the workspace, including macOS aliases such as /tmp.
      lPath := (lPath as NSString).stringByResolvingSymlinksInPath as not nullable String;
      while lMissing.Count > 0 do
        lPath := Path.Combine(lPath, lMissing.Pop);
      exit lPath;
    end;

    class method IsWithin(aRoot: not nullable String; aPath: not nullable String): Boolean;
    begin
      exit aPath.StartsWith(aRoot.TrimEnd('/') + "/");
    end;

    class method Resolve(aRoot: not nullable String; aFolder: not nullable String; aRelative: nullable String): nullable String;
    begin
      if not assigned(aRelative) or (length(aRelative) = 0) or aRelative.StartsWith("/")
        or aRelative.Contains(":") or aRelative.Contains("\") or aRelative.Contains(#0) then
        exit;
      var lPath := CanonicalPath(Path.Combine(aFolder, aRelative));
      if IsWithin(aRoot, lPath) and File.Exists(lPath) then
        exit lPath;
    end;

    class method ContentType(aPath: not nullable String): nullable String;
    begin
      case aPath.PathExtension.ToLower.TrimStart('.') of
        "png": exit "image/png";
        "jpg", "jpeg": exit "image/jpeg";
        "gif": exit "image/gif";
        "svg": exit "image/svg+xml";
        "webp": exit "image/webp";
        "avif": exit "image/avif";
        "mp3": exit "audio/mpeg";
        "wav": exit "audio/wav";
        "mp4": exit "video/mp4";
        "webm": exit "video/webm";
      end;
    end;

    class method ImageUrl(aRoot: not nullable String; aFolder: not nullable String; aValue: nullable String;
      aEncodeAsset: nullable SlideAssetEncoder := nil): nullable String;
    begin
      if not assigned(aValue) or (aValue = "false") then
        exit;
      if aValue.StartsWith("https://") or aValue.StartsWith("http://") then
        exit aValue;
      var lUnescaped := coalesce(Url.TryRemovePercentEncodingsFromPath(aValue, false), aValue);
      var lPath := Resolve(aRoot, aFolder, lUnescaped);
      var lType := if assigned(lPath) then ContentType(lPath) else nil;
      if assigned(lPath) and assigned(lType) then begin
        if assigned(aEncodeAsset) then
          exit aEncodeAsset(lPath, lType);
        var lEncoded: NSString := lPath.Substring(length(aRoot.TrimEnd('/')) + 1);
        exit "deck?file=" + lEncoded.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet);
      end;
    end;

    class method Revision(aText: not nullable String): not nullable String;
    begin
      var lBytes := Encoding.UTF8.GetBytes(aText);
      var lDigest := new Byte[32];
      CC_SHA256(lBytes, UInt32(length(lBytes)), lDigest);
      var lResult := new StringBuilder;
      for each lByte in lDigest do
        lResult.Append("0123456789abcdef"[lByte shr 4]).Append("0123456789abcdef"[lByte and 15]);
      exit lResult.ToString as not nullable;
    end;

    class method CreateNew(aPath: not nullable String; aText: not nullable String);
    begin
      Write(aPath, aText, NSDataWritingOptions.DataWritingWithoutOverwriting);
    end;

    class method WriteAtomically(aPath: not nullable String; aText: not nullable String);
    begin
      Write(aPath, aText, NSDataWritingOptions.DataWritingAtomic);
    end;

  private

    class method Write(aPath: not nullable String; aText: not nullable String; aOptions: NSDataWritingOptions);
    begin
      var lData: NSData := new Binary(Encoding.UTF8.GetBytes(aText));
      var lError: NSError := nil;
      if not lData.writeToFile(aPath) options(aOptions) error(var lError) then
        raise new Exception(coalesce(lError:localizedDescription as String, "Could not save " + aPath));
    end;

  end;

end.
