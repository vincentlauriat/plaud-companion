import Foundation

/// Conversion d'un texte Markdown (les notes IA de Plaud) en blocs Notion.
/// On reste volontairement simple : le rendu inline (gras/italique) n'est pas
/// parsé en rich_text structuré — chaque ligne devient un bloc lisible.
/// Notion impose : ≤ 2000 caractères par rich_text, ≤ 100 blocs par requête.
enum MarkdownToNotion {
    private static let maxText = 2000

    /// Bloc « rich_text » paragraphe/heading à partir d'un texte, découpé si > 2000 car.
    private static func richText(_ text: String) -> [[String: Any]] {
        guard !text.isEmpty else { return [] }
        var parts: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            let slice = remaining.prefix(maxText)
            parts.append(String(slice))
            remaining = remaining.dropFirst(slice.count)
        }
        return parts.map { ["type": "text", "text": ["content": $0]] }
    }

    private static func block(_ type: String, _ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": type,
            type: ["rich_text": richText(text)],
        ]
    }

    /// Convertit un Markdown complet en tableau de blocs Notion.
    static func blocks(from markdown: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("### ") {
                result.append(block("heading_3", String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(block("heading_2", String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(block("heading_1", String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                result.append(block("quote", String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(block("bulleted_list_item", String(line.dropFirst(2))))
            } else if let m = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                result.append(block("numbered_list_item", String(line[m.upperBound...])))
            } else {
                result.append(block("paragraph", line))
            }
        }
        return result
    }
}
