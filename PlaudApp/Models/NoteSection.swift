import Foundation

struct NoteSection: Codable, Identifiable {
    var id: String { dataId }
    let dataId: String
    let dataType: String
    let dataTitle: String?
    let dataTabName: String?
    let dataContent: String?
    let dataLink: String?
    /// Chemins d'images relatifs → URLs S3 pré-signées téléchargeables.
    let downloadLinkMap: [String: String]?

    enum CodingKeys: String, CodingKey {
        case dataId = "data_id"
        case dataType = "data_type"
        case dataTitle = "data_title"
        case dataTabName = "data_tab_name"
        case dataContent = "data_content"
        case dataLink = "data_link"
        case downloadLinkMap = "download_link_map"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dataId = try c.decode(String.self, forKey: .dataId)
        dataType = try c.decode(String.self, forKey: .dataType)
        dataTitle = try c.decodeIfPresent(String.self, forKey: .dataTitle)
        dataTabName = try c.decodeIfPresent(String.self, forKey: .dataTabName)
        dataLink = try c.decodeIfPresent(String.self, forKey: .dataLink)
        downloadLinkMap = try c.decodeIfPresent([String: String].self, forKey: .downloadLinkMap)

        // Décode dataContent : peut être une chaîne JSON imbriquée (nécessite un décodage supplémentaire)
        // ou une chaîne simple (Markdown). Extrait ai_content si présent, sinon utilise la chaîne brute.
        let rawContent = try c.decodeIfPresent(String.self, forKey: .dataContent)
        if let raw = rawContent, !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let aiContent = jsonObj["ai_content"] as? String {
            dataContent = aiContent
        } else {
            dataContent = rawContent
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dataId, forKey: .dataId)
        try c.encode(dataType, forKey: .dataType)
        try c.encodeIfPresent(dataTitle, forKey: .dataTitle)
        try c.encodeIfPresent(dataTabName, forKey: .dataTabName)
        try c.encodeIfPresent(dataContent, forKey: .dataContent)
        try c.encodeIfPresent(dataLink, forKey: .dataLink)
        try c.encodeIfPresent(downloadLinkMap, forKey: .downloadLinkMap)
    }

    var displayTitle: String { dataTitle ?? dataTabName ?? "" }

    /// `true` si le contenu n'est pas inline et doit être téléchargé depuis `dataLink`.
    var contentIsRemote: Bool {
        (dataContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && (dataLink?.isEmpty == false)
    }

    /// Remplace les chemins d'images relatifs par leurs URLs téléchargeables.
    func resolvingImages(in markdown: String) -> String {
        guard let map = downloadLinkMap, !map.isEmpty else { return markdown }
        var s = markdown
        for (path, url) in map {
            // Cible la forme Markdown `](chemin)` pour ne pas toucher d'autres textes.
            s = s.replacingOccurrences(of: "(\(path))", with: "(\(url))")
        }
        return s
    }

    /// URLs téléchargeables de toutes les images associées à cette note.
    var imageURLs: [URL] {
        (downloadLinkMap?.values ?? [:].values).compactMap { URL(string: $0) }
    }
}

struct TranscriptSegment: Codable {
    let startTime: Int?
    let endTime: Int?
    let content: String?
    let speaker: String?

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case content, speaker
    }

    var timestampFormatted: String {
        let ms = startTime ?? 0
        return String(format: "%02d:%02d", ms / 60000, (ms / 1000) % 60)
    }
}

struct OutlineSegment: Codable, Identifiable {
    let startTime: Int?
    let endTime: Int?
    let topic: String?
    let id: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case topic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(Int.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Int.self, forKey: .endTime)
        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        id = UUID().uuidString
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encodeIfPresent(topic, forKey: .topic)
    }

    var startFormatted: String { format(startTime) }
    var endFormatted: String { format(endTime) }

    private func format(_ ms: Int?) -> String {
        let t = (ms ?? 0) / 1000
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

struct RecordingDetail: Codable {
    let id: String
    let name: String?
    let createdAt: String?
    let startAt: String?
    let duration: Int?
    let noteList: [NoteSection]?
    let sourceList: [NoteSection]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case startAt = "start_at"
        case duration
        case noteList = "note_list"
        case sourceList = "source_list"
    }

    var transcriptSegments: [TranscriptSegment] {
        decoded(type: "transaction")
    }

    var outlineSegments: [OutlineSegment] {
        guard let sourceList else { return [] }
        let decoder = JSONDecoder()
        return sourceList
            .filter { $0.dataType == "outline" }
            .compactMap { $0.dataContent?.data(using: .utf8) }
            .flatMap { (try? decoder.decode([OutlineSegment].self, from: $0)) ?? [] }
    }

    var polishedTranscriptURL: String? {
        sourceList?.first { $0.dataType == "transaction_polish" }?.dataLink
    }

    private func decoded(type: String) -> [TranscriptSegment] {
        guard let sourceList else { return [] }
        let decoder = JSONDecoder()
        return sourceList
            .filter { $0.dataType == type }
            .compactMap { $0.dataContent?.data(using: .utf8) }
            .flatMap { (try? decoder.decode([TranscriptSegment].self, from: $0)) ?? [] }
    }
}
