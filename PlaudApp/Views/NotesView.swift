import SwiftUI
import AppKit

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
        let images = current?.imageURLs ?? []
        let showPicker = !summaryOnly && available.count > 1
        if showPicker || !images.isEmpty {
            HStack(spacing: 10) {
                if showPicker {
                    Picker("", selection: Binding(
                        get: { current?.dataId ?? "" },
                        set: { selectedId = $0 }
                    )) {
                        ForEach(available) { s in
                            Text(label(s)).tag(s.dataId)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 380)
                }
                Spacer()
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

    private func sanitized(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { !bad.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Export d'images vers le disque

enum ImageExporter {
    /// Enregistre une ou plusieurs images sur le disque via un panneau natif.
    @MainActor
    static func export(_ urls: [URL], suggestedName: String) async {
        guard !urls.isEmpty else { return }

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
    }

    private static func ext(_ url: URL) -> String {
        let e = url.pathExtension
        return e.isEmpty ? "jpg" : e
    }

    private static func download(_ url: URL, to dest: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: dest)
        } catch {
            // Échec silencieux : une image manquante ne doit pas bloquer les autres.
        }
    }
}
