<%@ Page Language="Oxygene" AutoEventWireup="true" %>
<script runat="server">
method Page_Load(aSender: Object; aEventArgs: EventArgs);
begin
  HiddenPanel.Visible := false;
end;
</script>
<asp:Panel ID="VisiblePanel" runat="server" CssClass="visible-panel">
  <span>visible child</span>
</asp:Panel>
<asp:Panel ID="HiddenPanel" runat="server" CssClass="hidden-panel">
  <span>hidden child</span>
</asp:Panel>
