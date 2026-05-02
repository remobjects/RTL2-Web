<%@ Page Language="Oxygene" MasterPageFile="~/Site.master" AutoEventWireup="true" Title="Default" %>
<%@ Register Src="~/Controls/EchoControl.ascx" TagName="EchoControl" TagPrefix="test" %>

<asp:Content ID="MainContent" ContentPlaceHolderID="Content" Runat="Server">
<%
  var lCount := if assigned(Session["count"]) then Int32(Session["count"]) else 0;
  inc(lCount);
  Session["count"] := lCount;
  RemObjects.Elements.Web.Application["last-query"] := Request.QueryString["q"];
  Response.Cookies["Seen"].Value := "yes";
  Response.Cookies["Flavor"]["kind"] := "chocolate";
  var lAcceptTypes := Request.AcceptTypes;
  var lUserLanguages := Request.UserLanguages;
  var lAcceptType := if length(lAcceptTypes) > 0 then lAcceptTypes[0] else "";
  var lUserLanguage := if length(lUserLanguages) > 0 then lUserLanguages[0] else "";
%>
query=<%=Request.QueryString["q"]%>
form=<%=Request.Form["name"]%>
session=<%=lCount%>
application=<%=RemObjects.Elements.Web.Application["last-query"]%>
seen=<%=Request.Cookies["Seen"]:Value%>
flavor=<%=Request.Cookies["Flavor"]:Values["kind"]%>
params-query=<%=Request.Params["q"]%>
params-form=<%=Request.Params["name"]%>
params-cookie=<%=Request.Params["Seen"]%>
params-server=<%=Request.Params["SERVER_NAME"]%>
params-default=<%=Request["q"]%>
context-current-query=<%=System.Web.HttpContext.Current.Request.QueryString["q"]%>
request-http-method=<%=Request.HttpMethod%>
request-request-type=<%=Request.RequestType%>
request-content-type=<%=Request.ContentType%>
request-content-length=<%=Request.ContentLength%>
request-total-bytes=<%=Request.TotalBytes%>
request-secure=<%=Request.IsSecureConnection%>
request-referrer=<%=Request.UrlReferrer:ToAbsoluteString%>
request-accept=<%=lAcceptType%>
request-language=<%=lUserLanguage%>
server-html=<%=Server.HtmlEncode("<server>")%>
server-url=<%=Server.UrlEncode("one two")%>
server-mappath=<%=Server.MapPath("~/Static/hello.txt").Replace("\", "/")%>
context-server-mappath=<%=System.Web.HttpContext.Current.Server.MapPath("/Static/hello.txt").Replace("\", "/")%>
request-physical-application-path=<%=Request.PhysicalApplicationPath.Replace("\", "/")%>
request-mappath=<%=Request.MapPath("Static/hello.txt").Replace("\", "/")%>
header-user-agent=<%=Request.Headers["User-Agent"]%>
header-user-agent-lower=<%=Request.Headers["user-agent"]%>
header-custom=<%=Request.Headers["X-Test-Header"]%>
server-http-host=<%=Request.ServerVariables["HTTP_HOST"]%>
server-name=<%=Request.ServerVariables["SERVER_NAME"]%>
server-port=<%=Request.ServerVariables["SERVER_PORT"]%>
server-method=<%=Request.ServerVariables["REQUEST_METHOD"]%>
server-query=<%=Request.ServerVariables["QUERY_STRING"]%>
server-path=<%=Request.ServerVariables["PATH_INFO"]%>
server-script-name=<%=Request.ServerVariables["SCRIPT_NAME"]%>
server-url=<%=Request.ServerVariables["URL"]%>
server-user-agent=<%=Request.ServerVariables["HTTP_USER_AGENT"]%>
server-name-lower=<%=Request.ServerVariables["server_name"]%>
server-https=<%=Request.ServerVariables["HTTPS"]%>
server-remote-addr=<%=Request.ServerVariables["REMOTE_ADDR"]%>
server-local-addr=<%=Request.ServerVariables["LOCAL_ADDR"]%>
<test:EchoControl ID="Echo" runat="server" Message="from-control" />
</asp:Content>
