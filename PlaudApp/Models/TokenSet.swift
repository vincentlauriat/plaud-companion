import Foundation

struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String?
    var expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
    }

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date().timeIntervalSince1970 * 1000 > exp - 60_000
    }
}
