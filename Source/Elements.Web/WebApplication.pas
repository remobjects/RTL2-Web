namespace RemObjects.Elements.Web;

type
  // Value snapshot; no live request/response objects are retained.
  WebErrorDiagnostic = public class
  public

    constructor(aDiagnostic: not nullable WebCompilerDiagnostic);
    begin
      Severity := aDiagnostic.Severity;
      Code := aDiagnostic.Code;
      Message := aDiagnostic.Message;
      FileName := aDiagnostic.FileName;
      SourceFileName := aDiagnostic.SourceFileName;
      Line := aDiagnostic.Line;
      Column := aDiagnostic.Column;
    end;

    property Severity: nullable String; readonly;
    property Code: nullable String; readonly;
    property Message: nullable String; readonly;
    property FileName: nullable String; readonly;
    property SourceFileName: nullable String; readonly;
    property Line: Integer; readonly;
    property Column: Integer; readonly;

  end;

  WebErrorContext = public class
  public

    constructor(aException: not nullable Exception; aRequestUrl: not nullable String;
                aRequestMethod: not nullable String; aPagePath: not nullable String);
    begin
      Exception := aException;
      RequestUrl := aRequestUrl;
      RequestMethod := aRequestMethod;
      PagePath := aPagePath;
      TimestampUtc := DateTime.UtcNow;
      var lSnapshot := new WebRequestError;
      lSnapshot.CaptureException(aException);
      var lDiagnostics := new List<WebErrorDiagnostic>;
      for each lDiagnostic in lSnapshot.Diagnostics do
        lDiagnostics.Add(new WebErrorDiagnostic(lDiagnostic));
      fDiagnostics := lDiagnostics;
    end;

    property Exception: not nullable Exception; readonly;
    property StatusCode: Integer read 500;
    property RequestUrl: not nullable String; readonly;
    property RequestMethod: not nullable String; readonly;
    property PagePath: not nullable String; readonly;
    property TimestampUtc: DateTime; readonly;
    // Return a copy so notification consumers cannot mutate the snapshot.
    property CompilationDiagnostics: array of WebErrorDiagnostic read fDiagnostics.ToArray;

  private

    fDiagnostics: List<WebErrorDiagnostic>;

  end;

  WebApplication = public class
  public

    property Context: WebContext read assembly write;
    property Request: WebRequest read Context.Request;
    property Response: WebResponse read Context.Response;
    property Server: WebServerForContext read Context.Server;
    property Session: WebSessionState read coalesce(fEventSession, Context:Session);

    method OnStart; virtual;
    begin
      InvokeLifecycleHandler("Application_Start");
    end;

    method OnEnd; virtual;
    begin
      InvokeLifecycleHandler("Application_End");
    end;

    method OnSessionStart; virtual;
    begin
      InvokeLifecycleHandler("Session_Start");
    end;

    method OnSessionEnd; virtual;
    begin
      InvokeLifecycleHandler("Session_End");
    end;

    method OnError(aError: not nullable WebErrorContext); virtual;
    begin
      {$IF ECHOES}
      var lFlags := System.Reflection.BindingFlags.Instance or System.Reflection.BindingFlags.Public or
                    System.Reflection.BindingFlags.NonPublic or System.Reflection.BindingFlags.DeclaredOnly;
      // Search all ancestors for the typed signature before considering legacy.
      for each lTyped in [true, false] do begin
        var lType := GetType;
        while assigned(lType) and (lType <> typeOf(WebApplication)) do begin
          for each lMethod in lType.GetMethods(lFlags) do begin
            if (caseInsensitive(lMethod.Name) <> "Application_Error") or lMethod.IsGenericMethod or
               (lMethod.ReturnType <> typeOf(System.Void)) then
              continue;
            var lParameters := lMethod.GetParameters;
            if lTyped and (length(lParameters) = 1) and (lParameters[0].ParameterType = typeOf(WebErrorContext)) then begin
              lMethod.Invoke(self, [aError]);
              exit;
            end;
            if not lTyped and (length(lParameters) = 2) and (lParameters[0].ParameterType = typeOf(Object)) and
               (lParameters[1].ParameterType = typeOf(EventArgs)) then begin
              lMethod.Invoke(self, [self, new EventArgs]);
              exit;
            end;
          end;
          lType := lType.BaseType;
        end;
      end;
      {$ENDIF}
    end;

  assembly

    property EventSession: nullable WebSessionState read fEventSession write fEventSession;

  private

    fEventSession: nullable WebSessionState;

    method InvokeLifecycleHandler(aName: not nullable String);
    begin
      {$IF ECHOES}
      var lFlags := System.Reflection.BindingFlags.Instance or System.Reflection.BindingFlags.Public or
                    System.Reflection.BindingFlags.NonPublic or System.Reflection.BindingFlags.DeclaredOnly;
      var lType := GetType;
      while assigned(lType) and (lType <> typeOf(WebApplication)) do begin
        for each lMethod in lType.GetMethods(lFlags) do begin
          if (caseInsensitive(lMethod.Name) = caseInsensitive(aName)) and not lMethod.IsGenericMethod and
             (lMethod.ReturnType = typeOf(System.Void)) then begin
            var lParameters := lMethod.GetParameters;
            if (length(lParameters) = 2) and (lParameters[0].ParameterType = typeOf(Object)) and
               (lParameters[1].ParameterType = typeOf(EventArgs)) then begin
              lMethod.Invoke(self, [self, new EventArgs]);
              exit;
            end;
          end;
        end;
        lType := lType.BaseType;
      end;
      {$ENDIF}
    end;

  end;

  WebServer = public partial class
  private

    method NotifyApplicationError(aEvent: not nullable HttpRequestEventArgs; aFactory: nullable WebPageFactory;
                                  aContext: nullable WebContext; aPath: not nullable String; aException: not nullable Exception);
    begin
      var lPrevious := WebContext.Current;
      try
        var lOriginal := CreateRequestContext(aEvent, aEvent.Request.Path, aEvent.Request.QueryString.ToString, aFactory);
        var lContext := coalesce(aContext, lOriginal);
        var lException := aException;
        {$IF ECHOES}
        while (lException is System.Reflection.TargetInvocationException) and assigned(lException.InnerException) do
          lException := lException.InnerException;
        {$ENDIF}
        lContext.Error := lException;
        WebContext.Current := lContext;
        lContext.Lifetime.EnsureStarted(aFactory, lContext);
        lContext.Lifetime.NotifyError(lContext, new WebErrorContext(lException, lOriginal.Request.Url.ToAbsoluteString,
          String(aEvent.Request.Header.RequestType), aPath));
      except
        on E: Exception do
          Log($"ESP Application_Error failed: {E}");
      finally
        WebContext.Current := lPrevious;
      end;
    end;

  end;

end.
