<%@ Page Language="Oxygene" MasterPageFile="~/Site.master" %>
<%@ Register Src="~/Shared.ascx" TagName="Shared" TagPrefix="test" %>
<asp:Content ID="Main" ContentPlaceHolderID="Content" Runat="Server">
page=two-v1
appcode=<%=SiteState.Token%>
<test:Shared runat="server" />
</asp:Content>
