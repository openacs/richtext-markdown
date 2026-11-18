ad_page_contract {
    Install the configured Markdown editor library on disk.
} {
    library:word,notnull
}

permission::require_permission -object_id [acs_magic_object security_context_root] -privilege admin

if {$library ni {marked dompurify turndown}} {
    ad_return_complaint 1 "Unknown Markdown editor library."
    ad_script_abort
}

set resource [::richtext::markdown::${library}::resource_info]
if {[ns_conn method] eq "GET"} {
    if {[dict get $resource local_p]} {
        ad_returnredirect .
        ad_script_abort
    }
    set title "Download [dict get $resource resourceName] [dict get $resource configuredVersion]"
    set context [list [list . "Richtext Markdown - Sitewide Admin"] $title]
    set csrf_token [security::csrf::new]
    return
}
if {[ns_conn method] ne "POST"} {
    ad_return_exception_page 405 "Method Not Allowed" "Use the download button on the sitewide admin page."
    ad_script_abort
}
security::csrf::new
security::csrf::validate

if {![dict get $resource local_p]} {
    try {
        ::richtext::markdown::download $resource
        ns_eval -sync {::util::resources::register_urns -prefix richtext::markdown}
    } on error {message} {
        ns_log error "richtext-markdown: $message"
        ad_return_error "Library download failed" "The configured library could not be installed. Check the server log for details."
        ad_script_abort
    }
}
ad_returnredirect .
