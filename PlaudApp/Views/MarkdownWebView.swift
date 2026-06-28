import SwiftUI
import WebKit

/// WebView qui rend du HTML/Markdown avec un style Apple natif.
/// Remplit son conteneur et gère son propre scroll.
///
/// `WKWebView` est identique sur macOS et iOS ; seule la conformité au
/// protocole de représentation diffère (`NSViewRepresentable` vs
/// `UIViewRepresentable`). Le moteur Markdown→HTML (`convert`/`wrapped`) est
/// partagé entre les deux plateformes.
struct MarkdownWebView {
    let html: String

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

            // On extrait images, liens et URLs derrière des jetons AVANT
            // d'appliquer l'emphase : sinon les `_`/`*` des URLs seraient
            // interprétés comme de l'italique et casseraient le lien.
            var placeholders: [(token: String, html: String)] = []
            func protectMatches(_ pattern: String, _ build: (NSString, NSTextCheckingResult) -> String) {
                guard let rx = try? NSRegularExpression(pattern: pattern) else { return }
                let ns = r as NSString
                let matches = rx.matches(in: r, range: NSRange(location: 0, length: ns.length))
                for m in matches.reversed() {
                    let token = "\u{0001}P\(placeholders.count)\u{0001}"
                    placeholders.append((token, build(ns, m)))
                    r = (r as NSString).replacingCharacters(in: m.range, with: token)
                }
            }
            // Images
            protectMatches(#"!\[([^\]]*)\]\(([^)]+)\)"#) { ns, m in
                "<img alt=\"\(ns.substring(with: m.range(at: 1)))\" src=\"\(ns.substring(with: m.range(at: 2)))\" loading=\"lazy\">"
            }
            // Liens `[texte](url)`
            protectMatches(#"\[([^\]]+)\]\(([^)]+)\)"#) { ns, m in
                "<a href=\"\(ns.substring(with: m.range(at: 2)))\">\(ns.substring(with: m.range(at: 1)))</a>"
            }
            // URLs nues
            protectMatches(#"https?://[^\s<>\x{0001}]+"#) { ns, m in
                let url = ns.substring(with: m.range)
                return "<a href=\"\(url)\">\(url)</a>"
            }

