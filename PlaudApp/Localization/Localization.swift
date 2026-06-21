import SwiftUI
import Observation

// MARK: - Apparence

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    var titleKey: String {
        switch self {
        case .system: return "appearance_system"
        case .light:  return "appearance_light"
        case .dark:   return "appearance_dark"
        }
    }
}

// MARK: - Langue

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en, zh
    var id: String { rawValue }

    /// Libellé affiché dans le sélecteur (langues dans leur propre graphie).
    var nativeName: String {
        switch self {
        case .system: return ""          // remplacé par la chaîne localisée "language_system"
        case .fr:     return "Français"
        case .en:     return "English"
        case .zh:     return "中文"
        }
    }
}

/// Identifiant de locale courant, lu par les modèles (formatage de dates)
/// sans dépendance directe à l'environnement SwiftUI.
enum AppLocale {
    static var identifier: String = "en_US"
}

// MARK: - Réglages observables

@Observable
@MainActor
final class AppSettings {
    var appearanceRaw: String {
        didSet { UserDefaults.standard.set(appearanceRaw, forKey: "appearance") }
    }
    var languageRaw: String {
        didSet {
            UserDefaults.standard.set(languageRaw, forKey: "language")
            AppLocale.identifier = localeIdentifier
        }
    }

    // MARK: Notion

    /// ID de la database Notion cible (non sensible).
    var notionDatabaseID: String {
        didSet { UserDefaults.standard.set(notionDatabaseID, forKey: "notionDatabaseID") }
    }
    /// Token d'intégration Notion — stocké dans le Keychain, jamais en clair.
    var notionToken: String {
        didSet { Keychain.set(notionToken, account: "notion-token") }
    }
    /// Synchroniser automatiquement après chaque rafraîchissement de la liste.
    var notionAutoSync: Bool {
        didSet { UserDefaults.standard.set(notionAutoSync, forKey: "notionAutoSync") }
    }

    var notionConfigured: Bool {
        !notionToken.isEmpty && !notionDatabaseID.isEmpty
    }

    init() {
        appearanceRaw = UserDefaults.standard.string(forKey: "appearance") ?? AppearanceMode.system.rawValue
        languageRaw = UserDefaults.standard.string(forKey: "language") ?? AppLanguage.system.rawValue
        notionDatabaseID = UserDefaults.standard.string(forKey: "notionDatabaseID") ?? ""
        notionToken = Keychain.get(account: "notion-token") ?? ""
        notionAutoSync = UserDefaults.standard.bool(forKey: "notionAutoSync")
        AppLocale.identifier = localeIdentifier
    }

    var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }
    var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .system }

    /// Code langue effectif (résout `.system` via les préférences de l'OS).
    var effectiveLang: String {
        if language == .system {
            let pref = Locale.preferredLanguages.first ?? "en"
            if pref.hasPrefix("fr") { return "fr" }
            if pref.hasPrefix("zh") { return "zh" }
            return "en"
        }
        return language.rawValue
    }

    var localeIdentifier: String {
        switch effectiveLang {
        case "fr": return "fr_FR"
        case "zh": return "zh_Hans"
        default:   return "en_US"
        }
    }

    // MARK: Traduction

    func t(_ key: String) -> String {
        let lang = effectiveLang
        return Strings.table[lang]?[key]
            ?? Strings.table["en"]?[key]
            ?? key
    }

    /// Compteur avec unité pluralisée : « 3 interventions », « 1 speaker »…
    func count(_ n: Int, _ oneKey: String, _ manyKey: String) -> String {
        let unit = t(n <= 1 ? oneKey : manyKey)
        return "\(n) \(unit)"
    }

    /// Résumé lisible d'une passe de synchro Notion.
    func notionSyncSummary(created: Int, updated: Int, skipped: Int, failed: Int, errors: [String]) -> String {
        var line = "\(t("notion_created")) : \(created)   ·   \(t("notion_updated")) : \(updated)   ·   \(t("notion_skipped")) : \(skipped)"
        if failed > 0 {
            line += "   ·   \(t("notion_failed")) : \(failed)"
            let detail = errors.prefix(5).joined(separator: "\n")
            if !detail.isEmpty { line += "\n\n" + detail }
        }
        return line
    }
}
