// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The app update list, shared by the Settings page and the menu bar panel so
/// both look and behave the same. `compact` shrinks it for the panel.
struct AppUpdatesListView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = AppUpdatesService.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @AppStorage(DefaultsKey.appUpdatesIncludeOnlineCatalog)
    private var includeOnlineCatalog = true
    @State private var showOperationDetails = false
    var compact = false

    private var text: AppUpdateStrings { FeatureStrings.appUpdates(l10n.language) }
    private var isBusy: Bool { updates.isChecking || homebrew.operation != nil }
    private var onlineCoverageIncomplete: Bool {
        includeOnlineCatalog
            && updates.hasCheckedThisSession
            && !updates.isChecking
            && !updates.onlineCatalogAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            summaryRow
            if updates.items.isEmpty {
                emptyState
            } else {
                if updates.selectableCount > 0 { selectionBar }
                list
                if updates.selectableCount > 0 { updateButton }
            }
            if onlineCoverageIncomplete {
                onlineFailure
            }
            if let status = homebrew.operationStatus {
                HomebrewOperationStatusView(status: status,
                                            log: homebrew.log,
                                            terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                            compact: compact,
                                            showDetails: $showOperationDetails,
                                            onCancel: homebrew.cancelOperation,
                                            onClear: homebrew.clearLog,
                                            onOpenTerminal: homebrew.openTerminalFallback)
                    .padding(compact ? 0 : 4)
            }
            if let error = updates.lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // No title here: both hosts already name the tool right above,
            // and repeating it made the card read like a second window.
            Text(lastCheckLine)
                .font(.system(size: compact ? 10.5 : 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                updates.check()
            } label: {
                if updates.isChecking {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(text.checking)
                    }
                    .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                } else {
                    Label(text.checkNow, systemImage: "arrow.clockwise")
                        .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
        }
    }

    private var lastCheckLine: String {
        guard let last = updates.lastCheck else { return text.neverChecked }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        // Named style so a check that just ran reads "now" instead of the
        // literal "in 0 seconds".
        formatter.dateTimeStyle = .named
        return String(format: text.lastCheckFormat,
                      formatter.localizedString(for: last, relativeTo: Date()))
    }

    // MARK: - States

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if updates.hasCheckedThisSession, !updates.isChecking, !onlineCoverageIncomplete {
                Label(text.upToDate, systemImage: "checkmark.circle.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.green)
            }
            Text(text.coverageNote)
                .font(.system(size: compact ? 9.5 : 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if updates.hasCheckedThisSession, !updates.packageManagerAvailable {
                Text(text.packageMissing)
                    .font(.system(size: compact ? 9.5 : 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onlineFailure: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(text.incompleteCheck, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                .foregroundStyle(.orange)
            Text(text.onlineUnavailable)
                .font(.system(size: compact ? 9.5 : 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Selection

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(text.selectAll) { updates.selectAll() }
                .disabled(updates.selectedCount == updates.selectableCount)
            Button(text.clearSelection) { updates.selectNone() }
                .disabled(updates.selectedCount == 0)
            Spacer(minLength: 0)
        }
        .buttonStyle(.link)
        .font(.system(size: compact ? 10 : 11))
    }

    @ViewBuilder
    private var list: some View {
        let rows = LazyVStack(alignment: .leading, spacing: Self.compactRowSpacing) {
            ForEach(updates.items) { item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            // Height lands on whole rows, so the list never ends with half a
            // row peeking out of the panel.
            ScrollView { rows }
                .frame(height: Self.compactHeight(rowCount: updates.items.count))
        } else {
            rows
        }
    }

    private static let compactRowHeight: CGFloat = 40
    private static let compactRowSpacing: CGFloat = 5
    private static let compactVisibleRows = 4

    static func compactHeight(rowCount: Int) -> CGFloat {
        let visible = min(max(rowCount, 1), compactVisibleRows)
        return CGFloat(visible) * compactRowHeight
            + CGFloat(visible - 1) * compactRowSpacing
    }

    private func row(_ item: AppUpdatesSupport.Item) -> some View {
        HStack(spacing: 9) {
            if item.isSelectable {
                Toggle(isOn: Binding(get: { updates.selection.contains(item.id) },
                                     set: { _ in updates.toggle(item) })) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel(item.name)
            } else {
                Color.clear
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }

            Image(nsImage: icon(for: item))
                .resizable()
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.name)
                        .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sourceBadge(for: item))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                Text(item.versionSummary)
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            Button {
                updates.update(item)
            } label: {
                Text(actionTitle(for: item))
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
            .help(actionHint(for: item))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(height: compact ? Self.compactRowHeight : nil)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func icon(for item: AppUpdatesSupport.Item) -> NSImage {
        guard let path = item.bundlePath, FileManager.default.fileExists(atPath: path) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func sourceBadge(for item: AppUpdatesSupport.Item) -> String {
        switch item.source {
        case .packageManager: return text.homebrewBadge
        case .appStore: return text.appStoreBadge
        case .onlineCatalog: return text.onlineBadge
        }
    }

    private func actionTitle(for item: AppUpdatesSupport.Item) -> String {
        switch item.source {
        case .packageManager: return text.updateOne
        case .appStore: return text.appStoreBadge
        case .onlineCatalog: return text.openApp
        }
    }

    private func actionHint(for item: AppUpdatesSupport.Item) -> String {
        switch item.source {
        case .packageManager: return text.updateOne
        case .appStore: return text.storeHint
        case .onlineCatalog: return text.openAppHint
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private var updateButton: some View {
        HStack(spacing: 8) {
            Button {
                updates.updateSelected()
            } label: {
                Text(String(format: text.updateSelectedFormat, updates.selectedCount))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .frame(maxWidth: compact ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .small : .regular)
            .disabled(updates.selectedCount == 0 || isBusy)
            if !compact {
                Spacer(minLength: 0)
            }
        }
    }
}
