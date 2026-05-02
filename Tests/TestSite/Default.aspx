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
%>
query=<%=Request.QueryString["q"]%>
form=<%=Request.Form["name"]%>
session=<%=lCount%>
application=<%=RemObjects.Elements.Web.Application["last-query"]%>
seen=<%=Request.Cookies["Seen"]:Value%>
flavor=<%=Request.Cookies["Flavor"]:Values["kind"]%>
<test:EchoControl ID="Echo" runat="server" Message="from-control" />
</asp:Content>
