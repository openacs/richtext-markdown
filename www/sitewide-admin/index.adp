<master>
<property name="doc(title)">@title;literal@</property>
<property name="context">@context;literal@</property>

<h1>@title@</h1>

<h2>Marked</h2>
<include src="/packages/acs-tcl/lib/check-installed"
         &resource_info=marked_info &download_url=marked_download_url
         &installed_p=marked_installed_p &=resource_path show_policy_p="0">

<h2>DOMPurify</h2>
<include src="/packages/acs-tcl/lib/check-installed"
         &resource_info=dompurify_info &download_url=dompurify_download_url
         &installed_p=dompurify_installed_p &=resource_path show_policy_p="0">

<h2>Turndown</h2>
<include src="/packages/acs-tcl/lib/check-installed"
         &resource_info=turndown_info &download_url=turndown_download_url
         &installed_p=turndown_installed_p &=resource_path show_policy_p="0">

<include src="/packages/acs-templating/lib/registered-urns" match="urn:ad:js:marked urn:ad:js:dompurify urn:ad:js:turndown">

<include src="/packages/acs-tcl/lib/external-javascript-policy">
