<div align="center">

# Plaud Companion

**A native macOS app to browse, read, and sync your [Plaud](https://www.plaud.ai) voice‑recording notes — and push them to Notion.**

[![Release](https://img.shields.io/github/v/release/vincentlauriat/plaud-companion?label=release&color=FF7A45)](https://github.com/vincentlauriat/plaud-companion/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)](#-license)

</div>

> [!NOTE]
> **Unofficial project.** Plaud Companion is a third‑party app and is **not affiliated with, endorsed by, or supported by Plaud.** It talks to Plaud's official **third‑party read‑only API** using your own credentials.

---

## 📖 Table of contents

- [What is Plaud Companion?](#-what-is-plaud-companion)
- [Features at a glance](#-features-at-a-glance)
- [Screenshots](#-screenshots)
- [How it works](#-how-it-works)
- [Installation](#-installation)
- [First launch & authentication](#-first-launch--authentication)
- [Using the app](#-using-the-app)
- [Notion sync (one‑way, incremental)](#-notion-sync-one-way-incremental)
- [Privacy & security](#-privacy--security)
- [Project layout](#-project-layout)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🧐 What is Plaud Companion?

Plaud devices record audio and the Plaud cloud turns it into **AI summaries, structured notes, and transcriptions**. The official mobile/web apps are great for capture — but if you live on a Mac and want to **read, search, archive, and reuse** that content, you're stuck switching contexts.

**Plaud Companion** is a small, fast, native macOS app that:

- 📂 Lists **all your recordings**, grouped by date, with instant search.
- 📝 Shows the **AI summary**, the **AI notes** (nicely rendered Markdown), and the **full transcription**.
- 🗣️ Breaks down **who spoke and for how long** (speaker stats).
- 🧭 Lets you click a chapter in the **outline** to jump straight to the matching transcript segments.
- 🔄 **Syncs everything to Notion** — one direction, only what changed, so you never re‑copy the same notes twice.
- 🌍 Speaks **English, French and Chinese**, follows light/dark mode, and works offline thanks to a local cache.

It is **read‑only** against Plaud (it never edits or deletes anything in your Plaud account) and stores nothing in the cloud of its own.

---

## ✨ Features at a glance

| Area | What you get |
|---|---|
| **Recordings list** | Paginated load of every recording, grouped into *Today / This week / Earlier*, with live search and a cache indicator. |
| **Summary tab** | The Plaud AI summary, rendered as clean HTML (headings, lists, quotes, code). |
| **AI Notes tab** | All note sections (`auto_sum_note`, `auto_sum_brief`…) with proper Markdown rendering. |
| **Transcription tab** | Three views: **Raw** (with timestamps & speakers), **Polished** (Plaud's cleaned‑up version), and **Outline** (chapters). |
| **Interactive outline** | Click a chapter → it expands and shows the raw transcript segments that fall within its time range. |
| **Speakers tab** | Per‑speaker talk time, percentage, and number of interventions, with progress bars. |
| **Notion sync** | One‑way **Plaud → Notion**, incremental (diff by content hash), works with a **database** *or* a **page**, auto‑fills table columns. |
| **Local cache** | Recordings and notes are cached under *Application Support* for instant reopening and offline reading. |
| **Localization** | English 🇬🇧 · French 🇫🇷 · Chinese 🇨🇳, plus *follow system language*. |
| **Appearance** | Light · Dark · System. |

---

## 📸 Screenshots

> _Add your own screenshots here once the repo is public._
>
> Suggested shots: the recordings list, the Summary tab, the Transcription/Outline tab, the Speakers tab, and the Notion settings panel. Drop the images in a `docs/` folder and reference them, e.g.:

```markdown
![Recordings list](docs/screenshot-list.png)
![Summary tab](docs/screenshot-summary.png)
![Notion settings](docs/screenshot-notion.png)
```

---

## ⚙️ How it works

```
┌──────────────────────────────┐
│  Plaud Companion (this app)  │   SwiftUI · macOS 14+
│  Models · Services · Views   │
└───────────────┬──────────────┘
                │ reads OAuth token from ~/.plaud/tokens-mcp.json
                │ (shared with the Plaud MCP server)
        ┌───────┴────────┐
        ▼                ▼
  Plaud third‑party   Notion API
  API (READ‑ONLY)     (v1, create/update pages)
```

- **Authentication** is shared with the [Plaud MCP server](https://www.npmjs.com/package/@plaud-ai/mcp): the app reads (and refreshes) the OAuth token stored in `~/.plaud/tokens-mcp.json`. You log in once via the MCP, and the app reuses that session.
- **Plaud access is read‑only.** The app only calls `GET …/files`. It cannot change or delete anything in your Plaud account.
- **A local cache** (`~/Library/Application Support/Plaud/`) keeps the recordings list and the AI notes so reopening is instant and works offline.
- **Notion sync** keeps a tiny local state file (`notion-sync.json`) so it knows what has already been pushed and only writes what changed.

---

## 📦 Installation

### Requirements

- **macOS 14 (Sonoma) or later**
- For building from source: **Xcode 15+** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`)

### Option A — Download (coming soon)

A **signed & notarized** `.dmg` will be published on the [**Releases**](https://github.com/vincentlauriat/plaud-companion/releases) page. Once available:

1. Download `PlaudCompanion-<version>.dmg`.
2. Open it and drag **Plaud Companion** into your `Applications` folder.
3. Launch it normally — because the app is notarized by Apple, Gatekeeper opens it without warnings.

> _Until the DMG is out, please build from source (Option B). Maintainers: see [`RELEASE.md`](RELEASE.md) for the signing/notarization pipeline._

### Option B — Build from source

```bash
# 1. Clone
git clone https://github.com/vincentlauriat/plaud-companion.git
cd plaud-companion

# 2. Generate the Xcode project (required after any source change)
xcodegen generate

# 3a. Build & run in Xcode
open Plaud.xcodeproj
#     then press ⌘R

# 3b. …or build from the command line
xcodebuild -project Plaud.xcodeproj -scheme Plaud -configuration Debug build
```

The produced app bundle is **`Plaud Companion.app`** (the Xcode target/scheme is named `Plaud`).

> Maintainers building a distributable DMG: run `./Scripts/release.sh <version>` — see [`RELEASE.md`](RELEASE.md).

---

## 🔐 First launch & authentication

Plaud Companion does **not** ask for your Plaud password. Instead it reuses the session created by the **Plaud MCP server**, stored at `~/.plaud/tokens-mcp.json`.

**The simplest way to create that session today is via [Claude Code](https://claude.com/claude-code) with the Plaud MCP configured:**

1. Install the Plaud MCP (`npx @plaud-ai/mcp`) and configure it in your MCP client.
2. Run the MCP `login` tool once — this writes `~/.plaud/tokens-mcp.json`.
3. Launch Plaud Companion. It reads the token, refreshes it automatically when needed, and your recordings appear.

> [!TIP]
> If the list is empty and you see an authentication error, your token is missing or expired. Re‑run the MCP `login` step, then hit **Refresh** in the app.

---

## 🖱️ Using the app

- **Browse** — the sidebar lists every recording, grouped by date. Type in the search box to filter by name. A small badge marks recordings whose notes are cached locally.
- **Refresh** — the toolbar refresh button re‑fetches the full list from Plaud.
- **Read** — select a recording to open the detail view with four tabs:
  - **Summary** — the AI summary.
  - **AI Notes** — all note sections, Markdown‑rendered.
  - **Transcription** — switch between **Raw**, **Polished**, and **Outline**.
  - **Speakers** — talk‑time statistics per speaker.
- **Explore the outline** — in the **Outline** sub‑tab, click any chapter to expand it and reveal the transcript lines (timestamp · speaker · text) that belong to that chapter's time range.
- **Settings** (`⌘,`) — appearance, language, and the **Notion** panel (below).

---

## 🔄 Notion sync (one‑way, incremental)

Push your Plaud notes into Notion and keep them up to date — **without re‑copying everything every time.**

### What it does

- **Direction:** Plaud → Notion only. Your Plaud data is never modified.
- **Incremental:** each recording's content is hashed (SHA‑256). On every sync the app **creates** missing pages, **updates** only the ones whose content changed, and **skips** the rest.
- **Self‑healing:** before syncing, the app checks which pages still exist in Notion. If you deleted some, they are **recreated** automatically.
- **Flexible target:** the ID you provide can be a **database** *or* a **page** — the app detects which and behaves accordingly.

### Setup (one time)

1. Go to **[notion.so/my-integrations](https://www.notion.so/my-integrations)** → **New integration** → copy the **Internal Integration Secret** (the token).
2. Open the Notion **database or page** you want to sync into → menu **•••** → **Connections** → add your integration. *(Without this step Notion returns a 404.)*
3. Copy the **URL** of that database/page from your browser.
4. In Plaud Companion: **Settings → Notion**, paste the **token** and the **URL** (the app extracts the ID itself — full URL or raw ID both work), then click **Test connection**.
5. Click **Sync** (in the recordings toolbar). Optionally enable **Sync after each refresh**.

### Database vs page

| You point at a… | Result |
|---|---|
| **Database** (e.g. a full‑page table) | Each recording becomes a **row** in the table. The title goes in the title column; extra columns are auto‑filled (see below). |
| **Page** | Each recording becomes a **sub‑page** inside that page. |

### Automatic column mapping (databases only)

If your database has columns matching these rules, the app fills them in addition to the title:

| Column type in Notion | Column name contains… | Filled with |
|---|---|---|
| **Date** | _(any name)_ | the recording's date |
| **Number** | `duration` / `length` / `durée` / `时长` | duration in **minutes** |
| **Text** | `plaud` | the Plaud recording ID (handy for de‑duplication) |

Columns that don't exist or aren't recognized are simply ignored — so this works with **any** database schema. Add a recognized column later and the next sync updates existing rows to fill it.

### What gets pushed

- **Title** = recording name
- **Body** = a metadata line (date · duration) + the **AI summary** + the **AI notes** (converted to Notion blocks)
- _(Transcriptions are not pushed by default — see the roadmap.)_

### Resetting

**Settings → Notion → Reset sync state** clears the local mapping. The next sync recreates every page from scratch — useful if you deleted everything in Notion and want a clean rebuild.

---

## 🛡️ Privacy & security

- **Your Plaud token** lives only in `~/.plaud/tokens-mcp.json` (shared with the MCP). It is never displayed, logged, or sent anywhere except to Plaud's own API.
- **Your Notion token** is stored in the **macOS Keychain** — never in plain text, never logged.
- **No telemetry.** The app makes no network calls other than to Plaud (read‑only) and, if you configure it, Notion.
- **Read‑only on Plaud.** The app cannot modify or delete your recordings.

---

## 🗂️ Project layout

```
plaud-companion/
├── PlaudApp/
│   ├── PlaudApp.swift              # @main entry point
│   ├── Models/                     # Recording, NoteSection, NotionModels…
│   ├── Services/                   # actors: PlaudAPI, TokenStore, PlaudCache,
│   │                               #         NotionAPI, NotionSyncService,
│   │                               #         NotionSyncStore, Keychain, MarkdownToNotion
│   ├── ViewModels/                 # RecordingsViewModel (@Observable @MainActor)
│   ├── Views/                      # ContentView, RecordingListView, RecordingDetailView,
│   │                               # NotesView, TranscriptView, InterlocutorsView,
│   │                               # MarkdownWebView, SettingsView…
│   ├── Localization/               # Strings (en/fr/zh) + AppSettings
│   └── Assets.xcassets/            # app icon
├── Scripts/
│   ├── release.sh                  # build → sign → DMG → notarize → staple
│   └── make-dmg-background.swift   # generates the DMG installer background
├── plaud                           # optional Python CLI (terminal browser)
├── project.yml                     # XcodeGen project definition
├── RELEASE.md                      # release / notarization guide
└── README.md
```

**Architecture in one line:** SwiftUI views → an `@Observable` view model → `actor`‑based services for networking, caching, auth, and Notion sync. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full picture.

---

## 🗺️ Roadmap

- [x] Recordings list, search, date grouping, local cache
- [x] Summary / AI Notes / Transcription (Raw · Polished · Outline) / Speakers tabs
- [x] Clean Markdown rendering (WebView)
- [x] Interactive outline → transcript drill‑down
- [x] **One‑way incremental Notion sync** (database or page, auto column mapping)
- [ ] Prebuilt signed `.dmg` on the Releases page
- [ ] Cache raw transcription & outline (currently re‑fetched per open)
- [ ] Built‑in audio player synced to transcript timestamps
- [ ] Export a recording to Markdown / PDF
- [ ] Optionally push transcriptions to Notion
- [ ] Configurable Notion column names (instead of heuristics)

---

## 🤝 Contributing

Issues and pull requests are welcome! If you build from source:

1. Make your changes under `PlaudApp/`.
2. Run `xcodegen generate` if you added/removed files.
3. Build (`xcodebuild … build` or ⌘R in Xcode) before opening a PR.

Please keep code identifiers and commit messages in **English**.

---

## 📄 License

Released under the **MIT License**. See [`LICENSE`](LICENSE) for details.

---

<div align="center">

Made with ❤️ for Plaud users on macOS · _Not affiliated with Plaud._

</div>
