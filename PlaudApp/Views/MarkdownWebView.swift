import SwiftUI
import WebKit

/// WebView qui rend du HTML/Markdown avec un style Apple natif.
/// Remplit son conteneur et gère son propre scroll.
struct MarkdownWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsMagnification = false
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        wv.loadHTMLString(wrapped(html), baseURL: nil)
    }

    // MARK: - Markdown → HTML

    static func convert(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var out = ""
        var i = 0
        var listStack: [(tag: String, indent: Int)] = []

        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }

        func inline(_ s: String) -> String {
            var r = escape(s)
            let opts: NSRegularExpression.Options = []
            func re(_ pattern: String, _ repl: String) {
                r = r.replacingOccurrences(of: pattern, with: repl, options: [.regularExpression])
            }
            re(#"\*\*\*(.+?)\*\*\*"#, "<strong><em>$1</em></strong>")
            re(#"\*\*(.+?)\*\*"#,    "<strong>$1</strong>")
            re(#"__(.+?)__"#,        "<strong>$1</strong>")
            re(#"\*(.+?)\*"#,        "<em>$1</em>")
            re(#"_([^_\s][^_]*)_"#, "<em>$1</em>")
            re(#"`([^`]+)`"#,        "<code>$1</code>")
            return r
        }

        func indent(of line: String) -> Int {
            line.prefix(while: { $0 == " " }).count
        }

        func closeLists(downTo level: Int) {
            while let top = listStack.last, top.indent >= level {
                out += "</\(top.tag)>\n"
                listStack.removeLast()
            }
        }

        func openList(tag: String, ind: Int) {
            closeLists(downTo: ind)
            if listStack.last?.indent != ind || listStack.last?.tag != tag {
                out += "<\(tag)>\n"
                listStack.append((tag, ind))
            }
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ind = indent(of: raw)

            // Headings
            if trimmed.hasPrefix("### ") {
                closeLists(downTo: 0)
                out += "<h3>\(inline(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("## ") {
                closeLists(downTo: 0)
                out += "<h2>\(inline(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                closeLists(downTo: 0)
                out += "<h1>\(inline(String(trimmed.dropFirst(2))))</h1>\n"

            // Unordered list
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                openList(tag: "ul", ind: ind)
                out += "<li>\(inline(String(trimmed.dropFirst(2))))</li>\n"

            // Ordered list
            } else if let m = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
                openList(tag: "ol", ind: ind)
                let body = String(trimmed[m.upperBound...])
                out += "<li>\(inline(body))</li>\n"

            // Blockquote
            } else if trimmed.hasPrefix("> ") {
                closeLists(downTo: 0)
                out += "<blockquote>\(inline(String(trimmed.dropFirst(2))))</blockquote>\n"

            // Double-dash detail line (Plaud-specific)
            } else if trimmed.hasPrefix("--") {
                closeLists(downTo: 0)
                out += "<p class=\"detail\">\(inline(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))</p>\n"

            // HR
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                closeLists(downTo: 0)
                out += "<hr>\n"

            // Empty line
            } else if trimmed.isEmpty {
                closeLists(downTo: 0)
                out += "<div class=\"gap\"></div>\n"

            // Paragraph
            } else {
                closeLists(downTo: 0)
                out += "<p>\(inline(trimmed))</p>\n"
            }
            i += 1
        }
        closeLists(downTo: 0)
        return out
    }

    // MARK: - HTML wrapper

    private func wrapped(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        *, *::before, *::after { box-sizing: border-box; }
        html, body {
            margin: 0; padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 13px;
            line-height: 1.65;
            background: transparent;
            color: #1d1d1f;
            -webkit-font-smoothing: antialiased;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #f5f5f7; }
        }
        .content { padding: 16px 20px; }
        h1 { font-size: 1.35em; font-weight: 700; margin: 1em 0 0.35em; padding-bottom: 0.2em; border-bottom: 1px solid rgba(128,128,128,0.2); }
        h2 { font-size: 1.15em; font-weight: 600; margin: 1em 0 0.25em; color: #0071e3; }
        @media (prefers-color-scheme: dark) { h2 { color: #0a84ff; } }
        h3 { font-size: 1em; font-weight: 600; margin: 0.8em 0 0.2em; }
        p { margin: 0.3em 0; }
        p.detail {
            margin: 0.15em 0 0.15em 1.2em;
            color: #6e6e73;
            font-size: 0.93em;
        }
        @media (prefers-color-scheme: dark) { p.detail { color: #98989d; } }
        ul, ol { margin: 0.25em 0; padding-left: 1.6em; }
        li { margin: 0.12em 0; }
        li > ul, li > ol { margin: 0.1em 0; }
        blockquote {
            border-left: 3px solid #0071e3;
            margin: 0.5em 0;
            padding: 0.25em 0.75em;
            color: #6e6e73;
            font-style: italic;
        }
        @media (prefers-color-scheme: dark) {
            blockquote { border-color: #0a84ff; color: #98989d; }
        }
        code {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 0.88em;
            background: rgba(128,128,128,0.12);
            padding: 0.1em 0.35em;
            border-radius: 4px;
        }
        hr { border: none; border-top: 1px solid rgba(128,128,128,0.2); margin: 1em 0; }
        .gap { height: 6px; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        .section-title {
            font-size: 1.15em;
            font-weight: 600;
            color: #0071e3;
            margin: 0 0 0.5em;
            padding-bottom: 0.2em;
            border-bottom: 1px solid rgba(0,113,227,0.2);
        }
        @media (prefers-color-scheme: dark) {
            .section-title { color: #0a84ff; border-color: rgba(10,132,255,0.2); }
        }
        .section { margin-bottom: 1.5em; }
        </style>
        </head>
        <body>
        <div class="content">
        \(body)
        </div>
        </body>
        </html>
        """
    }
}
