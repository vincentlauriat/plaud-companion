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
    /// Contenu Markdown résolu (images incluses) par `data_id` de note.
    var noteContents: [String: String] = [:]
    /// Message d'erreur de chargement par `data_id` (échec réseau d'une note distante).
    var noteErrors: [String: String] = [:]
    var loadingNoteIds: Set<String> = []
    var transcriptSegments: [TranscriptSegment] = []
    var polishedSegments: [TranscriptSegment] = []
    var outlineSegments: [OutlineSegment] = []
    var errorMessage: String?
    var cachedIds: Set<String> = []

    // MARK: Index des personnes (interlocuteurs)
    /// `recordingID → libellés de speakers`, alimenté progressivement à chaque
    /// `fetchDetail` et persisté via `PlaudCache`.
    var speakerIndex: [String: [String]] = [:]
    var isIndexing = false
    var indexDone = 0
    var indexTotal = 0

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

    /// Annuaire des personnes : inversion de `speakerIndex` (speaker → réunions),
    /// trié par nombre de réunions décroissant puis par nom.
    var people: [Person] {
        var byName: [String: [String]] = [:]
        for (recordingID, speakers) in speakerIndex {
            for speaker in speakers {
                byName[speaker, default: []].append(recordingID)
            }
        }
        return byName
            .map { Person(name: $0.key, recordingIDs: $0.value) }
            .sorted {
                $0.meetingCount != $1.meetingCount
                    ? $0.meetingCount > $1.meetingCount
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Réunions où cette personne apparaît, plus récentes en premier.
    func recordings(for person: Person) -> [Recording] {
        let ids = Set(person.recordingIDs)
        return recordings
            .filter { ids.contains($0.id) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
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
        // Tri chronologique croissant (plus anciens en premier) dans chaque groupe ;
        // dates absentes traitées comme très anciennes.
        let byDateAscending: (Recording, Recording) -> Bool = {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
        today.sort(by: byDateAscending)
        week.sort(by: byDateAscending)
        older.sort(by: byDateAscending)
        // Groupes ordonnés du plus ancien au plus récent (les plus anciennes en haut).
        return [("group_earlier", older), ("group_week", week), ("group_today", today)]
            .filter { !$0.recordings.isEmpty }
    }

    // MARK: - List

    func loadRecordings(forceRefresh: Bool = false) async {
        if speakerIndex.isEmpty {
            speakerIndex = await PlaudCache.shared.loadSpeakerIndex()
        }
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
        noteContents = [:]
        noteErrors = [:]
        loadingNoteIds = []
        transcriptSegments = []
        polishedSegments = []
        outlineSegments = []

        // Affiche d'abord le cache si présent (instantané), puis revalide
        // depuis le serveur en arrière-plan (stale-while-revalidate) afin de
        // refléter les noms de speakers / notes modifiés côté Plaud.
        let cached = await PlaudCache.shared.loadNotes(id: rec.id)
        if let cached { notes = cached }

        isLoadingDetail = (cached == nil)
        await fetchDetail(for: rec)
        isLoadingDetail = false
    }

    /// Force le re-téléchargement de l'enregistrement sélectionné en ignorant
    /// le cache (utile après un renommage de speakers côté Plaud).
    func refreshCurrentRecording() async {
        guard let rec = selectedRecording else { return }
        await PlaudCache.shared.clearNotes(id: rec.id)
        noteContents = [:]
        noteErrors = [:]
        loadingNoteIds = []
        transcriptSegments = []
        polishedSegments = []
        outlineSegments = []
        isLoadingDetail = true
        await fetchDetail(for: rec)
        isLoadingDetail = false
    }

    /// Récupère le détail complet depuis l'API et met à jour notes +
    /// transcription, puis réécrit le cache. Ignore la réponse si l'utilisateur
    /// a changé de sélection entre-temps.
    private func fetchDetail(for rec: Recording) async {
        do {
            let detail = try await PlaudAPI.shared.getFile(id: rec.id)
            guard rec.id == selectedRecording?.id else { return }
            notes = detail.noteList ?? []
            transcriptSegments = detail.transcriptSegments
            outlineSegments = detail.outlineSegments
            await indexSpeakers(from: detail, id: rec.id)
            // Le rendu déjà calculé pouvait provenir du cache (URLs d'images S3
            // pré-signées désormais expirées → 403). On l'invalide pour forcer un
            // recalcul avec les URLs fraîches de ce détail.
            noteContents = [:]
            noteErrors = [:]
            loadingNoteIds = []
            await PlaudCache.shared.saveNotes(id: rec.id, notes: notes)
            cachedIds.insert(rec.id)
        } catch {
            // En cas d'échec réseau, on conserve le cache déjà affiché.
            if notes.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    func loadTranscript() async {
        // selectRecording / refreshCurrentRecording remplissent déjà
        // transcriptSegments ; on ne re-fetch que s'ils sont absents.
        guard let rec = selectedRecording, transcriptSegments.isEmpty else { return }
        isLoadingDetail = true
        do {
            let detail = try await PlaudAPI.shared.getFile(id: rec.id)
            guard rec.id == selectedRecording?.id else { return }
            transcriptSegments = detail.transcriptSegments
            outlineSegments = detail.outlineSegments
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingDetail = false
    }

    /// Charge (et met en cache) le Markdown résolu d'une note. Le contenu est
    /// soit inline (`dataContent`), soit téléchargé depuis `dataLink` (S3).
    /// Les chemins d'images sont résolus en URLs téléchargeables.
    func loadNoteContent(_ section: NoteSection) async {
        let key = section.dataId
        if noteContents[key] != nil || loadingNoteIds.contains(key) { return }
        noteErrors[key] = nil

        // Contenu inline disponible : résolution immédiate, sans réseau.
        if let inline = section.dataContent,
           !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteContents[key] = section.resolvingImages(in: inline)
            return
        }

        guard let link = section.dataLink, !link.isEmpty else {
            noteContents[key] = ""
            return
        }

        loadingNoteIds.insert(key)
        defer { loadingNoteIds.remove(key) }
        do {
            let markdown = try await PlaudAPI.shared.fetchNoteMarkdown(from: link)
            noteContents[key] = section.resolvingImages(in: markdown)
        } catch {
            // Échec réseau : on sort du spinner en enregistrant l'erreur (la vue
            // propose de réessayer) plutôt que de laisser tourner indéfiniment.
            noteErrors[key] = error.localizedDescription
        }
    }

    /// Markdown brut d'une note (chemins d'images NON résolus, donc stables
    /// pour le hash de sync) : contenu inline ou téléchargé depuis `dataLink`.
    private func rawNoteMarkdown(_ section: NoteSection) async -> String {
        if let inline = section.dataContent,
           !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inline
        }
        if let link = section.dataLink, !link.isEmpty {
            return (try? await PlaudAPI.shared.fetchNoteMarkdown(from: link)) ?? ""
        }
        return ""
    }

    // MARK: - Index des personnes

    /// Libellés de speakers distincts et non vides d'un détail (les speakers `nil`
    /// — « Inconnu » — sont ignorés pour ne pas polluer l'annuaire).
    private func extractSpeakers(from detail: RecordingDetail) -> [String] {
        let names = detail.transcriptSegments.compactMap {
            $0.speaker?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Array(Set(names.filter { !$0.isEmpty })).sorted()
    }

    /// Extrait les speakers d'un détail et les persiste dans l'index (mémoire + disque).
    private func indexSpeakers(from detail: RecordingDetail, id: String) async {
        let speakers = extractSpeakers(from: detail)
        guard !speakers.isEmpty else { return }
        speakerIndex[id] = speakers
        await PlaudCache.shared.updateSpeakers(id: id, speakers: speakers)
    }

    /// Rattrapage complet : charge le détail de toutes les réunions pour bâtir
    /// l'annuaire des personnes d'un coup (N appels API, avec progression).
    func indexAllRecordings() async {
        guard !isIndexing, !recordings.isEmpty else { return }
        isIndexing = true
        indexDone = 0
        indexTotal = recordings.count
        for rec in recordings {
            if let detail = try? await PlaudAPI.shared.getFile(id: rec.id) {
                await indexSpeakers(from: detail, id: rec.id)
            }
            indexDone += 1
        }
        isIndexing = false
    }

    // MARK: - Synchro Notion

    /// Pousse tous les enregistrements vers Notion (création/màj incrémentale).
    func syncToNotion(settings: AppSettings) async {
        guard settings.notionConfigured, !isSyncing, !recordings.isEmpty else { return }
        isSyncing = true
        syncReport = nil
        syncDone = 0
        syncTotal = recordings.count

        // Assemble le contenu. On privilégie un détail FRAIS : les notes
        // distantes et les images sont servies par des URLs S3 pré-signées qui
        // expirent — un cache disque pourrait contenir des liens morts. Repli
        // sur le cache uniquement si le réseau échoue.
        var items: [NotionSyncService.Item] = []
        for rec in recordings {
            let noteList: [NoteSection]
            if let detail = try? await PlaudAPI.shared.getFile(id: rec.id) {
                noteList = detail.noteList ?? []
                await PlaudCache.shared.saveNotes(id: rec.id, notes: noteList)
                cachedIds.insert(rec.id)
            } else {
                noteList = await PlaudCache.shared.loadNotes(id: rec.id) ?? []
            }

            var resolved: [NotionSyncService.ResolvedNote] = []
            for note in noteList {
                let markdown = await rawNoteMarkdown(note)
                resolved.append(.init(
                    title: note.displayTitle,
                    markdown: markdown,
                    imageMap: note.downloadLinkMap ?? [:]
                ))
            }
            items.append(.init(recording: rec, notes: resolved))
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
