import Foundation

/// Client de l'API Notion (https://developers.notion.com).
/// Synchro unidirectionnelle Plaud → Notion : on crée et met à jour des pages
/// dans une database fournie par l'utilisateur.
actor NotionAPI {
    static let shared = NotionAPI()

    private func request(
        _ method: String,
        path: String,
        token: String,
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: NotionConfig.base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(NotionConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NotionError.httpError(code, message)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Teste la connexion et résout la cible : database (avec le nom de sa
    /// propriété titre, libre côté Notion) ou page (sous-pages enfants).
    func resolveTarget(id: String, token: String) async throws -> NotionTarget {
        do {
            let json = try await request("GET", path: "/databases/\(id)", token: token)
            if let props = json["properties"] as? [String: Any] {
                var schema: [String: String] = [:]
                var titleName: String?
                for (name, value) in props {
                    guard let dict = value as? [String: Any], let type = dict["type"] as? String else { continue }
                    schema[name] = type
                    if type == "title" { titleName = name }
                }
                if let titleName {
                    return NotionTarget(isDatabase: true, titleProperty: titleName, properties: schema)
                }
            }
            throw NotionError.noTitleProperty
        } catch let NotionError.httpError(code, _) where code == 400 || code == 404 {
            // L'ID n'est pas une database : on vérifie que c'est bien une page accessible.
            _ = try await request("GET", path: "/pages/\(id)", token: token)
            return NotionTarget(isDatabase: false, titleProperty: "title")
        }
    }

    /// IDs des pages réellement présentes (non archivées) sous la cible :
    /// entrées de la database, ou sous-pages directes d'une page.
    /// Sert à détecter les pages supprimées côté Notion → recréation.
    func liveChildIDs(target: NotionTarget, parentID: String, token: String) async throws -> Set<String> {
        var ids = Set<String>()
        var cursor: String?
        repeat {
            let json: [String: Any]
            if target.isDatabase {
                var body: [String: Any] = ["page_size": 100]
                if let cursor { body["start_cursor"] = cursor }
                json = try await request("POST", path: "/databases/\(parentID)/query", token: token, body: body)
            } else {
                var path = "/blocks/\(parentID)/children?page_size=100"
                if let cursor { path += "&start_cursor=\(cursor)" }
                json = try await request("GET", path: path, token: token)
            }
            for r in (json["results"] as? [[String: Any]] ?? []) {
                let archived = r["archived"] as? Bool ?? false
                guard !archived, let id = r["id"] as? String else { continue }
                // Pour une page parente, ne garder que les blocs « child_page ».
                if !target.isDatabase, r["type"] as? String != "child_page" { continue }
                ids.insert(id)
            }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return ids
    }

    /// Crée une page sous la cible (entrée de database ou sous-page). Retourne son ID.
    /// `properties` contient le titre + les colonnes mappées (construites par le service).
    func createPage(
        parentID: String,
        token: String,
        target: NotionTarget,
        properties: [String: Any],
        blocks: [[String: Any]]
    ) async throws -> String {
        let parent: [String: Any] = target.isDatabase
            ? ["database_id": parentID]
            : ["page_id": parentID]
        let body: [String: Any] = [
            "parent": parent,
            "properties": properties,
            "children": Array(blocks.prefix(100)),
        ]
        let json = try await request("POST", path: "/pages", token: token, body: body)
        guard let id = json["id"] as? String else { throw NotionError.httpError(0, "Réponse sans id de page") }
        // Notion limite à 100 blocs par requête : on ajoute le reste ensuite.
        if blocks.count > 100 {
            try await appendBlocks(pageID: id, token: token, blocks: Array(blocks.dropFirst(100)))
        }
        return id
    }

    // MARK: - File uploads (images)

    /// Téléverse un fichier vers Notion et retourne l'identifiant `file_upload`
    /// réutilisable dans un bloc image. Flux en deux temps : création de l'objet
    /// puis envoi du contenu en multipart. Limite Notion : 20 Mo en une partie.
    func uploadFile(data: Data, filename: String, contentType: String, token: String) async throws -> String {
        let created = try await request(
            "POST", path: "/file_uploads", token: token,
            body: ["filename": filename, "content_type": contentType]
        )
        guard let id = created["id"] as? String else {
            throw NotionError.httpError(0, "Réponse file_upload sans id")
        }
        let sendURL = (created["upload_url"] as? String)
            ?? (NotionConfig.base + "/file_uploads/\(id)/send")
        try await sendMultipart(
            urlString: sendURL, fileData: data,
            filename: filename, contentType: contentType, token: token
        )
        return id
    }

    private func sendMultipart(
        urlString: String, fileData: Data,
        filename: String, contentType: String, token: String
    ) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(NotionConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["message"] as? String
            throw NotionError.httpError(code, msg)
        }
    }

    /// Met à jour les propriétés (titre + colonnes mappées) d'une page existante.
    func updateProperties(pageID: String, token: String, properties: [String: Any]) async throws {
        let body: [String: Any] = ["properties": properties]
        _ = try await request("PATCH", path: "/pages/\(pageID)", token: token, body: body)
    }

    /// Remplace l'intégralité du corps d'une page : archive les blocs existants,
    /// puis ajoute les nouveaux. L'URL de la page est conservée.
    func replaceContent(pageID: String, token: String, blocks: [[String: Any]]) async throws {
        let existing = try await childBlockIDs(pageID: pageID, token: token)
        for id in existing {
            _ = try await request("DELETE", path: "/blocks/\(id)", token: token)
        }
        try await appendBlocks(pageID: pageID, token: token, blocks: blocks)
    }

    private func childBlockIDs(pageID: String, token: String) async throws -> [String] {
        var ids: [String] = []
        var cursor: String?
        repeat {
            var path = "/blocks/\(pageID)/children?page_size=100"
            if let cursor { path += "&start_cursor=\(cursor)" }
            let json = try await request("GET", path: path, token: token)
            let results = json["results"] as? [[String: Any]] ?? []
            ids.append(contentsOf: results.compactMap { $0["id"] as? String })
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return ids
    }

    /// Ajoute des blocs enfants par paquets de 100 (limite Notion).
    private func appendBlocks(pageID: String, token: String, blocks: [[String: Any]]) async throws {
        var index = 0
        while index < blocks.count {
            let chunk = Array(blocks[index..<min(index + 100, blocks.count)])
            _ = try await request(
                "PATCH",
                path: "/blocks/\(pageID)/children",
                token: token,
                body: ["children": chunk]
            )
            index += 100
        }
    }
}
