ad_library {
    Integrate Markdown with the OpenACS richtext widget.

    @author Gustaf Neumann
    @creation-date 18 Nov 2026
}

namespace eval ::richtext::markdown {}

ad_proc ::richtext::markdown::initialize_widget {
    -form_id
    -text_id
    {-options {}}
} {
    Attach the Markdown editor to an OpenACS richtext textarea.
} {
    set value [::template::element::get_property $form_id $text_id value]
    set format [::template::util::richtext::get_property format $value]
    if {$format ni [::template::util::richtext::formats]} {
        set format text/html
    }

    set image_upload_url [expr {[dict exists $options image_upload_url]
                               ? [dict get $options image_upload_url] : ""}]
    add_editor -text_id $text_id -format $format -image_upload_url $image_upload_url \
        -contents [::template::util::richtext::get_property contents $value]
}

ad_proc -public ::richtext::markdown::add_editor {
    -text_id:required
    -contents:required
    {-format text/html}
    {-format_field:boolean true}
    -repeat_template:boolean
    {-image_upload_url ""}
} {
    Enhance a textarea with the Markdown editor and submit rendered HTML.

    @param text_id the textarea ID
    @param contents the original textarea content before browser normalization
    @param format MIME type of the original content
    @param format_field whether the form has a companion MIME type field
    @param repeat_template whether the textarea is a disabled repeat template
    @param image_upload_url optional same-origin endpoint for pasted image blobs
} {
    set base /resources/richtext-markdown
    set ::acs_blank_master(markdown_toolbar) 1
    ::template::head::add_javascript -defer -order 10.1 -src urn:ad:js:marked
    ::template::head::add_javascript -defer -order 10.2 -src urn:ad:js:dompurify
    ::template::head::add_javascript -defer -order 10.4 -src $base/editor.js?v=8

    set original_html {}
    set legacy_html {}
    if {$format eq "text/html"} {
        set original_html $contents
        if {$original_html ne "" || $repeat_template_p} {
            ::template::head::add_javascript -defer -order 10.3 -src urn:ad:js:turndown
        }
    } elseif {$format ne "text/markdown"} {
        set legacy_html [ad_html_text_convert -from $format -to text/html -- $contents]
    }

    set image_options {}
    if {$image_upload_url ne ""} {
        set image_options [list $image_upload_url [::security::csrf::new] \
            [::lang::message::lookup "" richtext-markdown.Image_upload_pending "Uploading pasted image..." {} 0 0] \
            [::lang::message::lookup "" richtext-markdown.Image_upload_error "The image could not be uploaded." {} 0 0] \
            [::lang::message::lookup "" richtext-markdown.Pasted_image "Pasted image" {} 0 0]]
    }

    # Base64 keeps values out of the inline script syntax.
    set arguments {}
    foreach value [list $text_id $format \
                       [_ richtext-markdown.Render_error] [_ richtext-markdown.Unavailable] \
                       $legacy_html $original_html \
                       [string is true -strict $format_field_p] \
                       [string is true -strict $repeat_template_p] \
                       {*}$image_options] {
        lappend arguments \"[binary encode base64 [encoding convertto utf-8 $value]]\"
    }
    ::template::head::add_javascript -script [format {
        (window.openacsMarkdownWidgets ||= []).push([%s]);
    } [join $arguments {, }]]
    return {}
}

ad_proc ::richtext::markdown::render_widgets {} {
    Provide one theme-rendered toolbar template for all Markdown widgets on the page.
} {
    if {[info exists ::acs_blank_master(markdown_toolbar)]} {
        unset ::acs_blank_master(markdown_toolbar)
        ::template::add_footer -src /packages/richtext-markdown/lib/editor-toolbar
    }
}
