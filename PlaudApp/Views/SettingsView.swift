import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var testing = false
    @State private var testResult: String?
    @State private var cacheCleared = false
    @State private var plaudInfo: PlaudTokenInfo?
    @State private var refreshingPlaud = false
    @State private var plaudMessage: String?
    #if os(iOS)
    @State private var tokenInput = ""
    @State private var tokenPresent = false
    @State private var tokenMessage: String?
    #endif

    var body: some View {
        @Bindable var settings = settings

        Form {
            #if os(macOS)
            // Compte Plaud : la connexion se fait hors de l'app (login MCP via Claude
            // Code qui écrit ~/.plaud/tokens-mcp.json) — cette section rend l'état du
            // token visible et permet de le renouveler sans attendre un échec réseau.
            Section(settings.t("settings_plaud_account")) {
                plaudStatusRows
                Text(settings.t("plaud_reconnect_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .task { plaudInfo = await TokenStore.shared.tokenInfo() }
            #endif

            #if os(iOS)
            // Authentification : sur iOS, pas de fichier ~/.plaud partagé → l'utilisateur
            // colle le contenu de tokens-mcp.json (copié depuis son Mac).
            Section(settings.t("settings_token")) {
                plaudStatusRows
                Text(tokenPresent ? settings.t("token_present") : settings.t("token_absent"))
                    .font(.callout)
                    .foregroundStyle(tokenPresent ? Color.secondary : Color.primary)
                TextEditor(text: $tokenInput)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 90)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(settings.t("token_save")) {
                    Task { await saveToken() }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let tokenMessage {
                    Text(tokenMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .task {
                tokenPresent = await TokenStore.shared.hasToken()
                plaudInfo = await TokenStore.shared.tokenInfo()
            }
            #endif

            Section(settings.t("settings_appearance")) {
                Picker(settings.t("settings_appearance"), selection: $settings.appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(settings.t(mode.titleKey)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(settings.t("settings_language")) {
                Picker(settings.t("settings_language"), selection: $settings.languageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang == .system ? settings.t("language_system") : lang.nativeName)
                            .tag(lang.rawValue)
                    }
                }
                .labelsHidden()
            }

            Section(settings.t("settings_notion")) {
                SecureField(settings.t("notion_token"), text: $settings.notionToken)
                TextField(settings.t("notion_database"), text: $settings.notionDatabaseID)
                Toggle(settings.t("notion_autosync"), isOn: $settings.notionAutoSync)

                HStack {
                    Button(settings.t("notion_test")) {
                        Task { await testConnection() }
                    }
                    .disabled(!settings.notionConfigured || testing)
                    if testing { ProgressView().scaleEffect(0.6) }
                    if let testResult {
                        Text(testResult).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Button(settings.t("notion_reset"), role: .destructive) {
                    Task {
                        await NotionSyncStore.shared.reset()
                        testResult = settings.t("notion_reset_done")
                    }
                }
                .help(settings.t("notion_reset_help"))

                Text(settings.t("notion_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(settings.t("settings_cache")) {
                Button(settings.t("cache_clear"), role: .destructive) {
                    Task {
                        await PlaudCache.shared.clearAll()
                        cacheCleared = true
                    }
                }
                .help(settings.t("cache_clear_help"))
                if cacheCleared {
                    Text(settings.t("cache_cleared"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(settings.t("settings_about")) {
                Text(settings.t("settings_about_text"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 460, height: 640)
        #endif
    }

    // MARK: Compte Plaud

    /// Pastille d'état + expiration + bouton de renouvellement du token Plaud.
    @ViewBuilder
    private var plaudStatusRows: some View {
        HStack(spacing: 8) {
            Circle().fill(plaudStatusColor).frame(width: 9, height: 9)
            Text(plaudStatusText).font(.callout)
        }
        if let expiry = plaudInfo?.expiresAt, plaudInfo?.isExpired == false {
            Text("\(settings.t("plaud_token_valid_until")) \(formatDate(expiry))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        HStack {
            Button(settings.t("plaud_refresh_now")) {
                Task { await refreshPlaudToken() }
            }
            .disabled(plaudInfo?.hasRefreshToken != true || refreshingPlaud)
            if refreshingPlaud { ProgressView().scaleEffect(0.6) }
            if let plaudMessage {
                Text(plaudMessage).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var plaudStatusColor: Color {
        guard let info = plaudInfo else { return .red }
        if !info.isExpired { return .green }
        return info.hasRefreshToken ? .orange : .red
    }

    private var plaudStatusText: String {
        guard let info = plaudInfo else { return settings.t("plaud_status_absent") }
        if !info.isExpired { return settings.t("plaud_status_connected") }
        return settings.t(info.hasRefreshToken
            ? "plaud_status_expired_refreshable" : "plaud_status_expired")
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: AppLocale.identifier)
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func refreshPlaudToken() async {
        refreshingPlaud = true
        plaudMessage = nil
        do {
            _ = try await TokenStore.shared.forceRefresh()
            plaudMessage = settings.t("plaud_refresh_ok")
        } catch {
            plaudMessage = error.localizedDescription
        }
        plaudInfo = await TokenStore.shared.tokenInfo()
        refreshingPlaud = false
    }

    #if os(iOS)
    private func saveToken() async {
        do {
            try await TokenStore.shared.importToken(json: tokenInput)
            tokenPresent = true
            tokenInput = ""
            tokenMessage = settings.t("token_saved")
            plaudInfo = await TokenStore.shared.tokenInfo()
        } catch {
            tokenMessage = settings.t("token_invalid")
        }
    }
    #endif

    private func testConnection() async {
        testing = true
        testResult = nil
        do {
            _ = try await NotionAPI.shared.resolveTarget(
                id: NotionID.normalize(settings.notionDatabaseID), token: settings.notionToken)
            testResult = settings.t("notion_test_ok")
        } catch {
            testResult = error.localizedDescription
        }
        testing = false
    }
}
