ad_library {
    Manage the browser libraries used by the Markdown editor.
    
    @author Gustaf Neumann
    @creation-date 18 Nov 2026
}

namespace eval ::richtext::markdown {
    namespace eval marked {}
    namespace eval dompurify {}
    namespace eval turndown {}
}

ad_proc -private ::richtext::markdown::marked::resource_info {{-version ""}} {
    Describe the Marked browser resource for OpenACS resource management.
} {
    return [::richtext::markdown::resolve_resource -version $version [dict create \
        resourceName Marked resourceDir [acs_package_root_dir richtext-markdown/www/resources/vendor] \
        cdnHost cdn.jsdelivr.net cssFiles {} jsFiles marked.umd.js extraFiles {} \
        directory lib urnMap {urn:ad:js:marked marked.umd.js} \
        versionCheckAPI {cdn jsdelivr library marked count 1} \
        vulnerabilityCheck {service snyk library marked} \
        parameterInfo {package_key richtext-markdown parameter_name MarkedVersion default_value 18.2.1}]]
}

ad_proc -private ::richtext::markdown::dompurify::resource_info {{-version ""}} {
    Describe the DOMPurify browser resource for OpenACS resource management.
} {
    return [::richtext::markdown::resolve_resource -version $version [dict create \
        resourceName DOMPurify resourceDir [acs_package_root_dir richtext-markdown/www/resources/vendor] \
        cdnHost cdn.jsdelivr.net cssFiles {} jsFiles purify.min.js extraFiles {} \
        directory dist urnMap {urn:ad:js:dompurify purify.min.js} \
        versionCheckAPI {cdn jsdelivr library dompurify count 1} \
        vulnerabilityCheck {service snyk library dompurify} \
        parameterInfo {package_key richtext-markdown parameter_name DOMPurifyVersion default_value 3.4.18}]]
}

ad_proc -private ::richtext::markdown::turndown::resource_info {{-version ""}} {
    Describe the Turndown browser resource for converting legacy HTML to Markdown.
} {
    return [::richtext::markdown::resolve_resource -version $version [dict create \
        resourceName Turndown resourceDir [acs_package_root_dir richtext-markdown/www/resources/vendor] \
        cdnHost cdn.jsdelivr.net cssFiles {} jsFiles turndown.browser.umd.js extraFiles {} \
        directory lib urnMap {urn:ad:js:turndown turndown.browser.umd.js} \
        versionCheckAPI {cdn jsdelivr library turndown count 1} \
        vulnerabilityCheck {service snyk library turndown} \
        parameterInfo {package_key richtext-markdown parameter_name TurndownVersion default_value 7.2.5}]]
}

ad_proc -private ::richtext::markdown::resolve_resource {-version resource} {
    Resolve a configured version to a local file or a versioned jsDelivr URL.
} {
    dict with resource {
        dict with parameterInfo {
            if {$version eq ""} {
                set version [::parameter::get_global_value \
                                 -package_key $package_key -parameter $parameter_name -default $default_value]
            }
            if {![regexp {^[0-9]+[.][0-9]+[.][0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$} $version]} {
                ns_log warning "richtext-markdown: invalid $parameter_name; using $default_value"
                set version $default_value
            }
        }
        set configuredVersion $version
        set library [dict get $versionCheckAPI library]
        set cdn //$cdnHost/npm
        set versionSegment ${library}@$version/$directory
        set cspMap {}
        set prefix /resources/richtext-markdown/vendor/$versionSegment
        set path $resourceDir/$versionSegment/$jsFiles
        set local_p [expr {[file isfile $path] && [file readable $path]}]
        if {!$local_p} {
            set prefix $cdn/$versionSegment
            dict set cspMap [lindex [dict keys $urnMap] 0] [list script-src $cdnHost]
        } else {
            set cdnHost ""
        }
        set downloadURL https:$cdn/$versionSegment/$jsFiles
        set metadataURL https://data.jsdelivr.com/v1/package/npm/${library}@$version/flat
        set metadataPath /$directory/$jsFiles
        foreach key {configuredVersion cdn versionSegment cspMap prefix path local_p downloadURL metadataURL metadataPath} {
            dict set resource $key [set $key]
        }
    }
    return $resource
}

ad_proc -private ::richtext::markdown::download {resource} {
    Install the selected library locally after verifying its jsDelivr checksum.
} {
    set path [dict get $resource path]
    set directory [file dirname $path]
    file mkdir $directory
    set url [dict get $resource downloadURL]
    set metadata_url [dict get $resource metadataURL]
    set metadata_response [ns_http run -verify -timeout 15s $metadata_url]
    if {[dict get $metadata_response status] != 200} {
        error "Cannot obtain checksum metadata: $metadata_url"
    }
    set metadata [::util::json2dict [dict get $metadata_response body]]
    set expected ""
    foreach entry [dict get $metadata files] {
        if {[dict get $entry name] eq [dict get $resource metadataPath]} {
            set expected [dict get $entry hash]
            break
        }
    }
    # jsDelivr's file hash is a Base64-encoded SHA-256 digest.
    if {![regexp {^[A-Za-z0-9+/]{43}=$} $expected]} {
        error "Missing or invalid SHA-256 metadata for $url"
    }

    set response [ns_http run -verify -timeout 15s -spoolsize 1 $url]
    try {
        if {[dict get $response status] != 200 || ![dict exists $response file]} {
            error "Download failed with HTTP status [dict get $response status]"
        }
        set downloaded [dict get $response file]
        if {[ns_md file -digest sha256 -encoding base64 $downloaded] ne $expected} {
            error "Download failed SHA-256 verification: $url"
        }

        # Stage the downloaded file next to its destination so publication uses a single rename.
        set channel [file tempfile staged $directory/.download-]
        close $channel
        try {
            file copy -force -- $downloaded $staged
            file attributes $staged -permissions 0644
            file rename -force -- $staged $path
        } finally {
            file delete -- $staged
        }
    } finally {
        if {[dict exists $response file]} {
            file delete -- [dict get $response file]
        }
    }
}

# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
