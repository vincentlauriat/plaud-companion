import SwiftUI

struct NotesView: View {
    @Environment(AppSettings.self) private var settings
    let notes: [NoteSection]
    let summaryOnly: Bool

    private var displayed: [NoteSection] {
        let relevant = notes.filter {
            $0.dataType == "auto_sum_note" || $0.dataType == "auto_sum_brief"
        }
        if summaryOnly {
            return Array(relevant.prefix(1))
        }
        return relevant
    }

    private var bodyHTML: String {
        displayed.compactMap { section -> String? in
            guard let content = section.dataContent,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            var html = ""
            if !summaryOnly, !section.displayTitle.isEmpty {
                html += "<h2 class=\"section-title\">\(section.displayTitle)</h2>\n"
            }
            html += MarkdownWebView.convert(content)
            return "<div class=\"section\">\(html)</div>"
        }.joined(separator: "\n")
    }

    var body: some View {
        if displayed.isEmpty {
            ContentUnavailableView(
                settings.t("no_notes_title"),
                systemImage: "note.text",
                description: Text(settings.t("no_notes_desc"))
            )
        } else {
            MarkdownWebView(html: bodyHTML)
        }
    }
}
