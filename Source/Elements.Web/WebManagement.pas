namespace RemObjects.Elements.Web;

type
  // Compiler-independent transport. The host owns publication and persistence.
  WebManagementEventArgs = public class(EventArgs)
  public

    property IsUpdate: Boolean;
    property Json: Boolean;
    property OperationId: nullable String;
    property Since: nullable String;
    property ExpectedRevision: nullable String;
    property IdempotencyKey: nullable String;
    property StatusCode: Integer := 200;
    property Body: nullable String;

  end;

  WebPublicationErrorEventArgs = public class(EventArgs)
  public

    property Revision: nullable String;
    property Path: nullable String;
    property Message: nullable String;

  end;

  WebServer = public partial class
  public

    property RequireUpdateTrigger: Boolean;
    property AuthorizationToken: nullable String;
    event ManagementRequest: EventHandler;
    event PublicationError: EventHandler;

  private

    method HandleManagementRequest(aEvent: not nullable HttpRequestEventArgs): Boolean;
    begin
      var lPath := aEvent.Request.Path;
      // Public listener liveness only: no publication state, diagnostics or secrets.
      // Deployment proxies must be able to admit a host before its first publication.
      if lPath = "/__esp/health" then begin
        aEvent.Response.Header.SetHeaderValue("Cache-Control", "no-store");
        aEvent.Response.Header.SetHeaderValue("Content-Type", "text/plain; charset=utf-8");
        var lMethod := String(aEvent.Request.Header.RequestType).ToLowerInvariant;
        if lMethod in ["get", "head"] then begin
          aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(200);
          aEvent.Response.ContentString := if lMethod = "head" then "" else "ESP listener ready.";
        end
        else begin
          aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(405);
          aEvent.Response.Header.SetHeaderValue("Allow", "GET, HEAD");
          aEvent.Response.ContentString := "Method not allowed.";
        end;
        exit true;
      end;
      if (not RequireUpdateTrigger and (length(AuthorizationToken) = 0)) or
         not (lPath in ["/__esp/update", "/__esp/status"]) then
        exit false;
      result := true;
      aEvent.Response.Header.SetHeaderValue("Cache-Control", "no-store");
      aEvent.Response.Header.SetHeaderValue("Referrer-Policy", "no-referrer");
      aEvent.Response.Header.SetHeaderValue("X-Content-Type-Options", "nosniff");
      aEvent.Response.Header.SetHeaderValue("Content-Type", "application/json; charset=utf-8");
      var lUpdate := lPath = "/__esp/update";
      var lMethod := String(aEvent.Request.Header.RequestType).ToLowerInvariant;
      var lAuthorization := String(aEvent.Request.Header["Authorization"]:Value);
      var lToken: nullable String;
      if assigned(lAuthorization) then begin
        if lAuthorization.StartsWith("Bearer ") then
          lToken := lAuthorization.Substring(7);
      end
      else if not lUpdate then
        lToken := aEvent.Request.QueryString["token"];
      if (length(AuthorizationToken) > 0) and not TokenMatches(lToken) then begin
        aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(401);
        aEvent.Response.Header.SetHeaderValue("WWW-Authenticate", "Bearer");
        aEvent.Response.ContentString := '{"error":"Unauthorized"}';
        exit;
      end;
      if (lUpdate and (lMethod ≠ "post")) or (not lUpdate and not (lMethod in ["get", "head"])) then begin
        aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(405);
        aEvent.Response.Header.SetHeaderValue("Allow", if lUpdate then "POST" else "GET, HEAD");
        aEvent.Response.ContentString := '{"error":"Method not allowed"}';
        exit;
      end;
      var lArgs := new WebManagementEventArgs(IsUpdate := lUpdate,
        Json := lUpdate or (aEvent.Request.QueryString["format"] = "json"),
        OperationId := aEvent.Request.QueryString["operation"], Since := aEvent.Request.QueryString["since"],
        ExpectedRevision := aEvent.Request.Header["If-Match"]:Value,
        IdempotencyKey := aEvent.Request.Header["Idempotency-Key"]:Value);
      try
        ManagementRequest(self, lArgs);
      except
        on E: Exception do begin
          // Do not echo arbitrary host exceptions (or authorization) to clients.
          lArgs.StatusCode := 500;
          lArgs.Json := true;
          lArgs.Body := '{"error":"Management request failed"}';
        end;
      end;
      aEvent.Response.HttpCode := RemObjects.InternetPack.Http.HttpStatusCode(lArgs.StatusCode);
      if not lArgs.Json then
        aEvent.Response.Header.SetHeaderValue("Content-Type", "text/html; charset=utf-8");
      aEvent.Response.ContentString := if lMethod = "head" then "" else coalesce(lArgs.Body, "{}");
    end;

    method TokenMatches(aToken: nullable String): Boolean;
    begin
      var lExpected := coalesce(AuthorizationToken, "");
      var lActual := coalesce(aToken, "");
      var lDifference := length(lExpected) xor length(lActual);
      for i: Integer := 0 to length(lExpected)-1 do
        lDifference := lDifference or (Integer(lExpected[i]) xor (if i < length(lActual) then Integer(lActual[i]) else 0));
      result := lDifference = 0;
    end;

    method LeaseFile(aPath: not nullable String; aFactory: nullable WebPageFactory): not nullable Stream;
    begin
      if not assigned(aFactory) or (length(aFactory.PhysicalRootFolder) = 0) then
        exit new FileStream(aPath, FileOpenMode.ReadOnly);
      result := new WebSnapshotFileStream(aPath, aFactory);
    end;

  end;

  WebSnapshotFileStream = assembly class(FileStream)
  public

    constructor(aPath: not nullable String; aFactory: not nullable WebPageFactory);
    begin
      inherited constructor(aPath, FileOpenMode.ReadOnly);
      aFactory.Acquire;
      fFactory := aFactory;
    end;

    method Close; override;
    begin
      try
        inherited Close;
      finally
        var lFactory := fFactory;
        fFactory := nil;
        lFactory:Release;
      end;
    end;

  private

    fFactory: nullable WebPageFactory;

  end;

  // A content-only publication can retain the exact dynamic snapshot and state.
  WebPublicationPageFactory = public class(WebCompositePageFactory)
  public

    constructor(aFactory: not nullable WebPageFactory; aRoot: not nullable String; aBin: nullable String; aRevision: not nullable String);
    begin
      inherited constructor(aFactory.Lifetime);
      aFactory.Acquire;
      fInner := aFactory;
      AddFactory(aFactory);
      fRoot := aRoot;
      fBin := aBin;
      fRevision := aRevision;
      Retired += ReleaseInner;
    end;

    property PhysicalRootFolder: nullable String read fRoot; override;
    property PhysicalBinFolder: nullable String read fBin; override;
    property PublicationRevision: nullable String read fRevision; override;

  private

    fInner: nullable WebPageFactory;
    fRoot: String;
    fBin: nullable String;
    fRevision: String;

    method ReleaseInner(aSender: Object; aArgs: EventArgs);
    begin
      var lInner := fInner;
      fInner := nil;
      lInner:Release;
    end;

  end;

end.
