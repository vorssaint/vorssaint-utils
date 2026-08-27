// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SelectionActionBarView: View {
    let actions: [SelectionAction]
    let displayStyle: SelectionActionsDisplayStyle
    let strings: SelectionActionsStrings
    let maxVisible: Int
    let onSelect: (SelectionAction) -> Void
    let hoverChanged: (Bool) -> Void

    @State private var showingOverflow = false
    @State private var isHoveringBar = false

    private var visibleActions: [SelectionAction] {
        Array(actions.prefix(Swift.max(1, maxVisible)))
    }

    private var overflowActions: [SelectionAction] {
        actions.count > maxVisible ? Array(actions.dropFirst(Swift.max(1, maxVisible))) : []
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visibleActions) { action in
                actionButton(action)
            }
            if !overflowActions.isEmpty {
                overflowButton
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        // SwiftUI still tries to put a focus ring on the first button even
        // though the panel never takes key status; nothing here is
        // keyboard-navigated, so there is nothing for a focus ring to mean.
        .focusEffectDisabled()
        // Opening the overflow popover naturally moves the pointer off this
        // row's own bounds (the popover sits below it), which would fire
        // `onHover(false)` and resume the dismiss timer out from under
        // someone whose cursor is sitting right on the popover. Combining
        // both signals keeps the timer paused as long as either is true.
        .onHover { isHoveringBar = $0; updateHoverState() }
        .onChange(of: showingOverflow) { _, _ in updateHoverState() }
    }

    private func updateHoverState() {
        hoverChanged(isHoveringBar || showingOverflow)
    }

    private func actionButton(_ action: SelectionAction) -> some View {
        Button {
            onSelect(action)
        } label: {
            label(for: action)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help(strings.title(for: action))
    }

    private var overflowButton: some View {
        Button {
            showingOverflow = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .popover(isPresented: $showingOverflow, arrowEdge: .bottom) {
            overflowGrid
        }
    }

    /// The rest of the actions, in the same icon/word row style as the bar
    /// itself — wrapped into rows of `maxVisible` instead of one long native
    /// menu list, so it reads as more of the same bar rather than a
    /// different control.
    private var overflowGrid: some View {
        VStack(spacing: 2) {
            ForEach(Array(rowsOfOverflow.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.element) { index, action in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(width: 1, height: 18)
                        }
                        Button {
                            showingOverflow = false
                            onSelect(action)
                        } label: {
                            label(for: action)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                        .help(strings.title(for: action))
                    }
                }
            }
        }
        .padding(6)
        .focusEffectDisabled()
    }

    private var rowsOfOverflow: [[SelectionAction]] {
        let width = Swift.max(1, maxVisible)
        return stride(from: 0, to: overflowActions.count, by: width).map {
            Array(overflowActions[$0..<Swift.min($0 + width, overflowActions.count)])
        }
    }

    @ViewBuilder
    private func label(for action: SelectionAction) -> some View {
        switch displayStyle {
        case .icon:
            Image(systemName: action.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
        case .word:
            Text(strings.title(for: action))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 26)
        }
    }
}
