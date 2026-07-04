import Foundation

/// Table de traductions trilingue (fr / en / zh-Hans).
/// Clé → chaîne. La langue `en` sert de repli.
enum Strings {
    static let table: [String: [String: String]] = [
        "fr": [
            "app_name": "Plaud Companion",

            // Sidebar / liste
            "search_placeholder": "Rechercher…",
            "refresh": "Rafraîchir",
            "refresh_help": "Rafraîchir la liste depuis Plaud",
            "no_recordings_title": "Aucun enregistrement",
            "no_recordings_desc": "Vérifie ta connexion ou reconnecte-toi via Claude Code.",
            "cached_help": "Notes en cache local",

            // Groupes de dates
            "group_today": "Aujourd'hui",
            "group_week": "Cette semaine",
            "group_earlier": "Plus tôt",

            // Onglets détail
            "tab_summary": "Résumé",
            "tab_notes": "Notes IA",
            "tab_transcription": "Transcription",
            "tab_speakers": "Interlocuteurs",

            // Sous-onglets transcription
            "tr_raw": "Brute",
            "tr_polished": "Polie",
            "tr_outline": "Plan",

            // Chargement
            "loading": "Chargement…",
            "loading_transcript": "Chargement de la transcription…",
            "loading_polished": "Chargement de la transcription polie…",

            // Notes
            "no_notes_title": "Aucune note",
            "no_notes_desc": "Les notes IA ne sont pas encore disponibles pour cet enregistrement.",
            "note_load_failed": "Échec du chargement de la note",
            "retry": "Réessayer",

            // Transcription
            "no_transcript_title": "Transcription indisponible",
            "no_transcript_desc": "La transcription n'est pas encore disponible pour cet enregistrement.",

            // Plan / outline
            "no_outline_title": "Plan indisponible",
            "no_outline_desc": "Le plan n'est pas encore disponible. Charge d'abord la transcription brute.",
            "no_transcript_for_chapter": "Aucune transcription pour ce chapitre.",

            // Interlocuteurs
            "no_speakers_title": "Aucun interlocuteur",
            "no_speakers_desc": "Charge d'abord la transcription.",
            "unit_speaker_one": "interlocuteur",
            "unit_speaker_many": "interlocuteurs",
            "unit_intervention_one": "intervention",
            "unit_intervention_many": "interventions",

            // Sélection vide
            "empty_title": "Sélectionne un enregistrement",
            "empty_desc": "Choisis un enregistrement dans la liste pour voir ses notes et sa transcription.",

            // Erreur
            "error_title": "Erreur",
            "ok": "OK",

            // Réglages
            "settings_title": "Réglages",
            "settings_appearance": "Apparence",
            "appearance_system": "Système",
            "appearance_light": "Clair",
            "appearance_dark": "Sombre",
            "settings_language": "Langue",
            "language_system": "Système",
            "settings_about": "À propos",
            "settings_about_text": "Navigateur natif pour vos enregistrements Plaud.",
            // Authentification (collage du token, surtout sur iOS)
            "settings_token": "Authentification Plaud",
            "token_present": "Token présent. L'app est connectée.",
            "token_absent": "Aucun token. Colle ci-dessous le contenu de ~/.plaud/tokens-mcp.json (depuis ton Mac).",
            "token_paste_prompt": "Contenu de tokens-mcp.json",
            "token_save": "Enregistrer le token",
            "token_saved": "Token enregistré. ✅",
            "token_invalid": "JSON de token invalide.",
            "refresh_recording_help": "Re-télécharger cet enregistrement depuis Plaud (noms d'interlocuteurs, notes…)",
            "settings_cache": "Cache local",
            "cache_clear": "Vider le cache",
            "cache_clear_help": "Supprime les notes et transcriptions en cache. Elles seront re-téléchargées depuis Plaud.",
            "cache_cleared": "Cache vidé. Les données seront re-téléchargées à la prochaine ouverture.",
            "note_summary": "Résumé",
            "note_highlights": "Points à retenir",
            "note_generic": "Note",
            "save_image": "Enregistrer l'image",
            "save_images": "Enregistrer les images",
            "save_images_help": "Enregistrer les images de cette note sur le disque",
            "export_word": "Exporter en Word",
            "export_word_help": "Générer un document Word (.docx) de cette note, mise en page et images comprises",

            // Notion
            "settings_notion": "Synchronisation Notion",
            "notion_token": "Token d'intégration",
            "notion_database": "URL ou ID (base ou page)",
            "notion_autosync": "Synchroniser après chaque rafraîchissement",
            "notion_test": "Tester la connexion",
            "notion_test_ok": "Connexion réussie ✓",
            "notion_reset": "Réinitialiser l'état de sync",
            "notion_reset_help": "Oublie le mapping local : le prochain sync recréera toutes les pages.",
            "notion_reset_done": "État réinitialisé. Lance une synchro pour tout recréer.",
            "notion_help": "Crée une intégration sur notion.so/my-integrations, copie le token, puis partage ta base (ou une page) avec cette intégration et colle son ID ici. Une database reçoit des entrées ; une page reçoit des sous-pages.",
            "notion_sync": "Synchroniser",
            "notion_sync_help": "Pousser les enregistrements vers Notion",
            "notion_sync_done": "Synchronisation terminée",
            "notion_created": "Créés",
            "notion_updated": "Mis à jour",
            "notion_skipped": "Inchangés",
            "notion_failed": "Échecs",

            // Personnes / annuaire
            "mode_meetings": "Réunions",
            "mode_people": "Personnes",
            "search_people": "Rechercher une personne…",
            "index_all": "Tout indexer",
            "index_all_help": "Charger toutes les réunions pour compléter l'annuaire des personnes",
            "no_people_title": "Aucune personne",
            "no_people_desc": "Ouvre des réunions (ou lance « Tout indexer ») pour construire l'annuaire à partir des interlocuteurs détectés.",
            "no_person_recordings_title": "Aucune réunion",
            "no_person_recordings_desc": "Aucune réunion indexée pour cette personne.",
            "back": "Personnes",
        ],

        "en": [
            "app_name": "Plaud Companion",

            "search_placeholder": "Search…",
            "refresh": "Refresh",
            "refresh_help": "Refresh the list from Plaud",
            "no_recordings_title": "No recordings",
            "no_recordings_desc": "Check your connection or sign in again via Claude Code.",
            "cached_help": "Notes cached locally",

            "group_today": "Today",
            "group_week": "This week",
            "group_earlier": "Earlier",

            "tab_summary": "Summary",
            "tab_notes": "AI Notes",
            "tab_transcription": "Transcription",
            "tab_speakers": "Speakers",

            "tr_raw": "Raw",
            "tr_polished": "Polished",
            "tr_outline": "Outline",

            "loading": "Loading…",
            "loading_transcript": "Loading transcription…",
            "loading_polished": "Loading polished transcription…",

            "no_notes_title": "No notes",
            "no_notes_desc": "AI notes are not available yet for this recording.",
            "note_load_failed": "Failed to load note",
            "retry": "Retry",

            "no_transcript_title": "Transcription unavailable",
            "no_transcript_desc": "The transcription is not available yet for this recording.",

            "no_outline_title": "Outline unavailable",
            "no_outline_desc": "The outline is not available yet. Load the raw transcription first.",
            "no_transcript_for_chapter": "No transcription for this chapter.",

            "no_speakers_title": "No speakers",
            "no_speakers_desc": "Load the transcription first.",
            "unit_speaker_one": "speaker",
            "unit_speaker_many": "speakers",
            "unit_intervention_one": "intervention",
            "unit_intervention_many": "interventions",

            "empty_title": "Select a recording",
            "empty_desc": "Pick a recording from the list to see its notes and transcription.",

            "error_title": "Error",
            "ok": "OK",

            "settings_title": "Settings",
            "settings_appearance": "Appearance",
            "appearance_system": "System",
            "appearance_light": "Light",
            "appearance_dark": "Dark",
            "settings_language": "Language",
            "language_system": "System",
            "settings_about": "About",
            "settings_about_text": "A native companion for your Plaud recordings.",
            "settings_token": "Plaud authentication",
            "token_present": "Token present. The app is connected.",
            "token_absent": "No token. Paste the contents of ~/.plaud/tokens-mcp.json (from your Mac) below.",
            "token_paste_prompt": "Contents of tokens-mcp.json",
            "token_save": "Save token",
            "token_saved": "Token saved. ✅",
            "token_invalid": "Invalid token JSON.",
            "refresh_recording_help": "Re-download this recording from Plaud (speaker names, notes…)",
            "settings_cache": "Local cache",
            "cache_clear": "Clear cache",
            "cache_clear_help": "Removes cached notes and transcriptions. They will be re-downloaded from Plaud.",
            "cache_cleared": "Cache cleared. Data will be re-downloaded next time you open a recording.",
            "note_summary": "Summary",
            "note_highlights": "Key points",
            "note_generic": "Note",
            "save_image": "Save image",
            "save_images": "Save images",
            "save_images_help": "Save this note's images to disk",
            "export_word": "Export to Word",
            "export_word_help": "Generate a Word (.docx) document of this note, with layout and images",

            // Notion
            "settings_notion": "Notion sync",
            "notion_token": "Integration token",
            "notion_database": "URL or ID (database or page)",
            "notion_autosync": "Sync after each refresh",
            "notion_test": "Test connection",
            "notion_test_ok": "Connected ✓",
            "notion_reset": "Reset sync state",
            "notion_reset_help": "Forget the local mapping: the next sync recreates all pages.",
            "notion_reset_done": "State reset. Run a sync to recreate everything.",
            "notion_help": "Create an integration at notion.so/my-integrations, copy the token, then share your database (or a page) with that integration and paste its ID here. A database gets entries; a page gets sub-pages.",
            "notion_sync": "Sync",
            "notion_sync_help": "Push recordings to Notion",
            "notion_sync_done": "Sync complete",
            "notion_created": "Created",
            "notion_updated": "Updated",
            "notion_skipped": "Unchanged",
            "notion_failed": "Failed",

            // People / directory
            "mode_meetings": "Meetings",
            "mode_people": "People",
            "search_people": "Search a person…",
            "index_all": "Index all",
            "index_all_help": "Load all meetings to complete the people directory",
            "no_people_title": "No people",
            "no_people_desc": "Open meetings (or run “Index all”) to build the directory from detected speakers.",
            "no_person_recordings_title": "No meetings",
            "no_person_recordings_desc": "No indexed meetings for this person.",
            "back": "People",
        ],

        "zh": [
            "app_name": "Plaud Companion",

            "search_placeholder": "搜索…",
            "refresh": "刷新",
            "refresh_help": "从 Plaud 刷新列表",
            "no_recordings_title": "没有录音",
            "no_recordings_desc": "请检查网络连接，或通过 Claude Code 重新登录。",
            "cached_help": "笔记已本地缓存",

            "group_today": "今天",
            "group_week": "本周",
            "group_earlier": "更早",

            "tab_summary": "摘要",
            "tab_notes": "AI 笔记",
            "tab_transcription": "转录",
            "tab_speakers": "发言人",

            "tr_raw": "原始",
            "tr_polished": "润色",
            "tr_outline": "大纲",

            "loading": "加载中…",
            "loading_transcript": "正在加载转录…",
            "loading_polished": "正在加载润色转录…",

            "no_notes_title": "暂无笔记",
            "no_notes_desc": "此录音暂无 AI 笔记。",
            "note_load_failed": "笔记加载失败",
            "retry": "重试",

            "no_transcript_title": "暂无转录",
            "no_transcript_desc": "此录音暂无转录。",

            "no_outline_title": "暂无大纲",
            "no_outline_desc": "暂无大纲。请先加载原始转录。",
            "no_transcript_for_chapter": "本章节暂无转录。",

            "no_speakers_title": "暂无发言人",
            "no_speakers_desc": "请先加载转录。",
            "unit_speaker_one": "位发言人",
            "unit_speaker_many": "位发言人",
            "unit_intervention_one": "次发言",
            "unit_intervention_many": "次发言",

            "empty_title": "选择一个录音",
            "empty_desc": "从列表中选择一个录音，查看其笔记和转录。",

            "error_title": "错误",
            "ok": "好",

            "settings_title": "设置",
            "settings_appearance": "外观",
            "appearance_system": "跟随系统",
            "appearance_light": "浅色",
            "appearance_dark": "深色",
            "settings_language": "语言",
            "language_system": "跟随系统",
            "settings_about": "关于",
            "settings_about_text": "您的 Plaud 录音原生伴侣应用。",
            "settings_token": "Plaud 身份验证",
            "token_present": "已有令牌，应用已连接。",
            "token_absent": "无令牌。请在下方粘贴 ~/.plaud/tokens-mcp.json 的内容（来自你的 Mac）。",
            "token_paste_prompt": "tokens-mcp.json 的内容",
            "token_save": "保存令牌",
            "token_saved": "令牌已保存。✅",
            "token_invalid": "令牌 JSON 无效。",
            "refresh_recording_help": "从 Plaud 重新下载此录音（发言人名称、笔记…）",
            "settings_cache": "本地缓存",
            "cache_clear": "清除缓存",
            "cache_clear_help": "删除已缓存的笔记和转录，下次将从 Plaud 重新下载。",
            "cache_cleared": "缓存已清除。下次打开录音时将重新下载数据。",
            "note_summary": "摘要",
            "note_highlights": "要点",
            "note_generic": "笔记",
            "save_image": "保存图片",
            "save_images": "保存图片",
            "save_images_help": "将此笔记的图片保存到磁盘",
            "export_word": "导出为 Word",
            "export_word_help": "生成此笔记的 Word (.docx) 文档（含排版和图片）",

            // Notion
            "settings_notion": "Notion 同步",
            "notion_token": "集成令牌",
            "notion_database": "URL 或 ID（数据库或页面）",
            "notion_autosync": "每次刷新后同步",
            "notion_test": "测试连接",
            "notion_test_ok": "连接成功 ✓",
            "notion_reset": "重置同步状态",
            "notion_reset_help": "清除本地映射：下次同步将重新创建所有页面。",
            "notion_reset_done": "状态已重置。运行同步以重新创建所有内容。",
            "notion_help": "在 notion.so/my-integrations 创建集成，复制令牌，然后将数据库（或页面）共享给该集成并在此粘贴其 ID。数据库会新增条目；页面会创建子页面。",
            "notion_sync": "同步",
            "notion_sync_help": "将录音推送到 Notion",
            "notion_sync_done": "同步完成",
            "notion_created": "已创建",
            "notion_updated": "已更新",
            "notion_skipped": "未变更",
            "notion_failed": "失败",

            // 人物 / 目录
            "mode_meetings": "会议",
            "mode_people": "人物",
            "search_people": "搜索人物…",
            "index_all": "索引全部",
            "index_all_help": "加载所有会议以完善人物目录",
            "no_people_title": "暂无人物",
            "no_people_desc": "打开会议（或运行“索引全部”）以根据检测到的发言人构建目录。",
            "no_person_recordings_title": "暂无会议",
            "no_person_recordings_desc": "该人物暂无已索引的会议。",
            "back": "人物",
        ],
    ]
}
