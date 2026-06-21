# CHANGES

## 2026-06-21 (suite 11) — Pipeline DMG + notarisation

### Added
- **`Scripts/release.sh`** : pipeline de release inspiré de MarkdownViewer (sans Sparkle) — `xcodegen` → build Release (`CODE_SIGNING_ALLOWED=NO`) → codesign manuel **Developer ID + Hardened Runtime** (`--options runtime --timestamp`, retry ×5) → DMG avec layout Finder (background custom, lien `/Applications`, `hdiutil` UDRW→UDZO) → `notarytool submit --wait` → `stapler staple/validate`. Variables `SIGNING_IDENTITY` / `NOTARY_PROFILE` overridables ; vérifie le profil notary et explique comment le créer s'il manque.
- **`Scripts/make-dmg-background.swift`** : génère le fond du DMG (540×380, flèche orange Plaud).
- **`RELEASE.md`** : guide mainteneur (prérequis Apple Developer ID, `notarytool store-credentials`, cut release, publication `gh release`, versioning).

### Changed
- `project.yml` : ajout `MARKETING_VERSION` (1.0.0) / `CURRENT_PROJECT_VERSION` (1) ; `Info.plist` → `CFBundleShortVersionString = $(MARKETING_VERSION)`, `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`. Le script injecte la version (arg) et le build number (nb de commits git).
- `.gitignore` : ignore `*.dmg` et `dmg-staging/` (les binaires vont sur la page Releases, pas dans git).
- `README.md` : section Download mise à jour (DMG **notarisé** → ouverture sans avertissement Gatekeeper) + renvois vers `RELEASE.md` et `Scripts/release.sh` ; project layout enrichi (`Scripts/`, `RELEASE.md`).

### Decisions
- **Pas de Sparkle** (auto-update) pour Plaud Companion — pipeline volontairement réduit à build/sign/DMG/notarize/staple.
- Identité de signature : `Developer ID Application: Vincent LAURIAT (KFLACS69T9)` (présente dans le keychain). Profil notary `PlaudCompanion-Notary` à créer une fois (étape interactive, hors périmètre auto).

## 2026-06-21 (suite 10) — Init du repo git

### Added
- **Dépôt git initialisé** (branche `main`, commit initial). 44 fichiers : sources Swift, CLI Python `plaud`, `project.yml`, assets, `README.md`, `LICENSE`, `ARCHITECTURE.md`, `CHANGES.md`, `.gitignore`.
- **`.gitignore`** : exclut artefacts Xcode/macOS, `Plaud.xcodeproj/` (régénéré par XcodeGen), `__pycache__`, `.omc/`, `.claude/`, et les **docs de travail privées** (`CLAUDE.md`, `COMMANDS.md`, `MEMORY.md`, `PLAN.md`, `TODOS.md`) — non publiées car contiennent des infos perso/chemins locaux.

### Decisions
- Repo public cible : `vincentlauriat/plaud-companion`. Pas de push automatique (la création du remote GitHub et le push restent à faire manuellement).
- `Plaud.xcodeproj` non versionné (régénérable via `xcodegen generate`).

## 2026-06-21 (suite 9) — Documentation publique

### Docs
- **`README.md`** : README public très didactique (anglais) pour GitHub — pitch, table des matières, features, schéma « how it works », installation (DMG à venir + build from source), authentification (token MCP partagé), guide d'utilisation des onglets, **section Notion sync détaillée** (setup intégration, database vs page, table de mapping des colonnes, reset), privacy & security, project layout, roadmap, contributing. Badges shields.io (release auto via API GitHub, platform, Swift, license). Dépôt cible : `vincentlauriat/plaud-companion`.

### Added
- **`LICENSE`** : licence MIT (© 2026 Vincent Lauriat).

## 2026-06-21 (suite 8) — Notion : remplissage de colonnes de la table

### Added
- **Mapping automatique de colonnes** quand la cible est une database. `resolveTarget` récupère le schéma (`NotionTarget.properties` : nom → type) et `NotionSyncService.notionProperties` remplit défensivement :
  - colonne **Date** → date de l'enregistrement (ISO8601) ;
  - colonne **Number** nommée *durée/duration/length/时长* → durée en **minutes** ;
  - colonne **texte** dont le nom contient *plaud* → identifiant Plaud.
  - Colonnes absentes/non reconnues : ignorées (aucune erreur).
- Signature du schéma mappable incluse dans le hash (`mappableSignature`) : ajouter une colonne reconnue plus tard force la mise à jour des pages existantes pour la remplir.

### Changed
- `NotionAPI.createPage` prend désormais `properties: [String: Any]` (titre + colonnes) ; `updateTitle(…title:)` → `updateProperties(…properties:)`. Suppression de `pageTitleProperty` (le nom de la colonne titre vient du schéma de la cible).

