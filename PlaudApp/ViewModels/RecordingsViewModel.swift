import Foundation
import Observation

@Observable
@MainActor
final class RecordingsViewModel {
    var recordings: [Recording] = []
    var searchText: String = ""
    var isLoadingList = false
    var isLoadingDetail = false
    var isLoadingPolished = false
    var selectedRecording: Recording?
    var notes: [NoteSection] = []
    var transcriptSegments: [TranscriptSegment] = []
    var polishedSegments: [TranscriptSegment] = []
    var outlineSegments: [OutlineSegment] = []
    var errorMessage: String?
    var cachedIds: Set<String> = []

    // MARK: Synchro Notion
    var isSyncing = false
    var syncDone = 0
    var syncTotal = 0
    var syncReport: SyncReport?
    var showSyncReport = false

    var filtered: [Recording] {
        guard !searchText.isEmpty else { return recordings }
        return recordings.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var grouped: [(key: String, recordings: [Recording])] {
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        var today: [Recording] = [], week: [Recording] = [], older: [Recording] = []
        for rec in filtered {
            if let d = rec.date {
                if cal.isDateInToday(d) { today.append(rec) }
                else if d >= weekAgo { week.append(rec) }
                else { older.append(rec) }
            } else {
                older.append(rec)
            }
        }
        return [("group_today", today), ("group_week", week), ("group_earlier", older)]
            .filter { !$0.recordings.isEmpty }
    }

    // MARK: - List

    func loadRecordings(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = await PlaudCache.shared.loadRecordings(), !cached.isEmpty {
            recordings = cached
            await rebuildCachedIds(for: cached)
        }
        isLoadingList = true
        errorMessage = nil
        do {
            var all: [Recording] = []
            var page = 1
            while true {
                let result = try await PlaudAPI.shared.listFiles(page: page, pageSize: 50)
                all.append(contentsOf: result.data)
                if result.data.count < 50 { break }
                page += 1
            }
            recordings = all
            await PlaudCache.shared.saveRecordings(all)
            await rebuildCachedIds(for: all)
        } catch {
            if recordings.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoadingList = false
    }

    func refresh() async {
        await PlaudCache.shared.clearRecordings()
        await loadRecordings(forceRefresh: true)
    }

    private func rebuildCachedIds(for recs: [Recording]) async {
        var ids = Set<String>()
        for rec in recs where await PlaudCache.shared.isCached(id: rec.id) {
            ids.insert(rec.id)
        }
        cachedIds = ids
    }

    // MARK: - Detail

    func selectRecording(_ rec: Recording) async {
        guard rec.id != selectedRecording?.id else { return }
        selectedRecording = rec
        notes = []
        transcriptSegments = []
        polishedSegments = []
        outlineSegments = []

        if let cached = await PlaudCache.shared.loadNotes(id: rec.id) {
            notes = cached
            return
        }

        isLoadingDetail = true
        do {
            let detail = try await PlaudAPI.shared.getFile(id: rec.id)
            notes = detail.noteList ?? []
            await PlaudCache.shared.saveNotes(id: rec.id, notes: notes)
            cachedIds.insert(rec.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingDetail = false
    }

    func loadTranscript() async {
        guard let rec = selectedRecording, transcriptSegments.isEmpty else { return }
        isLoadingDetail = true
        do {
            let detail = try await PlaudAPI.shared.getFile(id: rec.id)
            transcriptSegments = detail.transcriptSegments
            outlineSegments = detail.outlineSegments
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingDetail = false
    }

    // MARK: - Synchro Notion

    /// Pousse tous les enregistrements vers Notion (création/màj incrémentale).
    func syncToNotion(settings: AppSettings) async {
        guard settings.notionConfigured, !isSyncing, !recordings.isEmpty else { return }
        isSyncing = true
        syncReport = nil
        syncDone = 0
        syncTotal = recordings.count

        // Assemble le contenu (notes en cache, fetch sinon).
        var items: [NotionSyncService.Item] = []
        for rec in recordings {
            let notes: [NoteSection]
            if let cached = await PlaudCache.shared.loadNotes(id: rec.id) {
                notes = cached
            } else if let detail = try? await PlaudAPI.shared.getFile(id: rec.id) {
                notes = detail.noteList ?? []
                await PlaudCache.shared.saveNotes(id: rec.id, notes: notes)
                cachedIds.insert(rec.id)
            } else {
                notes = []
            }
            items.append(.init(recording: rec, notes: notes))
        }

        let report = await NotionSyncService.shared.sync(
            items: items,
            token: settings.notionToken,
            databaseID: settings.notionDatabaseID
        ) { done, total in
            Task { @MainActor in
                self.syncDone = done
                self.syncTotal = total
            }
        }

        syncReport = report
        showSyncReport = true
        isSyncing = false
    }

    func loadPolishedTranscript() async {
        guard let rec = selectedRecording, polishedSegments.isEmpty else { return }
        isLoadingPolished = true
        do {
            let detail = try await PlaudAPI.shared.getFile(id: rec.id)
            if let url = detail.polishedTranscriptURL {
                polishedSegments = try await PlaudAPI.shared.fetchPolished(from: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPolished = false
    }
}
