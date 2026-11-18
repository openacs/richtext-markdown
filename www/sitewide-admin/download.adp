<master>
<property name="doc(title)">@title;literal@</property>
<property name="context">@context;literal@</property>

<h1>@title@</h1>
<form action="download" method="post">
  <input type="hidden" name="library" value="@library@">
  <input type="hidden" name="__csrf_token" value="@csrf_token@">
  <button type="submit" class="btn btn-secondary">Download</button>
  <a href=".">Cancel</a>
</form>
