// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Hosts one of the island's pages in the regular utility detail navigation.
/// The page's service reads for as long as the panel shows it, with or
/// without the island.
struct PanelIslandPageView: View {
    let module: NotchModule
    var onClose: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var panelFocus = MenuPanelFocus.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var readerID = UUID()

    private var isVisible: Bool { inNotch || panelFocus.popoverIsVisible }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(module.title(l10n.language), systemImage: module.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { NotchService.shared.openSettings(showing: module) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(l10n.s.menuSettings)
                .accessibilityLabel(l10n.s.menuSettings)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(l10n.s.uninstallerCancel)
                .accessibilityLabel(l10n.s.uninstallerCancel)
            }
            // The island's own page, in the panel's width and appearance.
            GeometryReader { proxy in
                page(CGSize(width: proxy.size.width, height: pageHeight))
            }
            .frame(height: pageHeight)
            // Like the preview in Settings, the panel leaves the island's state and keys alone.
            .environment(\.notchSettingsPreview, true)
        }
        .onAppear { syncReader() }
        .onChange(of: isVisible) { _, _ in syncReader() }
        .onDisappear { PanelModuleDemand.shared.setVisible(false, module, id: readerID) }
    }

    private var pageHeight: CGFloat {
        switch module {
        case .agents: return 460
        case .timer: return 200
        case .downloads, .music: return 300
        default: return 360
        }
    }

    @ViewBuilder private func page(_ size: CGSize) -> some View {
        switch module {
        case .agents: NotchAgentsView(size: size)
        case .calendar: NotchCalendarView(size: size)
        case .timer: NotchTimerView(size: size)
        case .downloads: NotchDownloadsView(size: size)
        default: EmptyView()
        }
    }

    private func syncReader() {
        PanelModuleDemand.shared.setVisible(isVisible, module, id: readerID)
        guard isVisible else { return }
        switch module {
        case .agents: AgentUsageService.shared.pageDidAppear()
        default: break
        }
    }
}
