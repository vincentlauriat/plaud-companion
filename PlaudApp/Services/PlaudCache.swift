import Foundation

actor PlaudCache {
    static let shared = PlaudCache()

    private let cacheDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plaud/cache")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let notes = base.appendingPathComponent("notes")
        try? FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        return base
    }()

    // MARK: Recordings list

    func loadRecordings() -> [Recording]? {
        let url = cacheDir.appendingPathComponent("recordings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Recording].self, from: data)
    }

    func saveRecordings(_ recordings: [Recording]) {
        let url = cacheDir.appendingPathComponent("recordings.json")
        try? JSONEncoder().encode(recordings).write(to: url)
    }

    func clearRecordings() {
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("recordings.json"))
    }

    // MARK: Notes per recording

    func loadNotes(id: String) -> [NoteSection]? {
        let url = cacheDir.appendingPathComponent("notes/\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([NoteSection].self, from: data)
    }

    func saveNotes(id: String, notes: [NoteSection]) {
        let url = cacheDir.appendingPathComponent("notes/\(id).json")
        try? JSONEncoder().encode(notes).write(to: url)
    }

    func isCached(id: String) -> Bool {
        FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent("notes/\(id).json").path
        )
    }

    // MARK: Index des interlocuteurs (speakers)

    /// Index `recordingID → [libellés de speakers]`, construit progressivement à
    /// chaque ouverture d'un enregistrement (les speakers ne sont pas dans le
    /// cache des notes, seulement dans les segments de transcription en mémoire).
    func loadSpeakerIndex() -> [String: [String]] {
        let url = cacheDir.appendingPathComponent("speakers.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    func saveSpeakerIndex(_ index: [String: [String]]) {
        let url = cacheDir.appendingPathComponent("speakers.json")
        try? JSONEncoder().encode(index).write(to: url)
    }

    /// Met à jour l'entrée d'un seul enregistrement et persiste immédiatement
    /// (la progression d'une indexation longue survit ainsi à une interruption).
    func updateSpeakers(id: String, speakers: [String]) {
        var index = loadSpeakerIndex()
        index[id] = speakers
        saveSpeakerIndex(index)
    }

    /// Invalide le cache de notes d'un seul enregistrement (force un re-fetch).
    func clearNotes(id: String) {
        try? FileManager.default.removeItem(
            at: cacheDir.appendingPathComponent("notes/\(id).json")
        )
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let notes = cacheDir.appendingPathComponent("notes")
        try? FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    }
}
