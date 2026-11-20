namespace SlidesTests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Slides;

type
  Program = public static class
  public
    method Main(aArguments: array of String): Integer;
    begin
      var lResult := Runner.RunTests(Discovery.DiscoverTests) withListener(Runner.DefaultListener);
      exit if lResult.State = TestState.Succeeded then 0 else 1;
    end;
  end;

  DeckTests = public class(Test)
  public

    method RendersNotesRevealsAndDurations;
    begin
      var lDeck := new SlideDeck("---"+#10+"title: Example"+#10+"duration: 5m"+#10+"slideDuration: 1:30"+#10+
        "---"+#10+"# First"+#10#10+"<v-clicks>"+#10#10+"- One"+#10#10+"</v-clicks>"+#10#10+
        "```text"+#10+"---"+#10+"```"+#10#10+"<!--"+#10+"Only for the speaker"+#10+"-->"+#10+
        "---"+#10+"# Second");
      Check.AreEqual(2, lDeck.Count);
      var lPresenter := lDeck.Render("/tmp", "/tmp", true);
      var lSlides := lPresenter["slides"] as JsonArray;
      var lFirst := lSlides[0] as JsonObject;
      Check.IsTrue(lFirst["html"].StringValue.Contains('data-reveal="list"'));
      Check.IsTrue(lFirst["html"].StringValue.Contains("<code class="));
      Check.IsTrue(lFirst["notes"].StringValue.Contains("Only for the speaker"));
      Check.AreEqual(Int64(90), lFirst["duration"].IntegerValue);
      Check.AreEqual(Int64(300), lPresenter["duration"].IntegerValue);
      var lAudience := lDeck.Render("/tmp", "/tmp", false);
      Check.IsFalse(assigned(((lAudience["slides"] as JsonArray)[0] as JsonObject)["notes"]));
    end;

    method ConfiguresTimersIndependently;
    begin
      for each lSetting in ["presentationTimer", "slideTimer"] do begin
        var lDeck := new SlideDeck("---" + #10 + lSetting + ": false" + #10 + "---" + #10 + "# Slide");
        var lPresenter := lDeck.Render("/tmp", "/tmp", true);
        Check.IsTrue(assigned(lPresenter[lSetting]));
        Check.IsFalse(lPresenter[lSetting].BooleanValue);
        var lOtherSetting := if lSetting = "presentationTimer" then "slideTimer" else "presentationTimer";
        Check.IsFalse(assigned(lPresenter[lOtherSetting]));
        Check.IsFalse(assigned(lDeck.Render("/tmp", "/tmp", false)[lSetting]));
      end;
    end;

    method AppliesARevisionChangingBatch;
    begin
      var lDeck := new SlideDeck("# One"+#10+"---"+#10+"# Two");
      var lEdits := JsonArray.TryFromString('[{"op":"insert","slide":3,"markdown":"# Three","frontMatter":{"layout":"cover"}},'+
        '{"op":"move","slide":3,"to":1},{"op":"update","slide":1,"notes":"Timing cue"},{"op":"delete","slide":2}]');
      var lDraft := new SlideDeck(lDeck.Apply(lEdits));
      Check.AreEqual(2, lDraft.Count);
      Check.IsTrue(lDraft.Revision <> lDeck.Revision);
      Check.AreEqual("Three", (lDraft.Outline[0] as JsonObject)["title"].StringValue);
      var lFirst := (lDraft.Render("/tmp", "/tmp", true)["slides"] as JsonArray)[0] as JsonObject;
      Check.AreEqual("cover", lFirst["layout"].StringValue);
      Check.IsTrue(lFirst["notes"].StringValue.Contains("Timing cue"));
      var lCleared := new SlideDeck(lDraft.Apply(JsonArray.TryFromString(
        '[{"op":"update","slide":1,"frontMatter":{"layout":null}}]')));
      var lClearedFirst := (lCleared.Render("/tmp", "/tmp", false)["slides"] as JsonArray)[0] as JsonObject;
      Check.AreEqual("default", lClearedFirst["layout"].StringValue);
    end;

    method RejectsMalformedEditsAndStyles;
    begin
      var lDeck := new SlideDeck("# First" + #10#10 + "<!-- private -->");
      var lEdited := new SlideDeck(lDeck.Apply(JsonArray.TryFromString(
        '[{"op":"update","slide":1,"markdown":"# Revised"}]')));
      Check.IsTrue(((lEdited.Render("/tmp", "/tmp", true)["slides"] as JsonArray)[0] as JsonObject)["notes"].StringValue.Contains("private"));
      try
        lDeck.Apply(JsonArray.TryFromString('[{"op":"delete","slide":1},{"op":"move","slide":2,"to":1}]'));
        Check.IsTrue(false);
      except
        on E: Exception do Check.AreEqual(1, lDeck.Count);
      end;
      try
        SlideDeck.ParseStyle('{"version":1,"light":{"backgroundColor":"invalid"}}');
        Check.IsTrue(false);
      except
        on E: Exception do Check.IsTrue((E.Message as String).Contains("color"));
      end;
    end;

    method ResolvesAliasesForNewFiles;
    begin
      var lFolderName := NSUUID.UUID.UUIDString as not nullable String;
      var lFolder := Path.Combine("/private/tmp", lFolderName);
      Folder.Create(lFolder, true);
      try
        var lRelative := Path.Combine(lFolderName, "new.slides");
        var lCanonical := SlideFiles.CanonicalPath(Path.Combine("/private/tmp", lRelative));
        Check.AreEqual(lCanonical, SlideFiles.CanonicalPath(Path.Combine("/tmp", lRelative)));
        Check.IsTrue(SlideFiles.IsWithin(SlideFiles.CanonicalPath(lFolder), lCanonical));
      finally
        Folder.Delete(lFolder);
      end;
    end;

    method HostsIndependentPreviewsAndRestarts;
    begin
      var lRoot := SlideFiles.CanonicalPath(Path.Combine(NSTemporaryDirectory as String, NSUUID.UUID.UUIDString as String));
      Folder.Create(lRoot, true);
      var lHost := new SlideHost(lRoot, lRoot);
      try
        var lOne := Path.Combine(lRoot, "one.slides");
        var lTwo := Path.Combine(lRoot, "two.slides");
        SlideFiles.CreateNew(lOne, "# One");
        SlideFiles.CreateNew(lTwo, "# Two");
        var lFirst := lHost.OpenDeck(lRoot, lOne);
        var lPort := lHost.Port;
        var lSecond := lHost.OpenDeck(lRoot, lTwo);
        Check.IsTrue(lPort > 0);
        Check.AreEqual(lPort, lHost.Port);
        Check.IsTrue(lFirst.URL <> lSecond.URL);
        Check.AreEqual(2, lHost.ListPreviews(lRoot).Count);
        Check.IsTrue(lHost.CloseDeck(lRoot, lOne));
        Check.AreEqual(1, lHost.ListPreviews(lRoot).Count);
        lHost.Stop;
        Check.AreEqual(0, lHost.Port);
        Check.AreEqual(0, lHost.ListPreviews(lRoot).Count);
        Check.IsTrue(lHost.OpenDeck(lRoot, lTwo).URL <> lSecond.URL);
        Check.IsTrue(lHost.Port > 0);
      finally
        lHost.Stop;
        Folder.Delete(lRoot);
      end;
    end;

    method ExportsLocalAssetsWithoutStartingTheHost;
    begin
      var lRoot := SlideFiles.CanonicalPath(Path.Combine(NSTemporaryDirectory as String, NSUUID.UUID.UUIDString as String));
      Folder.Create(lRoot, true);
      try
        SlideFiles.CreateNew(Path.Combine(lRoot, "presenter.html"),
          '<html><head><link rel="stylesheet" href="slides.css"></head><body><script type="module" src="slides.js"></script></body></html>');
        SlideFiles.CreateNew(Path.Combine(lRoot, "slides.css"), 'body { background: url("assets/background-light.png") }');
        SlideFiles.CreateNew(Path.Combine(lRoot, "slides.js"), 'document.title = "Audience";');
        SlideFiles.CreateNew(Path.Combine(lRoot, "highlight.pack.js"), '');
        SlideFiles.CreateNew(Path.Combine(lRoot, "highlight-vs.css"), "");
        SlideFiles.CreateNew(Path.Combine(lRoot, "background-light.png"), 'test light background');
        SlideFiles.CreateNew(Path.Combine(lRoot, "background-dark.png"), 'test dark background');
        SlideFiles.CreateNew(Path.Combine(lRoot, "shared art.svg"), '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
        var lPath := Path.Combine(lRoot, "test.slides");
        SlideFiles.CreateNew(lPath, "---" + #10 + "logo: shared art.svg" + #10 + "---" + #10 +
          "# Audience" + #10#10 + "![Shared art](<shared art.svg>)" + #10#10 + "<!-- Private note -->");
        var lHost := new SlideHost(lRoot, lRoot);
        var lHtml := lHost.ExportAudienceHtml(lRoot, lPath);
        Check.AreEqual(0, lHost.Port);
        Check.IsTrue(lHtml.Contains('id="exported-deck"'));
        Check.IsTrue(lHtml.Contains('data:image/png;base64,'));
        Check.IsTrue(lHtml.Contains('data:image/svg+xml;base64,'));
        Check.IsFalse(lHtml.Contains("Private note"));
        Check.IsFalse(lHtml.Contains('src="slides.js"'));
      finally
        Folder.Delete(lRoot);
      end;
    end;

    method ResolvesStyleArtWithinTheWorkspace;
    begin
      var lRoot := SlideFiles.CanonicalPath(Path.Combine(NSTemporaryDirectory as String, NSUUID.UUID.UUIDString as String));
      var lStyles := Path.Combine(lRoot, "styles");
      var lDeckFolder := Path.Combine(lRoot, "decks");
      Folder.Create(lStyles, true);
      Folder.Create(lDeckFolder, true);
      try
        var lImage := Path.Combine(lRoot, "team logo.png");
        SlideFiles.CreateNew(lImage, "test asset");
        SlideFiles.CreateNew(Path.Combine(lStyles, "team.json"),
          '{"version":1,"light":{"background":"../team logo.png","logo":"../team logo.png","textColor":"#334455"}}');
        var lDeck := new SlideDeck("---"+#10+"style: ../styles/team.json"+#10+"---"+#10+
          "# One"+#10+"---"+#10+"background: false"+#10+"---"+#10+"# Two");
        var lSlides := lDeck.Render(lRoot, lDeckFolder, false)["slides"] as JsonArray;
        var lFirst := lSlides[0] as JsonObject;
        Check.AreEqual("deck?file=team%20logo%2Epng", lFirst["background"].StringValue);
        Check.AreEqual(lFirst["background"].StringValue, lFirst["logo"].StringValue);
        Check.AreEqual("false", (lSlides[1] as JsonObject)["background"].StringValue);
        Check.IsFalse(assigned(SlideFiles.Resolve(lDeckFolder, lDeckFolder, "../team logo.png")));
      finally
        Folder.Delete(lRoot);
      end;
    end;

  end;

end.
