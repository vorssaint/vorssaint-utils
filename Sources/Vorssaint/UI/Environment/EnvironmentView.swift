// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct EnvironmentView: View {
    @ObservedObject private var service = EnvironmentService.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: EnvironmentFeatureStrings { FeatureStrings.environment(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "terminal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.title).font(.headline)
                Spacer()
                if service.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button(strings.copyReport) {
                    guard let report = service.report else { return }
                    let text = EnvironmentSupport.reportText(report)
                    GeneralPasteboardAccess.shared.async({
                        NSPasteboard.general.clearContents()
                        return NSPasteboard.general.setString(text, forType: .string)
                    }, then: { copied in
                        if !copied { NSSound.beep() }
                    })
                }
                .controlSize(.small)
                .disabled(service.report == nil || service.isRefreshing)
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).help(FeatureStrings.portManager(l10n.language).refresh)
                .disabled(service.isRefreshing)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            Divider()
            if let report = service.report {
                Form {
                    pathSection(report)
                    commandsSection(report)
                }
                .formStyle(.grouped)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service.refresh() }
        .onDisappear { service.cancel() }
    }

    private func pathSection(_ report: EnvironmentReport) -> some View {
        let terminalOnly = Set(report.terminalOnlyPath)
        return Section {
            if !report.readLoginShell {
                Label(strings.shellUnavailable, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.terminal).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(report.terminalPath, id: \.self) { entry in
                    HStack(spacing: 6) {
                        Text(entry)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(terminalOnly.contains(entry) ? Color.orange : Color.primary)
                            .textSelection(.enabled)
                        if terminalOnly.contains(entry) {
                            Text(strings.terminalOnly)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4).padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.apps).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(report.appPath, id: \.self) { entry in
                    Text(entry)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Text(terminalOnly.isEmpty ? strings.noDifference : strings.pathNote)
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(strings.pathTitle)
        }
    }

    private func commandsSection(_ report: EnvironmentReport) -> some View {
        Section {
            ForEach(report.tools) { tool in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tool.command).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Spacer(minLength: 4)
                        Text(tool.path == nil ? strings.notFound : tool.version ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Group {
                        if let path = tool.path { Text(path) }
                        if let shim = tool.shimTarget {
                            Text(String(format: strings.runsFormat, shim)).foregroundStyle(.secondary)
                        }
                        ForEach(tool.shadowedPaths, id: \.self) { shadowed in
                            Text("\(strings.shadowed): \(shadowed)").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            Text(strings.commandsNote).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(strings.commandsTitle)
        }
    }
}
