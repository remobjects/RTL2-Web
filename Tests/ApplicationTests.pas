namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  ApplicationTests = public class(Test)
  public

    method CompilerDiagnosticsAreNotExceptionStacks;
    begin
      var lFailure := new WebCompilationException("Compilation failed.");
      lFailure.AddDiagnostic("Error", "E42", "Unknown identifier <bad>", "/site/Portal/Login.aspx", nil, 12, 7);
      lFailure.AddDiagnostic("Warning", "W1", "Warning message", "/external/shared.pas", nil, 4, 2);
      var lServer := new WebServer(PhysicalRootFolder := "/site");
      var lHtml := lServer.RenderException(lFailure);
      Assert.IsTrue(lHtml.Contains("./Portal/Login.aspx:12:7"));
      Assert.IsTrue(lHtml.Contains("&lt;unknown&gt;/shared.pas:4:2"));
      Assert.IsTrue(lHtml.Contains("E42"));
      Assert.IsTrue(lHtml.Contains("Unknown identifier &lt;bad&gt;"));
      Assert.IsFalse(lHtml.Contains("/site/"));
      Assert.IsFalse(lHtml.Contains("/external/"));
      Assert.IsFalse(lHtml.Contains("Stack trace"));
      Assert.IsFalse(lHtml.Contains("exception-type"));
      Assert.IsFalse(lHtml.Contains("compiler-source"));
    end;

    method CompilerFailureSurvivesSnapshotOverlay;
    begin
      var lFailure := new WebCompilationException("Compilation failed.");
      lFailure.AddDiagnostic("Error", "E42", "broken", nil, nil, 0, 0);
      var lSnapshot := new WebCompositePageFactory(new WebApplicationLifetime);
      lSnapshot.AddFailureException("/broken", lFailure);
      try
        lSnapshot.FindClassForPath("/broken");
        Assert.Fail("Expected a compiler failure");
      except
        on E: WebCompilationException do
          Assert.AreEqual(E.Diagnostics.Count, 1);
      end;
    end;

    method CompilerSourceRequiresDebugAndOptIn;
    begin
      var lFile := System.IO.Path.GetTempFileName;
      try
        File.WriteText(lFile, "before"#10"<unsafe>"#10"after");
        var lFailure := new WebCompilationException("Compilation failed.");
        lFailure.AddDiagnostic("Error", "E42", "broken", lFile, lFile, 2, 1);
        var lServer := new WebServer(ShowCompilerErrorSource := true);
        Assert.IsFalse(lServer.RenderException(lFailure).Contains("class=""compiler-source"""));
        lServer.DebugMode := true;
        var lHtml := lServer.RenderException(lFailure);
        Assert.IsTrue(lHtml.Contains("class=""compiler-source"""));
        Assert.IsTrue(lHtml.Contains("&lt;unsafe&gt;"));
        Assert.IsTrue(lHtml.Contains("source-line source-error"));
        Assert.IsFalse(lHtml.Contains("file://"));
        Assert.IsFalse(lHtml.Contains(lFile));
        var lLink := System.Text.RegularExpressions.Regex.Match(lHtml, 'href="/__esp/source/([^"]+)"');
        Assert.IsTrue(lLink.Success);
        var lToken := lLink.Groups[1].Value;
        var lViewer := lServer.RenderDiagnosticSource(lToken);
        Assert.IsTrue(lViewer.Contains("&lt;unsafe&gt;"));
        Assert.IsFalse(lViewer.Contains(lFile));
        Assert.IsNil(lServer.RenderDiagnosticSource("../../"+lFile));
        Assert.IsNil(lServer.RenderDiagnosticSource("unknown-token"));
        lServer.DebugMode := false;
        Assert.IsNil(lServer.RenderDiagnosticSource(lToken));
        Assert.IsFalse(lServer.RenderException(lFailure).Contains("/__esp/source/"));
        lServer.DebugMode := true;
        lServer.ShowCompilerErrorSource := false;
        Assert.IsFalse(lServer.RenderException(lFailure).Contains("class=""compiler-source"""));
      finally
        System.IO.File.Delete(lFile);
      end;
    end;

    method RuntimeStackPathsUseTheSameDisplayRule;
    begin
      var lServer := new WebServer(PhysicalRootFolder := "/site");
      var lRender := typeOf(WebServer).GetMethod("RenderStackFrame", System.Reflection.BindingFlags.Instance or System.Reflection.BindingFlags.NonPublic);
      var lInside := lRender.Invoke(lServer, ["at Test.Render in /site/Portal/Login.aspx.pas:line 12"]) as String;
      var lOutside := lRender.Invoke(lServer, ["at Test.Render in /site-other/shared.pas:line 5"]) as String;
      Assert.IsTrue(lInside.Contains("./Portal/Login.aspx.pas:12"));
      Assert.IsFalse(lInside.Contains("/site/"));
      Assert.IsTrue(lOutside.Contains("&lt;unknown&gt;/shared.pas:5"));
      Assert.IsFalse(lOutside.Contains("/site-other/"));
      lServer.RegisterDiagnosticSourceFolder("/temp/inputs/000001", "./");
      lServer.RegisterDiagnosticSourceFolder("/temp/obj/Asmx", "./<generated>/");
      var lCaptured := lRender.Invoke(lServer, ["at Test.Render in /temp/inputs/000001/Portal/Login.aspx:line 12"]) as String;
      var lGenerated := lRender.Invoke(lServer, ["at Test.Render in /temp/obj/Asmx/Portal-Login.aspx.g.pas:line 80"]) as String;
      var lOther := lRender.Invoke(lServer, ["at Test.Render in /temp/inputs/000001-other/Portal/Login.aspx:line 12"]) as String;
      Assert.IsTrue(lCaptured.Contains("./Portal/Login.aspx:12"));
      Assert.IsTrue(lGenerated.Contains("./&lt;generated&gt;/Portal-Login.aspx.g.pas:80"));
      Assert.IsFalse(lCaptured.Contains("/temp/"));
      Assert.IsTrue(lOther.Contains("&lt;unknown&gt;/Login.aspx:12"));
    end;

    method SnapshotRetiresAfterLastRequest;
    begin
      var lSnapshot := new WebCompositePageFactory(new WebApplicationLifetime);
      var lNotifications := 0;
      lSnapshot.Retired += (s, e) -> inc(lNotifications);
      lSnapshot.Acquire;
      lSnapshot.Acquire;
      lSnapshot.Retire;
      Assert.AreEqual(lNotifications, 0);
      lSnapshot.Release;
      Assert.AreEqual(lNotifications, 0);
      lSnapshot.Release;
      Assert.AreEqual(lNotifications, 1);
      lSnapshot.Retire;
      Assert.AreEqual(lNotifications, 1);
    end;

    method HostStatusIsExplicitlyGatedAndEscaped;
    begin
      var lStatus := new WebHostStatus(Summary := "Ready <test>", Generation := 3, ActiveGeneration := 2, RetainedGenerations := "1, 2");
      lStatus.AddUnit("./Page.aspx", "Failed", "Unit.dll", "Unknown <identifier>");
      var lServer := new WebServer(HostStatus := lStatus);
      Assert.IsNil(lServer.RenderHostStatus);
      lServer.DebugMode := true;
      var lHtml := lServer.RenderHostStatus;
      Assert.IsTrue(lHtml.Contains("Ready &lt;test&gt;"));
      Assert.IsTrue(lHtml.Contains("Unknown &lt;identifier&gt;"));
      Assert.IsTrue(lHtml.Contains("./Page.aspx"));
      Assert.IsTrue(lHtml.Contains("Unit.dll"));
      lServer.DebugMode := false;
      Assert.IsNil(lServer.RenderHostStatus);
    end;

    method StaticLookupMatchesDirectoryAndFileCase;
    begin
      var lRoot := Path.Combine(System.IO.Path.GetTempPath, "esp-static-"+System.Guid.NewGuid.ToString);
      Folder.Create(Path.Combine(lRoot, "Images", "Logos"));
      try
        var lFile := Path.Combine(lRoot, "Images", "Logos", "Sample.txt");
        File.WriteText(lFile, "sample");
        var lServer := new WebServer(PhysicalRootFolder := lRoot);
        var lResolve := typeOf(WebServer).GetMethod("ResolveStaticFile", System.Reflection.BindingFlags.Instance or System.Reflection.BindingFlags.NonPublic);
        var lResolved := lResolve.Invoke(lServer, ["/IMAGES/logos/SAMPLE.TXT"]) as String;
        Assert.AreEqual(File.ReadText(lResolved), "sample");
        Assert.IsNil(lResolve.Invoke(lServer, ["/images/logos/missing.txt"]));
        Assert.IsNil(lResolve.Invoke(lServer, ["/missing/logos/sample.txt"]));
        Assert.IsNil(lResolve.Invoke(lServer, ["/images/%2e%2e/sample.txt"]));
      finally
        System.IO.Directory.Delete(lRoot, true);
      end;
    end;

    method PageSnapshotsCanShareApplicationLifetime;
    begin
      var lLifetime := new WebApplicationLifetime;
      var lFirst := new WebCompositePageFactory(lLifetime);
      var lSecond := new WebCompositePageFactory(lLifetime);
      var lRecycled := new WebCompositePageFactory(new WebApplicationLifetime);
      Assert.IsTrue(lFirst.Lifetime = lSecond.Lifetime);
      Assert.IsFalse(lFirst.Lifetime = lRecycled.Lifetime);
    end;

    method PublishingFreezesSnapshot;
    begin
      var lSnapshot := new WebCompositePageFactory(new WebApplicationLifetime);
      lSnapshot.Acquire;
      var lRejected := false;
      try
        lSnapshot.AddFailure("/test", "broken");
      except
        on E: Exception do
          lRejected := E.Message.Contains("snapshot is immutable");
      end;
      lSnapshot.Release;
      Assert.IsTrue(lRejected);
    end;

    method StoresAndClearsValues;
    begin
      Application.RemoveAll;
      Assert.AreEqual(Application.Keys.Count, 0);

      Application["cache-key"] := "cached";

      Assert.AreEqual(Application["cache-key"], "cached");
      Assert.AreEqual(Application.Keys.Count, 1);

      Application.RemoveAll;

      Assert.IsNil(Application["cache-key"]);
      Assert.AreEqual(Application.Keys.Count, 0);
    end;

  end;

end.