            func re(_ pattern: String, _ repl: String) {
                r = r.replacingOccurrences(of: pattern, with: repl, options: [.regularExpression])
            }
            re(#"~~(.+?)~~"#,         "<del>$1</del>")
            re(#"\*\*\*(.+?)\*\*\*"#, "<strong><em>$1</em></strong>")
            re(#"\*\*(.+?)\*\*"#,    "<strong>$1</strong>")
            re(#"__(.+?)__"#,        "<strong>$1</strong>")
            re(#"\*(.+?)\*"#,        "<em>$1</em>")
            re(#"_([^_\s][^_]*)_"#, "<em>$1</em>")
            re(#"`([^`]+)`"#,        "<code>$1</code>")
            // Réinjecte les éléments protégés.
            for ph in placeholders {
                r = r.replacingOccurrences(of: ph.token, with: ph.html)
            }
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
            // Ferme uniquement les listes plus profondes (indentation supérieure).
            while let top = listStack.last, top.indent > ind {
                out += "</\(top.tag)>\n"
                listStack.removeLast()
            }
            // Même niveau mais type différent (ul↔ol) : on referme avant de rouvrir.
            if let top = listStack.last, top.indent == ind, top.tag != tag {
                out += "</\(top.tag)>\n"
                listStack.removeLast()
            }
            // N'ouvre une nouvelle liste que si aucune n'est déjà ouverte à ce niveau.
            if listStack.last?.indent != ind {
                out += "<\(tag)>\n"
                listStack.append((tag, ind))
            }
        }

        func isTableSep(_ s: String) -> Bool {
            // Séparateur GFM : doit contenir un `|` (évite de confondre avec un HR
            // `---` placé après une ligne de texte qui contiendrait un `|`).
            s.range(of: #"^\s*\|?[\s:|-]*-{1,}[\s:|-]*\|?\s*$"#, options: .regularExpression) != nil
                && s.contains("-") && s.contains("|")
        }
        func tableCells(_ s: String) -> [String] {
            var line = s.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") { line.removeFirst() }
            if line.hasSuffix("|") { line.removeLast() }
            return line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ind = indent(of: raw)

            // Bloc de code ``` … ```
            if trimmed.hasPrefix("```") {
                closeLists(downTo: 0)
                i += 1
                var code = ""
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code += escape(lines[i]) + "\n"
                    i += 1
                }
                out += "<pre><code>\(code)</code></pre>\n"
                i += 1   // saute le ``` fermant
                continue
            }

            // Tableau GFM : ligne d'en-tête `| … |` suivie d'un séparateur `|---|`
            if trimmed.contains("|"), i + 1 < lines.count, isTableSep(lines[i + 1]) {
                closeLists(downTo: 0)
                let header = tableCells(trimmed)
                out += "<table><thead><tr>"
                out += header.map { "<th>\(inline($0))</th>" }.joined()
                out += "</tr></thead><tbody>\n"
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard row.contains("|"), !row.isEmpty else { break }
                    let cells = tableCells(row)
                    out += "<tr>" + cells.map { "<td>\(inline($0))</td>" }.joined() + "</tr>\n"
                    i += 1
                }
                out += "</tbody></table>\n"
                continue
            }

            // Headings (1 à 6)
            if let h = trimmed.range(of: #"^#{1,6} "#, options: .regularExpression) {
                closeLists(downTo: 0)
                let level = trimmed.distance(from: trimmed.startIndex, to: h.upperBound) - 1
                let body = String(trimmed[h.upperBound...])
                out += "<h\(level)>\(inline(body))</h\(level)>\n"

            // Cases à cocher `- [ ]` / `- [x]`
            } else if let cb = trimmed.range(of: #"^[-*] \[[ xX]\] "#, options: .regularExpression) {
                openList(tag: "ul", ind: ind)
                let checked = trimmed.lowercased().hasPrefix("- [x]") || trimmed.lowercased().hasPrefix("* [x]")
                let body = String(trimmed[cb.upperBound...])
                let box = checked ? "☑" : "☐"
                let cls = checked ? "task done" : "task"
                out += "<li class=\"\(cls)\"><span class=\"cb\">\(box)</span> \(inline(body))</li>\n"

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

            // HR : une ligne composée uniquement de tirets/étoiles/underscores (3+)
            } else if trimmed.range(of: #"^([-*_])\1{2,}$"#, options: .regularExpression) != nil {
                closeLists(downTo: 0)
                out += "<hr>\n"

            // Double-dash detail line (Plaud-specific) : `--` suivi de contenu
            } else if trimmed.hasPrefix("--") {
                closeLists(downTo: 0)
                out += "<p class=\"detail\">\(inline(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))</p>\n"

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
        h4 { font-size: 0.95em; font-weight: 600; margin: 0.7em 0 0.15em; color: #3a3a3c; }
        h5, h6 { font-size: 0.9em; font-weight: 600; margin: 0.6em 0 0.15em; color: #6e6e73; }
        @media (prefers-color-scheme: dark) {
            h4 { color: #d1d1d6; }
            h5, h6 { color: #98989d; }
        }
        a { color: #0071e3; text-decoration: none; }
        a:hover { text-decoration: underline; }
        @media (prefers-color-scheme: dark) { a { color: #0a84ff; } }
        del { color: #8e8e93; }
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
        img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            margin: 0.5em 0;
            display: block;
            box-shadow: 0 1px 4px rgba(0,0,0,0.12);
        }
        .gap { height: 6px; }
        li.task { list-style: none; margin-left: -1.2em; }
        li.task .cb { color: #0071e3; font-weight: 600; margin-right: 0.3em; }
        li.task.done { color: #8e8e93; }
        li.task.done .cb { color: #34c759; }
        @media (prefers-color-scheme: dark) { li.task .cb { color: #0a84ff; } }
        pre {
            background: rgba(128,128,128,0.12);
            border-radius: 6px;
            padding: 0.7em 0.9em;
            overflow-x: auto;
            margin: 0.6em 0;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 0.85em;
            line-height: 1.5;
            white-space: pre;
        }
        table {
            border-collapse: collapse;
            margin: 0.6em 0;
            font-size: 0.95em;
            width: 100%;
        }
        th, td {
            border: 1px solid rgba(128,128,128,0.3);
            padding: 0.35em 0.6em;
            text-align: left;
            vertical-align: top;
        }
        th { background: rgba(128,128,128,0.1); font-weight: 600; }
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

// MARK: - Conformité au protocole de représentation (par plateforme)
//
// `WKWebView` est identique des deux côtés ; seule la conformité diffère
// (`NSViewRepresentable` sur macOS, `UIViewRepresentable` sur iOS). On la place
// dans des extensions conditionnelles plutôt que dans la déclaration de la
// struct, car `#if` ne peut pas scinder une déclaration de type ouverte.

#if os(macOS)
extension MarkdownWebView: NSViewRepresentable {
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
}
#else
extension MarkdownWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        // Fond transparent pour épouser l'arrière-plan SwiftUI.
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        wv.loadHTMLString(wrapped(html), baseURL: nil)
    }
}
#endif
