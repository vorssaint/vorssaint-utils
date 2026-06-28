// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowLayoutSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = WindowLayoutService.shared
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showInPanel = true
    @AppStorage(DefaultsKey.windowLayoutShortcutsEnabled) private var shortcutsEnabled = true

    private var text: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.showInPanel, isOn: $showInPanel)
                Text(text.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(text.permissionCaption, systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }

            Section(text.shortcuts) {
                Toggle(text.shortcuts, isOn: $shortcutsEnabled)
                    .onChange(of: shortcutsEnabled) { _, _ in
                        WindowLayoutService.shared.syncWithPreferences()
                    }
                Text(text.shortcutsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(WindowLayoutAction.shortcutActions) { action in
                    WindowLayoutShortcutRow(action: action,
                                            isEnabled: shortcutsEnabled && permissions.accessibility)
                }
                if !service.failedShortcutActions.isEmpty {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section(text.halves) {
                actionRow(.leftHalf)
                actionRow(.rightHalf)
                actionRow(.topHalf)
                actionRow(.bottomHalf)
            }

            Section(text.thirds) {
                actionRow(.leftThird)
                actionRow(.centerThird)
                actionRow(.rightThird)
                actionRow(.leftTwoThirds)
                actionRow(.rightTwoThirds)
            }

            Section(text.corners) {
                actionRow(.topLeft)
                actionRow(.topRight)
                actionRow(.bottomLeft)
                actionRow(.bottomRight)
            }

            Section(text.other) {
                actionRow(.maximize)
                actionRow(.center)
                actionRow(.nextDisplay)
                actionRow(.restore)
                if let message = resultMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(resultColor)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func actionRow(_ action: WindowLayoutAction) -> some View {
        Button {
            service.apply(action)
        } label: {
            Label(title(for: action), systemImage: symbol(for: action))
        }
        .disabled(!permissions.accessibility)
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
}

private struct WindowLayoutShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    let action: WindowLayoutAction
    let isEnabled: Bool
    @AppStorage private var rawValue: String
    @State private var errorText: String?

    init(action: WindowLayoutAction, isEnabled: Bool) {
        self.action = action
        self.isEnabled = isEnabled
        _rawValue = AppStorage(wrappedValue: action.defaultShortcut.storageValue, action.shortcutKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(action.title(FeatureStrings.windowLayout(l10n.language)))
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut,
                                       isEnabled: isEnabled,
                                       recordingTitle: l10n.s.shortcutRecording,
                                       invalidAction: { errorText = l10n.s.shortcutInvalid },
                                       captureAction: save)
                    .frame(width: 108, height: 28)
                    .disabled(!isEnabled)
                Button(l10n.s.shortcutReset) {
                    rawValue = action.defaultShortcut.storageValue
                    errorText = nil
                    WindowLayoutService.shared.syncWithPreferences()
                }
                .disabled(!isEnabled || shortcut == action.defaultShortcut)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: rawValue) ?? action.defaultShortcut
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.allCases.first(where: { $0.savedShortcut == shortcut }) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: action) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        rawValue = shortcut.storageValue
        errorText = nil
        WindowLayoutService.shared.syncWithPreferences()
    }
}
