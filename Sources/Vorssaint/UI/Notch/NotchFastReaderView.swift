// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The reader on the island's page. Same session as the floating window, so
/// moving between the two continues from the word on screen rather than
/// starting the selection again.
///
/// The strip is short and wide, which decides what is here: the chunk, the
/// faded neighbours and a progress line. The transport and the speed live in
/// the floating window, because a row of buttons at this height would leave
/// the word no room, and the keys reach the reader here anyway.
struct NotchFastReaderView: View {
    @ObservedObject private var session = FastReaderSession.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(DefaultsKey.fastReaderFocusPoint) private var focusPointEnabled = true

    /// Narrower than the floating window's, and for the same reason it exists
    /// there: a neighbour is context, so it gives way before the word does.
    private static let contextWidth: CGFloat = 78
    private static let readingFontSize: CGFloat = 26
    private static let contextFontSize: CGFloat = 15

    private var strings: FastReaderFeatureStrings { FeatureStrings.fastReader(l10n.language) }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            readingRow
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var readingRow: some View {
        if let chunk = session.currentChunk {
            HStack(spacing: 0) {
                contextText(previousChunkText, truncating: .head, alignment: .trailing)

                if focusPointEnabled {
                    let runs = focusRuns(for: chunk)
                    // The sides share what the focus character leaves over,
                    // equally, which centres it without a slot of its own.
                    Text(runs.before)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(runs.focus)
                        .foregroundStyle(PanelMetricColor.red(for: colorScheme))
                        .fixedSize(horizontal: true, vertical: false)
                    Text(runs.after)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(chunk.text)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                contextText(nextChunkText, truncating: .tail, alignment: .leading)
            }
            .font(.system(size: Self.readingFontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        } else {
            // Nothing read yet on this launch. Saying so beats an empty strip
            // that reads as the island having failed to draw.
            Text(strings.noSelection)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ProgressView(value: session.progress)
                .progressViewStyle(.linear)
                .tint(PanelMetricColor.cyan(for: colorScheme))
            Text(session.isFinished
                     ? strings.finishedCaption
                     : clockText(session.remainingSeconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10, design: .rounded))
        .opacity(session.chunks.isEmpty ? 0 : 1)
    }

    private func contextText(_ text: String?,
                             truncating: Text.TruncationMode,
                             alignment: Alignment) -> some View {
        Text(text ?? "")
            .font(.system(size: Self.contextFontSize, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.35))
            .truncationMode(truncating)
            .lineLimit(1)
            .frame(width: Self.contextWidth, alignment: alignment)
    }

    private var previousChunkText: String? {
        let i = session.index - 1
        guard session.chunks.indices.contains(i) else { return nil }
        return session.chunks[i].text
    }

    private var nextChunkText: String? {
        let i = session.index + 1
        guard session.chunks.indices.contains(i) else { return nil }
        return session.chunks[i].text
    }

    private func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private func focusRuns(for chunk: ReaderChunk) -> (before: String, focus: String, after: String) {
        FastReaderFocusRuns.split(chunk)
    }
}
