// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelWindowLayoutView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = WindowLayoutService.shared
    @AppStorage(DefaultsKey.windowLayoutShortcutsEnabled) private var shortcutsEnabled = true

    var onClose: () -> Void

    private var text: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            intro
            actionGroup(title: text.halves, actions: [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
            actionGroup(title: text.thirds, actions: [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
            actionGroup(title: text.corners, actions: [.topLeft, .topRight, .bottomLeft, .bottomRight])
            actionGroup(title: text.other, actions: [.maximize, .center, .nextDisplay, .restore])
            if let message = resultMessage {
                Label(message, systemImage: resultSymbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(resultColor)
                    .panelCard()
            }
        }
        .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(text.shortcuts, isOn: $shortcutsEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 10.5, weight: .medium))
                .onChange(of: shortcutsEnabled) { _, _ in
                    WindowLayoutService.shared.syncWithPreferences()
                }
            if shortcutsEnabled {
                Text(text.shortcutsCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !permissions.accessibility {
                Button {
                    Permissions.shared.requestAccessibility()
                    Permissions.shared.openAccessibilitySettings()
                } label: {
                    Label(text.missingPermission, systemImage: "hand.raised.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .panelCard()
    }

    private func actionGroup(title groupTitle: String, actions: [WindowLayoutAction]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(groupTitle.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.tertiary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                ForEach(actions) { action in
                    Button {
                        service.apply(action)
                    } label: {
                        VStack(spacing: 2) {
                            Label(title(for: action), systemImage: symbol(for: action))
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            if shortcutsEnabled, action.supportsShortcut {
                                Text(action.savedShortcut.displayString)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!permissions.accessibility)
                }
            }
        }
        .panelCard()
    }

    private func title(for action: WindowLayoutAction) -> String {
        action.title(text)
    }

    private func symbol(for action: WindowLayoutAction) -> String {
        switch action {
        case .leftHalf: return "rectangle.leftthird.inset.filled"
        case .rightHalf: return "rectangle.rightthird.inset.filled"
        case .topHalf: return "rectangle.topthird.inset.filled"
        case .bottomHalf: return "rectangle.bottomthird.inset.filled"
        case .leftThird: return "rectangle.leftthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .rightThird: return "rectangle.rightthird.inset.filled"
        case .leftTwoThirds: return "rectangle.leadinghalf.filled"
        case .rightTwoThirds: return "rectangle.trailinghalf.filled"
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "scope"
        case .nextDisplay: return "arrow.right.to.line"
        case .restore: return "arrow.uturn.backward"
        }
    }

    private var resultMessage: String? {
        switch service.lastResult {
        case .success(let restored): return restored ? text.restored : text.done
        case .failure(.missingAccessibility): return text.missingPermission
        case .failure(.noWindow): return text.noWindow
        case .failure(.noRestore): return text.noRestore
        case .failure(.failed): return text.failed
        case nil: return nil
        }
    }

    private var resultColor: Color {
        switch service.lastResult {
        case .success: return .green
        case .failure: return .orange
        case nil: return .secondary
        }
    }

    private var resultSymbol: String {
        switch service.lastResult {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case nil: return "info.circle"
        }
    }
}
