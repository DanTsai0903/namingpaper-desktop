import SwiftUI
import WebKit

/// Renders markdown + LaTeX content using a WKWebView with locally bundled marked.js and KaTeX.
struct MarkdownLatexView: NSViewRepresentable {
    let content: String
    @Binding var dynamicHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChanged")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        // The bubble's SwiftUI frame is sized to the body's scrollHeight, so the
        // WKWebView itself should never need to scroll. Suppress the scroll view's
        // bounce/elasticity so a stray pixel can't drag content out of place.
        webView.enclosingScrollView?.verticalScrollElasticity = .none
        webView.enclosingScrollView?.horizontalScrollElasticity = .none
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Use the katex resource folder as baseURL so CSS can find fonts
        let baseURL = Bundle.main.resourceURL?.appendingPathComponent("Resources/katex") ?? Bundle.main.bundleURL
        let html = Self.buildHTML(content: content)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dynamicHeight: $dynamicHeight)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var dynamicHeight: Binding<CGFloat>

        init(dynamicHeight: Binding<CGFloat>) {
            self.dynamicHeight = dynamicHeight
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightChanged" else { return }
            let h: CGFloat
            if let n = message.body as? NSNumber {
                h = CGFloat(truncating: n)
            } else if let d = message.body as? Double {
                h = CGFloat(d)
            } else {
                return
            }
            DispatchQueue.main.async {
                if abs(self.dynamicHeight.wrappedValue - h) > 0.5 {
                    self.dynamicHeight.wrappedValue = h
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.scheme == "namingpaper", url.host == "page",
                   let pageStr = url.pathComponents.last, let page = Int(pageStr) {
                    NotificationCenter.default.post(name: .navigateToPage, object: nil, userInfo: ["page": page])
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    // MARK: - HTML

    private static func buildHTML(content: String) -> String {
        // JSON-encode the content so it's safe to embed in JS
        let jsonData = try! JSONEncoder().encode(content)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Regex patterns for citation matching — use raw strings to avoid Swift escape issues.
        // Captures the inside (digits + commas + dashes + spaces) so the JS callback can
        // split it into multiple badges. Supports forms like:
        //   [p. 3]  [p.3]  [pp. 3-5]  [Page 3]  [Pages 3, 4, 5]  [p. 1, 5]
        let citeBracketPattern = #"\[(?:pp?\.|pages?)\s*(\d[\d\s,\-–]*)\]"#
        // Same shapes wrapped in parentheses: (p. 525), (pp. 3-5), (Pages 3, 4, 5)
        let citeParenPattern = #"\((?:pp?\.|pages?)\s*(\d[\d\s,\-–]*)\)"#

        // Read bundled JS/CSS inline so we don't depend on file:// URL loading
        let katexCSS = readBundledFile("Resources/katex/katex.min.css") ?? ""
        let katexJS = readBundledFile("Resources/katex/katex.min.js") ?? ""
        let markedJS = readBundledFile("Resources/marked.min.js") ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(katexCSS)</style>
        <script>\(katexJS)</script>
        <script>\(markedJS)</script>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            /* Suppress all scrolling at the document level — the SwiftUI frame is
               sized to scrollHeight by the heightChanged callback, so the bubble
               always encloses the full content. If the reported height ever lags
               behind reality, we'd rather clip than show a scrollbar inside the
               bubble (which the user explicitly does not want). */
            html, body { overflow: hidden !important; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                font-size: 13px;
                line-height: 1.5;
                color: #e0e0e0;
                padding: 0;
                -webkit-font-smoothing: antialiased;
            }
            h1, h2, h3, h4, h5, h6 {
                margin-top: 12px;
                margin-bottom: 6px;
                font-weight: 600;
            }
            h1 { font-size: 18px; }
            h2 { font-size: 16px; }
            h3 { font-size: 15px; }
            h4 { font-size: 14px; }
            p { margin-bottom: 8px; }
            ul, ol { margin-bottom: 8px; padding-left: 20px; }
            li { margin-bottom: 4px; }
            li > ul, li > ol { margin-bottom: 0; }
            code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 12px;
                background: rgba(255,255,255,0.08);
                padding: 1px 4px;
                border-radius: 3px;
            }
            pre {
                background: rgba(255,255,255,0.06);
                padding: 10px;
                border-radius: 6px;
                overflow-x: auto;
                margin-bottom: 8px;
            }
            pre code { background: none; padding: 0; }
            strong { font-weight: 600; }
            .katex-display {
                margin: 12px 0;
                overflow-x: auto;
                overflow-y: hidden;
            }
            .katex { font-size: 1.05em; }
            blockquote {
                border-left: 3px solid rgba(255,255,255,0.2);
                padding-left: 12px;
                margin: 8px 0;
                color: #aaa;
            }
            a { color: #5ac8c8; }
            a.citation {
                display: inline-flex;
                align-items: center;
                gap: 2px;
                font-size: 10px;
                font-weight: 600;
                padding: 1px 5px;
                background: rgba(90,200,200,0.15);
                color: #5ac8c8 !important;
                border-radius: 4px;
                text-decoration: none;
                cursor: pointer;
                vertical-align: super;
                line-height: 1;
                margin: 0 1px;
            }
            a.citation:hover { background: rgba(90,200,200,0.3); }

            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
                code { background: rgba(0,0,0,0.06); }
                pre { background: rgba(0,0,0,0.04); }
                blockquote { border-left-color: rgba(0,0,0,0.2); color: #666; }
            }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        (function() {
            var raw = \(jsonString);

            // Protect code blocks from math processing
            var codeBlocks = [];
            raw = raw.replace(/```[\\s\\S]*?```/g, function(m) {
                codeBlocks.push(m);
                return '%%CODE_' + (codeBlocks.length - 1) + '%%';
            });
            raw = raw.replace(/`[^`\\n]+`/g, function(m) {
                codeBlocks.push(m);
                return '%%CODE_' + (codeBlocks.length - 1) + '%%';
            });

            // Extract display math $$...$$
            var displayMath = [];
            raw = raw.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(_, tex) {
                displayMath.push(tex);
                return '%%DMATH_' + (displayMath.length - 1) + '%%';
            });

            // Extract inline math $...$
            var inlineMath = [];
            raw = raw.replace(/\\$([^\\$\\n]+?)\\$/g, function(_, tex) {
                inlineMath.push(tex);
                return '%%IMATH_' + (inlineMath.length - 1) + '%%';
            });

            // Restore code blocks before markdown
            for (var c = 0; c < codeBlocks.length; c++) {
                raw = raw.replace('%%CODE_' + c + '%%', codeBlocks[c]);
            }

            // Render markdown
            var html = marked.parse(raw);

            // Render display math
            for (var i = 0; i < displayMath.length; i++) {
                var rendered;
                try {
                    rendered = katex.renderToString(displayMath[i].trim(), { displayMode: true, throwOnError: false });
                } catch(e) {
                    rendered = '<pre>' + displayMath[i] + '</pre>';
                }
                html = html.replace('%%DMATH_' + i + '%%', rendered);
            }

            // Render inline math
            for (var j = 0; j < inlineMath.length; j++) {
                var rendered;
                try {
                    rendered = katex.renderToString(inlineMath[j].trim(), { displayMode: false, throwOnError: false });
                } catch(e) {
                    rendered = '<code>' + inlineMath[j] + '</code>';
                }
                html = html.replace('%%IMATH_' + j + '%%', rendered);
            }

            // Convert citation patterns into clickable superscript badges.
            // The inner capture may contain a single page ("3"), a range ("3-5"),
            // a comma-separated list ("3, 4, 5"), or a mix ("1, 3-5, 7"). Emit one
            // badge per part so each is independently clickable.
            function citeBadges(match, inner) {
                if (!inner) return match;
                var parts = inner.split(/\\s*,\\s*/);
                var out = '';
                for (var i = 0; i < parts.length; i++) {
                    var part = parts[i].trim();
                    var rangeMatch = part.match(/^(\\d+)\\s*[-\\u2013]\\s*(\\d+)$/);
                    if (rangeMatch) {
                        var start = rangeMatch[1];
                        var end = rangeMatch[2];
                        out += '<a class="citation" href="namingpaper://page/' + start + '">\\u2197\\u00A0' + start + '-' + end + '</a>';
                    } else if (/^\\d+$/.test(part)) {
                        out += '<a class="citation" href="namingpaper://page/' + part + '">\\u2197\\u00A0' + part + '</a>';
                    }
                }
                return out || match;
            }
            html = html.replace(new RegExp(\(Self.jsStringLiteral(citeBracketPattern)), 'gi'), citeBadges);
            html = html.replace(new RegExp(\(Self.jsStringLiteral(citeParenPattern)), 'gi'), citeBadges);

            document.getElementById('content').innerHTML = html;

            // Push body height back to the host whenever it changes so the SwiftUI
            // bubble stays exactly as tall as the rendered content — that way the
            // WKWebView never has anything to scroll. Use ONLY body.scrollHeight:
            // documentElement.clientHeight (and offsetHeight) reflect the WKWebView
            // viewport, which equals whatever frame SwiftUI just gave us. Mixing
            // those into a Math.max creates a feedback loop — the bubble keeps
            // ratcheting up because each new frame grows the viewport, which then
            // gets reported back as the "content" height.
            function postHeight() {
                var h = Math.ceil(document.body.scrollHeight);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightChanged) {
                    window.webkit.messageHandlers.heightChanged.postMessage(h);
                }
            }
            postHeight();
            if (typeof ResizeObserver !== 'undefined') {
                var ro = new ResizeObserver(function() { postHeight(); });
                ro.observe(document.body);
            }
            window.addEventListener('load', postHeight);
            if (document.fonts && document.fonts.ready) {
                document.fonts.ready.then(postHeight);
            }
            // Belt-and-braces: a few delayed re-measurements catch late layout
            // shifts from KaTeX font swaps that ResizeObserver may miss when the
            // glyph metrics change without altering the body box.
            setTimeout(postHeight, 50);
            setTimeout(postHeight, 200);
            setTimeout(postHeight, 600);
        })();
        </script>
        </body>
        </html>
        """
    }

    /// Converts a Swift string into a single-quoted JS string literal,
    /// escaping backslashes and single quotes so the regex pattern survives intact.
    private static func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    private static func readBundledFile(_ relativePath: String) -> String? {
        // Try as a resource path component
        let components = relativePath.split(separator: "/")
        let filename: String
        let subdirectory: String?

        if components.count > 1 {
            filename = String(components.last!)
            subdirectory = components.dropLast().joined(separator: "/")
        } else {
            filename = relativePath
            subdirectory = nil
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}
