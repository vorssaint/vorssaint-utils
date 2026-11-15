// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact Disk Analyzer entry for the utilities section. Opens the workspace
/// window where scanning and cleanup happen.
struct PanelDiskAnalyzerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared

    var onClose: () -> Void

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            status
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.pageTitle, systemImage: "square.grid.3x3.fill")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .diskAnalyzer
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
            Text(strings.panelCaption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Button {
                service.showWindow()
                onClose()
            } label: {
                Label(strings.openWindow, systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            if !permissions.fullDiskAccess {
                Label(strings.fullDiskNote, systemImage: "externaldrive.badge.person.crop")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var status: some View {
        switch service.phase {
        case .scanning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(format: strings.scanningFormat,
                            DiskAnalyzerSupport.formatBytes(service.progress.bytes),
                            service.progress.files))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .panelCard()
        case .ready:
            if let root = service.root {
                HStack {
                    Text(root.name.isEmpty ? root.path : root.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(DiskAnalyzerSupport.formatBytes(root.size))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .panelCard()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .panelCard()
        case .idle:
            EmptyView()
        }
    }
}
