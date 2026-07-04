import SwiftUI

/// Mode de navigation de la barre latérale : par réunion ou par personne.
enum BrowseMode: String, CaseIterable, Identifiable {
    case meetings, people
    var id: String { rawValue }
    var titleKey: String { self == .meetings ? "mode_meetings" : "mode_people" }
}

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var vm = RecordingsViewModel()
    @State private var selectedId: String?
    @State private var browseMode: BrowseMode = .meetings
    #if os(iOS)
    @State private var showingSettings = false
    #endif

    /// Barre latérale : sélecteur de mode + liste (réunions ou personnes).
    @ViewBuilder private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $browseMode) {
                ForEach(BrowseMode.allCases) { mode in
                    Text(settings.t(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            switch browseMode {
            case .meetings:
                RecordingListView(vm: vm, selectedId: $selectedId)
            case .people:
                PeopleListView(vm: vm, selectedId: $selectedId)
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                #endif
        } detail: {
            if vm.selectedRecording != nil {
                RecordingDetailView(vm: vm)
            } else {
                EmptySelectionView()
            }
        }
        .task { await vm.loadRecordings() }
        .onChange(of: selectedId) { _, id in
            guard let id, let rec = vm.recordings.first(where: { $0.id == id }) else { return }
            Task { await vm.selectRecording(rec) }
        }
        .alert(settings.t("error_title"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(settings.t("ok")) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        #if os(iOS)
        // À la fermeture des Réglages (où l'on colle le token), on recharge la liste.
        .sheet(isPresented: $showingSettings, onDismiss: {
            Task { await vm.loadRecordings() }
        }) {
            NavigationStack {
                SettingsView()
                    .environment(settings)
                    .navigationTitle(settings.t("settings_title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(settings.t("ok")) { showingSettings = false }
                        }
                    }
            }
        }
        #endif
    }
}
