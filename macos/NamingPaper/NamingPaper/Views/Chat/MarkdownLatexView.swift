import SwiftUI
import WebKit

/// Renders markdown + LaTeX content using a WKWebView with locally bundled marked.js and KaTeX.
struct MarkdownLatexView: NSViewRepresentable {
    let content: String
    @Binding var dynamicHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Use the katex resource folder as baseURL so CSS can find fonts
        let baseURL = Bundle.main.resourceURL?.appendingPathComponent("Resources/katex") ?? Bundle.main.bundleURL
        let html = Self.buildHTML(content: content)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dynamicHeight: $dynamicHeight)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var dynamicHeight: Binding<CGFloat>

        init(dynamicHeight: Binding<CGFloat>) {
            self.dynamicHeight = dynamicHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.dynamicHeight.wrappedValue = h
                    }
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

        // Regex patterns for citation matching — use raw strings to avoid Swift escape issues
        // Match [p.3], [p. 3], [pp.3-5], [pp. 3-5] with brackets
        let citeBracketPattern = #"\[pp?\.\s*(\d+)(?:\s*[-–]\s*(\d+))?\]"#
        // Match (p.3), (p. 525), (pp. 3-5) with parentheses
        let citeParenPattern = #"\(pp?\.\s*(\d+)(?:\s*[-–]\s*(\d+))?\)"#
        // Match [page 3] or [Page 3]
        let citeWordPattern = #"\[page\s+(\d+)\]"#

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

            // Convert citation patterns into clickable superscript badges
            function citeBadge(match, p1) {
                return '<a class="citation" href="namingpaper://page/' + p1 + '">' + '\\u2197\\u00A0' + p1 + '</a>';
            }
            html = html.replace(new RegExp(\(Self.jsStringLiteral(citeBracketPattern)), 'gi'), citeBadge);
            html = html.replace(new RegExp(\(Self.jsStringLiteral(citeParenPattern)), 'gi'), citeBadge);
            html = html.replace(new RegExp(\(Self.jsStringLiteral(citeWordPattern)), 'gi'), citeBadge);

            document.getElementById('content').innerHTML = html;
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
