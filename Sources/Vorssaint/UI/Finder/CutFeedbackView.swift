// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Floating HUD that shows which files are held for a move (after ⌘X) and then
/// confirms the move (after ⌘V). Lives in a borderless panel managed by
/// `FinderCutPaste`.
struct CutFeedbackView: View {
    @EnvironmentObject private var service: FinderCutPaste
    @ObservedObject private var l10n = L10n.shared

    private let maxRows = 5

    var body: some View {
        Group {
            if let result = service.lastResult {
                resultBody(result)
            } else {
                markedBody
            }
        }
        .padding(14)
        .frame(width: 286)
        .background(HUDBackdrop(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: service.marked)
        .animation(.easeOut(duration: 0.18), value: service.lastResult)
    }

    // MARK: Marked for move

    private var markedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(l10n.s.cutReadyTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(service.marked.count)")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Button {
                    service.cancelPendingCut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(l10n.s.cutCancel)
                .accessibilityLabel(l10n.s.cutCancel)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(service.marked.prefix(maxRows)) { item in
                    HStack(spacing: 7) {
                        Image(nsImage: item.icon)
                            .resizable().frame(width: 17, height: 17)
                        Text(item.name)
                            .font(.system(size: 12))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if service.marked.count > maxRows {
                    Text("+\(service.marked.count - maxRows)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }

            HStack(spacing: 6) {
                ShortcutCaps(keys: ["⌘", "V"])
                Text(l10n.s.cutReadyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 1)
        }
    }

    // MARK: Move confirmed

    private func resultBody(_ result: FinderCutPaste.MoveResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(result.failed == 0 ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.s.cutDoneTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(movedText(result.moved))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if result.failed > 0 {
                    Text(l10n.s.cutSomeFailed)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func movedText(_ count: Int) -> String {
        count == 1 ? l10n.s.cutMovedSingular : String(format: l10n.s.cutMovedPluralFormat, count)
    }
}
