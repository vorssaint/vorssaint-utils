// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Disk Analyzer hosted in the Utilities section of the menu panel / island.
struct PanelDiskAnalyzerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @Environment(\.notchPresentation) private var inNotch

    var onClose: () -> Void

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    private var showsResults: Bool {
        if case .ready = service.phase { return service.root != nil }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            DiskAnalyzerWorkspaceView(compact: true)
                .frame(maxHeight: inNotch && showsResults ? .infinity : nil, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Pin to the Utilities scroll viewport so the outer page does not
        // scroll; the file list keeps its own scroller underneath the map.
        .frame(height: inNotch && showsResults ? DiskAnalyzerSupport.islandResultsBodyHeight : nil,
               alignment: .top)
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
        }
        .onDisappear {
            // Island growth recreates this view; only tear down when Utilities
            // actually closed the tool.
            guard !service.isPresentedInUtilities else { return }
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            if service.phase == .scanning {
                service.cancel()
            }
        }
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
}
