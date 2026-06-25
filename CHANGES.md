# CHANGES

## 2026-06-25 — Fix : décodage des notes abîmées (JSON imbriqué)

### Fixed
- **Notes affichées cassées dans l'app** (accents visibles comme `é`, sauts de ligne comme `\\n`). Cause : l'API Plaud retourne `data_content` comme une **chaîne JSON échappée** (ex. `"{\"ai_content\": \"...\"}"`), que Swift décodait comme une simple string sans parser le JSON imbriqué. Résultat : la chaîne brute avec tous les échappements restait visible.
- Solution : ajout d'un décodeur personnalisé `init(from:)` dans `NoteSection` qui détecte et parse le JSON imbriqué, extrait le champ `ai_content`, et l'utilise au lieu de la chaîne brute. Les notes dont `data_content` est du JSON valide sont désormais correctement décodées.

### Changed
- `NoteSection` : ajout de `init(from:)` et `encode(to:)` personnalisés pour gérer le décodage imbriqué de `data_content`.

### Validation
- Test unitaire (script Swift) : décodage d'une note test avec accents (`café`, `élève`) et sauts de ligne — tous les caractères spéciaux sont maintenant décodés correctement ✅. Build ✅.

## 2026-06-24 (suite 3) — Export d'une note en Word (.docx)

### Added
- **Export Word** : bouton « Exporter en Word » dans l'onglet Notes (à côté de « Enregistrer les images »). Génère un vrai `.docx` de la note affichée, avec **mise en page** (titres, listes, cases à cocher, gras/italique/barré/code, tableaux, citations) et **images embarquées**.
- `DocxExporter` (dans `NotesView.swift`) : génération **Office Open XML à la main** — convertisseur Markdown → corps `document.xml`, téléchargement + intégration des images dans `word/media`, et un mini **écrivain ZIP** maison (`DocxZip` + `DocxCRC32`, méthode « stored »). Aucune dépendance externe.
- Clés de localisation fr/en/zh : `export_word`, `export_word_help`.

### Decisions
- **Pourquoi générer le `.docx` à la main** : les API natives `NSAttributedString` (`.officeOpenXML`) **n'embarquent pas les images** dans un `.docx` (seul `.rtfd`, un bundle, le fait — vérifié). La génération OOXML directe est la seule voie native pour un Word autonome avec images.
- Images redimensionnées (largeur max ~600 px) ; conversion px → EMU (×9525).

### Validation
- Pipeline validé hors app : `document.xml` **bien formé** (xmllint), image présente dans `word/media`, document **relu par `textutil`** (titres, cases à cocher, listes, tableau, échappement XML `&`/`<`). Build ✅.

## 2026-06-24 (suite 2) — Rendu Markdown des notes plus complet

### Fixed
- **Éléments Markdown non interprétés dans les notes.** Analyse du contenu réel : `#### ` (titres niv. 4, 43×) affichés en texte brut, et surtout **cases à cocher `- [ ]` / `- [x]` (1079×)** rendues `[ ]` littéral. Corrigé dans `MarkdownWebView.convert`.
- **`---` parasite.** Une ligne séparatrice `---` était captée par la règle « `--` détail » (affichait un `-` isolé) ; HR remis en priorité et restreint aux lignes de tirets/étoiles/underscores.
- **Listes éclatées.** Bug préexistant de `openList` : chaque item était enfermé dans son propre `<ul>`. Les items de même niveau sont désormais regroupés et l'imbrication est correcte.

