import Foundation

/// Configuration de la synchronisation Notion.
/// Le token d'intégration vit dans le Keychain (jamais en clair) ; seul le
/// databaseID (non sensible) est conservé dans `UserDefaults` via `AppSettings`.
enum NotionConfig {
    static let apiVersion = "2022-06-28"
    static let base = "https://api.notion.com/v1"
}

/// Extraction de l'ID Notion depuis une URL complète ou un ID brut.
/// Une URL Notion finit par 32 caractères hex (ex. `…Titre-386c45f4d9f0…`),
/// éventuellement suivis de `?v=…`. On renvoie un UUID au format 8-4-4-4-12.
enum NotionID {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutQuery = trimmed.components(separatedBy: "?").first ?? trimmed

        // Dernière séquence de 32 hexadécimaux dans l'URL/slug.
        if let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{32}") {
            let range = NSRange(withoutQuery.startIndex..., in: withoutQuery)
            if let last = regex.matches(in: withoutQuery, range: range).last,
               let r = Range(last.range, in: withoutQuery) {
                return formatUUID(String(withoutQuery[r]))
            }
        }
        // Repli : un UUID déjà tireté (les tirets cassent la regex ci-dessus).
        let hex = withoutQuery.filter(\.isHexDigit)
        if hex.count == 32 { return formatUUID(hex) }
        return withoutQuery
    }

    private static func formatUUID(_ hex32: String) -> String {
        let s = Array(hex32.lowercased())
        guard s.count == 32 else { return hex32 }
        func seg(_ a: Int, _ b: Int) -> String { String(s[a..<b]) }
        return "\(seg(0,8))-\(seg(8,12))-\(seg(12,16))-\(seg(16,20))-\(seg(20,32))"
    }
}

/// Cible de synchro résolue : l'ID fourni peut désigner une database
/// (entrées dans la table) ou une page (sous-pages créées dedans).
struct NotionTarget {
    let isDatabase: Bool
    /// Nom de la propriété de type titre. Pour une page enfant c'est « title ».
    let titleProperty: String
    /// Schéma de la database : nom de colonne → type Notion (date, number,
    /// rich_text…). Vide pour une page (pas de colonnes).
    var properties: [String: String] = [:]
}

/// État de synchronisation d'un enregistrement Plaud vers Notion.
/// Persisté localement dans `Application Support/Plaud/notion-sync.json`.
struct SyncRecord: Codable {
    let recordingID: String
    var notionPageID: String
    /// SHA-256 du contenu poussé : permet de détecter qu'un enregistrement a changé.
    var contentHash: String
    var syncedAt: Date
}

/// Résultat d'une passe de synchronisation, présenté à l'utilisateur.
struct SyncReport {
    var created = 0
    var updated = 0
    var skipped = 0
    var failed = 0
    var errors: [String] = []

    var total: Int { created + updated + skipped + failed }
    var didFail: Bool { failed > 0 }
}

enum NotionError: LocalizedError {
    case notConfigured
    case noTitleProperty
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Synchronisation Notion non configurée (token ou base manquant)."
        case .noTitleProperty:
            return "La base Notion ne contient pas de propriété de type titre."
        case .httpError(let code, let body):
            if let body, !body.isEmpty { return "Notion HTTP \(code) — \(body)" }
            return "Notion HTTP \(code)"
        }
    }
}
