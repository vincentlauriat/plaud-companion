import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var vm = RecordingsViewModel()
    @State private var selectedId: String?

    var body: some View {
        NavigationSplitView {
            RecordingListView(vm: vm, selectedId: $selectedId)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
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
    }
}
