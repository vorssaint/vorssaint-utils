// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The installed browsers in the panel; a click makes one the default.
struct PanelDefaultBrowserView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DefaultBrowserService.shared

    var onClose: () -> Void

    private var strings: DefaultBrowserFeatureStrings { FeatureStrings.defaultBrowser(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(spacing: 2) {
                if service.browsers.isEmpty {
                    Text(strings.empty)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(service.browsers) { browser in
                    row(browser)
                }
            }
            .panelCard()
            Text(service.failure ?? strings.confirmNote)
                .font(.system(size: 10.5))
                .foregroundStyle(service.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
        }
        // The macOS confirmation takes focus; the panel stays behind it.
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.reload()
        }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: "globe")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .defaultBrowser
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

    private func row(_ browser: DefaultBrowserSupport.Browser) -> some View {
        let isCurrent = service.isCurrent(browser)
        return Button {
            service.makeDefault(browser)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path))
                    .resizable().frame(width: 18, height: 18)
                Text(browser.name).font(.system(size: 12))
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || service.changing)
    }
}
