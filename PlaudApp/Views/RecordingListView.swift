import SwiftUI

struct RecordingListView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: RecordingsViewModel
    @Binding var selectedId: String?

    var body: some View {
        List(selection: $selectedId) {
            ForEach(vm.grouped, id: \.key) { group in
                Section(settings.t(group.key)) {
                    ForEach(group.recordings) { rec in
                        RecordingRowView(
                            recording: rec,
                            isCached: vm.cachedIds.contains(rec.id)
                        )
                        .tag(rec.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $vm.searchText, placement: .sidebar, prompt: settings.t("search_placeholder"))
        .navigationTitle(settings.t("app_name"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        await vm.refresh()
                        if settings.notionAutoSync && settings.notionConfigured {
                            await vm.syncToNotion(settings: settings)
                        }
                    }
                } label: {
                    if vm.isLoadingList {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Label(settings.t("refresh"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(vm.isLoadingList)
                .help(settings.t("refresh_help"))
            }
            if settings.notionConfigured {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await vm.syncToNotion(settings: settings) }
                    } label: {
                        if vm.isSyncing {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            Label(settings.t("notion_sync"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(vm.isSyncing || vm.isLoadingList)
                    .help(settings.t("notion_sync_help"))
                }
            }
        }
        .alert(settings.t("notion_sync_done"), isPresented: $vm.showSyncReport) {
            Button(settings.t("ok")) { vm.showSyncReport = false }
        } message: {
            if let r = vm.syncReport {
                Text(settings.notionSyncSummary(created: r.created, updated: r.updated,
                                                skipped: r.skipped, failed: r.failed,
                                                errors: r.errors))
            }
        }
        .overlay {
            if vm.recordings.isEmpty && !vm.isLoadingList {
                ContentUnavailableView(
                    settings.t("no_recordings_title"),
                    systemImage: "mic.slash",
                    description: Text(settings.t("no_recordings_desc"))
                )
            }
        }
    }
}
