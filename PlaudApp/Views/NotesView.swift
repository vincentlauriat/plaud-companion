import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NotesView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: RecordingsViewModel
    /// `true` pour l'onglet Résumé (uniquement `auto_sum_note`, sans sélecteur).
    let summaryOnly: Bool

    @State private var selectedId: String = ""
    @State private var exporting = false

    /// Notes affichables : contenu inline (`dataContent`) ou distant (`dataLink`).
    private var available: [NoteSection] {
        let withContent = vm.notes.filter { s in
            (s.dataContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                || (s.dataLink?.isEmpty == false)
        }
        return summaryOnly ? withContent.filter { $0.dataType == "auto_sum_note" } : withContent
    }

    private var current: NoteSection? {
        available.first { $0.dataId == selectedId } ?? available.first
    }

    private func label(_ s: NoteSection) -> String {
        switch s.dataType {
        case "auto_sum_note": return settings.t("note_summary")
        case "high_light":    return settings.t("note_highlights")
        default:
            let t = s.displayTitle
            return t.isEmpty ? settings.t("note_generic") : t
        }
    }

    var body: some View {
        if available.isEmpty {
            ContentUnavailableView(
                settings.t("no_notes_title"),
                systemImage: "note.text",
                description: Text(settings.t("no_notes_desc"))
            )
        } else {
            VStack(spacing: 0) {
                toolbar
                content
            }
        }
    }

    // MARK: Barre d'outils (sélecteur + export images)

    @ViewBuilder
    private var toolbar: some View {
        if let s = current {
            let images = s.imageURLs
            let showPicker = !summaryOnly && available.count > 1
            let ready = vm.noteContents[s.dataId]?.isEmpty == false
            HStack(spacing: 10) {
                if showPicker {
                    // Menu plutôt qu'un Picker : le libellé replié est tronqué sur une
                    // ligne (ne « mange » plus l'écran), alors que le menu déroulé
                    // montre chaque titre en entier.
                    Menu {
                        ForEach(available) { n in
                            Button {
                                selectedId = n.dataId
                            } label: {
                                if n.dataId == s.dataId {
                                    Label(label(n), systemImage: "checkmark")
                                } else {
                                    Text(label(n))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(label(s))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 320, alignment: .leading)
                    }
                }
                Spacer()
                Button {
                    Task { await exportWord() }
                } label: {
                    Label(settings.t("export_word"), systemImage: "doc.richtext")
                }
                .disabled(exporting || !ready)
                .help(settings.t("export_word_help"))
                if !images.isEmpty {
                    Button {
                        Task { await exportImages(images) }
                    } label: {
                        Label(
                            images.count == 1 ? settings.t("save_image") : settings.t("save_images"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .disabled(exporting)
                    .help(settings.t("save_images_help"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            Divider()
        }
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if let s = current {
            if let md = vm.noteContents[s.dataId] {
                if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        settings.t("no_notes_title"),
                        systemImage: "note.text",
                        description: Text(settings.t("no_notes_desc"))
                    )
                } else {
                    MarkdownWebView(html: bodyHTML(md, section: s))
                }
            } else if let err = vm.noteErrors[s.dataId] {
                ContentUnavailableView {
                    Label(settings.t("note_load_failed"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button(settings.t("retry")) {
                        Task {
                            vm.noteErrors[s.dataId] = nil
                            await vm.loadNoteContent(s)
                        }
                    }
                }
            } else {
                ProgressView(settings.t("loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await vm.loadNoteContent(s) }
            }
        }
    }

    private func bodyHTML(_ markdown: String, section: NoteSection) -> String {
        var html = ""
        if !summaryOnly {
            let title = label(section)
            if !title.isEmpty {
                html += "<h2 class=\"section-title\">\(title)</h2>\n"
            }
        }
        html += MarkdownWebView.convert(markdown)
        return "<div class=\"section\">\(html)</div>"
    }

    // MARK: Export images

    private func exportImages(_ urls: [URL]) async {
        exporting = true
        defer { exporting = false }
        let base = sanitized(vm.selectedRecording?.displayName ?? "image")
        await ImageExporter.export(urls, suggestedName: base.isEmpty ? "image" : base)
    }

    private func exportWord() async {
        guard let s = current,
              let markdown = vm.noteContents[s.dataId], !markdown.isEmpty else { return }
        exporting = true
        defer { exporting = false }
        let recordingName = vm.selectedRecording?.displayName ?? ""
        let titled = recordingName.isEmpty ? label(s) : "\(recordingName) — \(label(s))"
        let base = sanitized(titled)
        await DocxExporter.export(
            markdown: markdown,
            noteTitle: label(s),
            recordingName: recordingName,
            suggestedName: base.isEmpty ? "note" : base
        )
    }

    private func sanitized(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { !bad.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Export d'images vers le disque

enum ImageExporter {
    /// Enregistre/partage une ou plusieurs images.
    /// - macOS : panneau natif d'enregistrement (`NSSavePanel`/`NSOpenPanel`).
    /// - iOS : feuille de partage (`UIActivityViewController`) après téléchargement local.
    @MainActor
    static func export(_ urls: [URL], suggestedName: String) async {
        guard !urls.isEmpty else { return }

        #if os(macOS)
        if urls.count == 1 {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(suggestedName).\(ext(urls[0]))"
            guard panel.runModal() == .OK, let dest = panel.url else { return }
            await download(urls[0], to: dest)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let dir = panel.url else { return }
            for (i, url) in urls.enumerated() {
                let dest = dir.appendingPathComponent("\(suggestedName)_\(i + 1).\(ext(url))")
                await download(url, to: dest)
            }
        }
        #else
        // Télécharge chaque image dans un fichier temporaire nommé, puis partage.
        let tmp = FileManager.default.temporaryDirectory
        var files: [URL] = []
        for (i, url) in urls.enumerated() {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let name = urls.count == 1
                ? "\(suggestedName).\(ext(url))"
                : "\(suggestedName)_\(i + 1).\(ext(url))"
            let dest = tmp.appendingPathComponent(name)
            if (try? data.write(to: dest)) != nil { files.append(dest) }
        }
        guard !files.isEmpty else { return }
        ShareSheet.present(files)
        #endif
    }

    private static func ext(_ url: URL) -> String {
        let e = url.pathExtension
        return e.isEmpty ? "jpg" : e
    }

    #if os(macOS)
    private static func download(_ url: URL, to dest: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: dest)
        } catch {
            // Échec silencieux : une image manquante ne doit pas bloquer les autres.
        }
    }
    #endif
}

#if os(iOS)
/// Présente une feuille de partage iOS depuis n'importe quel contexte `@MainActor`.
enum ShareSheet {
    @MainActor
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad : ancre le popover au centre pour éviter un crash sans source.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
}
#endif

// MARK: - Export d'une note en document Word (.docx)

/// Génère un véritable `.docx` (Office Open XML) à la main : mise en page
/// (titres, listes, cases à cocher, gras/italique, tableaux) + **images
/// embarquées** dans `word/media`. Les API `NSAttributedString` ne savent pas
/// inclure d'images dans un `.docx`, d'où cette génération directe (OOXML + ZIP).
enum DocxExporter {
    private struct Span { var text = ""; var bold = false; var italic = false; var code = false; var strike = false }
    private struct DocxImage { let data: Data; let ext: String; let rId: String; let fileName: String; let cx: Int; let cy: Int }

    @MainActor
    static func export(markdown: String, noteTitle: String, recordingName: String, suggestedName: String) async {
        // 1. Télécharge les images référencées (octets + dimensions).
        var images: [String: DocxImage] = [:]
        var n = 1
        for url in orderedImageURLs(in: markdown) {
            if let img = await downloadImage(url, index: n) { images[url] = img; n += 1 }
        }

        // 2. Corps OOXML + 3. paquet .docx (ZIP « stored »).
        let body = buildBody(markdown: markdown, title: noteTitle, subtitle: recordingName, images: images)
        let docx = package(documentBody: body, images: images)

        // 4. Enregistrement.
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = "\(suggestedName).docx"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? docx.write(to: dest)
        #else
        // iOS : écrit dans un fichier temporaire puis ouvre la feuille de partage.
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(suggestedName).docx")
        guard (try? docx.write(to: dest)) != nil else { return }
        ShareSheet.present([dest])
        #endif
    }

    // MARK: Images

    private static func orderedImageURLs(in md: String) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in MarkdownToNotion.imagePaths(in: md) where p.hasPrefix("http") {
            if seen.insert(p).inserted { out.append(p) }
        }
        return out
    }

    private static func downloadImage(_ urlString: String, index: Int) async -> DocxImage? {
        // Dimensions lues via ImageIO (CoreGraphics) — portable macOS/iOS, sans AppKit.
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pixelsWide = props[kCGImagePropertyPixelWidth] as? Double,
              let pixelsHigh = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        var ext = url.pathExtension.lowercased()
        if ext == "jpeg" { ext = "jpg" }
        if !["png", "jpg", "gif"].contains(ext) { ext = "jpg" }
        let maxW = 600.0   // largeur max en points (page A4 ≈ 6,3")
        let scale = pixelsWide > maxW ? maxW / pixelsWide : 1.0
        let cx = max(1, Int(pixelsWide * scale * 9525))   // 1 px = 9525 EMU
        let cy = max(1, Int(pixelsHigh * scale * 9525))
        return DocxImage(data: data, ext: ext, rId: "rId\(100 + index)",
                         fileName: "image\(index).\(ext)", cx: cx, cy: cy)
    }

    // MARK: Markdown → corps OOXML

    private static func buildBody(markdown: String, title: String, subtitle: String,
                                  images: [String: DocxImage]) -> String {
        var out = paragraph(runs(spans(title), boldAll: true, sz: 40))
        if !subtitle.isEmpty {
            out += paragraph(runs(spans(subtitle), italicAll: true, sz: 22, color: "666666"))
        }
        out += hr()

        let lines = markdown.components(separatedBy: "\n")
        var i = 0, docPr = 1

        func isTableSep(_ s: String) -> Bool {
            s.range(of: #"^\s*\|?[\s:|-]*-{1,}[\s:|-]*\|?\s*$"#, options: .regularExpression) != nil
                && s.contains("-") && s.contains("|")
        }
        func cells(_ s: String) -> [String] {
            var l = s.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("|") { l.removeFirst() }
            if l.hasSuffix("|") { l.removeLast() }
            return l.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            let level = raw.prefix { $0 == " " }.count / 2
            if t.isEmpty { i += 1; continue }

            // Bloc de code
            if t.hasPrefix("```") {
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    out += paragraph("<w:r><w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/><w:sz w:val=\"20\"/></w:rPr><w:t xml:space=\"preserve\">\(escape(lines[i]))</w:t></w:r>")
                    i += 1
                }
                i += 1
                continue
            }
            // Tableau GFM
            if t.contains("|"), i + 1 < lines.count, isTableSep(lines[i + 1]) {
                let header = cells(t)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard r.contains("|"), !r.isEmpty else { break }
                    rows.append(cells(r)); i += 1
                }
                out += table(header: header, rows: rows)
                continue
            }
            // Image seule
            if t.range(of: #"^!\[[^\]]*\]\([^)]+\)$"#, options: .regularExpression) != nil {
                if let url = MarkdownToNotion.imagePaths(in: t).first, let img = images[url] {
                    out += drawing(img, docPrId: docPr); docPr += 1
                }
                i += 1; continue
            }
            // Titres 1–6
            if let h = t.range(of: #"^#{1,6} "#, options: .regularExpression) {
                let lvl = t.distance(from: t.startIndex, to: h.upperBound) - 1
                let sizes = [34, 28, 24, 22, 22, 22]
                out += paragraph(runs(spans(String(t[h.upperBound...])), boldAll: true,
                                      sz: sizes[min(lvl, 6) - 1], color: lvl == 2 ? "1A5FB4" : nil),
                                 spacingBefore: 160)
            // Cases à cocher
            } else if let cb = t.range(of: #"^[-*] \[[ xX]\] "#, options: .regularExpression) {
                let checked = t.lowercased().hasPrefix("- [x]") || t.lowercased().hasPrefix("* [x]")
                out += paragraph(plain(checked ? "☑  " : "☐  ") + runs(spans(String(t[cb.upperBound...]))),
                                 indent: 360 + level * 360)
            // Liste à puces
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                out += paragraph(plain("•  ") + runs(spans(String(t.dropFirst(2)))),
                                 indent: 360 + level * 360)
            // Liste numérotée
            } else if let m = t.range(of: #"^\d+\. "#, options: .regularExpression) {
                out += paragraph(plain(String(t[..<m.upperBound])) + runs(spans(String(t[m.upperBound...]))),
                                 indent: 360 + level * 360)
            // Citation
            } else if t.hasPrefix("> ") {
                out += paragraph(runs(spans(String(t.dropFirst(2))), italicAll: true, color: "555555"),
                                 indent: 360)
            // Séparateur
            } else if t.range(of: #"^([-*_])\1{2,}$"#, options: .regularExpression) != nil {
                out += hr()
            // Ligne détail Plaud
            } else if t.hasPrefix("--") {
                out += paragraph(runs(spans(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)),
                                      color: "888888"), indent: 360)
            // Paragraphe
            } else {
                out += paragraph(runs(spans(t)))
            }
            i += 1
        }
        return out
    }

    // MARK: Inline → runs

    /// Découpe un texte Markdown inline en segments stylés (gras/italique/code/barré).
    private static func spans(_ raw: String) -> [Span] {
        // Liens → texte ; images inline retirées (gérées en blocs).
        var s = raw.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1", options: [.regularExpression])
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: [.regularExpression])
        var result: [Span] = []
        var bold = false, italic = false, code = false, strike = false
        var buf = ""
        func emit() {
            guard !buf.isEmpty else { return }
            result.append(Span(text: buf, bold: bold, italic: italic, code: code, strike: strike))
            buf = ""
        }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count {
                let two = String(chars[i...i + 1])
                if two == "**" { emit(); bold.toggle(); i += 2; continue }
                if two == "~~" { emit(); strike.toggle(); i += 2; continue }
            }
            switch chars[i] {
            case "*": emit(); italic.toggle()
            case "`": emit(); code.toggle()
            default: buf.append(chars[i])
            }
            i += 1
        }
        emit()
        return result
    }

    private static func runs(_ list: [Span], boldAll: Bool = false, italicAll: Bool = false,
                             sz: Int? = nil, color: String? = nil) -> String {
        list.map { sp in
            let b = sp.bold || boldAll, it = sp.italic || italicAll
            var rpr = ""
            if b || it || sp.code || sp.strike || sz != nil || color != nil {
                rpr = "<w:rPr>"
                if b { rpr += "<w:b/>" }
                if it { rpr += "<w:i/>" }
                if sp.strike { rpr += "<w:strike/>" }
                if sp.code { rpr += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/>" }
                if let sz { rpr += "<w:sz w:val=\"\(sz)\"/><w:szCs w:val=\"\(sz)\"/>" }
                if let color { rpr += "<w:color w:val=\"\(color)\"/>" }
                rpr += "</w:rPr>"
            }
            return "<w:r>\(rpr)<w:t xml:space=\"preserve\">\(escape(sp.text))</w:t></w:r>"
        }.joined()
    }

    private static func plain(_ s: String) -> String {
        "<w:r><w:t xml:space=\"preserve\">\(escape(s))</w:t></w:r>"
    }

    // MARK: Paragraphes / tableaux / images (OOXML)

    private static func paragraph(_ runsXML: String, indent: Int = 0, spacingBefore: Int = 0) -> String {
        var ppr = ""
        if indent > 0 || spacingBefore > 0 {
            ppr = "<w:pPr>"
            if spacingBefore > 0 { ppr += "<w:spacing w:before=\"\(spacingBefore)\"/>" }
            if indent > 0 { ppr += "<w:ind w:left=\"\(indent)\"/>" }
            ppr += "</w:pPr>"
        }
        return "<w:p>\(ppr)\(runsXML)</w:p>"
    }

    private static func hr() -> String {
        "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"CCCCCC\"/></w:pBdr></w:pPr></w:p>"
    }

    private static func table(header: [String], rows: [[String]]) -> String {
        let cols = max(header.count, rows.map(\.count).max() ?? 0)
        guard cols > 0 else { return "" }
        func cell(_ text: String, bold: Bool) -> String {
            "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr>\(paragraph(runs(spans(text), boldAll: bold)))</w:tc>"
        }
        func row(_ arr: [String], bold: Bool) -> String {
            var c = arr; while c.count < cols { c.append("") }
            return "<w:tr>" + c.prefix(cols).map { cell($0, bold: bold) }.joined() + "</w:tr>"
        }
        let b = "<w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/>"
        let borders = "<w:tblBorders>"
            + "<w:top w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/><w:left w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/>"
            + b + "<w:right w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/>"
            + "<w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"999999\"/>"
            + "</w:tblBorders>"
        var grid = "<w:tblGrid>"; for _ in 0..<cols { grid += "<w:gridCol/>" }; grid += "</w:tblGrid>"
        var t = "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/>\(borders)</w:tblPr>\(grid)"
        t += row(header, bold: true)
        for r in rows { t += row(r, bold: false) }
        t += "</w:tbl><w:p/>"
        return t
    }

    private static func drawing(_ img: DocxImage, docPrId: Int) -> String {
        "<w:p><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
        + "<wp:extent cx=\"\(img.cx)\" cy=\"\(img.cy)\"/><wp:docPr id=\"\(docPrId)\" name=\"\(img.fileName)\"/>"
        + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic>"
        + "<pic:nvPicPr><pic:cNvPr id=\"\(docPrId)\" name=\"\(img.fileName)\"/><pic:cNvPicPr/></pic:nvPicPr>"
        + "<pic:blipFill><a:blip r:embed=\"\(img.rId)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
        + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(img.cx)\" cy=\"\(img.cy)\"/></a:xfrm>"
        + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>"
        + "</wp:inline></w:drawing></w:r></w:p>"
    }

    // MARK: Empaquetage .docx

    private static func package(documentBody: String, images: [String: DocxImage]) -> Data {
        let doc = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
            + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
            + " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
            + " xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\""
            + " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
            + " xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>"
            + documentBody
            + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1134\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\"/></w:sectPr></w:body></w:document>"

        let contentTypes = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>"
            + "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/><Default Extension=\"gif\" ContentType=\"image/gif\"/>"
            + "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

        let rels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

        var docRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for img in images.values {
            docRels += "<Relationship Id=\"\(img.rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(img.fileName)\"/>"
        }
        docRels += "</Relationships>"

        var zip = DocxZip()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rels.utf8))
        zip.add("word/document.xml", Data(doc.utf8))
        zip.add("word/_rels/document.xml.rels", Data(docRels.utf8))
        for img in images.values { zip.add("word/media/\(img.fileName)", img.data) }
        return zip.finalize()
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Mini écrivain ZIP (méthode « stored », sans compression)

private struct DocxZip {
    private var out = Data()
    private struct Entry { let name: String; let crc: UInt32; let size: Int; let offset: Int }
    private var entries: [Entry] = []

    private func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    private func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    mutating func add(_ name: String, _ content: Data) {
        let crc = DocxCRC32.checksum(content)
        let offset = out.count
        let nb = Data(name.utf8)
        out.append(le32(0x0403_4b50)); out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(0)); out.append(le16(0)); out.append(le32(crc))
        out.append(le32(UInt32(content.count))); out.append(le32(UInt32(content.count)))
        out.append(le16(UInt16(nb.count))); out.append(le16(0)); out.append(nb); out.append(content)
        entries.append(Entry(name: name, crc: crc, size: content.count, offset: offset))
    }

    mutating func finalize() -> Data {
        let cdStart = out.count
        var cd = Data()
        for e in entries {
            let nb = Data(e.name.utf8)
            cd.append(le32(0x0201_4b50)); cd.append(le16(20)); cd.append(le16(20)); cd.append(le16(0))
            cd.append(le16(0)); cd.append(le16(0)); cd.append(le16(0)); cd.append(le32(e.crc))
            cd.append(le32(UInt32(e.size))); cd.append(le32(UInt32(e.size)))
            cd.append(le16(UInt16(nb.count))); cd.append(le16(0)); cd.append(le16(0)); cd.append(le16(0))
            cd.append(le16(0)); cd.append(le32(0)); cd.append(le32(UInt32(e.offset))); cd.append(nb)
        }
        out.append(cd)
        out.append(le32(0x0605_4b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(cd.count))); out.append(le32(UInt32(cdStart))); out.append(le16(0))
        return out
    }
}

private enum DocxCRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
