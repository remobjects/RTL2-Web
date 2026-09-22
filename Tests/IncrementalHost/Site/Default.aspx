<%@ Page Language="Oxygene" MasterPageFile="~/Site.master" %>
<%@ Register Src="~/Shared.ascx" TagName="Shared" TagPrefix="test" %>
<asp:Content ID="Main" ContentPlaceHolderID="Content" Runat="Server">
<%
  var lCount := if assigned(Session["count"]) then Int32(Session["count"]) else 0;
  inc(lCount);
  Session["count"] := lCount;
  if not assigned(RemObjects.Elements.Web.Application["token"]) then
    RemObjects.Elements.Web.Application["token"] := SiteState.Token;
%>
page=one-v1
session=<%=lCount%>
appcode=<%=SiteState.Token%>
application=<%=RemObjects.Elements.Web.Application["token"]%>
private=<%=RemObjects.Elements.Web.WebRuntime.ReadTextFile("~/App_Private/catalog.txt")%>
<test:Shared runat="server" />
</asp:Content>
