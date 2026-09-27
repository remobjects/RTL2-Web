namespace RemObjects.Elements.Web;

type
  WebHostUnitStatus = public class
  public

    property Name: nullable String;
    property State: nullable String;
    property Artifact: nullable String;
    property Error: nullable String;

  end;

  // Hosts publish a completed value object; no compiler/assembly objects are
  // retained by the portable status renderer.
  WebHostStatus = public class
  public

    property Summary: nullable String;
    property Generation: Integer;
    property ActiveGeneration: Integer;
    property RetainedGenerations: nullable String;
    property Error: nullable String;
    property Units := new List<WebHostUnitStatus>; readonly;
    property Failure: nullable Exception;
    property Diagnostics := new List<WebCompilerDiagnostic>; readonly;

    method AddDiagnostics(aUnit: nullable String; aDiagnostics: nullable Exception);
    begin
      if aDiagnostics is WebCompilationException then begin
        for each lDiagnostic in (aDiagnostics as WebCompilationException).Diagnostics do
          Diagnostics.Add(new WebCompilerDiagnostic(UnitName := aUnit, Severity := lDiagnostic.Severity,
            Code := lDiagnostic.Code, Message := lDiagnostic.Message, FileName := lDiagnostic.FileName,
            SourceFileName := lDiagnostic.SourceFileName, Line := lDiagnostic.Line, Column := lDiagnostic.Column));
      end
      else if assigned(aDiagnostics) then begin
        AddProjectDiagnostic("Error", aDiagnostics.Message);
      end;
    end;

    method AddProjectDiagnostic(aSeverity: nullable String; aMessage: nullable String);
    begin
      Diagnostics.Add(new WebCompilerDiagnostic(UnitName := "Project", Severity := aSeverity, Message := aMessage));
    end;

    method AddUnit(aName: nullable String; aState: nullable String; aArtifact: nullable String; aError: nullable String);
    begin
      Units.Add(new WebHostUnitStatus(Name := aName, State := aState, Artifact := aArtifact, Error := aError));
    end;

  end;

  // Runtime-owned transport: hosts do not expose their compiler's message types.
  WebCompilerDiagnostic = public class
  public

    property UnitName: nullable String;
    property Severity: nullable String;
    property Code: nullable String;
    property Message: nullable String;
    property FileName: nullable String;
    property SourceFileName: nullable String;
    property Line: Integer;
    property Column: Integer;

  end;

  WebCompilationException = public class(Exception)
  public

    constructor(aMessage: not nullable String);
    begin
      inherited constructor(aMessage);
    end;

    property Diagnostics := new List<WebCompilerDiagnostic>; readonly;

    method AddDiagnostic(aSeverity: nullable String; aCode: nullable String; aMessage: nullable String;
                         aFileName: nullable String; aSourceFileName: nullable String; aLine: Integer; aColumn: Integer);
    begin
      Diagnostics.Add(new WebCompilerDiagnostic(Severity := aSeverity, Code := aCode, Message := aMessage,
        FileName := aFileName, SourceFileName := aSourceFileName, Line := aLine, Column := aColumn));
    end;

  end;

end.