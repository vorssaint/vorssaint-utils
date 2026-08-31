// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelRecentCapturesView: View {
    var onClose: () -> Void

    var body: some View {
        RecentCapturesView(onClose: onClose, keyboardSection: .utilities)
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
        }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}

/// Local ids for the per-capture rows, in the one place they are spelled —
/// see `MediaWorkspaceView` for the same arrangement.
private enum RecentCaptureKeyboardID {
    static func open(_ entry: RecentCaptureEntry) -> String { "recentCapture-\(entry.id)-open" }
    static func remove(_ entry: RecentCaptureEntry) -> String { "recentCapture-\(entry.id)-remove" }
}

/// The same history surface is used by the menu panel and by the floating
/// palette opened from editors and the Command Bar.
struct RecentCapturesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = RecentCaptureService.shared
    @ObservedObject private var navigator = PanelKeyboardNavigator.shared
    @State private var confirmingClear = false

    var onClose: (() -> Void)?
    /// Non-nil only when hosted in the panel; see `KeepAwakeIconPicker`.
    var keyboardSection: PanelSectionID? = nil

    private var text: RecentCaptureStrings {
        FeatureStrings.recentCaptures(l10n.language)
    }

    private var visibleEntries: [RecentCaptureEntry] {
        history.entries.filter { entry in
            entry.kind == .screenshot
                ? AppFeature.screenshot.isAvailable
                : AppFeature.screenRecorder.isAvailable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .onAppear { history.reload() }
        .onChange(of: confirmingClear) { _, confirming in
            PanelInteractionState.shared.isPresentingPopoverModal = confirming
        }
        .onDisappear {
            PanelInteractionState.shared.isPresentingPopoverModal = false
        }
        .confirmationDialog(text.clear,
                            isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(text.clear, role: .destructive) {
                history.clear()
            }
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                confirmingClear = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(text.clear)
            .accessibilityLabel(text.clear)
            .disabled(visibleEntries.isEmpty)
            .panelKeyboardRow(visibleEntries.isEmpty ? nil : keyboardSection.map { PanelRowID($0, "recentCaptures-clear") },
                              actions: PanelRowActions(activate: { confirmingClear = true }))
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(l10n.s.uninstallerCancel)
                .accessibilityLabel(l10n.s.uninstallerCancel)
                .panelKeyboardRow(keyboardSection.map { PanelRowID($0, "recentCaptures-close") },
                                  actions: PanelRowActions(activate: onClose))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibleEntries.isEmpty {
            Text(text.empty)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .panelCard()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(visibleEntries) { entry in
                            row(entry).id(entry.id)
                        }
                    }
                    .panelKeyboardRowList(visibleEntries.flatMap(keyboardRows))
                }
                .onChange(of: navigator.focus) { _, focus in
                    guard let entryID = focusedEntryID(focus) else { return }
                    proxy.scrollTo(entryID, anchor: .center)
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func row(_ entry: RecentCaptureEntry) -> some View {
        HStack(spacing: 10) {
            preview(entry)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.kind == .screenshot ? text.screenshot : text.recording)
                    .font(.system(size: 11.5, weight: .semibold))
                if entry.kind == .recording, let name = entry.recordingURL?.lastPathComponent {
                    Text(name)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(entry.createdAt, style: .relative)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Button(entry.kind == .screenshot ? text.restore : text.open) {
                        history.open(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .panelKeyboardRow(keyboardRow(RecentCaptureKeyboardID.open(entry)),
                                      actions: PanelRowActions(activate: { history.open(entry) }), cornerRadius: 6)
                    Button {
                        history.remove(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(text.remove)
                    .accessibilityLabel(text.remove)
                    .panelKeyboardRow(keyboardRow(RecentCaptureKeyboardID.remove(entry)),
                                      actions: PanelRowActions(activate: { history.remove(entry) }), cornerRadius: 6)
                }
            }
            Spacer(minLength: 0)
        }
        .panelCard()
    }

    private func keyboardRow(_ localID: String) -> PanelRowID? {
        keyboardSection.map { PanelRowID($0, localID) }
    }

    /// What one capture contributes to the keyboard order, in the order the
    /// two buttons sit in the row.
    private func keyboardRows(for entry: RecentCaptureEntry) -> [PanelRowID] {
        [RecentCaptureKeyboardID.open(entry), RecentCaptureKeyboardID.remove(entry)]
            .compactMap(keyboardRow)
    }

    private func focusedEntryID(_ focus: PanelFocusTarget?) -> RecentCaptureEntry.ID? {
        guard case .row(let row)? = focus, row.section == keyboardSection else { return nil }
        return visibleEntries.first { keyboardRows(for: $0).contains(row) }?.id
    }

    @ViewBuilder
    private func preview(_ entry: RecentCaptureEntry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.13))
            if let image = history.thumbnail(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: entry.kind == .screenshot ? "photo" : "film")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 104, height: 68)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Borderless palette content. Its compact fixed width keeps the same list
/// readable over either editor without covering the work area.
struct RecentCapturesWindowView: View {
    var onClose: () -> Void

    var body: some View {
        RecentCapturesView(onClose: onClose)
            .padding(14)
            .frame(width: 440)
            .background(HUDBackdrop(cornerRadius: 18, contrast: .high))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
