import SwiftUI

struct RecordingRowView: View {
    @Environment(AppSettings.self) private var settings
    let recording: Recording
    let isCached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recording.displayName)
                .font(.body)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Text(recording.dateFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !recording.durationFormatted.isEmpty {
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(recording.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help(settings.t("cached_help"))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
