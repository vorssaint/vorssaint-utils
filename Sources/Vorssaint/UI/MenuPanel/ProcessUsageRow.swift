// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ProcessUsageRow: View {
    let row: ProcessUsage
    let value: String
    var iconSize: CGFloat = 15
    var leadingPadding: CGFloat = 0

    // Focus doubles as the selection: SwiftUI already keeps it exclusive within
    // the window, so no shared selection state is needed across the lists.
    @FocusState private var selected: Bool
    @ObservedObject private var l10n = L10n.shared

    private var canForceQuit: Bool { ProcessUsageService.shared.canForceQuit(row) }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(selected ? 0.18 : 0))
            )
            .focusable()
            .focusEffectDisabled()
            .focused($selected)
            .onTapGesture(count: 2) {
                selected = true
                ProcessUsageService.shared.activate(row)
            }
            .onTapGesture { selected = true }
            .onKeyPress(.return) {
                guard ProcessUsageService.shared.canActivate(row) else { return .ignored }
                ProcessUsageService.shared.activate(row)
                return .handled
            }
            .onKeyPress(.delete) {
                guard canForceQuit else { return .ignored }
                ProcessUsageService.shared.confirmForceQuit(row)
                return .handled
            }
            .contextMenu {
                // Disabled rather than absent: a blank menu reads as broken,
                // and the guard refuses every process we do not own.
                Button(FeatureStrings.killProcess(l10n.language).forceKillButton, role: .destructive) {
                    ProcessUsageService.shared.confirmForceQuit(row)
                }
                .disabled(!canForceQuit)
            }
            .help(row.name)
    }

    private var content: some View {
        HStack(spacing: 7) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            Text(row.name)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.leading, leadingPadding)
    }
}
