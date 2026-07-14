// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowLayoutSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = WindowLayoutService.shared
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showInPanel = true
    @AppStorage(DefaultsKey.windowLayoutShortcutsEnabled) private var shortcutsEnabled = true
    @AppStorage(DefaultsKey.windowGestureEnabled) private var gestureEnabled = false
    @AppStorage(DefaultsKey.windowGestureModifiers) private var gestureModifiers = WindowGestureSupport.defaultModifierStorageValue
    @AppStorage(DefaultsKey.windowGestureRaiseWindow) private var gestureRaiseWindow = false
    // Same preference the Switcher page exposes next to Dock Preview; it is
    // mirrored here because it is a window-juggling behavior people look for
    // on this page too.
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false

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

            Section(text.gestureSection) {
                Toggle(text.gestureEnable, isOn: $gestureEnabled)
                    .onChange(of: gestureEnabled) { _, _ in
                        WindowLayoutService.shared.syncWithPreferences()
                    }
                Text(text.gestureCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if gestureEnabled {
                    WindowGestureModifierPicker(storageValue: $gestureModifiers,
                                                title: text.gestureModifiers)
                        .onChange(of: gestureModifiers) { _, _ in
                            WindowLayoutService.shared.syncWithPreferences()
                        }
                    WindowGestureHints(modifierStorage: gestureModifiers,
                                       moveText: text.gestureMove,
                                       resizeText: text.gestureResize)
                    Text(text.gestureResizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(text.gestureRaiseWindow, isOn: $gestureRaiseWindow)
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
                if !service.failedShortcutActions.isEmpty {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle(l10n.s.dockClickCycleWindows, isOn: $dockClickCycleWindows)
                    .onChange(of: dockClickCycleWindows) { _, _ in
                        DockClickService.shared.syncWithPreferences()
                    }
                Text(l10n.s.dockClickCycleWindowsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section(text.sixths) {
                actionRow(.topLeftSixth)
                actionRow(.topCenterSixth)
                actionRow(.topRightSixth)
                actionRow(.bottomLeftSixth)
                actionRow(.bottomCenterSixth)
                actionRow(.bottomRightSixth)
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

    /// One row per action: try-it button on the left, the action's global
    /// shortcut recorder inline on the right — every action is adjustable
    /// right where it lives, no separate shortcut list to hunt for.
    private func actionRow(_ action: WindowLayoutAction) -> some View {
        WindowLayoutActionRow(action: action,
                              title: title(for: action),
                              symbol: symbol(for: action),
                              applyEnabled: permissions.accessibility,
                              shortcutEnabled: shortcutsEnabled && permissions.accessibility)
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
        case .topLeftSixth: return "arrow.up.left"
        case .topCenterSixth: return "arrow.up"
        case .topRightSixth: return "arrow.up.right"
        case .bottomLeftSixth: return "arrow.down.left"
        case .bottomCenterSixth: return "arrow.down"
        case .bottomRightSixth: return "arrow.down.right"
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

private struct WindowLayoutActionRow: View {
    @ObservedObject private var l10n = L10n.shared
    let action: WindowLayoutAction
    let title: String
    let symbol: String
    let applyEnabled: Bool
    let shortcutEnabled: Bool
    @AppStorage private var rawValue: String
    @State private var errorText: String?

    init(action: WindowLayoutAction,
         title: String,
         symbol: String,
         applyEnabled: Bool,
         shortcutEnabled: Bool) {
        self.action = action
        self.title = title
        self.symbol = symbol
        self.applyEnabled = applyEnabled
        self.shortcutEnabled = shortcutEnabled
        _rawValue = AppStorage(
            wrappedValue: action.defaultShortcut?.storageValue
                ?? WindowLayoutAction.clearedShortcutStorageValue,
            action.shortcutKey
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    WindowLayoutService.shared.apply(action)
                } label: {
                    Label(title, systemImage: symbol)
                }
                .disabled(!applyEnabled)
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut
                                           ?? action.defaultShortcut
                                           ?? .windowLayoutLeftDefault,
                                       isEnabled: shortcutEnabled,
                                       recordingTitle: l10n.s.shortcutRecording,
                                       emptyTitle: shortcut == nil ? l10n.s.shortcutNone : nil,
                                       invalidAction: { errorText = l10n.s.shortcutInvalid },
                                       captureAction: save)
                    .frame(width: 108, height: 28)
                    .disabled(!shortcutEnabled)
                Button {
                    rawValue = WindowLayoutAction.clearedShortcutStorageValue
                    errorText = nil
                    WindowLayoutService.shared.syncWithPreferences()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!shortcutEnabled || shortcut == nil)
                .help(l10n.s.shortcutClear)
                .accessibilityLabel(l10n.s.shortcutClear)
                Button(l10n.s.shortcutReset) {
                    rawValue = action.defaultShortcut?.storageValue
                        ?? WindowLayoutAction.clearedShortcutStorageValue
                    errorText = nil
                    WindowLayoutService.shared.syncWithPreferences()
                }
                .disabled(!shortcutEnabled || shortcut == action.defaultShortcut)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var shortcut: GlobalShortcut? {
        WindowLayoutAction.resolvedShortcut(storedValue: rawValue,
                                            defaultShortcut: action.defaultShortcut)
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
