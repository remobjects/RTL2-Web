namespace RemObjects.Elements.Web;

type
  WebSessionState = public class
  public

    property SessionID: String read assembly write;
    property IsNewSession: Boolean read assembly write;
    property Timeout: Integer read fTimeout write SetTimeout;
    property Expires: not nullable DateTime read private write := DateTime.UtcNow.AddMinutes(SessionManager.DEFAULT_SESSION_TIMEOUT_MINUTES);
    property IsExpired: Boolean read Expires < DateTime.UtcNow;

    property Item[aName: not nullable String]: nullable Object read fSessionState[aName] write SetSessionState; default;
    property Keys: sequence of String read fSessionState.Keys;
    property Count: Integer read fSessionState.Count;

    method Abandon;
    begin
      Clear;
      SessionManager.AbandonSession(self);
    end;

    method Clear;
    begin
      fSessionState.RemoveAll;
    end;

    method Remove(aName: not nullable String);
    begin
      fSessionState[aName] := nil;
    end;

    method RemoveAll;
    begin
      Clear;
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
      Expires := DateTime.UtcNow.AddMinutes(Timeout);
    end;

  private

    fTimeout: Integer := SessionManager.DEFAULT_SESSION_TIMEOUT_MINUTES;
    fSessionState := new Dictionary<String,Object>;

    method SetSessionState(aName: not nullable String; aValue: nullable Object);
    begin
      fSessionState[aName] := aValue;
    end;

    method SetTimeout(aValue: Integer);
    begin
      fTimeout := aValue;
      ExtendSession;
    end;

  end;

  SessionManager = static class
  assembly

    class var fActiveSessions := new Dictionary<String,WebSessionState>; readonly;
    class var fMonitor := new Monitor;

    class method FindOrCreateSession(aContext: not nullable WebContext): not nullable WebSessionState;
    begin
      var lSessionCookie := aContext.Request.Cookies[SESSION_ID_COOKIE_NAME];
      var lSessionID := coalesce(lSessionCookie:Values["ID"], lSessionCookie:Values[""]);
      if assigned(lSessionID) then begin
        //Log($"Looking for session with id {lSessionID}");
        var lSession := locking fMonitor do fActiveSessions[lSessionID];
        if assigned(lSession) then begin
          if not lSession:IsExpired then begin
            lSession.ExtendSession;
            lSession.IsNewSession := false;
            result := lSession;
          end
          else begin
            locking fMonitor do
              fActiveSessions[lSessionID] := nil;
          end;
        end;
      end;

      if not assigned(result) then begin
        lSessionID := Guid.NewGuid.ToString(GuidFormat.Default);
        aContext.Response.Cookies[SESSION_ID_COOKIE_NAME][""] := lSessionID;
        aContext.Response.Cookies[SESSION_ID_COOKIE_NAME].HttpOnly := true;
        result := new WebSessionState(lSessionID);
        result.IsNewSession := true;
        locking fMonitor do
          fActiveSessions[lSessionID] := result;
        //Log($"Created new session for id {lSessionID}");
      end;
    end;

    class method AbandonSession(aSession: nullable WebSessionState);
    begin
      if assigned(aSession) and assigned(aSession.SessionID) then
        locking fMonitor do
          fActiveSessions[aSession.SessionID] := nil;
    end;

    class method ExpireSessions;
    begin
      for each k in fActiveSessions.Keys.UniqueCopy do
        if fActiveSessions[k].IsExpired then
          locking fMonitor do
            fActiveSessions[k] := nil;
    end;

    const DEFAULT_SESSION_TIMEOUT_MINUTES = 10;
    const SESSION_ID_COOKIE_NAME = "EspSessionId";

  end;
end.