import SwiftUI

struct SpeakerStat: Identifiable {
    let id = UUID()
    let name: String
    let totalMs: Int
    let interventions: Int

    var formattedDuration: String {
        let s = totalMs / 1000
        let m = s / 60, sec = s % 60
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

struct InterlocutorsView: View {
    @Environment(AppSettings.self) private var settings
    let segments: [TranscriptSegment]

    private var stats: [SpeakerStat] {
        var dict: [String: (ms: Int, count: Int)] = [:]
        for seg in segments {
            let sp = seg.speaker ?? "Inconnu"
            let dur = max(0, (seg.endTime ?? seg.startTime ?? 0) - (seg.startTime ?? 0))
            dict[sp, default: (0, 0)].ms += dur
            dict[sp, default: (0, 0)].count += 1
        }
        return dict
            .map { SpeakerStat(name: $0.key, totalMs: $0.value.ms, interventions: $0.value.count) }
            .sorted { $0.totalMs > $1.totalMs }
    }

    private var totalMs: Int { stats.reduce(0) { $0 + $1.totalMs } }

    var body: some View {
        if segments.isEmpty {
            ContentUnavailableView(
                settings.t("no_speakers_title"),
                systemImage: "person.2",
                description: Text(settings.t("no_speakers_desc"))
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(settings.count(stats.count, "unit_speaker_one", "unit_speaker_many"))
                        .font(.headline)
                        .padding(.bottom, 4)

                    ForEach(stats) { stat in
                        SpeakerCard(stat: stat, total: totalMs)
                    }
                }
                .padding()
            }
        }
    }
}

private struct SpeakerCard: View {
    @Environment(AppSettings.self) private var settings
    let stat: SpeakerStat
    let total: Int

    private var ratio: Double {
        total > 0 ? Double(stat.totalMs) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.accentColor)
                Text(stat.name)
                    .font(.body.bold())
                Spacer()
                Text(stat.formattedDuration)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * ratio, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.0f%%", ratio * 100))
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(settings.count(stat.interventions, "unit_intervention_one", "unit_intervention_many"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
