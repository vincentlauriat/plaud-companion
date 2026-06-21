# ARCHITECTURE

Source de vérité technique du projet Plaud.

## Vue d'ensemble

```
┌─────────────┐     ┌──────────────────────────────┐
│   CLI ./plaud│     │  App macOS (Plaud.xcodeproj) │
│  (Python)   │     │       SwiftUI, macOS 14+     │
└──────┬──────┘     └───────────────┬──────────────┘
       │                            │
       │   lit/écrit ~/.plaud/tokens-mcp.json (OAuth)
       │                            │
       └─────────────┬──────────────┘
                     ▼
   https://platform.plaud.ai/developer/api/open/third-party
              (API tierce, READ-ONLY)
```

## App macOS — couches

| Couche | Fichiers | Rôle |
|---|---|---|
| App | `PlaudApp.swift` | `@main`, `WindowGroup` |
| Models | `Recording.swift`, `NoteSection.swift`, `TokenSet.swift` | structs `Codable` |
| Services | `TokenStore.swift` (actor), `PlaudAPI.swift` (actor), `PlaudCache.swift` (actor) | auth, réseau, cache |
| Services (Notion) | `NotionAPI.swift` (actor), `MarkdownToNotion.swift`, `NotionSyncService.swift` (actor), `NotionSyncStore.swift` (actor), `Keychain.swift` | synchro Plaud → Notion |
| ViewModel | `RecordingsViewModel.swift` | `@Observable @MainActor` |
| Views | `ContentView`, `RecordingListView`, `RecordingRowView`, `RecordingDetailView`, `NotesView`, `TranscriptView`, `InterlocutorsView`, `MarkdownWebView`, `EmptySelectionView`, `SettingsView` | UI |

## Modèle de données (API)

`GET /files/{id}` → `RecordingDetail` :
- `note_list[]` : `auto_sum_note`, `auto_sum_brief` (Markdown dans `data_content`).
- `source_list[]` — 3 types :
  - `transaction` → transcription **brute** : JSON `[{start_time, end_time, content, speaker}]` dans `data_content`.
  - `outline` → **plan** : JSON `[{start_time, end_time, topic}]` dans `data_content`.
  - `transaction_polish` → transcription **polie** : URL S3 pré-signée dans `data_link` (TTL 300 s, à fetcher sans auth).

## Auth (TokenStore)

- Lit `~/.plaud/tokens-mcp.json` (partagé avec le MCP).
- Refresh si `expires_at − now < 60 s` : POST `…/oauth/third-party/access-token/refresh`.
- Réécrit le token dans le même fichier (compat MCP).
- Sécurité : les valeurs de token ne sont jamais affichées ni loggées.

## Cache (PlaudCache)

- Répertoire : `~/Library/Application Support/Plaud/`
- `recordings.json` — liste complète (recréée au refresh).
- `notes/<id>.json` — `note_list` par enregistrement (mis en cache au 1er affichage).
- Transcriptions non mises en cache (volumineuses ; la polie expire en 300 s).

## UI — onglets de détail

1. **Résumé** — première note IA (rendu WebView).
2. **Notes IA** — toutes les sections de notes.
3. **Transcription** — sous-onglets : Brute · Polie · Plan.
4. **Interlocuteurs** — stats de temps de parole par locuteur (depuis `transaction`).

## Synchro Notion (Plaud → Notion, unidirectionnelle)

```
Recordings + Notes (cache/API Plaud)
        │  buildMarkdown → SHA-256
        ▼
NotionSyncService ──┬─ état: notion-sync.json (recordingID → {pageID, hash, syncedAt})
                    │     hash = → skip   |   hash ≠ → update   |   absent → create
                    ▼
                NotionAPI  ──►  https://api.notion.com/v1  (Notion-Version 2022-06-28)
```

- **Diff** : `notion-sync.json` (`Application Support/Plaud/`) porte le `contentHash` (SHA-256 du titre + corps). L'API Plaud n'a pas d'`updated_at`, donc le hash fait foi.
- **Pages vivantes** : avant la boucle, `liveChildIDs` liste les pages réellement présentes côté Notion (entrées de la base via `POST /databases/{id}/query`, ou sous-pages `child_page` via `GET /blocks/{id}/children`). Un enregistrement dont la page a été supprimée est **recréé** (sinon l'état local croirait à tort qu'elle existe). Listing en échec → repli sur l'état local (pas de doublons). Bouton « Réinitialiser l'état de sync » (`NotionSyncStore.reset()`) pour forcer une recréation complète.
- **Cible** : `resolveTarget(id:)` détecte si l'ID est une **database** (entrées dans la table) ou une **page** (sous-pages enfants). Fallback : `GET /databases/{id}` → si 400/404, on tente `GET /pages/{id}`.
- **Create** : `POST /pages`, parent = `database_id` (database) ou `page_id` (page) ; titre dans la propriété de type `title` (nom découvert pour une database, `title` pour une page) ; corps = blocs Markdown.
- **Update** : `PATCH /pages/{id}` (titre) + `replaceContent` = archive des blocs enfants (`DELETE /blocks/{id}`) puis ré-append (`PATCH /blocks/{id}/children`, paquets de 100). URL conservée.
- **Mapping** : titre toujours rempli ; résumé/notes vont dans le corps. Si la cible est une **database**, `resolveTarget` lit le schéma (`NotionTarget.properties`) et `notionProperties` remplit aussi, défensivement : colonne **Date** → date de l'enregistrement, **Number** « durée/duration/length » → minutes, **texte** « …plaud… » → identifiant Plaud. Colonnes absentes ignorées → reste compatible avec tout schéma. La signature des colonnes mappables entre dans le hash (ajout d'une colonne ⇒ re-remplissage des pages existantes).
- **Auth** : token d'intégration en **Keychain** (`Keychain.swift`, `account: notion-token`), jamais loggé. `databaseID` + `autoSync` en `UserDefaults` via `AppSettings`.
- **Markdown → blocs** : `MarkdownToNotion` gère headings (`#`/`##`/`###`), listes (`-`/`*`/`1.`), citations (`>`), paragraphes ; découpe rich_text à 2000 caractères.
- **Pré-requis utilisateur** : créer une intégration sur notion.so/my-integrations, puis partager la database cible avec l'intégration (sinon HTTP 404).

## Build

- Génération projet : `xcodegen generate` (régénérer après tout ajout de fichier source).
- Build : `xcodebuild -project Plaud.xcodeproj -scheme Plaud -configuration Debug build`.
- Sandbox désactivé via `PlaudApp/Plaud.entitlements` (lecture du token hors conteneur).

## Nom & icône

- Nom affiché : **« Plaud Compagnion »** (`PRODUCT_NAME` / `CFBundleName` / `CFBundleDisplayName`). La cible/scheme Xcode reste `Plaud` ; bundle produit = `Plaud Compagnion.app`.
- Icône : `PlaudApp/Assets.xcassets/AppIcon.appiconset` (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). PNG générés par `/tmp/genicon.swift` (CoreGraphics) aux tailles mac 16→1024.
