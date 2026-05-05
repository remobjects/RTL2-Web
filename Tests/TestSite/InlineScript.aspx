<%@ Page Language="Oxygene" %>
<script runat="server">
method InlineMessage: String;
begin
  result := "inline-script-ok";
end;
</script>
<%= InlineMessage %>
