import Foundation

struct NoteSection: Codable, Identifiable {
    var id: String { dataId }
    let dataId: String
    let dataType: String
    let dataTitle: String?
    let dataTabName: String?
    let dataContent: String?
    let dataLink: String?

    enum CodingKeys: String, CodingKey {
        case dataId = "data_id"
        case dataType = "data_type"
        case dataTitle = "data_title"
        case dataTabName = "data_tab_name"
        case dataContent = "data_content"
        case dataLink = "data_link"
    }

    var displayTitle: String { dataTitle ?? dataTabName ?? "" }
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
