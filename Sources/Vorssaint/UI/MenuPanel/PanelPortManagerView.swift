// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelPortManagerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = PortManagerService.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var pending: PortManagerEntry?
    @State private var force = false

    var onClose: () -> Void

    private var strings: PortManagerFeatureStrings { FeatureStrings.portManager(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            if service.refreshFailed {
                Label(strings.loadFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelCard()
            }
            entriesList
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.refresh()
        }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(pending.map { String(format: strings.terminateFormat, $0.processName) } ?? "",
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(l10n.s.uninstallerCancel, role: .cancel) { pending = nil }
            Button(force ? strings.forceKill : strings.kill, role: .destructive) {
                if let pending { service.terminate(pending, force: force) }
                pending = nil
            }
        } message: {
            Text(String(format: strings.terminateMessageFormat,
                        pending?.port ?? 0, pending?.pid ?? 0))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: "network")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .portManager
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
                Text(strings.listeningCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: strings.openFormat, service.filteredEntries.count))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField(strings.filter, text: $service.query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(strings.refresh)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var entriesList: some View {
        if service.filteredEntries.isEmpty {
            if service.refreshFailed {
                EmptyView()
            } else if service.hasLoadedOnce {
                emptyState
            } else {
                loadingState
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(service.filteredEntries) { entry in
                        portRow(entry)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "network.slash")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text(strings.empty)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(strings.emptyHint)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
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

    private func portRow(_ entry: PortManagerEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("\(entry.port)")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    Text(entry.protocolName)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    if PortManagerSupport.listensOnAllInterfaces(entry.address) {
                        PortManagerAllInterfacesBadge(strings: strings, fontSize: 8.5, showsLabel: false)
                    }
                }
                Text(entry.processName)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                Text("PID \(entry.pid)  •  \(entry.address)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if AppFeature.killProcess.isAvailable {
                HStack(spacing: 4) {
                    Button(strings.kill) { confirmTermination(entry, force: false) }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                    Button { confirmTermination(entry, force: true) } label: { Image(systemName: "bolt.fill") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel(strings.forceKill)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .contextMenu {
            PortManagerRowActions(entry: entry, language: l10n.language)
        }
    }

    /// The alert would hang from the island as a sheet; there it asks on its own.
    private func confirmTermination(_ entry: PortManagerEntry, force: Bool) {
        guard inNotch else {
            self.force = force
            pending = entry
            return
        }
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(String(format: strings.terminateFormat, entry.processName),
                                             message: String(format: strings.terminateMessageFormat, entry.port, entry.pid),
                                             action: force ? strings.forceKill : strings.kill, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            service.terminate(entry, force: force)
        }
    }
}
