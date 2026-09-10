// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ProcessUsageRow: View {
    let row: ProcessUsage
    let value: String
    var iconSize: CGFloat = 15
    var leadingPadding: CGFloat = 0
    /// Non-nil wires this row into keyboard navigation. Left nil where the
    /// list isn't otherwise part of a keyboard-navigable section.
    var keyboardRow: PanelRowID? = nil

    var body: some View {
        // Every row is a keyboard stop so the arrows move one visible row at
        // a time. A process with no app to bring forward (kernel_task,
        // WindowServer...) still takes focus; it just has nothing for Return
        // to do, so the navigator hands that key back.
        let canActivate = ProcessUsageService.shared.canActivate(row)
        Group {
            if canActivate {
                Button {
                    ProcessUsageService.shared.activate(row)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .panelKeyboardRow(keyboardRow, actions: PanelRowActions(
            activate: canActivate ? { ProcessUsageService.shared.activate(row) } : nil))
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
