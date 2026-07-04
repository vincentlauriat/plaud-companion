import SwiftUI

/// Annuaire des personnes (interlocuteurs). Drill-down géré par un état local
/// (`selectedPerson`) plutôt qu'un `NavigationStack` imbriqué : dans la colonne
/// d'une `NavigationSplitView`, un `NavigationLink` pilote la sélection de colonne
/// et ne pousse pas — le drill-down explicite fonctionne sur macOS comme sur iOS.
struct PeopleListView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var vm: RecordingsViewModel
    @Binding var selectedId: String?
    @State private var selectedPerson: Person?
    @State private var search = ""

    private var people: [Person] {
        guard !search.isEmpty else { return vm.people }
        return vm.people.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        if let person = selectedPerson {
            PersonRecordingsView(
                vm: vm,
                person: person,
                selectedId: $selectedId,
                onBack: { selectedPerson = nil }
            )
        } else {
            directory
        }
    }

    private var directory: some View {
        List {
            ForEach(people) { person in
                Button {
                    selectedPerson = person
                } label: {
                    PersonRowView(person: person)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .contentShape(Rectangle())
                #endif
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: settings.t("search_people"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await vm.indexAllRecordings() }
                } label: {
                    if vm.isIndexing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.65)
                            Text("\(vm.indexDone)/\(vm.indexTotal)")
                                .font(.caption.monospacedDigit())
                        }
                    } else {
                        Label(settings.t("index_all"), systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .disabled(vm.isIndexing || vm.recordings.isEmpty)
                .help(settings.t("index_all_help"))
            }
        }
        .overlay {
            if vm.people.isEmpty {
                ContentUnavailableView(
                    settings.t("no_people_title"),
                    systemImage: "person.2.slash",
                    description: Text(settings.t("no_people_desc"))
                )
            }
        }
    }
}

private struct PersonRowView: View {
    let person: Person

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .foregroundStyle(Color.accentColor)
            Text(person.name)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(person.meetingCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 2)
    }
}
