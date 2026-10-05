namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  LocalizationTests = public class(Test)
  public

    method MissingManagerRequiresExplicitRegistration;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.App.Provider := nil;
        lSite.Factory.Check := c -> begin
          ExpectFailure(->Application.ActiveLocalizationManager.GetText(c, "key"), "Set Application.ActiveLocalizationManager");
          Application.ActiveLocalizationManager := new JsonLocalizationManager;
          Assert.IsTrue(Application.ActiveLocalizationManager is JsonLocalizationManager);
        end;
        lSite.CheckRequest;
      end;
    end;

    method DefaultsFallbackAndRawText;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"home":{"note":"  <b>& {name}</b>  ","fallback":"English"}}';
        lSite.Factory.Catalogs["/App_Private/Localization/nl.json"] := '{"home":{"note":" Nederlands ","fallback":"  "}}';
        lSite.Factory.Check := c -> begin
          var lManager := Application.ActiveLocalizationManager;
          Assert.IsTrue(lManager is JsonLocalizationManager);
          Assert.AreEqual(c.LocalizationLanguage, "en");
          Assert.AreEqual(lManager.GetText(c, "home.note"), "  <b>& {name}</b>  ");
          c.LocalizationLanguage := "nl";
          Assert.AreEqual(lManager.GetText(c, "home.note"), " Nederlands ");
          Assert.AreEqual(lManager.GetText(c, "home.fallback"), "English");
          c.LocalizationLanguage := nil;
          Assert.AreEqual(c.LocalizationLanguage, "en");
          Assert.AreEqual(lManager.GetText(c, "home.note"), "  <b>& {name}</b>  ");
        end;
        lSite.CheckRequest;
      end;
    end;

    method LanguageTagsAndInvalidPaths;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"key":"English"}';
        for each lLanguage in ["pap", "nl-nl", "zh-hant-tw", "es-419", "de-1996"] do
          lSite.Factory.Catalogs["/App_Private/Localization/"+lLanguage+".json"] := '{"key":"translated"}';
        lSite.Factory.Check := c -> begin
          var lManager := Application.ActiveLocalizationManager;
          for each lLanguage in ["PAP", "nl-NL", "zh-Hant-TW", "es-419", "de-1996"] do begin
            c.LocalizationLanguage := lLanguage;
            Assert.AreEqual(lManager.GetText(c, "key"), "translated");
          end;
          for each lLanguage in ["", "../nl", "nl/../../secret", "nl\\secret", "nl.json", " nl", "nl"#10, "en--us", "e", "english", "en-@"] do begin
            c.LocalizationLanguage := lLanguage;
            Assert.AreEqual(lManager.GetText(c, "key"), "English");
          end;
          c.LocalizationLanguage := "fr";
          Assert.AreEqual(lManager.GetText(c, "key"), "English");
        end;
        lSite.CheckRequest;
        Assert.AreEqual(lSite.Factory.Reads.Count, 7); // English, five translations, missing French only.
      end;
    end;

    method InvalidTranslationsFallbackAndEnglishFailuresExplainWhy;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"key":"English","blank":" ","number":42}';
        var lInvalid := ['{broken}', '[]', '{"key":42}', '{"key":null}', '{"key":{"nested":"no"}}', '{"key":""}'];
        for i: Integer := 0 to length(lInvalid)-1 do
          lSite.Factory.Catalogs["/App_Private/Localization/es-"+(100+i).ToString+".json"] := lInvalid[i];
        lSite.Factory.Check := c -> begin
          var lManager := Application.ActiveLocalizationManager;
          for i: Integer := 0 to length(lInvalid)-1 do begin
            c.LocalizationLanguage := "es-"+(100+i).ToString;
            Assert.AreEqual(lManager.GetText(c, "key"), "English");
          end;
          for each lKey in ["missing", "blank", "number", "key.child", "key."] do
            ExpectFailure(->lManager.GetText(c, lKey), lKey);
          ExpectFailure(->new JsonLocalizationManager("~/absent").GetText(c, "key"), "/absent/en.json");
          ExpectFailure(->new JsonLocalizationManager("~/broken").GetText(c, "key"), "/broken/en.json");
        end;
        lSite.Factory.Catalogs["/broken/en.json"] := '[]';
        lSite.CheckRequest;
      end;
    end;

    method FolderSelectionAndCachesStaySeparate;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.Catalogs["/main/en.json"] := '{"key":"main English","mainOnly":"only main"}';
        lSite.Factory.Catalogs["/main/nl.json"] := '{"key":"main Dutch"}';
        lSite.Factory.Catalogs["/apps/App_Private/Localization/en.json"] := '{"key":"apps English"}';
        lSite.Factory.Check := c -> begin
          c.LocalizationLanguage := "nl";
          var lManager := new JsonLocalizationManager("~/main", FolderResolver := x ->
            if assigned(x.Items["apps"]) then "~/apps/App_Private/Localization" else "");
          Assert.AreEqual(lManager.GetText(c, "key"), "main Dutch");
          c.Items["apps"] := true;
          Assert.AreEqual(lManager.GetText(c, "key"), "apps English");
          ExpectFailure(->lManager.GetText(c, "mainOnly"), "/apps/App_Private/Localization/en.json");
          c.Items.Remove("apps");
          Assert.AreEqual(lManager.GetText(c, "key"), "main Dutch");
          var lOther := new JsonLocalizationManager("/apps/App_Private/Localization/");
          Assert.AreEqual(lOther.GetText(c, "key"), "apps English");
        end;
        lSite.CheckRequest;
        Assert.AreEqual(lSite.Factory.Reads["/main/nl.json"], 1);
        Assert.AreEqual(lSite.Factory.Reads["/apps/App_Private/Localization/en.json"], 1);
        Assert.AreEqual(lSite.Factory.Reads["/apps/App_Private/Localization/nl.json"], 1);
      end;
    end;

    method RequestCacheAndUpdatesBetweenRequests;
    begin
      using lSite := new LocalizationFixture do begin
        var lPath := "/App_Private/Localization/en.json";
        lSite.Factory.Catalogs[lPath] := '{"key":"old"}';
        lSite.Factory.Check := c -> begin
          var lManager := Application.ActiveLocalizationManager;
          Assert.AreEqual(lManager.GetText(c, "key"), "old");
          lSite.Factory.Catalogs[lPath] := '{"key":"new"}';
          Assert.AreEqual(lManager.GetText(c, "key"), "old");
        end;
        lSite.CheckRequest;
        lSite.Factory.Check := c -> Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "key"), "new");
        lSite.CheckRequest;
        Assert.AreEqual(lSite.Factory.Reads[lPath], 2);
      end;
    end;

    method UsesSuppliedContextRatherThanAmbientContext;
    begin
      using lFirst := new LocalizationFixture do
      using lSecond := new LocalizationFixture do begin
        lFirst.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"key":"first"}';
        lSecond.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"key":"second"}';
        var lFirstContext: WebContext;
        lFirst.Factory.Check := c -> begin lFirstContext := c; end;
        lFirst.CheckRequest;
        lSecond.Factory.Check := c -> begin
          var lManager := Application.ActiveLocalizationManager;
          Assert.AreEqual(lManager.GetText(lFirstContext, "key"), "first");
          Assert.AreEqual(lManager.GetText(c, "key"), "second");
        end;
        lSecond.CheckRequest;
      end;
    end;

    method PhysicalAndEmbeddedPrivateCatalogs;
    begin
      var lRoot := System.IO.Path.Combine(System.IO.Path.GetTempPath, Guid.NewGuid.ToString);
      System.IO.Directory.CreateDirectory(System.IO.Path.Combine(lRoot, "App_Private", "Localization"));
      try
        using lSite := new LocalizationFixture do begin
          lSite.Server.PhysicalRootFolder := lRoot;
          var lPath := System.IO.Path.Combine(lRoot, "App_Private", "Localization", "en.json");
          File.WriteText(lPath, #$FEFF+'{"key":"physical"}');
          lSite.Factory.Check := c -> begin
            Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "key"), "physical");
            Assert.AreEqual(new JsonLocalizationManager("~/embedded").GetText(c, "key"), "embedded");
          end;
          lSite.CheckRequest;
          File.WriteText(lPath, '{"key":"updated"}');
          lSite.Factory.Check := c -> Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "key"), "updated");
          lSite.CheckRequest;
          using lResponse := lSite.Client.GetAsync(lSite.Url+"/App_Private/Localization/en.json").GetAwaiter.GetResult do
            Assert.AreEqual(Integer(lResponse.StatusCode), 404);
        end;
      finally
        System.IO.Directory.Delete(lRoot, true);
      end;
    end;

    method StartupRegistrationResetIsolationAndShutdown;
    begin
      using lFirst := new LocalizationFixture do
      using lSecond := new LocalizationFixture do begin
        lFirst.Factory.App.Provider := new TestLocalizationManager("first");
        lSecond.Factory.App.Provider := new TestLocalizationManager("second");
        var lLastContext: WebContext;
        lFirst.Factory.Check := c -> begin
          lLastContext := c;
          Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "anything"), "first");
          Application.ActiveLocalizationManager := nil;
          ExpectFailure(->Application.ActiveLocalizationManager.GetText(c, "key"), "No localization manager is configured");
          Application.ActiveLocalizationManager := new JsonLocalizationManager;
          Assert.IsTrue(Application.ActiveLocalizationManager = Application.ActiveLocalizationManager);
          Application.ActiveLocalizationManager := lFirst.Factory.App.Provider;
        end;
        lSecond.Factory.Check := c -> Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "anything"), "second");
        lFirst.CheckRequest;
        lSecond.CheckRequest;
        Assert.AreEqual(lFirst.Factory.App.Starts, 1);
        lFirst.Server.Stop;
        Assert.IsTrue(lFirst.Factory.App.EndProvider = lFirst.Factory.App.Provider);
        var lPrevious := WebContext.Current;
        try
          WebContext.Current := lLastContext;
          ExpectFailure(->Application.ActiveLocalizationManager.GetText(lLastContext, "key"), "No localization manager is configured");
        finally
          WebContext.Current := lPrevious;
        end;
        lSecond.CheckRequest;
        Assert.AreEqual(lSecond.Factory.App.Starts, 1);
      end;
    end;

    method ChainedTransfersCarryLanguageBeforeInitializationAndKeepQueries;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.App.Provider := new JsonLocalizationManager(FolderResolver := c ->
          if c.Request.Path.StartsWith("/apps/") then "~/apps/App_Private/Localization" else nil);
        lSite.Factory.Catalogs["/apps/App_Private/Localization/pap.json"] := '{"key":"apps Papiamentu"}';
        lSite.Factory.Catalogs["/apps/App_Private/Localization/de.json"] := '{"key":"apps German"}';
        lSite.Factory.Check := c -> begin
          case c.Request.Path of
            "/start": begin
              c.LocalizationLanguage := "nl";
              c.Items["unrelated"] := "do not copy";
              c.Server.Transfer("/middle?original=a%26b&duplicate=1&duplicate=2");
            end;
            "/middle": begin
              Assert.AreEqual(c.LocalizationLanguage, "nl");
              Assert.IsNil(c.Items["unrelated"]);
              c.LocalizationLanguage := "pap";
              raise new System.Reflection.TargetInvocationException(new TransferToNewPathException("/apps/end?original=a%26b&duplicate=1&duplicate=2"));
            end;
          end;
        end;
        Assert.AreEqual(lSite.Get("/start?discarded=yes"), "pap|apps Papiamentu|a&b|1,2||apps German");
      end;
    end;

    method ConcurrentRequestsKeepLanguagesAndProvidersIndependent;
    begin
      using lSite := new LocalizationFixture do begin
        lSite.Factory.Catalogs["/App_Private/Localization/en.json"] := '{"key":"English"}';
        lSite.Factory.Catalogs["/App_Private/Localization/nl.json"] := '{"key":"Dutch"}';
        lSite.Factory.Check := c -> begin
          var lLanguage := c.Request.QueryString["language"];
          c.LocalizationLanguage := lLanguage;
          var lExpected := if lLanguage = "nl" then "Dutch" else "English";
          for i: Integer := 0 to 20 do begin
            Assert.AreEqual(Application.ActiveLocalizationManager.GetText(c, "key"), lExpected);
            System.Threading.Thread.Yield;
          end;
        end;
        var lTasks := new List<System.Threading.Tasks.Task<String>>;
        for i: Integer := 0 to 19 do
          lTasks.Add(lSite.Client.GetStringAsync(lSite.Url+"/check?language="+if i mod 2 = 0 then "nl" else "en"));
        for each lTask in lTasks do
          Assert.AreEqual(lTask.GetAwaiter.GetResult, "ok");
        Assert.AreEqual(lSite.Factory.App.Starts, 1);
      end;
    end;

  private
    class method ExpectFailure(aAction: block: String; aFragment: String);
    begin
      try
        aAction();
      except
        on E: RemObjects.Elements.RTL.InvalidOperationException do begin
          Assert.IsTrue(E.Message.Contains(aFragment));
          exit;
        end;
      end;
      Assert.Fail("Expected localization failure: "+aFragment);
    end;
  end;

  LocalizationFixture = class(IDisposable)
  public
    constructor;
    begin
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      Factory := new LocalizationTestFactory;
      Factory.App.Provider := new JsonLocalizationManager;
      Server := new WebServer(PageFactory := Factory);
      Server.Start(lPort);
      Url := $"http://127.0.0.1:{lPort}";
    end;
    property Factory: LocalizationTestFactory; readonly;
    property Server: WebServer; readonly;
    property Url: String; readonly;
    property Client := new System.Net.Http.HttpClient; readonly;
    method Get(aPath: String): String;
    begin
      using lResponse := Client.GetAsync(Url+aPath).GetAwaiter.GetResult do begin
        var lText := lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult;
        Assert.AreEqual(Integer(lResponse.StatusCode), 200, lText);
        result := lText;
      end;
    end;
    method CheckRequest;
    begin
      Assert.AreEqual(Get("/check"), "ok");
    end;
    method Dispose;
    begin
      Server.Stop;
      Client.Dispose;
    end;
  end;

  LocalizationTestFactory = class(WebPageFactory)
  public
    property Check: block(c: WebContext);
    property App := new LocalizationTestApplication<String>; readonly;
    property Catalogs := new Dictionary<String, String>; readonly;
    property Reads := new System.Collections.Concurrent.ConcurrentDictionary<String, Integer>; readonly;
    method CreateApplication: nullable WebApplication; override;
    begin
      result := App;
    end;
    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      if aPath = "/apps/end" then
        exit new LocalizationTransferTarget;
      if aPath in ["/check", "/start", "/middle"] then
        result := new LocalizationCheckHandler(Check := Check);
    end;
    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;
    method FindEmbeddedResourceForPath(aPath: not nullable String): nullable String; override;
    begin
      if aPath = "/embedded/en.json" then
        result := "LocalizationEmbeddedEnglish";
    end;
    method OpenResource(aPath: not nullable String; aPublicOnly: Boolean): nullable Stream; override;
    begin
      if aPublicOnly then
        exit;
      if aPath.EndsWith(".json") then
        Reads.AddOrUpdate(aPath, 1, (k, v) -> v+1);
      var lText := Catalogs[aPath];
      if assigned(lText) then
        exit new MemoryStream(Encoding.UTF8.GetBytes(lText));
      result := inherited;
    end;
  end;

  LocalizationCheckHandler = class(IHttpHandler)
  public
    property Check: block(c: WebContext);
    method ProcessRequest(aContext: WebContext);
    begin
      Check(aContext);
      aContext.Response.Write("ok");
    end;
  end;

  LocalizationTransferTarget = class(Page)
  protected
    method OnInit(e: EventArgs); override;
    begin
      Assert.AreEqual(Context.LocalizationLanguage, "pap");
      Assert.IsNil(Context.Items["unrelated"]);
      var lManager := Application.ActiveLocalizationManager;
      Response.Write(Context.LocalizationLanguage+"|"+lManager.GetText(Context, "key")+"|"+
        Request.QueryString["original"]+"|"+Request.QueryString["duplicate"]+"|"+Request.QueryString["language"]+"|");
      Assert.AreEqual(Request.QueryString.Count, 2);
      Context.LocalizationLanguage := "de";
      Response.Write(lManager.GetText(Context, "key"));
    end;
  end;

  TestLocalizationManager = class(ILocalizationManager)
  public
    constructor(aText: String);
    begin
      fText := aText;
    end;
    method GetText(aContext: WebContext; aKey: String): String;
    begin
      result := fText;
    end;
  private
    field fText: String;
  end;

  // An open generic fixture is excluded from automatic application discovery
  // in other test factories sharing this assembly. This factory creates it explicitly.
  LocalizationTestApplication<T> = class(WebApplication)
  public
    property Provider: ILocalizationManager;
    property EndProvider: ILocalizationManager;
    property Starts: Integer;
    method OnStart; override;
    begin
      inc(Starts);
      if assigned(Provider) then
        Application.ActiveLocalizationManager := Provider;
    end;
    method OnEnd; override;
    begin
      EndProvider := Application.ActiveLocalizationManager;
    end;
  end;
end.
