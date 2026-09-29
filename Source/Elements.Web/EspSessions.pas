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
      Store:AbandonSession(self);
      Clear;
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

    property Store: SessionManager;

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

  SessionManager = class
  assembly

    property Owner: WebApplicationLifetime;

    var fActiveSessions := new Dictionary<String,WebSessionState>; readonly;
    var fMonitor := new Monitor;

    method FindOrCreateSession(aContext: not nullable WebContext; out aCreated: Boolean): not nullable WebSessionState;
    begin
      aCreated := false;
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
            var lRemoved := false;
            locking fMonitor do
              if fActiveSessions[lSessionID] = lSession then begin
                fActiveSessions[lSessionID] := nil;
                lRemoved := true;
              end;
            if lRemoved then
              Owner:NotifySessionEnd(lSession);
          end;
        end;
      end;

      if not assigned(result) then begin
        lSessionID := Guid.NewGuid.ToString(GuidFormat.Default);
        aContext.Response.Cookies[SESSION_ID_COOKIE_NAME][""] := lSessionID;
        aContext.Response.Cookies[SESSION_ID_COOKIE_NAME].HttpOnly := true;
        result := new WebSessionState(lSessionID);
        result.Store := self;
        result.IsNewSession := true;
        locking fMonitor do
          fActiveSessions[lSessionID] := result;
        aCreated := true;
        //Log($"Created new session for id {lSessionID}");
      end;
    end;

    method AbandonSession(aSession: nullable WebSessionState);
    begin
      if assigned(aSession) and assigned(aSession.SessionID) then begin
        var lRemoved := false;
        locking fMonitor do
          if fActiveSessions[aSession.SessionID] = aSession then begin
            fActiveSessions[aSession.SessionID] := nil;
            lRemoved := true;
          end;
        if lRemoved then
          Owner:NotifySessionEnd(aSession);
      end;
    end;

    method ExpireSessions;
    begin
      var lExpired := new List<WebSessionState>;
      locking fMonitor do
        for each k in fActiveSessions.Keys.UniqueCopy do
          if fActiveSessions[k].IsExpired then begin
            lExpired.Add(fActiveSessions[k]);
            fActiveSessions[k] := nil;
          end;
      for each lSession in lExpired do
        Owner:NotifySessionEnd(lSession);
    end;

    method EndAll;
    begin
      var lSessions := new List<WebSessionState>;
      locking fMonitor do begin
        for each lSession in fActiveSessions.Values do
          lSessions.Add(lSession);
        fActiveSessions.RemoveAll;
      end;
      for each lSession in lSessions do
        Owner:NotifySessionEnd(lSession);
    end;

    const DEFAULT_SESSION_TIMEOUT_MINUTES = 10;
    const SESSION_ID_COOKIE_NAME = "EspSessionId";

  end;
end.
