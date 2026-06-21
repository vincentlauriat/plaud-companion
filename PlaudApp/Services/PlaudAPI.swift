import Foundation

actor PlaudAPI {
    static let shared = PlaudAPI()

    private let base = "https://platform.plaud.ai/developer/api/open/third-party"

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let token = try await TokenStore.shared.getAccessToken()
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func listFiles(page: Int = 1, pageSize: Int = 50) async throws -> RecordingList {
        try await get("/files/?page=\(page)&page_size=\(pageSize)")
    }

    func getFile(id: String) async throws -> RecordingDetail {
        try await get("/files/\(id)")
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
