import SwiftUI

// MARK: - Transcript (brute / polie)

struct TranscriptView: View {
    @Environment(AppSettings.self) private var settings
    let segments: [TranscriptSegment]

    private struct SpeakerBlock: Identifiable {
        let id = UUID()
        let speaker: String
        let segments: [TranscriptSegment]
    }

    private var speakerBlocks: [SpeakerBlock] {
        var blocks: [SpeakerBlock] = []
        var currentSpeaker: String? = nil
        var currentSegs: [TranscriptSegment] = []

        for seg in segments {
            let sp = seg.speaker ?? ""
            if sp != currentSpeaker {
                if !currentSegs.isEmpty {
                    blocks.append(SpeakerBlock(speaker: currentSpeaker ?? "", segments: currentSegs))
                }
                currentSpeaker = sp
                currentSegs = [seg]
            } else {
                currentSegs.append(seg)
            }
        }
        if !currentSegs.isEmpty {
            blocks.append(SpeakerBlock(speaker: currentSpeaker ?? "", segments: currentSegs))
        }
        return blocks
    }

    var body: some View {
        if segments.isEmpty {
            ContentUnavailableView(
                settings.t("no_transcript_title"),
                systemImage: "waveform",
                description: Text(settings.t("no_transcript_desc"))
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(speakerBlocks) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            if !block.speaker.isEmpty {
                                Text(block.speaker)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.top, 14)
                                    .padding(.horizontal, 20)
                            }

                            ForEach(Array(block.segments.enumerated()), id: \.offset) { _, seg in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(seg.timestampFormatted)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(minWidth: 38, alignment: .trailing)
                                        .padding(.top, 2)
                                    Text(seg.content ?? "")
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Plan / Outline (chapitres dépliables)

struct OutlineView: View {
    @Environment(AppSettings.self) private var settings
    let segments: [OutlineSegment]
    let transcript: [TranscriptSegment]

    @State private var expanded: Set<String> = []

    /// Segments de transcription dont le début tombe dans la plage du chapitre.
    private func transcriptFor(_ chapter: OutlineSegment) -> [TranscriptSegment] {
        let start = chapter.startTime ?? 0
        let end = chapter.endTime ?? .max
        return transcript.filter { seg in
            let t = seg.startTime ?? 0
            return t >= start && t < end
        }
    }

    var body: some View {
        if segments.isEmpty {
            ContentUnavailableView(
                settings.t("no_outline_title"),
                systemImage: "list.bullet.indent",
                description: Text(settings.t("no_outline_desc"))
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                        chapterRow(index: index, seg: seg)
                        if index < segments.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func chapterRow(index: Int, seg: OutlineSegment) -> some View {
        let isOpen = expanded.contains(seg.id)

        VStack(alignment: .leading, spacing: 0) {
            // En-tête de chapitre, cliquable
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isOpen { expanded.remove(seg.id) } else { expanded.insert(seg.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())
                        .padding(.top, 1)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(seg.topic ?? "(sans titre)")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text("\(seg.startFormatted) – \(seg.endFormatted)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Transcription du chapitre (dépliée)
            if isOpen {
                let segs = transcriptFor(seg)
                if segs.isEmpty {
                    Text(settings.t("no_transcript_for_chapter"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 54)
                        .padding(.trailing, 20)
                        .padding(.bottom, 10)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                            HStack(alignment: .top, spacing: 10) {
                                Text(s.timestampFormatted)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(minWidth: 38, alignment: .trailing)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    if let sp = s.speaker, !sp.isEmpty {
                                        Text(sp)
                                            .font(.caption2.bold())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    Text(s.content ?? "")
                                        .font(.callout)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.leading, 54)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
