import Foundation

struct Recording: Codable, Identifiable {
    let id: String
    let name: String?
    let createdAt: String
    let startAt: String?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case startAt = "start_at"
        case duration
    }

    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? createdAt }

    var durationFormatted: String {
        guard let ms = duration, ms > 0 else { return "" }
        let s = ms / 1000
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)h\(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m\(String(format: "%02d", sec))s" }
        return "\(sec)s"
    }

    var date: Date? {
        let src = startAt ?? createdAt
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: src) { return d }
        return ISO8601DateFormatter().date(from: src)
    }

    var dateFormatted: String {
        guard let d = date else { return (startAt ?? createdAt) }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale(identifier: AppLocale.identifier)
        return df.string(from: d)
    }
}

struct RecordingList: Codable {
    let data: [Recording]
}
