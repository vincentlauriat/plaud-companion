import Foundation

enum PlaudError: LocalizedError {
    case tokenMissing
    case noRefreshToken
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .tokenMissing:
            #if os(iOS)
            return "Token Plaud introuvable. Colle ton token dans les Réglages (⚙️)."
            #else
            return "Token Plaud introuvable. \(Self.reconnectHint)"
            #endif
        case .noRefreshToken: return "Token expiré et aucun refresh token disponible. \(Self.reconnectHint)"
        case .httpError(let code):
            switch code {
            case 401, 403:
                return "Accès refusé (HTTP \(code)). Ta session Plaud a peut-être expiré. \(Self.reconnectHint)"
            default:
                return "Erreur HTTP \(code)"
            }
        }
    }

    /// Où se reconnecter : dans l'app si le client OAuth dédié est configuré, sinon via le MCP.
    private static var reconnectHint: String {
        #if os(macOS)
        if PlaudOAuth.isConfigured { return "Reconnecte-toi dans Réglages → Compte Plaud." }
        return "Reconnecte-toi via Claude Code (login MCP Plaud)."
        #else
        return "Colle un nouveau token dans les Réglages (⚙️)."
        #endif
    }
}

/// Photographie de l'état du token pour l'UI des Réglages (sans déclencher de refresh).
struct PlaudTokenInfo: Sendable {
    let expiresAt: Date?
    let hasRefreshToken: Bool
    let isExpired: Bool
}

actor TokenStore {
    static let shared = TokenStore()

    // macOS : fichier partagé `~/.plaud/tokens-mcp.json` écrit par le CLI MCP Plaud.
    // iOS : pas de home partagé → on stocke dans le conteneur de l'app
    // (`Application Support/Plaud/tokens-mcp.json`), alimenté par l'utilisateur
    // (collage du token dans les Réglages ou import via l'app Fichiers).
    private let tokenURL: URL = {
        #if os(macOS)
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".plaud/tokens-mcp.json")
        #else
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plaud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tokens-mcp.json")
        #endif
    }()

    private let refreshURL = URL(string:
        "https://platform.plaud.ai/developer/api/oauth/third-party/access-token/refresh")!

    func getAccessToken() async throws -> String {
        let tokens = try load()
        guard tokens.isExpired else { return tokens.accessToken }
        return try await refreshOrReload(tokens)
    }

    /// Force un rafraîchissement du token quel que soit `expires_at`. Utile quand
    /// le serveur rejette l'access token (401/403) avant son expiration nominale
    /// (révocation ou rotation côté serveur, `expires_at` local trop optimiste).
    func forceRefresh() async throws -> String {
        let tokens = try load()
        return try await refreshOrReload(tokens)
    }

    /// Rafraîchit ; en cas d'échec, relit le fichier : le MCP Plaud (ou un login) a pu
    /// le réécrire entre-temps avec des tokens neufs, rendant notre refresh token caduc.
    private func refreshOrReload(_ tokens: TokenSet) async throws -> String {
        do {
            return try await refresh(tokens).accessToken
        } catch {
            if let current = try? load(), current.accessToken != tokens.accessToken, !current.isExpired {
                return current.accessToken
            }
            throw error
        }
    }

    /// Enregistre des tokens obtenus par un login (connexion OAuth intégrée).
    func store(_ tokens: TokenSet) throws {
        try save(tokens)
    }

    /// `true` si un fichier de token valide est présent (décodable).
    func hasToken() -> Bool {
        (try? load()) != nil
    }

    /// État courant du token pour affichage, ou `nil` si aucun fichier valide.
    func tokenInfo() -> PlaudTokenInfo? {
        guard let tokens = try? load() else { return nil }
        return PlaudTokenInfo(
            expiresAt: tokens.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            hasRefreshToken: tokens.refreshToken != nil,
            isExpired: tokens.isExpired
        )
    }

    /// Importe un token collé par l'utilisateur (contenu de `tokens-mcp.json`).
    /// Surtout utile sur iOS où il n'existe pas de fichier `~/.plaud` partagé.
    /// Lève `PlaudError.tokenMissing` si le JSON est invalide.
    func importToken(json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(TokenSet.self, from: data),
              !tokens.accessToken.isEmpty else {
            throw PlaudError.tokenMissing
        }
        try save(tokens)
    }

    private func load() throws -> TokenSet {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            throw PlaudError.tokenMissing
        }
        let data = try Data(contentsOf: tokenURL)
        return try JSONDecoder().decode(TokenSet.self, from: data)
    }

    private func save(_ tokens: TokenSet) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(tokens)
        // Mêmes droits que le MCP Plaud : dossier 0700, fichier 0600, réappliqués à chaque
        // écriture. Fichier temporaire créé directement en 0600 puis renommé : le MCP ne
        // lit jamais un JSON à moitié écrit, et les tokens ne passent jamais par du 0644.
        let fm = FileManager.default
        let dir = tokenURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let tmp = dir.appendingPathComponent(".\(tokenURL.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data,
                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(tmp.path, tokenURL.path) != 0 {
            let code = errno
            try? fm.removeItem(at: tmp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func refresh(_ tokens: TokenSet) async throws -> TokenSet {
        guard let refreshToken = tokens.refreshToken else {
            throw PlaudError.noRefreshToken
        }
        var req = URLRequest(url: refreshURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(plaudUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = "refresh_token=\(refreshToken)".data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudError.httpError(http.statusCode)
        }

        struct RefreshResponse: Codable {
            let accessToken: String
            let refreshToken: String?
            let tokenType: String?
            let expiresIn: Double?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
            }
        }
        let resp2 = try JSONDecoder().decode(RefreshResponse.self, from: data)
        let newTokens = TokenSet(
            accessToken: resp2.accessToken,
            refreshToken: resp2.refreshToken ?? tokens.refreshToken,
            tokenType: resp2.tokenType ?? "Bearer",
            expiresAt: resp2.expiresIn.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }
        )
        try save(newTokens)
        return newTokens
    }
}
