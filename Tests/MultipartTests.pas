namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.Elements.Web;

type
  MultipartTests = public class(Test)
  public
    method BoundaryLinesPreservePayload;
    begin
      // Positive/negative guards: only complete delimiter lines split binary files and adjacent fields.
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new MultipartTestFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          for each lPayload in ["abc"+#13#10+"--ESP-boundary-not-a-boundary"+#0+#255,
                                "--ESP-boundary-at-content-start",
                                "inline--ESP-boundary"+#13#10+"tail",
                                "abc"+#13#10+"--ESP-boundary--invalid",
                                "abc"+#13#10+"--ESP-boundary "+#9+"invalid",
                                "abc"+#13#10+"--ESP-boundar", ""] do begin
            for each lEnding in ["--", "--"+#13#10, "-- "+#9+#13#10] do begin
              var lBody := "--ESP-boundary"+#13#10+
                'Content-Disposition: form-data; name="file"; filename="data.bin"'+#13#10+#13#10+
                lPayload+#13#10+"--ESP-boundary "+#9+#13#10+
                'Content-Disposition: form-data; name="note"'+#13#10+#13#10+
                "after"+#13#10+"--ESP-boundary"+lEnding;
              var lBytes := System.Text.Encoding.UTF8.GetBytes(lBody);
              using lContent := new System.Net.Http.ByteArrayContent(lBytes) do begin
                lContent.Headers.ContentType := new System.Net.Http.Headers.MediaTypeHeaderValue("multipart/form-data");
                lContent.Headers.ContentType.Parameters.Add(new System.Net.Http.Headers.NameValueHeaderValue("boundary", "ESP-boundary"));
                using lResponse := lClient.PostAsync($"http://127.0.0.1:{lPort}/upload", lContent).GetAwaiter.GetResult do begin
                  Assert.AreEqual(Integer(lResponse.StatusCode), 200);
                  Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult,
                    "after|1|"+System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(lPayload)));
                end;
              end;
            end;
          end;
        end;
      finally
        lServer.Stop;
      end;
    end;
  end;

  MultipartTestFactory = class(WebPageFactory)
  public
    method FindClassForPath(aPath: not nullable String): nullable Object; override;
    begin
      result := new MultipartTestHandler;
    end;
    method FindRedirectForPath(aPath: not nullable String): nullable String; override; empty;
  end;

  MultipartTestHandler = class(IHttpHandler)
  public
    method ProcessRequest(Context: WebContext);
    begin
      var lFile := Context.Request.Files[0];
      var lBytes := new Byte[lFile.ContentLength];
      var lStream := lFile.InputStream;
      var lOffset := 0;
      while lOffset < length(lBytes) do begin
        var lRead := lStream.Read(lBytes, lOffset, length(lBytes)-lOffset);
        if lRead = 0 then break;
        inc(lOffset, lRead);
      end;
      Context.Response.Write(Context.Request.Form["note"]+"|"+Context.Request.Files.Count.ToString+"|"+System.Convert.ToBase64String(lBytes));
    end;
  end;
end.
