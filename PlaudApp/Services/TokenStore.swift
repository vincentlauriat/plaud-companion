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
            return "Token Plaud introuvable. Connecte-toi d'abord via Claude Code."
            #endif
        case .noRefreshToken: return "Token expiré et aucun refresh token disponible. Reconnecte-toi via Claude Code."
        case .httpError(let code):
            switch code {
            case 401, 403:
                return "Accès refusé (HTTP \(code)). Ta session Plaud a peut-être expiré — reconnecte-toi (login Plaud)."
            default:
                return "Erreur HTTP \(code)"
            }
        }
    }
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
        var tokens = try load()
        if tokens.isExpired {
            tokens = try await refresh(tokens)
        }
        return tokens.accessToken
    }

    /// Force un rafraîchissement du token quel que soit `expires_at`. Utile quand
    /// le serveur rejette l'access token (401/403) avant son expiration nominale
    /// (révocation ou rotation côté serveur, `expires_at` local trop optimiste).
    func forceRefresh() async throws -> String {
        let tokens = try load()
        return try await refresh(tokens).accessToken
    }

    /// `true` si un fichier de token valide est présent (décodable).
    func hasToken() -> Bool {
        (try? load()) != nil
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
        try encoder.encode(tokens).write(to: tokenURL)
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
