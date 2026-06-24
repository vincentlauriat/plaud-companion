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

    /// Tous les chemins d'images référencés (`![alt](chemin)`) dans un texte.
    static func imagePaths(in markdown: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#) else { return [] }
        let ns = markdown as NSString
        return rx.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func todoBlock(_ text: String, checked: Bool) -> [String: Any] {
        [
            "object": "block",
            "type": "to_do",
            "to_do": ["rich_text": richText(text), "checked": checked],
        ]
    }

    private static func imageBlock(_ uploadID: String) -> [String: Any] {
        [
            "object": "block",
            "type": "image",
            "image": ["type": "file_upload", "file_upload": ["id": uploadID]],
        ]
    }

    /// Retire les images Markdown inline d'une ligne (utilisé pour le texte :
    /// les images sont gérées comme blocs séparés, jamais comme texte cassé).
    private static func stripInlineImages(_ s: String) -> String {
        s.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]+\)"#, with: "", options: [.regularExpression]
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Convertit un Markdown complet en tableau de blocs Notion.
    /// `imageUploads` mappe un chemin d'image (tel qu'il apparaît dans le
    /// Markdown) vers un identifiant `file_upload` Notion déjà téléversé : les
    /// lignes-image correspondantes deviennent des blocs image. Les images sans
    /// upload sont retirées plutôt que rendues en texte cassé.
    static func blocks(from markdown: String, imageUploads: [String: String] = [:]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        let imageLine = try? NSRegularExpression(pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#)

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Ligne constituée d'une seule image.
            if let imageLine,
               let m = imageLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let path = (line as NSString).substring(with: m.range(at: 1))
                if let uploadID = imageUploads[path] {
                    result.append(imageBlock(uploadID))
                }
                continue
            }

            // Image(s) inline au milieu de texte : on extrait l'image, on garde le texte.
            if line.contains("![") {
                for path in imagePaths(in: line) {
                    if let uploadID = imageUploads[path] { result.append(imageBlock(uploadID)) }
                }
                let text = stripInlineImages(line)
                if !text.isEmpty { result.append(block("paragraph", text)) }
                continue
            }

            // Case à cocher `- [ ]` / `- [x]` → bloc to_do natif Notion.
            if let cb = line.range(of: #"^[-*] \[[ xX]\] "#, options: .regularExpression) {
                let checked = line.lowercased().hasPrefix("- [x]") || line.lowercased().hasPrefix("* [x]")
                result.append(todoBlock(String(line[cb.upperBound...]), checked: checked))
            } else if let h = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                // Notion ne va que jusqu'à heading_3 : on plafonne les niveaux 4-6.
                let level = min(3, line.distance(from: line.startIndex, to: h.upperBound) - 1)
                result.append(block("heading_\(level)", String(line[h.upperBound...])))
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
