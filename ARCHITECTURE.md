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
- `note_list[]` — plusieurs notes par enregistrement, types observés :
  - `auto_sum_note` / `auto_sum_brief` → résumé IA, Markdown **inline** dans `data_content`.
  - `consumer_note` → note par template (détaillée) : `data_content` **vide**, contenu Markdown dans `data_link` (URL S3 pré-signée).
  - `high_light` → « Points à retenir » : idem, contenu dans `data_link` (S3).
  - `download_link_map` (par note) : `{ chemin_relatif → URL S3 }` qui résout les images `![..](permanent/.../mark/xxx.jpg)` du Markdown vers des URLs téléchargeables.
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
- `notes/<id>.json` — `note_list` par enregistrement.
- **Stale-while-revalidate** : `selectRecording` affiche le cache puis revalide en arrière-plan (les noms de speakers / notes modifiés côté Plaud se mettent à jour). `clearNotes(id:)` invalide un enregistrement ; `refreshCurrentRecording()` force le re-fetch ; `clearAll()` exposé via Réglages → « Vider le cache ».
- Contenus volatils **non cachés sur disque** (URLs S3 pré-signées qui expirent) : transcription polie, contenu distant des notes (`data_link`), images. Le contenu Markdown résolu des notes est mis en cache **mémoire** (`RecordingsViewModel.noteContents`, par `data_id`).

## UI — onglets de détail

1. **Résumé** — note `auto_sum_note` (rendu WebView, images incluses).
2. **Notes IA** — **sélecteur déroulant** de toutes les notes (`auto_sum_note`, `consumer_note`, `high_light`). Contenu inline ou téléchargé depuis `data_link` à la demande (`loadNoteContent`). Images résolues via `download_link_map` ; bouton **« Enregistrer les images »** (`ImageExporter` → `NSSavePanel`/`NSOpenPanel`) ; bouton **« Exporter en Word »** (`DocxExporter`).

## Export Word (`DocxExporter`, dans `NotesView.swift`)

Génère un véritable `.docx` (Office Open XML) **à la main**, car les API `NSAttributedString` (`.officeOpenXML`) n'embarquent pas les images (seul `.rtfd`, un bundle, le fait). Pipeline : Markdown → corps `word/document.xml` (titres, listes, cases à cocher, gras/italique/barré/code, tableaux, citations), téléchargement + intégration des images dans `word/media` (résolution px→EMU ×9525, largeur cap ~600 px, relations `r:embed`), puis empaquetage via un mini écrivain ZIP maison (`DocxZip` + `DocxCRC32`, méthode « stored », sans dépendance). Validé hors app (xmllint + `textutil`).
3. **Transcription** — sous-onglets : Brute · Polie · Plan.
4. **Interlocuteurs** — stats de temps de parole par locuteur (depuis `transaction`).

## Rendu Markdown (`MarkdownWebView.convert`)

Markdown → HTML (WKWebView, style Apple light/dark). Gère : titres `#`…`######`, listes `-`/`*`/`1.` (regroupées + imbriquées), **cases à cocher** `- [ ]`/`- [x]` (☐/☑), citations `>`, lignes détail Plaud `--`, séparateurs, **liens** `[..](..)` + URLs nues, **barré** `~~..~~`, gras/italique, **code inline + blocs** ```` ``` ````, **tableaux** GFM, et **images** `![..](..)` (chemins résolus en amont via `download_link_map`). Les URLs sont protégées par des jetons avant l'emphase pour ne pas être cassées.

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
- **Contenu poussé** : titre + ligne de métadonnées + **toutes les notes** (résumé, points à retenir, notes par template). Le contenu distant (`consumer_note`/`high_light`) est téléchargé depuis `data_link` au moment de la sync (`RecordingsViewModel.rawNoteMarkdown` → `NotionSyncService.ResolvedNote`). La sync re-fetch un **détail frais** par enregistrement (liens S3 valides), repli sur cache si réseau KO.
- **Images** : `NotionSyncService.buildBlocks` téléverse les images **référencées** dans le corps (chemin → URL S3 via `download_link_map` → `NotionAPI.uploadFile`), dédoublonnage par URL, puis `MarkdownToNotion.blocks(from:imageUploads:)` insère des blocs `image` de type `file_upload`. **File upload Notion** en 2 temps : `POST /file_uploads` (`{filename, content_type}` → `{id, upload_url}`) puis envoi `multipart/form-data` (champ `file`, ≤ 20 Mo). Images **persistantes** (pas de lien S3 qui expire).
- **Hash stable** : le `contentHash` est calculé sur le Markdown **brut** (chemins d'images relatifs, contenu inline), **pas** sur les URLs S3 volatiles → pas de re-sync en boucle. Les images ne sont téléversées que lors d'un **create/update** réel (jamais sur un `skip`).
- **Mapping colonnes** : titre toujours rempli. Si la cible est une **database**, `resolveTarget` lit le schéma (`NotionTarget.properties`) et `notionProperties` remplit défensivement : **Date** → date, **Number** « durée/duration/length » → minutes, **texte** « …plaud… » → identifiant Plaud. Colonnes absentes ignorées. La signature des colonnes mappables entre dans le hash.
- **Auth** : token d'intégration en **Keychain** (`Keychain.swift`, `account: notion-token`), jamais loggé. `databaseID` + `autoSync` en `UserDefaults` via `AppSettings`.
- **Markdown → blocs** (`MarkdownToNotion`) : headings `#`…`######` (plafonnés à `heading_3`), **cases à cocher** `- [ ]`/`- [x]` → blocs **`to_do`** natifs (état coché), listes (`-`/`*`/`1.`), citations (`>`), images (`file_upload`), paragraphes ; rich_text découpé à 2000 caractères.
- **Pré-requis utilisateur** : créer une intégration sur notion.so/my-integrations, puis partager la database cible avec l'intégration (sinon HTTP 404).

## Release (DMG + notarisation)

- `Scripts/release.sh <version>` : `xcodegen` → build Release (`CODE_SIGNING_ALLOWED=NO`) → codesign **Developer ID + Hardened Runtime** (`--options runtime --timestamp`) → DMG (layout Finder + `Scripts/make-dmg-background.swift`, `hdiutil` UDRW→UDZO) → `notarytool submit --wait` → `stapler staple`.
- Pas de Sparkle (pas d'auto-update). Versioning : `MARKETING_VERSION` (arg) + `CURRENT_PROJECT_VERSION` (nb de commits git) injectés au build, lus par `Info.plist` via `$(…)`.
- Détails et prérequis : voir `RELEASE.md`.

## Build

- Génération projet : `xcodegen generate` (régénérer après tout ajout de fichier source).
- Build : `xcodebuild -project Plaud.xcodeproj -scheme Plaud -configuration Debug build`.
- Sandbox désactivé via `PlaudApp/Plaud.entitlements` (lecture du token hors conteneur).

## Nom & icône

- Nom affiché : **« Plaud Compagnion »** (`PRODUCT_NAME` / `CFBundleName` / `CFBundleDisplayName`). La cible/scheme Xcode reste `Plaud` ; bundle produit = `Plaud Compagnion.app`.
- Icône : `PlaudApp/Assets.xcassets/AppIcon.appiconset` (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). PNG générés par `/tmp/genicon.swift` (CoreGraphics) aux tailles mac 16→1024.
