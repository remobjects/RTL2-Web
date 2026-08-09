namespace RemObjects.Elements.Web;

type
  HtmlLandingPage = public static class
  public

    class method RenderCardPage(aTitle: not nullable String; aBodyHtml: not nullable String): not nullable String;
    begin
      result := ##"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>{{EscapeHtml(aTitle)}}</title>
          <style>
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #f5f7fb;
              color: #1f2937;
            }
            .wrap {
              max-width: 48rem;
              margin: 8vh auto;
              padding: 0 1.5rem;
            }
            .card {
              background: white;
              border-radius: 16px;
              box-shadow: 0 18px 50px rgba(15, 23, 42, 0.10);
              padding: 1.75rem;
              border: 1px solid #e5e7eb;
              overflow: hidden;
            }
            h1 {
              margin: 0 0 0.75rem;
              font-size: 1.5rem;
              line-height: 1.2;
            }
            p {
              margin: 0.5rem 0;
              line-height: 1.5;
            }
            code {
              background: #f3f4f6;
              padding: 0.1rem 0.35rem;
              border-radius: 6px;
            }
            a { color: #7c83ff; }
            @media (max-width: 36rem) {
              .wrap {
                margin: 1rem auto;
                padding: 0 1rem;
              }
              .card {
                border-radius: 12px;
                padding: 1.25rem;
              }
            }
            @media (prefers-color-scheme: dark) {
              body {
                background: #111827;
                color: #e5e7eb;
              }
              .card {
                background: #1f2937;
                border-color: #374151;
                box-shadow: 0 18px 50px rgba(0, 0, 0, 0.35);
              }
              code { background: #374151; }
              a { color: #a5b4fc; }
            }
          </style>
        </head>
        <body>
          <div class="wrap">
            <main class="card">
              {{aBodyHtml}}
            </main>
          </div>
        </body>
        </html>
        """;
    end;

    class method EscapeHtml(aValue: nullable String): not nullable String;
    begin
      result := coalesce(aValue, "");
      result := result.Replace("&", "&amp;");
      result := result.Replace("<", "&lt;");
      result := result.Replace(">", "&gt;");
      result := result.Replace("""", "&quot;");
      result := result.Replace("'", "&#39;");
    end;

  end;

end.
