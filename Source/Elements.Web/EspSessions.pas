namespace RemObjects.Elements.Web;

type
  WebSessionState = public class
  public

    property SessionID: String read assembly write;
    property Expires: not nullable DateTime read private write := DateTime.UtcNow.AddMinutes(SessionManager.ESP_SESSION_EXPIRATION_MINUTES);
    property IsExpired: Boolean read Expires < DateTime.UtcNow;

    property Item[aName: not nullable String]: nullable Object read fSessionState[aName] write SetSessionState; default;
    property Keys: sequence of String read fSessionState.Keys;

    method Abandon;
    begin

    end;

    method Clear;
    begin
      fSessionState.RemoveAll;
    end;

    [ToString]
    method ToString: String; override;
    begin
      var lResult := new StringBuilder;
      lResult.AppendLine($"Session {SessionID}");
      for each k in fSessionState.Keys.OrderBy(k -> k) do
        lResult.AppendLine($"{k} = {fSessionState[k]}");
      result := lResult.ToString;
    end;

  assembly

    constructor(aSessionID: String);
    begin
      SessionID := aSessionID;
    end;

    method ExtendSession;
    begin
      Expires := DateTime.UtcNow.AddMinutes(SessionManager.ESP_SESSION_EXPIRATION_MINUTES);
    end;

  private

    fSessionState := new Dictionary<String,Object>;

    method SetSessionState(aName: not nullable String; aValue: nullable Object);
    begin
      fSessionState[aName] := aValue;
    end;

  end;

  SessionManager = static class
  assembly

    class var fActiveSessions := new Dictionary<String,WebSessionState>; readonly;

    class method FindOrCreateSession(aContext: not nullable WebContext): not nullable WebSessionState;
    begin
      var lSessionID := aContext.Request.Cookies[ESP_SESSION_ID_COOKIE_NAME]:Values["ID"];
      if assigned(lSessionID) then begin
        //Log($"Looking for session with id {lSessionID}");
        var lSession := locking fActiveSessions do fActiveSessions[lSessionID];
        if assigned(lSession) then begin
          if not lSession:IsExpired then begin
            lSession.ExtendSession;
            result := lSession;
          end
          else begin
            locking fActiveSessions do
              fActiveSessions[lSessionID] := nil;
          end;
        end;
      end;

      if not assigned(result) then begin
        lSessionID := Guid.NewGuid.ToString(GuidFormat.Default);
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME]["ID"] := lSessionID;
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME].Expires := DateTime.UtcNow.AddMinutes(ESP_SESSION_EXPIRATION_MINUTES);
        aContext.Response.Cookies[ESP_SESSION_ID_COOKIE_NAME].Domain := aContext.Request.Url.Host;
        result := new WebSessionState(lSessionID);
        locking fActiveSessions do
          fActiveSessions[lSessionID] := result;
        //Log($"Created new session for id {lSessionID}");
      end;
    end;

    class method ExpireSessions;
    begin
      for each k in fActiveSessions.Keys.UniqueCopy do
        if fActiveSessions[k].IsExpired then
          locking fActiveSessions do
            fActiveSessions[k] := nil;
    end;

    const ESP_SESSION_EXPIRATION_MINUTES = 10;
    const ESP_SESSION_ID_COOKIE_NAME = "ESP_Session";

  end;
end.