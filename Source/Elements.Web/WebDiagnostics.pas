namespace RemObjects.Elements.Web;

type
  // Store diagnostic values and text, never exceptions or page instances from collectible generations.
  WebRequestError = public class
  public

    property Id: Int64;
    property Timestamp: nullable String;
    property MethodName: nullable String;
    property Path: nullable String;
    property StatusCode: Integer;
    property ResponseStatusCode: Integer;
    property Generation: Integer;
    property Revision: nullable String;
    property Message: nullable String;
    property ExceptionDetails: nullable String;
    property Diagnostics := new List<WebCompilerDiagnostic>; readonly;

    method CaptureStatus(aStatusCode: Integer);
    begin
      if (StatusCode = 0) and (aStatusCode ≥ 500) and (aStatusCode ≤ 599) then
        StatusCode := aStatusCode;
    end;

    method CaptureException(aException: not nullable Exception);
    begin
      CaptureStatus(500);
      if not assigned(Message) then
        Message := aException.Message;
      var lException: nullable Exception := aException;
      while assigned(lException) do begin
        if lException is WebCompilationException then begin
          if (Diagnostics.Count = 0) and (Message = aException.Message) then
            Message := lException.Message;
          // Copy the diagnostics now: later builds must not rewrite request history.
          var lSnapshot := new WebHostStatus;
          lSnapshot.AddDiagnostics(nil, lException);
          Diagnostics.Add(lSnapshot.Diagnostics);
        end;
        {$IF ECHOES}
        lException := lException.InnerException;
        {$ELSE}
        lException := nil;
        {$ENDIF}
      end;
      var lDetails := aException.ToString;
      ExceptionDetails := if assigned(ExceptionDetails) then ExceptionDetails+Environment.LineBreak+lDetails else lDetails;
    end;

  end;

  WebServer = public partial class
  private

    method RecordRequestError(aEvent: not nullable HttpRequestEventArgs; aFactory: nullable WebPageFactory; aFailure: not nullable WebRequestError);
    begin
      aFailure.CaptureStatus(Integer(aEvent.Response.HttpCode));
      if aFailure.StatusCode = 0 then
        exit;
      aFailure.Timestamp := DateTime.UtcNow.ToISO8601String;
      aFailure.MethodName := String(aEvent.Request.Header.RequestType);
      // Deliberately omit query strings, cookies and authorization headers.
      aFailure.Path := aEvent.Request.Path;
      aFailure.ResponseStatusCode := Integer(aEvent.Response.HttpCode);
      aFailure.Revision := aFactory:PublicationRevision;
      if not assigned(aFailure.Message) then
        aFailure.Message := $"HTTP {aFailure.StatusCode}";
      locking fDiagnosticMonitor do begin
        inc(fRequestErrorSequence);
        aFailure.Id := fRequestErrorSequence;
        while fRecentErrors.Count ≥ 1000 do
          fRecentErrors.Dequeue;
        fRecentErrors.Enqueue(aFailure);
      end;
    end;

    method RenderDiagnosticsPage(aErrors: Boolean; aJson: Boolean; aToken: nullable String): not nullable String;
    begin
      var lDocument := new JsonObject;
      var lItems := new JsonArray;
      var lRows := new StringBuilder;
      var lStatus: nullable WebHostStatus;
      var lErrors := new List<WebRequestError>;
      locking fDiagnosticMonitor do begin
        lStatus := fHostStatus;
        if aErrors then
          for each lError in fRecentErrors do
            lErrors.Add(lError);
      end;
      lDocument["generation"] := coalesce(lStatus:Generation, 0);
      lDocument["activeGeneration"] := coalesce(lStatus:ActiveGeneration, 0);
      var lTokenQuery := if (length(AuthorizationToken) > 0) and (length(aToken) > 0) then "token="+HttpUtility.UrlEncode(aToken) else "";
      if aErrors then begin
        lDocument["errors"] := lItems;
        lDocument["capacity"] := 1000;
        lDocument["persistent"] := false;
        for each lError in lErrors.Reverse do begin
          var lItem := new JsonObject;
          lItem["id"] := lError.Id;
          lItem["timestamp"] := lError.Timestamp;
          lItem["method"] := lError.MethodName;
          lItem["path"] := lError.Path;
          lItem["status"] := lError.StatusCode;
          lItem["responseStatus"] := lError.ResponseStatusCode;
          lItem["generation"] := lError.Generation;
          lItem["revision"] := lError.Revision;
          lItem["message"] := lError.Message;
          lItem["exception"] := lError.ExceptionDetails;
          var lDiagnostics := new JsonArray;
          var lCompilerDetails := new StringBuilder;
          var lFiles := new StringBuilder;
          var lFileNames := new HashSet<String>;
          for each lDiagnostic in lError.Diagnostics do begin
            var lDiagnosticItem := new JsonObject;
            lDiagnosticItem["severity"] := lDiagnostic.Severity;
            lDiagnosticItem["code"] := lDiagnostic.Code;
            lDiagnosticItem["message"] := lDiagnostic.Message;
            lDiagnosticItem["file"] := DiagnosticDisplayPath(lDiagnostic.FileName);
            lDiagnosticItem["line"] := lDiagnostic.Line;
            lDiagnosticItem["column"] := lDiagnostic.Column;
            var lSource := DiagnosticSourceLink(lDiagnostic.FileName, lDiagnostic.SourceFileName, lDiagnostic.Line);
            lDiagnosticItem["sourceUrl"] := lSource;
            lDiagnostics.Add(lDiagnosticItem);
            var lLocation := DiagnosticDisplayPath(lDiagnostic.FileName);
            if (length(lLocation) > 0) and not lFileNames.Contains(lLocation) then begin
              lFileNames.Add(lLocation);
              if lFiles.Length > 0 then
                lFiles.Append(", ");
              var lFileHtml := HtmlLandingPage.EscapeHtml(lLocation);
              if assigned(lSource) then
                lFileHtml := $'<a href="{HtmlLandingPage.EscapeHtml(lSource+(if length(lTokenQuery) > 0 then "?"+lTokenQuery else ""))}">{lFileHtml}</a>';
              lFiles.Append(lFileHtml);
            end;
            if lDiagnostic.Line > 0 then
              lLocation := lLocation+$":{lDiagnostic.Line}:{lDiagnostic.Column}";
            var lLocationHtml := HtmlLandingPage.EscapeHtml(lLocation);
            if assigned(lSource) then
              lLocationHtml := $'<a href="{HtmlLandingPage.EscapeHtml(lSource+(if length(lTokenQuery) > 0 then "?"+lTokenQuery else ""))}">{lLocationHtml}</a>';
            lCompilerDetails.AppendLine(lLocationHtml+" "+HtmlLandingPage.EscapeHtml($"{lDiagnostic.Severity} {lDiagnostic.Code}: {lDiagnostic.Message}"));
          end;
          lItem["diagnostics"] := lDiagnostics;
          lItems.Add(lItem);
          var lDetails := if lError.Diagnostics.Count > 0 then lCompilerDetails.ToString else if assigned(lError.ExceptionDetails) then HtmlLandingPage.EscapeHtml(lError.ExceptionDetails) else nil;
          var lMessage := if lFiles.Length > 0 then "Compilation failed for" else HtmlLandingPage.EscapeHtml(lError.Message);
          if assigned(lDetails) then
            lMessage := $'<button class="error-toggle" type="button" aria-expanded="false" aria-controls="error-{lError.Id}" onclick="toggleError(this)">{lMessage}</button>';
          if lFiles.Length > 0 then
            lMessage := lMessage+" "+lFiles.ToString;
          lRows.Append($"<tr><td>{HtmlLandingPage.EscapeHtml(lError.Timestamp)}</td><td>{HtmlLandingPage.EscapeHtml(lError.MethodName)} {HtmlLandingPage.EscapeHtml(lError.Path)}</td><td>{lError.StatusCode}</td><td>{lError.ResponseStatusCode}</td><td>{lMessage}</td></tr>");
          if assigned(lDetails) then
            lRows.Append($'<tr id="error-{lError.Id}" class="error-detail-row" hidden><td></td><td colspan="4" class="error-detail-cell"><div class="error-trace"><pre>{lDetails}</pre></div></td></tr>');
        end;
      end
      else begin
        lDocument["diagnostics"] := lItems;
        lDocument["summary"] := lStatus:Summary;
        var lDiagnostics := new List<WebCompilerDiagnostic>;
        if assigned(lStatus) then begin
          lDiagnostics.Add(lStatus.Diagnostics);
          // Compatibility with hosts that predate structured status diagnostics.
          if (lDiagnostics.Count = 0) and assigned(lStatus.Failure) then begin
            var lFallback := new WebHostStatus;
            lFallback.AddDiagnostics("Project", lStatus.Failure);
            lDiagnostics.Add(lFallback.Diagnostics);
          end;
        end;
        for each lDiagnostic in lDiagnostics do begin
          var lItem := new JsonObject;
          lItem["unit"] := lDiagnostic.UnitName;
          lItem["severity"] := lDiagnostic.Severity;
          lItem["code"] := lDiagnostic.Code;
          lItem["message"] := lDiagnostic.Message;
          lItem["file"] := DiagnosticDisplayPath(lDiagnostic.FileName);
          lItem["line"] := lDiagnostic.Line;
          lItem["column"] := lDiagnostic.Column;
          var lSource := DiagnosticSourceLink(lDiagnostic.FileName, lDiagnostic.SourceFileName, lDiagnostic.Line);
          lItem["sourceUrl"] := lSource;
          lItems.Add(lItem);
          var lLocation := DiagnosticDisplayPath(lDiagnostic.FileName);
          if lDiagnostic.Line > 0 then
            lLocation := lLocation+$":{lDiagnostic.Line}:{lDiagnostic.Column}";
          var lLocationHtml := HtmlLandingPage.EscapeHtml(lLocation);
          if assigned(lSource) then
            lLocationHtml := $'<a href="{HtmlLandingPage.EscapeHtml(lSource+(if length(lTokenQuery) > 0 then "?"+lTokenQuery else ""))}">{lLocationHtml}</a>';
          lRows.Append($"<tr><td>{HtmlLandingPage.EscapeHtml(lDiagnostic.Severity)}</td><td>{HtmlLandingPage.EscapeHtml(lDiagnostic.UnitName)}</td><td>{lLocationHtml}</td><td>{HtmlLandingPage.EscapeHtml(lDiagnostic.Code)}</td><td>{HtmlLandingPage.EscapeHtml(lDiagnostic.Message)}</td></tr>");
        end;
      end;
      if aJson then
        exit lDocument.ToJsonString;
      var lTitle := if aErrors then "ESP Request Errors" else "ESP Diagnostics";
      var lDescription := if aErrors then "Latest 1,000 failed requests, newest first. History resets when the server restarts." else "Current diagnostics from builds already attempted. This page does not trigger validation or compilation.";
      var lHeaders := if aErrors then "<th>Time (UTC)</th><th>Request</th><th>Error status</th><th>Response status</th><th>Details</th>" else "<th>Severity</th><th>Unit</th><th>Location</th><th>Code</th><th>Message</th>";
      var lQuery := if length(lTokenQuery) > 0 then "?"+lTokenQuery else "";
      var lJsonQuery := "?format=json"+(if length(lTokenQuery) > 0 then "&"+lTokenQuery else "");
      var lPath := if aErrors then "/__esp/errors" else "/__esp/diagnostics";
      if lItems.Count = 0 then
        lRows.Append("<tr><td colspan=""5"">"+(if aErrors then "No request errors recorded." else "No diagnostics reported.")+"</td></tr>");
      result := HtmlLandingPage.RenderCardPage(lTitle, ##"""
        <style>
          .wrap { max-width: 90rem; } .table-scroll { overflow-x: auto; }
          table { width: 100%; border-collapse: collapse; font-size: .85rem; }
          th, td { text-align: left; vertical-align: top; padding: .65rem; border-bottom: 1px solid #94a3b844; overflow-wrap: anywhere; }
          th { white-space: nowrap; }
          td:last-child { white-space: pre-wrap; }
          .error-toggle { border: 0; padding: 0; background: none; color: inherit; font: inherit; text-align: left; cursor: pointer; }
          .error-toggle::before { content: "▸"; display: inline-block; width: 1em; }
          .error-toggle[aria-expanded="true"]::before { content: "▾"; }
          .error-detail-cell { max-width: 0; }
          .error-trace { overflow-x: auto; }
          .error-trace pre { margin: 0; white-space: pre; overflow-wrap: normal; word-break: normal; }
        </style>
        <script>
          function toggleError(button) {
            const expanded = button.getAttribute("aria-expanded") !== "true";
            button.setAttribute("aria-expanded", String(expanded));
            document.getElementById(button.getAttribute("aria-controls")).hidden = !expanded;
          }
        </script>
        <h1>{{lTitle}}</h1>
        <nav><a href="/__esp/status{{HtmlLandingPage.EscapeHtml(lQuery)}}">Status</a> · <a href="/__esp/diagnostics{{HtmlLandingPage.EscapeHtml(lQuery)}}">Diagnostics</a> · <a href="/__esp/errors{{HtmlLandingPage.EscapeHtml(lQuery)}}">Request errors</a> · <a href="{{lPath}}{{HtmlLandingPage.EscapeHtml(lJsonQuery)}}">JSON</a> · <a href="{{lPath}}{{HtmlLandingPage.EscapeHtml(lQuery)}}">Refresh</a></nav>
        <p>{{lDescription}}</p>
        <p>{{HtmlLandingPage.EscapeHtml(lStatus:Summary)}}</p>
        <div class="table-scroll"><table><thead><tr>{{lHeaders}}</tr></thead><tbody>{{lRows}}</tbody></table></div>
        """);
    end;

  end;

end.
