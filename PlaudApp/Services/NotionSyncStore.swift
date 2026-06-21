import Foundation

/// Persistance de l'état de synchronisation Notion.
/// Mapping `recordingID → SyncRecord` dans `Application Support/Plaud/notion-sync.json`.
/// C'est ce fichier qui permet la synchro incrémentale (création/màj/skip).
actor NotionSyncStore {
    static let shared = NotionSyncStore()

    private let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plaud")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("notion-sync.json")
    }()

    private var cache: [String: SyncRecord]?

    private func loadAll() -> [String: SyncRecord] {
        if let cache { return cache }
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([SyncRecord].self, from: data)) ?? []
        let map = Dictionary(uniqueKeysWithValues: records.map { ($0.recordingID, $0) })
        cache = map
        return map
    }

    func record(for recordingID: String) -> SyncRecord? {
        loadAll()[recordingID]
    }

    func upsert(_ record: SyncRecord) {
        var map = loadAll()
        map[record.recordingID] = record
        cache = map
        persist(map)
    }

    /// Vide tout l'état de sync : le prochain run recréera toutes les pages.
    func reset() {
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist(_ map: [String: SyncRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(Array(map.values)).write(to: fileURL)
    }
}
