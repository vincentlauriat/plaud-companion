import Foundation

enum PlaudError: LocalizedError {
    case tokenMissing
    case noRefreshToken
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .tokenMissing: return "Token Plaud introuvable. Connecte-toi d'abord via Claude Code."
        case .noRefreshToken: return "Token expiré et aucun refresh token disponible. Reconnecte-toi via Claude Code."
        case .httpError(let code): return "Erreur HTTP \(code)"
        }
    }
}

actor TokenStore {
    static let shared = TokenStore()

    private let tokenURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".plaud/tokens-mcp.json")

    private let refreshURL = URL(string:
        "https://platform.plaud.ai/developer/api/oauth/third-party/access-token/refresh")!

    func getAccessToken() async throws -> String {
        var tokens = try load()
        if tokens.isExpired {
            tokens = try await refresh(tokens)
        }
        return tokens.accessToken
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
