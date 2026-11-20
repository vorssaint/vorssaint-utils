// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Kill Process, compact enough for the menu panel: a searchable list of
/// running processes with kill and force-kill actions. Reuses
/// `KillProcessService` so the protected-process guard and confirmation
/// behaviour stay in the one place, identical to the Settings page and the
/// Command Bar rows.
struct PanelKillProcessView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = KillProcessService.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var pending: KillProcessEntry?
    @State private var force = false

    var onClose: () -> Void

    private var strings: KillProcessFeatureStrings { FeatureStrings.killProcess(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            entriesList
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.refresh()
        }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(alertTitle,
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(l10n.s.uninstallerCancel, role: .cancel) { pending = nil }
            Button(force ? strings.forceKillButton : strings.killButton, role: .destructive) {
                if let pending { service.kill(pending, force: force) }
                pending = nil
            }
        } message: {
            Text(pending?.path ?? "")
        }
    }

    private var alertTitle: String {
        guard let pending else { return "" }
        return String(format: force ? strings.confirmForceKillFormat : strings.confirmKillFormat,
                      pending.name)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.pageTitle, systemImage: "xmark.octagon")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .killProcess
                appDelegate()?.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(format: strings.processCountFormat, service.filteredEntries.count))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if service.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            HStack(spacing: 6) {
                TextField(strings.searchPlaceholder, text: $service.query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button {
                    service.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(strings.refreshTooltip)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var entriesList: some View {
        if service.filteredEntries.isEmpty {
            if service.hasLoadedOnce {
                emptyState
            } else {
                loadingState
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(service.filteredEntries) { entry in
                        processRow(entry)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text(strings.emptyStateTitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .panelCard()
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .panelCard()
    }

    private func processRow(_ entry: KillProcessEntry) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: ResponsibleProcess.icon(for: entry.pid))
                .resizable()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: strings.pidLabelFormat, entry.pid))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Button(strings.killButton) { confirmTermination(entry, force: false) }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .disabled(entry.isProtected)
                Button { confirmTermination(entry, force: true) } label: { Image(systemName: "bolt.fill") }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .accessibilityLabel(strings.forceKillButton)
                    .disabled(entry.isProtected)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    /// The alert would hang from the island as a sheet; there it asks on its own.
    private func confirmTermination(_ entry: KillProcessEntry, force: Bool) {
        guard inNotch else {
            self.force = force
            pending = entry
            return
        }
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(String(format: force ? strings.confirmForceKillFormat : strings.confirmKillFormat,
                                                    entry.name),
                                             message: entry.path,
                                             action: force ? strings.forceKillButton : strings.killButton, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            service.kill(entry, force: force)
        }
    }
}
