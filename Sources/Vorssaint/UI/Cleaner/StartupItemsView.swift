// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Cleaner's startup tab: the launch agents that start with your Mac, with
/// a switch for the ones in your own Library.
struct StartupItemsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var manager = StartupItemsManager.shared

    private var mine: [StartupItemsManager.Item] { manager.items.filter(\.isUserAgent) }
    private var shared: [StartupItemsManager.Item] { manager.items.filter { !$0.isUserAgent } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.s.startupIntro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(l10n.s.startupRefresh) { manager.refresh() }
                    .disabled(manager.isLoading)
            }
            .padding(16)
            if let failed = manager.lastFailure {
                Label("\(l10n.s.startupFailed): \(failed)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider()
            if manager.items.isEmpty && !manager.isLoading {
                Text(l10n.s.startupNone).foregroundStyle(.secondary).padding(40)
            } else {
                List {
                    if !mine.isEmpty {
                        Section(l10n.s.startupYours) { ForEach(mine) { row($0) } }
                    }
                    if !shared.isEmpty {
                        Section(l10n.s.startupShared) { ForEach(shared) { row($0) } }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { manager.refresh() }
    }

    private func row(_ item: StartupItemsManager.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { manager.setEnabled($0, for: item) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!item.canToggle || manager.isLoading)
            Image(nsImage: icon(for: item))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Label(statusText(item.status), systemImage: statusIcon(item.status))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(item.status == .leftover ? Color.orange : Color.secondary)
                    .lineLimit(1)
                Text(item.program)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if item.isUserAgent && !item.canToggle {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .help(l10n.s.startupLocked)
                    .accessibilityLabel(l10n.s.startupLocked)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)
            .accessibilityLabel(l10n.s.cleanerRevealInFinder)
        }
        .padding(.vertical, 2)
        .help(detailsHelp(item))
    }

    private func statusText(_ status: StartupItemSupport.Status) -> String {
        switch status {
        case .leftover: return l10n.s.startupLeftover
        case .atLogin: return l10n.s.startupAtLogin
        case .onDemand: return l10n.s.startupOnDemand
        }
    }

    private func statusIcon(_ status: StartupItemSupport.Status) -> String {
        switch status {
        case .leftover: return "questionmark.app"
        case .atLogin: return "power"
        case .onDemand: return "clock"
        }
    }

    /// The owning app's icon when there is one, else the program's own icon.
    private func icon(for item: StartupItemsManager.Item) -> NSImage {
        let path = StartupItemSupport.owningApp(ofProgram: item.program)?.path ?? item.program
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// The technical details kept out of the row, shown when hovering over it.
    private func detailsHelp(_ item: StartupItemsManager.Item) -> String {
        var lines = [item.displayName, item.label, item.program, statusText(item.status)]
        if let added = item.added {
            lines.append(String(format: l10n.s.largeFilesAddedFormat,
                                added.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
