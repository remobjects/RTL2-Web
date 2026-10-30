namespace RemObjects.Elements.Web.Tests;

uses
  RemObjects.Elements.EUnit,
  RemObjects.InternetPack.Http,
  RemObjects.Elements.Web;

type
  MultipartTests = public class(Test)
  public
    method ChunkedRequestFraming;
    begin
      // Contract: framing is decoded with validation on/off; trailers cannot consume the next request and malformed/ambiguous bodies never dispatch.
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      for each lValidate in [true, false] do begin
        var lServer := new ChunkedTransportServer(Port := lPort, ValidateRequests := lValidate, CloseConnectionsOnShutdown := true);
        lServer.Open;
        try
          var lHead := "POST / HTTP/1.1"+#13#10+"Host: localhost"+#13#10;
          var lChunked := "Transfer-Encoding: ChUnKeD"+#13#10;
          var lClose := "Connection: close"+#13#10#13#10;
          var lBody := "3;test=yes"+#13#10+"abc"+#13#10+"0"+#13#10+"X-Note: ignored"+#13#10#13#10;
          var lNext := lHead+"Content-Length: 1"+#13#10+lClose+"z";
          var lResult := SendChunkedProbe(lPort, lHead+lChunked+"Connection: keep-alive"+#13#10#13#10+lBody+lNext);
          Assert.IsTrue(lResult.Contains("3:abc"));
          Assert.IsTrue(lResult.Contains("1:z"));
          Assert.AreEqual(lServer.Dispatched, 2);
          for each lInvalid in ["G"+#13#10, "80000000"+#13#10, "1"+#13#10+"aX"+#13#10, "0"+#10#10] do begin
            lResult := SendChunkedProbe(lPort, lHead+lChunked+lClose+lInvalid);
            Assert.IsTrue(lResult.Contains(" 400 ") or lResult.Contains(" 413 "));
          end;
          lResult := SendChunkedProbe(lPort, lHead+lChunked+"Content-Length: invalid"+#13#10+lClose+lBody);
          Assert.IsTrue(lResult.Contains(" 400 "));
          lResult := SendChunkedProbe(lPort, lHead+"Transfer-Encoding: gzip, chunked"+#13#10+lClose+lBody);
          Assert.IsTrue(lResult.Contains(" 501 "));
          Assert.AreEqual(lServer.Dispatched, 2);
          // Contract: the shared decoder still reads chunked client responses with or without keep-alive.
          for each lKeepAlive in [false, true] do begin
            var lClient := new RemObjects.InternetPack.Http.HttpClient(KeepAlive := lKeepAlive);
            using lResponse := lClient.GetResponse($"http://127.0.0.1:{lPort}/client") do begin
              Assert.AreEqual(lResponse.ContentString, "reply");
              lResponse.DataConnection.Close;
            end;
          end;
        finally
          lServer.Close;
        end;
      end;
    end;

    method SendChunkedProbe(aPort: Integer; aRequest: String): String;
    private;
    begin
      using lClient := new System.Net.Sockets.TcpClient do begin
        lClient.ReceiveTimeout := 5000;
        lClient.Connect(System.Net.IPAddress.Loopback, aPort);
        using lStream := lClient.GetStream do begin
          var lBytes := System.Text.Encoding.ASCII.GetBytes(aRequest);
          lStream.Write(lBytes, 0, length(lBytes));
          lClient.Client.Shutdown(System.Net.Sockets.SocketShutdown.Send);
          using lReader := new System.IO.StreamReader(lStream) do
            result := lReader.ReadToEnd;
        end;
      end;
    end;

    method BoundaryLinesPreservePayload; public;
    begin
      // Contract: fixed/chunked bodies split only at complete delimiters; preserve raw 00/FF bytes and adjacent fields.
      var lReservation := new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
      lReservation.Start;
      var lPort := (lReservation.LocalEndpoint as System.Net.IPEndPoint).Port;
      lReservation.Stop;
      var lServer := new WebServer(PageFactory := new MultipartTestFactory);
      lServer.Start(lPort);
      try
        using lClient := new System.Net.Http.HttpClient do begin
          for each lChunked in [false, true] do begin
          lClient.DefaultRequestHeaders.TransferEncodingChunked := lChunked;
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
              var lBytes := System.Text.Encoding.Latin1.GetBytes(lBody);
              using lContent := new System.Net.Http.ByteArrayContent(lBytes) do begin
                lContent.Headers.ContentType := new System.Net.Http.Headers.MediaTypeHeaderValue("multipart/form-data");
                lContent.Headers.ContentType.Parameters.Add(new System.Net.Http.Headers.NameValueHeaderValue("boundary", "ESP-boundary"));
                using lResponse := lClient.PostAsync($"http://127.0.0.1:{lPort}/upload", lContent).GetAwaiter.GetResult do begin
                  Assert.AreEqual(Integer(lResponse.StatusCode), 200);
                  Assert.AreEqual(lResponse.Content.ReadAsStringAsync.GetAwaiter.GetResult,
                    "after|1|"+System.Convert.ToBase64String(System.Text.Encoding.Latin1.GetBytes(lPayload)));
                end;
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

  ChunkedTransportServer = class(HttpServer)
  public
    property Dispatched: Integer;
  protected
    method HandleHttpRequest(aConnection: RemObjects.InternetPack.Connection; aRequest: HttpServerRequest; aResponse: HttpServerResponse); override;
    begin
      // Contract: handler sees decoded length/content; framing failures must not reach it.
      inc(Dispatched);
      if aRequest.Path = "/client" then begin
        aResponse.BeginChunkedResponse;
        aResponse.WriteChunk("reply");
        aResponse.EndChunkedResponse;
        exit;
      end;
      aResponse.ContentString := aRequest.ContentLength.ToString+":"+aRequest.ContentString;
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