### Added (rendu `MarkdownWebView.convert`)
- Titres **niveau 1 à 6** (`#`…`######`) ; **cases à cocher** ☐/☑ stylées ; **liens** `[texte](url)` + **URLs nues** (autolink, URLs protégées de l'emphase) ; **barré** `~~…~~` ; **blocs de code** ```` ``` ```` ; **tableaux** GFM `| … |`.
- CSS associé : h4-h6, `li.task`, `<a>`, `<del>`, `<pre>/<code>`, `<table>`.

### Changed (cohérence sync Notion)
- `MarkdownToNotion` : `#### `+ → `heading_3` (plafond Notion) ; cases à cocher → blocs **`to_do`** natifs (avec état coché). → Notion reçoit des vraies cases à cocher au lieu de `[ ]` en texte.

### Validation
- `convert()` (fonction pure) extraite et **testée hors app** sur des cas réels (titres, cases, tableau, liens, code, barré, imbrication) — rendu HTML vérifié. Build ✅.

## 2026-06-24 (suite) — Sync Notion : contenu complet des notes + images persistantes

### Fixed
- **Sync Notion incomplète.** `buildMarkdown` n'utilisait que `dataContent`, donc les notes `consumer_note` / `high_light` (contenu sur S3) partaient **vides** vers Notion (titre seul). Désormais leur contenu est téléchargé et poussé en entier.
- **Images absentes/cassées dans Notion.** `MarkdownToNotion` ne gérait pas les images ; les chemins relatifs partaient en texte brut. Désormais les images sont **téléversées dans Notion** (persistantes) et insérées comme blocs image.

### Added
- `NotionAPI.uploadFile(data:filename:contentType:token:)` — flux *file upload* Notion en 2 temps (`POST /file_uploads` puis envoi `multipart/form-data`). Validé avec `Notion-Version 2022-06-28`.
- `MarkdownToNotion.blocks(from:imageUploads:)` + `imagePaths(in:)` — produit des blocs image `file_upload` ; les images sans upload sont retirées (pas de texte cassé).
- `NotionSyncService.ResolvedNote` (titre + markdown brut + map chemin→URL S3) ; `buildBlocks(body:item:token:)` téléverse à la demande les images **référencées** (dédoublonnage par URL), `uploadImage(s3url:token:)`, `contentType(for:)`.
- `RecordingsViewModel.rawNoteMarkdown(_:)` — markdown brut d'une note (inline ou S3) pour la sync.

### Changed
- `NotionSyncService.Item.notes` : `[NoteSection]` → `[ResolvedNote]`.
- `syncToNotion` re-fetch un **détail frais** par enregistrement (liens S3 valides), repli sur cache si réseau KO ; assemble les `ResolvedNote`.
- **Hash de sync stable** : calculé sur le markdown **brut** (chemins relatifs), pas sur les URLs S3 volatiles → pas de re-sync en boucle ; les images ne sont téléversées que lors d'un create/update réel (jamais sur un `skipped`).

### Notes techniques
- Première sync après cette mise à jour : les pages ayant des notes distantes seront **mises à jour une fois** (le hash inclut maintenant leur contenu).
- Coût : la sync fait désormais un appel `getFile` par enregistrement (liens frais) + un upload par image lors des create/update.

## 2026-06-24 — Notes multiples + images des notes

### Fixed
- **Une seule note affichée par enregistrement.** `NotesView` ne gardait que les sections `auto_sum_note` ; les notes `consumer_note` (notes par template) et `high_light` (« Points à retenir ») étaient téléchargées mais jamais affichées. L'app montre désormais **toutes** les notes du `note_list`.
- **Images des notes en lien cassé.** `MarkdownWebView.convert` ne gérait pas la syntaxe image Markdown `![alt](url)`, et les images Plaud sont référencées par **chemin relatif** (`permanent/…/mark/xxx.jpg`). Résultat : aucune image ne s'affichait.

### Added
- **Sélecteur de notes** (menu déroulant) dans l'onglet « Notes IA » quand un enregistrement a plusieurs notes (Résumé, Points à retenir, et chaque note par titre).
- **Rendu des images** dans les notes : résolution des chemins relatifs via le nouveau champ `NoteSection.downloadLinkMap` (chemin → URL S3 pré-signée), support `<img>` dans `MarkdownWebView.convert` (avec protection des URLs contre les règles d'emphase) + CSS image (coins arrondis, ombre, responsive).
- **Téléchargement des images** d'une note vers le disque (`ImageExporter`) : `NSSavePanel` pour une image, `NSOpenPanel` (choix de dossier) pour plusieurs.
- `PlaudAPI.fetchNoteMarkdown(from:)` — télécharge le Markdown d'une note depuis `data_link` (S3) pour les notes dont `data_content` est vide (`consumer_note`/`high_light`).
- `RecordingsViewModel.loadNoteContent(_:)` + cache mémoire `noteContents` (par `data_id`) ; contenu résolu (images incluses), inline ou distant.
- Clés de localisation fr/en/zh : `note_summary`, `note_highlights`, `note_generic`, `save_image`, `save_images`, `save_images_help`.

### Changed
- `NotesView` prend désormais le `RecordingsViewModel` (au lieu d'un `[NoteSection]`) pour gérer le chargement à la demande du contenu distant et le cache.
- `NoteSection` : nouveaux champs/aides `downloadLinkMap`, `contentIsRemote`, `resolvingImages(in:)`, `imageURLs`.

### Notes techniques
- Les URLs S3 (contenu distant + images) sont **pré-signées et expirent** ; elles ne sont pas mises en cache sur disque. Le stale-while-revalidate de `selectRecording` (fix du 06-23) garantit des liens frais à chaque ouverture.

## 2026-06-23 — Rafraîchissement des données d'un enregistrement (fix cache speakers)

### Fixed
- **Les noms d'interlocuteurs (et notes) modifiés côté Plaud ne se mettaient jamais à jour dans l'app.** Cause : `selectRecording` retournait le cache `notes/{id}.json` sans jamais revalider, et `loadTranscript()` était bloqué par son guard `transcriptSegments.isEmpty` tant qu'on restait sur la même réunion → `transcriptSegments` (source des onglets Transcription & Interlocuteurs) jamais re-fetché.

### Added
- `PlaudCache.clearNotes(id:)` — invalide le cache d'un seul enregistrement.
- `RecordingsViewModel.refreshCurrentRecording()` — force le re-téléchargement de l'enregistrement sélectionné (notes + transcription + plan) en ignorant le cache, puis réécrit le cache.
- Bouton **rafraîchir** (icône `arrow.clockwise`) dans l'en-tête du détail d'un enregistrement (`RecordingDetailView`).
- Section **Cache local** dans les Réglages avec bouton **Vider le cache** (branche le `PlaudCache.clearAll()` déjà existant, jusqu'ici non exposé en UI).
- Clés de localisation fr/en/zh : `refresh_recording_help`, `settings_cache`, `cache_clear`, `cache_clear_help`, `cache_cleared`.

### Changed
- `selectRecording` passe en **stale-while-revalidate** : affiche le cache instantanément (si présent), puis revalide depuis le serveur en arrière-plan et remplit d'emblée `transcriptSegments` / `outlineSegments` (l'onglet Interlocuteurs est donc à jour sans second appel API). La réponse est ignorée si l'utilisateur a changé de sélection entre-temps.
- Helper privé `fetchDetail(for:)` factorise la logique de fetch + cache partagée par `selectRecording` et `refreshCurrentRecording`.

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
- **Identifiants Apple réutilisés de MarkdownViewer** : identité `Developer ID Application: Vincent LAURIAT (KFLACS69T9)` + profil notary partagé **`AppliMacVincentGithub`** (apple-id `vincent@lauriat.fr`, team `KFLACS69T9`) — déjà en place, aucune création nécessaire.

### Build
- **`PlaudCompanion-1.0.0.dmg` produit, signé, notarisé (Apple : Accepted) et stapled** (~497 Ko). Vérifié : `spctl` → *accepted, source=Notarized Developer ID*.
- **Release `v1.0.0` publiée sur GitHub** avec le DMG en asset : https://github.com/vincentlauriat/plaud-companion/releases/tag/v1.0.0 (commits poussés sur `main`).

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
