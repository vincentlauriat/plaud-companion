import Foundation
import CryptoKit

/// Orchestration de la synchro Plaud → Notion.
/// Pour chaque enregistrement : on assemble le contenu (titre + métadonnées +
/// résumé + notes IA), on calcule son SHA-256, puis selon l'état local on crée,
/// met à jour, ou ignore la page Notion correspondante.
actor NotionSyncService {
    static let shared = NotionSyncService()

    struct Item {
        let recording: Recording
        let notes: [NoteSection]
    }

    /// Synchronise une liste d'enregistrements. `progress` est appelé après
    /// chaque enregistrement traité (index courant, total).
    func sync(
        items: [Item],
        token: String,
        databaseID: String,
        progress: @Sendable (Int, Int) -> Void
    ) async -> SyncReport {
        var report = SyncReport()
        let parentID = NotionID.normalize(databaseID)

        let target: NotionTarget
        do {
            target = try await NotionAPI.shared.resolveTarget(id: parentID, token: token)
        } catch {
            report.failed = items.count
            report.errors.append(error.localizedDescription)
            return report
        }

        // Pages réellement présentes dans Notion : permet de recréer ce qui a été
        // supprimé côté Notion. En cas d'échec du listing, on garde l'ancien
        // comportement (faire confiance à l'état local) pour éviter les doublons.
        let liveIDs = try? await NotionAPI.shared.liveChildIDs(
            target: target, parentID: parentID, token: token)

        // Inclus dans le hash : si l'utilisateur ajoute une colonne mappable plus
        // tard, le hash change → les pages existantes sont mises à jour pour la remplir.
        let schemaSig = mappableSignature(target)

        for (i, item) in items.enumerated() {
            let title = item.recording.displayName
            let body = buildMarkdown(for: item)
            let hash = sha256(title + "\n" + body + "\n" + schemaSig)

            do {
                let existing = await NotionSyncStore.shared.record(for: item.recording.id)
                let pageAlive = existing.map { liveIDs?.contains($0.notionPageID) ?? true } ?? false

                let properties = notionProperties(target: target, title: title, recording: item.recording)

                if let existing, pageAlive {
                    if existing.contentHash == hash {
                        report.skipped += 1
                    } else {
                        try await NotionAPI.shared.updateProperties(
                            pageID: existing.notionPageID, token: token, properties: properties
                        )
                        try await NotionAPI.shared.replaceContent(
                            pageID: existing.notionPageID, token: token,
                            blocks: MarkdownToNotion.blocks(from: body)
                        )
                        await NotionSyncStore.shared.upsert(SyncRecord(
                            recordingID: item.recording.id, notionPageID: existing.notionPageID,
                            contentHash: hash, syncedAt: Date()
                        ))
                        report.updated += 1
                    }
                } else {
                    let pageID = try await NotionAPI.shared.createPage(
                        parentID: parentID, token: token,
                        target: target, properties: properties,
                        blocks: MarkdownToNotion.blocks(from: body)
                    )
                    await NotionSyncStore.shared.upsert(SyncRecord(
                        recordingID: item.recording.id, notionPageID: pageID,
                        contentHash: hash, syncedAt: Date()
                    ))
                    report.created += 1
                }
            } catch {
                report.failed += 1
                report.errors.append("\(title) : \(error.localizedDescription)")
            }
            progress(i + 1, items.count)
        }
        return report
    }

    /// Construit les propriétés Notion : titre + colonnes de la database remplies
    /// défensivement selon leur type/nom (les colonnes absentes sont ignorées).
    /// - Date → date de l'enregistrement
    /// - Number nommée « durée/duration » → durée en minutes
    /// - Texte nommé « …plaud… » → identifiant Plaud
    private func notionProperties(target: NotionTarget, title: String, recording: Recording) -> [String: Any] {
        var props: [String: Any] = [
            target.titleProperty: ["title": [["text": ["content": String(title.prefix(2000))]]]]
        ]
        for (name, type) in target.properties where name != target.titleProperty {
            let lname = name.lowercased()
            switch type {
            case "date":
                if let d = recording.date {
                    let iso = ISO8601DateFormatter().string(from: d)
                    props[name] = ["date": ["start": iso]]
                }
            case "number":
                if isDurationName(lname), let ms = recording.duration, ms > 0 {
                    props[name] = ["number": Int((Double(ms) / 60000.0).rounded())]
                }
            case "rich_text":
                if lname.contains("plaud") {
                    props[name] = ["rich_text": [["text": ["content": recording.id]]]]
                }
            default:
                break
            }
        }
        return props
    }

    private func isDurationName(_ lname: String) -> Bool {
        ["dur", "length", "时长", "時長"].contains { lname.contains($0) }
    }

    /// Signature des colonnes que l'app sait remplir (triée). Sert au hash :
    /// un changement de schéma mappable force la mise à jour des pages.
    private func mappableSignature(_ target: NotionTarget) -> String {
        guard target.isDatabase else { return "" }
        return target.properties
            .filter { name, type in
                guard name != target.titleProperty else { return false }
                let lname = name.lowercased()
                return type == "date"
                    || (type == "number" && isDurationName(lname))
                    || (type == "rich_text" && lname.contains("plaud"))
            }
            .map { "\($0.key):\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }

    /// Assemble le corps Markdown : ligne de métadonnées + chaque section de notes.
    private func buildMarkdown(for item: Item) -> String {
        var parts: [String] = []
        let meta = [item.recording.dateFormatted, item.recording.durationFormatted]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !meta.isEmpty { parts.append("> \(meta)") }

        for note in item.notes {
            let title = note.displayTitle
            if !title.isEmpty { parts.append("## \(title)") }
            if let content = note.dataContent, !content.isEmpty { parts.append(content) }
        }
        return parts.joined(separator: "\n\n")
    }

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
