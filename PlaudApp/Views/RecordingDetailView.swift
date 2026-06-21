import SwiftUI

struct RecordingDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: RecordingsViewModel
    @State private var selectedTab = 0
    @State private var transcriptType = 0  // 0=Brute, 1=Polie, 2=Plan

    var recording: Recording? { vm.selectedRecording }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let rec = recording {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.displayName)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Label(rec.dateFormatted, systemImage: "calendar")
                        if !rec.durationFormatted.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Label(rec.durationFormatted, systemImage: "clock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider()

            // Tab bar
            Picker("", selection: $selectedTab) {
                Text(settings.t("tab_summary")).tag(0)
                Text(settings.t("tab_notes")).tag(1)
                Text(settings.t("tab_transcription")).tag(2)
                Text(settings.t("tab_speakers")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Content
            ZStack {
                if vm.isLoadingDetail && (selectedTab == 0 || selectedTab == 1) {
                    ProgressView(settings.t("loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case 0:
                        NotesView(notes: vm.notes, summaryOnly: true)
                    case 1:
                        NotesView(notes: vm.notes, summaryOnly: false)
                    case 2:
                        transcriptTab
                    case 3:
                        InterlocutorsView(segments: vm.transcriptSegments)
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedTab) { _, tab in
            switch tab {
            case 2: Task { await vm.loadTranscript() }
            case 3: Task { await vm.loadTranscript() }
            default: break
            }
        }
        .onChange(of: transcriptType) { _, type in
            if type == 1 { Task { await vm.loadPolishedTranscript() } }
            else if type == 0 { Task { await vm.loadTranscript() } }
        }
        .onChange(of: vm.selectedRecording?.id) { _, _ in
            selectedTab = 0
            transcriptType = 0
        }
    }

    @ViewBuilder
    private var transcriptTab: some View {
        VStack(spacing: 0) {
            // Sous-picker de type de transcription
            Picker("", selection: $transcriptType) {
                Text(settings.t("tr_raw")).tag(0)
                Text(settings.t("tr_polished")).tag(1)
                Text(settings.t("tr_outline")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            ZStack {
                if vm.isLoadingDetail && transcriptType != 1 {
                    ProgressView(settings.t("loading_transcript"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isLoadingPolished && transcriptType == 1 {
                    ProgressView(settings.t("loading_polished"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch transcriptType {
                    case 0:
                        TranscriptView(segments: vm.transcriptSegments)
                    case 1:
                        TranscriptView(segments: vm.polishedSegments)
                    case 2:
                        OutlineView(segments: vm.outlineSegments, transcript: vm.transcriptSegments)
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
