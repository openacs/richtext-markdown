(() => {
    "use strict";

    const sourceComment = /<!--openacs-markdown:v1:([A-Za-z0-9+/]+={0,2})-->\s*$/;
    const encoder = new TextEncoder();
    const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

    function decode(value) {
        return decoder.decode(Uint8Array.from(atob(value), byte => byte.charCodeAt(0)));
    }

    function encode(value) {
        const bytes = encoder.encode(value);
        let binary = "";
        for (let offset = 0; offset < bytes.length; offset += 8192) {
            binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
        }
        return btoa(binary);
    }

    const toolbarTemplate = document.getElementById("richtext-markdown-toolbar");

    const purify = window.DOMPurify;
    const parser = window.marked && new window.marked.Marked({
        gfm: true,
        renderer: {
            checkbox({ checked }) {
                return checked ? "☑ " : "☐ ";
            }
        }
    });

    // Wiki references are plain text for Markdown; the embedding application
    // resolves them later. Preserve punctuation inside them as well.
    if (parser) {
        parser.use({ extensions: [{
            name: "wikiReference",
            level: "inline",
            start: source => source.indexOf("[["),
            tokenizer(source) {
                const match = /^\[\[[^\r\n]*?\]\]/.exec(source);
                if (match) return { type: "wikiReference", raw: match[0], text: match[0] };
            },
            renderer: token => token.text.replace(/&/g, "&amp;")
                .replace(/</g, "&lt;").replace(/>/g, "&gt;")
        }] });
    }

    const converter = typeof window.TurndownService === "function"
        ? new window.TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" })
        : null;
    if (converter) {
        const escapeMarkdown = converter.escape;
        converter.escape = text => text.split(/(\[\[[^\r\n]*?\]\])/g)
            .map((part, index) => index % 2 ? part : escapeMarkdown.call(converter, part))
            .join("");
        // These elements have no equivalent that preserves their full structure in Markdown.
        converter.keep(["table", "dl", "sub", "sup"]);
        converter.addRule("strikethrough", {
            filter: ["del", "s", "strike"],
            replacement: content => "~~" + content + "~~"
        });
    }

    function sanitize(html, asFragment = false) {
        return purify.sanitize(html, {
            USE_PROFILES: { html: true },
            FORBID_TAGS: ["form", "input", "button", "select", "textarea", "style"],
            FORBID_ATTR: ["style", "id", "name"],
            ALLOW_DATA_ATTR: false,
            RETURN_DOM_FRAGMENT: asFragment
        });
    }

    function markdownSource(html) {
        const match = sourceComment.exec(html);
        if (match) {
            try {
                return decode(match[1]);
            } catch (error) {
                // Treat malformed metadata as an ordinary HTML comment.
            }
        }
        if (html && converter) {
            try {
                const fragment = sanitize(html, true);
                // Turndown recognizes code blocks only as PRE > CODE. Legacy
                // wiki pages also use bare PRE, sometimes with styled spans.
                for (const pre of fragment.querySelectorAll("pre")) {
                    for (const br of pre.querySelectorAll("br")) br.replaceWith("\n");
                    if (pre.childNodes.length !== 1 || pre.firstChild?.nodeName !== "CODE") {
                        const code = document.createElement("code");
                        code.className = pre.querySelector("code")?.className || "";
                        code.textContent = pre.textContent;
                        pre.replaceChildren(code);
                    }
                }
                return converter.turndown(fragment);
            } catch (error) {
                // Keep the HTML editable if conversion fails.
            }
        }
        return html;
    }

    const editors = new WeakMap();
    let nextImageId = 0;

    function initialize(field, [, initialFormat, renderError, unavailable, legacyHtml, originalHtml, formatField,
        , uploadUrl, uploadToken, uploadPending, uploadError, imageLabel]) {
        const form = field && field.form;
        if (!(field instanceof HTMLTextAreaElement) || !form || field.matches(":disabled") || field.readOnly || !field.name) {
            return;
        }
        const id = field.id;
        const name = field.name;
        const expectsFormatField = formatField !== "0" && formatField !== "false";
        const format = expectsFormatField ? form.elements.namedItem(name + ".format") : null;
        if (expectsFormatField && (!(format instanceof HTMLInputElement) || format.type !== "hidden")) {
            return;
        }

        const status = document.createElement("div");
        status.setAttribute("role", "alert");
        status.hidden = true;
        field.after(status);
        if (!parser || !purify || !purify.isSupported || !toolbarTemplate) {
            if (format) format.value = initialFormat;
            status.textContent = unavailable;
            status.hidden = false;
            // Keep existing data available and prevent saving Markdown without a renderer.
            field.readOnly = true;
            form.addEventListener("submit", event => event.preventDefault());
            return;
        }

        // Reading the original HTML from the server also preserves leading newlines
        // that the browser can consume while parsing the textarea.
        const initialValue = initialFormat === "text/html" ? (originalHtml ?? field.value) : field.value;
        field.defaultValue = initialFormat === "text/html" ? markdownSource(initialValue) : initialValue;
        field.value = field.defaultValue;
        const initialSource = field.value;

        const htmlField = document.createElement("input");
        htmlField.type = "hidden";
        htmlField.name = name;
        if (field.hasAttribute("form")) {
            htmlField.setAttribute("form", field.getAttribute("form"));
        }
        field.removeAttribute("name");
        field.after(htmlField);

        const toolbar = toolbarTemplate.content.firstElementChild.cloneNode(true);
        const write = toolbar.querySelector('[data-markdown-mode="write"]');
        const previewButton = toolbar.querySelector('[data-markdown-mode="preview"]');
        write.setAttribute("aria-controls", id);
        field.before(toolbar);

        // A wrapper keeps hidden effective even when the theme sets the textarea display.
        const source = document.createElement("div");
        field.before(source);
        source.append(field);

        const preview = document.createElement("div");
        preview.id = id + ".markdown-preview";
        previewButton.setAttribute("aria-controls", preview.id);
        preview.hidden = true;
        preview.setAttribute("aria-label", previewButton.textContent.trim());
        preview.setAttribute("role", "region");
        status.before(preview);

        let cachedSource;
        let cachedHtml;
        let uploading = false;

        function showStatus(message) {
            status.textContent = message;
            status.hidden = false;
        }
        function render() {
            if (field.value !== cachedSource) {
                cachedHtml = sanitize(parser.parse(field.value, { async: false })).trim();
                cachedSource = field.value;
            }
            return cachedHtml;
        }

        function unchanged() {
            return field.value === initialSource && initialFormat !== "text/markdown";
        }

        function sync() {
            if (unchanged()) {
                // Preserve an unchanged legacy value, including its original MIME type.
                htmlField.value = initialValue;
                if (format) format.value = initialFormat;
            } else {
                const html = render();
                htmlField.value = html ? html + "\n<!--openacs-markdown:v1:" + encode(field.value) + "-->" : "";
                if (format) format.value = "text/html";
            }
        }

        function syncWithFeedback() {
            if (uploading) {
                showStatus(uploadPending);
                return false;
            }
            try {
                sync();
                status.hidden = true;
                return true;
            } catch (error) {
                showStatus(renderError);
                return false;
            }
        }

        const listeners = new AbortController();
        const options = { signal: listeners.signal };

        function selectMode(previewMode) {
            source.hidden = previewMode;
            preview.hidden = !previewMode;
            write.setAttribute("aria-pressed", String(!previewMode));
            previewButton.setAttribute("aria-pressed", String(previewMode));
            write.classList.toggle("active", !previewMode);
            previewButton.classList.toggle("active", previewMode);
        }

        function showEditor() {
            selectMode(false);
        }
        write.addEventListener("click", () => {
            showEditor();
            field.focus();
        }, options);
        field.addEventListener("invalid", showEditor, options);
        previewButton.addEventListener("click", () => {
            if (uploading) {
                return;
            }
            try {
                preview.innerHTML = unchanged()
                    ? sanitize(initialFormat === "text/html" ? initialValue : legacyHtml)
                    : render();
            } catch (error) {
                showStatus(renderError);
                return;
            }
            status.hidden = true;
            selectMode(true);
        }, options);

        if (uploadUrl && uploadToken) {
            field.addEventListener("paste", async event => {
                const image = Array.from(event.clipboardData?.files || [])
                    .find(file => file.type.startsWith("image/"));
                if (!image || event.defaultPrevented) {
                    return;
                }
                event.preventDefault();
                if (uploading) {
                    return;
                }

                const selectedText = field.value.slice(field.selectionStart, field.selectionEnd);
                const marker = "<!--openacs-image:" + Date.now() + ":" + ++nextImageId + "-->";
                field.setRangeText(marker, field.selectionStart, field.selectionEnd, "end");
                uploading = true;
                showStatus(uploadPending);
                let replacement = selectedText;
                let failed = false;
                try {
                    const body = new FormData();
                    body.append("upload", image);
                    body.append("__csrf_token", uploadToken);
                    const response = await fetch(uploadUrl, {
                        method: "POST",
                        credentials: "same-origin",
                        mode: "same-origin",
                        redirect: "error",
                        body
                    });
                    if (response.status !== 201) {
                        throw new Error("Unexpected image upload response");
                    }
                    const url = new URL((await response.text()).trim(), window.location.href);
                    if (url.origin !== window.location.origin || !/^https?:$/.test(url.protocol)) {
                        throw new Error("Unexpected image URL");
                    }
                    const alt = imageLabel.replace(/[\\[\]]/g, "\\$&");
                    replacement = "![" + alt + "](<" + url.pathname + url.search + ">)";
                } catch (error) {
                    failed = true;
                } finally {
                    const position = field.value.indexOf(marker);
                    if (position !== -1) {
                        field.setRangeText(replacement, position, position + marker.length, "preserve");
                    }
                    uploading = false;
                    syncWithFeedback();
                    if (failed) {
                        showStatus(uploadError);
                    }
                }
            }, options);
        }

        syncWithFeedback();
        field.addEventListener("change", syncWithFeedback, options);
        form.addEventListener("submit", event => {
            if (!syncWithFeedback()) {
                event.preventDefault();
            }
        }, { ...options, capture: true });
        form.addEventListener("formdata", event => {
            if (uploading) {
                return;
            }
            if (syncWithFeedback()) {
                event.formData.set(name, htmlField.value);
                if (format) event.formData.set(format.name, format.value);
            } else {
                event.formData.delete(name);
                if (format) event.formData.delete(format.name);
            }
        }, options);

        editors.set(field, () => {
            if (!syncWithFeedback()) {
                return false;
            }
            listeners.abort();
            field.name = name;
            field.defaultValue = htmlField.value;
            field.value = field.defaultValue;
            source.replaceWith(field);
            toolbar.remove();
            htmlField.remove();
            preview.remove();
            status.remove();
            editors.delete(field);
            return true;
        });
    }

    const configurations = new Map();
    for (const encoded of window.openacsMarkdownWidgets || []) {
        const config = encoded.map(decode);
        const id = config[0];
        configurations.set(id, config);
        if (config[7] !== "1" && config[7] !== "true") {
            initialize(document.getElementById(id), config);
        }
    }

    window.openacsMarkdown = {
        mountCopy(field, templateId) {
            const config = configurations.get(templateId);
            if (config && !editors.has(field)) {
                const current = config.slice();
                current[5] = field.value;
                initialize(field, current);
            }
        },
        restore(field) {
            return editors.get(field)?.() ?? true;
        }
    };
})();