## 2026-06-21 (suite 7) — Notion : recréation des pages supprimées + reset

### Fixed
- **Pages supprimées dans Notion n'étaient jamais recréées** : l'état local pointait toujours vers elles, donc l'app tentait un « mise à jour » (ou « inchangé ») au lieu de recréer.

### Added
- `NotionAPI.liveChildIDs(target:parentID:token:)` : liste les pages réellement présentes (non archivées) — entrées de la database (`POST /databases/{id}/query`) ou sous-pages `child_page` (`GET /blocks/{id}/children`), paginé.
- `NotionSyncService` utilise ce set : un enregistrement dont la page n'existe plus est **recréé** (compté en « Créés »). Si le listing échoue, repli sur l'état local (évite les doublons).
- `NotionSyncStore.reset()` + bouton **« Réinitialiser l'état de sync »** (rôle destructif) dans `SettingsView` : vide `notion-sync.json` → prochain run recrée tout. Clés fr/en/zh.

## 2026-06-21 (suite 6) — Notion : titre résolu sur la page à l'update

### Fixed
- **Mise à jour de titre échouait (HTTP 400 « Invalid property identifier »)** quand une page existante avait une propriété titre différente de la cible courante (ex. sous-page créée avec « title » alors que la cible est désormais une base dont la colonne titre s'appelle « Nom »).

### Changed
- `NotionAPI.updateTitle` ne prend plus `titleProperty` : il **lit la vraie propriété titre de la page** via `GET /pages/{id}` (nouveau `pageTitleProperty`) avant le PATCH. Robuste quel que soit le parent d'origine.

## 2026-06-21 (suite 5) — Notion : accepte une URL ou un ID

### Added
- `NotionID.normalize(_:)` (dans `NotionModels`) : extrait l'ID Notion depuis une **URL complète** (ex. `…/Titre-386c45f4d9f0…?v=…`) **ou** un ID brut, et le renvoie au format UUID `8-4-4-4-12`. Prend la dernière séquence de 32 hex ; repli pour un UUID déjà tireté.
- Appliqué dans `NotionSyncService.sync` et `SettingsView.testConnection` : le champ accepte désormais l'URL ou l'ID.

### Changed
- Libellé du champ (fr/en/zh) : « ID de la base » → « URL ou ID (base ou page) ».

## 2026-06-21 (suite 4) — Notion : support page + database

### Fixed
- **Synchro Notion échouait (HTTP 400) quand l'ID fourni était une page** et non une database. `NotionAPI.titlePropertyName` supposait une database.

### Changed
- `NotionAPI` : `titlePropertyName` → `resolveTarget(id:token:)` qui détecte automatiquement le type :
  - **database** → entrées dans la table (`parent: database_id`, propriété titre découverte) ;
  - **page** → sous-pages créées dedans (`parent: page_id`, propriété `title`).
  - Fallback : si `GET /databases/{id}` renvoie 400/404, on tente `GET /pages/{id}`.
- `createPage(databaseID:titleProperty:…)` → `createPage(parentID:target:…)` (parent dynamique selon `NotionTarget`).
- `NotionSyncService` et `SettingsView.testConnection` utilisent `resolveTarget`.
- Nouveau type `NotionTarget { isDatabase, titleProperty }` dans `NotionModels`.
- Textes d'aide (fr/en/zh) : précisent qu'une base **ou** une page est acceptée.

## 2026-06-21 (suite 3) — Synchro Notion

### Added
- **Synchro Plaud → Notion** (unidirectionnelle, incrémentale). Nouveaux fichiers :
  - `Models/NotionModels.swift` — `NotionConfig` (apiVersion `2022-06-28`, base `api.notion.com/v1`), `SyncRecord` (mapping état), `SyncReport`, `NotionError`.
  - `Services/Keychain.swift` — stockage sécurisé du token d'intégration (jamais loggé).
  - `Services/NotionAPI.swift` (actor) — `titlePropertyName` (test + découverte de la propriété titre), `createPage`, `updateTitle`, `replaceContent` (archive blocs + ré-append), pagination des enfants, append par paquets de 100.
  - `Services/MarkdownToNotion.swift` — conversion Markdown → blocs Notion (headings, listes, citations ; découpe rich_text à 2000 car.).
  - `Services/NotionSyncStore.swift` (actor) — persistance de l'état dans `Application Support/Plaud/notion-sync.json`.
  - `Services/NotionSyncService.swift` (actor) — orchestration : hash SHA-256 du contenu → créer / mettre à jour / ignorer.
- **Réglages Notion** dans `SettingsView` : token (SecureField), ID de base, toggle auto-sync, bouton « Tester la connexion ».
- **Bouton « Synchroniser »** dans la toolbar de la liste (visible si configuré) + alerte de rapport (créés / màj / inchangés / échecs).
- `AppSettings` : `notionToken` (Keychain), `notionDatabaseID` + `notionAutoSync` (UserDefaults), `notionConfigured`, `notionSyncSummary(...)`.
- `RecordingsViewModel` : `isSyncing`, `syncDone/syncTotal`, `syncReport`, `syncToNotion(settings:)`.
- Clés de localisation Notion (fr / en / zh).

### Decisions
- **Détection des diffs par SHA-256** du contenu poussé (titre + corps), stocké dans `notion-sync.json` : l'API Plaud n'expose pas d'`updated_at`, le hash est donc la source de vérité. Identique → skip (rien recopié).
- **Mise à jour = archiver les blocs + réécrire** (pas recréer la page) : l'URL Notion est conservée.
- **Mapping minimal robuste** : seule la propriété **titre** (nom découvert dynamiquement) est remplie ; date/durée/résumé/notes vont dans le **corps** de la page → fonctionne avec n'importe quel schéma de database.
- **Token en Keychain**, jamais en `UserDefaults` ni loggé.
- **Déclenchement** : manuel (bouton) + auto après chaque rafraîchissement si l'option est activée.

## 2026-06-21 (suite 2)

### Added
- **Icône de l'app** : `Assets.xcassets/AppIcon.appiconset` (squircle dégradé orange `#FF9F45`→`#FF5B33` + waveform blanche). Générée par `/tmp/genicon.swift` (CoreGraphics/AppKit) aux tailles 16/32/64/128/256/512/1024 → compilée en `AppIcon.icns`.

### Changed
- **Renommage** : l'app s'appelle désormais **« Plaud Compagnion »** (`PRODUCT_NAME`, `CFBundleName`, `CFBundleDisplayName`). La cible/scheme Xcode reste `Plaud` ; le bundle produit est `Plaud Compagnion.app`.
- `project.yml` : ajout de `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` et `PRODUCT_NAME: Plaud Compagnion`.

### Notes
- Orthographe « Compagnion » conservée telle que demandée (hybride FR « Compagnon » / EN « Companion »). Modifiable en une ligne si besoin.

## 2026-06-21 (suite)

### Added
- **Mode Plan interactif** : chaque chapitre (`outline`) est désormais dépliable (clic → chevron qui pivote). À l'ouverture, affiche les segments de transcription brute dont le `start_time` tombe dans la plage `[start_time, end_time)` du chapitre (timestamp + locuteur + texte). Message « Aucune transcription pour ce chapitre » si vide.

### Changed
- `OutlineView` reçoit maintenant `transcript: [TranscriptSegment]` en plus de `segments`. `RecordingDetailView` lui passe `vm.transcriptSegments` (déjà chargé à l'ouverture de l'onglet Transcription).

## 2026-06-21

### Added
- `MarkdownWebView.swift` — rendu Markdown propre via `WKWebView` (HTML + CSS style Apple, light/dark auto, gère titres/listes/citations/code/HR + lignes `--` détail Plaud).
- `InterlocutorsView.swift` — onglet « Interlocuteurs » : statistiques par locuteur (temps de parole, %, nombre d'interventions) avec barres de progression.
- `OutlineView` (dans `TranscriptView.swift`) — affichage du plan/chapitres (`outline`) avec timestamps début–fin.
- 3 types de transcription dans l'onglet Transcription : **Brute** (`transaction`), **Polie** (`transaction_polish` via URL S3 pré-signée), **Plan** (`outline`).
- `PlaudAPI.fetchPolished(from:)` — récupère la transcription polie depuis l'URL S3 (sans auth, TTL 300 s).
- Modèle `OutlineSegment` + champ `dataLink` sur `NoteSection` + helpers `outlineSegments` / `polishedTranscriptURL` sur `RecordingDetail`.
- `RecordingsViewModel` : `polishedSegments`, `outlineSegments`, `loadPolishedTranscript()`, `isLoadingPolished`.

### Changed
- `NotesView.swift` — remplace `SimpleMarkdownView` (rendu basique) par `MarkdownWebView` (rendu HTML propre).
- `RecordingDetailView.swift` — 4 onglets (Résumé · Notes IA · Transcription · Interlocuteurs) ; sous-picker Brute/Polie/Plan dans Transcription.
- `TranscriptSegment` — ajout du champ `end_time` (utilisé pour les stats de temps de parole).

### Decisions
- Rendu Markdown via WebView plutôt que `AttributedString(markdown:)` : meilleur contrôle du style (titres colorés, blockquotes, listes imbriquées) et cohérence light/dark.
- Transcription polie non mise en cache (URL S3 expire en 300 s, re-fetch à la demande).
