// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelRecentCapturesView: View {
    var onClose: () -> Void

    var body: some View {
        RecentCapturesView(onClose: onClose)
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
        }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}

/// The same history surface is used by the menu panel and by the floating
/// palette opened from editors and the Command Bar.
struct RecentCapturesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = RecentCaptureService.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var confirmingClear = false

    var onClose: (() -> Void)?
    /// Inside the island the list becomes a rail of cards that fill this
    /// area and continue sideways.
    var notchSize: CGSize? = nil

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
            if notchSize == nil { header }
            content
        }
        .onAppear { history.reload() }
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
                if inNotch { confirmClearAboveIsland() } else { confirmingClear = true }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(text.clear)
            .accessibilityLabel(text.clear)
            .disabled(visibleEntries.isEmpty)
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
            }
        }
    }

    /// The dialog would hang from the island as a sheet; there it asks on its own.
    private func confirmClearAboveIsland() {
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(text.clear, message: "", action: text.clear, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            history.clear()
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
                .frame(height: notchSize == nil ? 92 : nil)
                .frame(maxHeight: notchSize == nil ? nil : .infinity)
                .panelCard()
        } else if let notchSize {
            let rows = NotchLayout.railRows(count: visibleEntries.count,
                                            perRow: NotchLayout.railCapacity(width: notchSize.width, itemWidth: 236, spacing: 8),
                                            rowHeight: 88, spacing: 8, height: notchSize.height)
            let cardHeight = (notchSize.height - CGFloat(rows - 1) * 8) / CGFloat(rows)
            NotchRail(items: visibleEntries, rows: rows, itemWidth: 236, width: notchSize.width) { entry in
                row(entry).frame(height: cardHeight)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(visibleEntries) { entry in
                        row(entry)
                    }
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
                }
            }
            Spacer(minLength: 0)
        }
        .panelCard()
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
