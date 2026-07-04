import SwiftUI

/// Réunions d'une personne (drill-down depuis `PeopleListView`). Un en-tête avec
/// bouton retour remplace la navigation par pile. Sélectionner une ligne met à
/// jour `selectedId`, ce qui déclenche l'affichage du détail dans la colonne droite.
struct PersonRecordingsView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: RecordingsViewModel
    let person: Person
    @Binding var selectedId: String?
    let onBack: () -> Void

    private var meetings: [Recording] { vm.recordings(for: person) }

    var body: some View {
        List(selection: $selectedId) {
            ForEach(meetings) { rec in
                RecordingRowView(
                    recording: rec,
                    isCached: vm.cachedIds.contains(rec.id)
                )
                .tag(rec.id)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .overlay {
            if meetings.isEmpty {
                ContentUnavailableView(
                    settings.t("no_person_recordings_title"),
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(settings.t("no_person_recordings_desc"))
                )
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Label(settings.t("back"), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer(minLength: 8)

                Image(systemName: "person.fill")
                    .foregroundStyle(Color.accentColor)
                Text(person.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}
