// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact quarantine manager flow for the menu panel. Reuses
/// QuarantineManagerService so scanning and removal rules stay identical to
/// the larger Settings page.
struct PanelQuarantineManagerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var manager = QuarantineManagerService.shared
    @State private var dropTargeted = false
    @State private var detailEntry: QuarantineManagerService.Entry?

    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            manager.scan(paths: urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
        .sheet(item: $detailEntry) { entry in
            QuarantineDetailView(entry: entry) { detailEntry = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .empty: emptyState
        case .scanning: busyState(l10n.s.quarantineManagerScanning)
        case .results: resultsState
        case .removing: busyState(l10n.s.quarantineManagerRemoving)
        case let .done(cleared, failed): doneState(cleared: cleared, failed: failed)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.quarantineManagerName, systemImage: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Button {
                manager.scanApplications()
            } label: {
                Label(l10n.s.quarantineManagerScanApplications, systemImage: "square.grid.2x2")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            dropZone

            Button {
                manager.browseForTargets()
            } label: {
                Label(l10n.s.quarantineManagerPick, systemImage: "plus.app")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: true)
            }
        }
        .panelCard()
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .frame(height: 96)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                    Text(l10n.s.quarantineManagerIntroTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
            )
            .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private func busyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .panelCard()
    }

    private var resultsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            resultsHeader
            Divider()
            entryList
            Divider()
            footer
        }
        .panelCard()
    }

    private var resultsHeader: some View {
        HStack(spacing: 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.s.quarantineManagerFoundTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                    if manager.totalFound > manager.entries.count {
                        Text("\(manager.entries.count) / \(manager.totalFound)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Button { manager.refreshScan() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button { manager.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(manager.entries) { entry in row(entry) }
        }
    }

    private func row(_ entry: QuarantineManagerService.Entry) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: selectionBinding(entry.id))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.relativePath)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Button {
                detailEntry = entry
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 24)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: l10n.s.quarantineManagerSelectedFormat,
                            manager.selection.count, manager.entries.count))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            HStack {
                Button(l10n.s.quarantineManagerClearSelection) { manager.selectNone() }
                    .controlSize(.small)
                    .disabled(manager.selection.isEmpty)
                Spacer()
                Button {
                    manager.removeQuarantineFromSelected()
                } label: {
                    Label(l10n.s.quarantineManagerRemoveSelected, systemImage: "shield.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(manager.selection.isEmpty)
            }
        }
    }

    private func doneState(cleared: Int, failed: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text(l10n.s.quarantineManagerDoneTitle)
                .font(.system(size: 14, weight: .bold))
            Text(String(format: l10n.s.quarantineManagerClearedFormat, cleared))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if failed > 0 {
                Text(l10n.s.quarantineManagerSomeFailed)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(l10n.s.quarantineManagerContinue) {
                manager.continueAfterDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .panelCard()
    }

    private func selectionBinding(_ id: QuarantineManagerService.Entry.ID) -> Binding<Bool> {
        Binding(
            get: { manager.selection.contains(id) },
            set: { _ in manager.toggle(id) }
        )
    }
}
