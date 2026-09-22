// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PortManagerView: View {
    @ObservedObject private var service = PortManagerService.shared
    @State private var pending: PortManagerEntry?
    @State private var force = false
    @ObservedObject private var l10n = L10n.shared

    private var strings: PortManagerFeatureStrings { FeatureStrings.portManager(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "network")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.title).font(.headline)
                Spacer()
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).help(strings.refresh)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(strings.filter, text: $service.query).textFieldStyle(.plain)
                if service.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(9).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 14).padding(.bottom, 8)
            Divider()
            if service.refreshFailed {
                Label(strings.loadFailed, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
            if service.filteredEntries.isEmpty {
                if service.refreshFailed {
                    Spacer()
                } else if service.hasLoadedOnce {
                    emptyState
                } else {
                    loadingState
                }
            } else {
                List(service.filteredEntries) { entry in
                    portRow(entry)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service.refresh() }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash").font(.system(size: 25)).foregroundStyle(.tertiary)
            Text(strings.empty).font(.callout).foregroundStyle(.secondary)
            Text(strings.emptyHint).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(entry.protocolName)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                Text(entry.processName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text("PID \(entry.pid)  •  \(entry.address)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if AppFeature.killProcess.isAvailable {
                HStack(spacing: 4) {
                    Button(strings.kill) { force = false; pending = entry }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                    Button { force = true; pending = entry } label: { Image(systemName: "bolt.fill") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel(strings.forceKill)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                }
            }
        }
        .padding(.vertical, 3)
    }
}
