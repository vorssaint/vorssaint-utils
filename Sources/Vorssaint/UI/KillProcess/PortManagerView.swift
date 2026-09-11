// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PortManagerView: View {
    var onClose: (() -> Void)? = nil
    @ObservedObject private var service = PortManagerService.shared
    @State private var pending: PortManagerEntry?
    @State private var force = false
    @ObservedObject private var l10n = L10n.shared

    private var strings: PortManagerFeatureStrings { FeatureStrings.portManager(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(strings.back)
                }
                Image(systemName: "network")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.title).font(.headline)
                Spacer()
                Text(String(format: strings.openFormat, service.filteredEntries.count))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help(strings.refresh)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(strings.filter, text: $service.query).textFieldStyle(.plain) }
                .padding(9).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 14).padding(.bottom, 8)
            Divider()
            if service.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash").font(.system(size: 25)).foregroundStyle(.tertiary)
                    Text(strings.empty).font(.callout).foregroundStyle(.secondary)
                    Text(strings.emptyHint).font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if onClose == nil {
                List(service.filteredEntries) { entry in
                    portRow(entry)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(service.filteredEntries) { entry in
                            portRow(entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .frame(height: 245)
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

    private func portRow(_ entry: PortManagerEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text("\(entry.port)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(entry.protocolName)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
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
                HStack(spacing: 6) {
                    Button(strings.kill) { force = false; pending = entry }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                    Button { force = true; pending = entry } label: { Image(systemName: "bolt.fill") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel(strings.forceKill)
                        .disabled(entry.startedAt == nil
                                  || KillProcessService.isProtected(pid: entry.pid, name: entry.processName))
                }
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }
}
