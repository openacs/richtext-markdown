ad_page_contract {
    Show Markdown editor libraries, their current sources, and upstream advisories.
} {
}

permission::require_permission -object_id [acs_magic_object security_context_root] -privilege admin

set title "Richtext Markdown - Sitewide Admin"
set context [list $title]
set resource_path vendor

set marked_info [::richtext::markdown::marked::resource_info]
set marked_installed_p [dict get $marked_info local_p]
set marked_download_url download?library=marked

set dompurify_info [::richtext::markdown::dompurify::resource_info]
set dompurify_installed_p [dict get $dompurify_info local_p]
set dompurify_download_url download?library=dompurify

set turndown_info [::richtext::markdown::turndown::resource_info]
set turndown_installed_p [dict get $turndown_info local_p]
set turndown_download_url download?library=turndown
