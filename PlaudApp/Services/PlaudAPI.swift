import Foundation

/// User-Agent explicite envoyé sur toutes les requêtes vers `platform.plaud.ai`.
/// Cloudflare (qui protège ce host) bloque les User-Agents de bibliothèques/bots
/// avec une erreur 1010 (« Access denied ») ; on se présente donc avec un UA de
/// navigateur stable pour ne pas être filtré, quel que soit l'UA que `URLSession`
/// choisirait par défaut.
let plaudUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

actor PlaudAPI {
    static let shared = PlaudAPI()

    private let base = "https://platform.plaud.ai/developer/api/open/third-party"

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        let data = try await authorizedData(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// GET authentifié. Si le serveur rejette le token (401/403), force un
    /// rafraîchissement puis réessaie une fois — couvre le cas d'un access token
    /// révoqué avant son expiration nominale (sinon l'app boucle sur des 403).
    private func authorizedData(from url: URL) async throws -> Data {
        let token = try await TokenStore.shared.getAccessToken()
        var (data, resp) = try await URLSession.shared.data(for: authorizedRequest(url, token: token))
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403,
           let fresh = try? await TokenStore.shared.forceRefresh() {
            (data, resp) = try await URLSession.shared.data(for: authorizedRequest(url, token: fresh))
        }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudError.httpError(http.statusCode)
        }
        return data
    }

    private func authorizedRequest(_ url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(plaudUserAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    func listFiles(page: Int = 1, pageSize: Int = 50) async throws -> RecordingList {
        try await get("/files/?page=\(page)&page_size=\(pageSize)")
    }

    func getFile(id: String) async throws -> RecordingDetail {
        try await get("/files/\(id)")
    }

    /// Récupère le contenu Markdown d'une note depuis une URL S3 pré-signée
    /// (cas des `consumer_note` / `high_light` dont `data_content` est vide).
    func fetchNoteMarkdown(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudError.httpError(http.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Récupère la transcription polie depuis une URL S3 pré-signée (sans auth).
    func fetchPolished(from urlString: String) async throws -> [TranscriptSegment] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudError.httpError(http.statusCode)
        }
        if let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
            return segments
        }
        // Fallback : texte brut → un seul segment
        let text = String(data: data, encoding: .utf8) ?? ""
        return [TranscriptSegment(startTime: nil, endTime: nil, content: text, speaker: nil)]
    }
}
