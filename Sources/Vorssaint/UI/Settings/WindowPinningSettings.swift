// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowPinningSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var pinning = WindowPinningService.shared
    @AppStorage(DefaultsKey.windowPinningEnabled) private var enabled = false
    @AppStorage(DefaultsKey.windowPinningShortcut) private var shortcutRaw =
        GlobalShortcut.windowPinningDefault.storageValue
    @AppStorage(DefaultsKey.windowPinningShowOnAllSpaces) private var showOnAllSpaces = false
    @State private var shortcutError: String?
    @State private var recordingShortcut = false
    @State private var pendingShortcutTakeOver: GlobalShortcut?

    private var text: WindowPinningStrings { FeatureStrings.windowPinning(l10n.language) }

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: shortcutRaw) ?? .windowPinningDefault
    }

    var body: some View {
        Form {
            if AppFeature.windowPinning.isAvailable {
                Section {
                    Toggle(text.enableToggle, isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            WindowPinningService.shared.syncWithPreferences()
                        }
                    Text(text.enableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if enabled && !pinning.pinningAvailable {
                        Label(text.unsupportedTitle, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Text(text.unsupportedCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if enabled {
                        shortcutRow
                        Toggle(text.allSpacesToggle, isOn: $showOnAllSpaces)
                            .onChange(of: showOnAllSpaces) { _, _ in
                                WindowPinningOverlayManager.shared.syncSpacesPreference()
                            }
                        Text(text.allSpacesCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(text.pinNowButton) {
                            WindowPinningService.shared.toggleFocusedWindow(source: .menu)
                        }
                        Button(text.unpinAllButton) {
                            WindowPinningService.shared.unpinAll()
                        }
                        .disabled(pinning.pinnedCount == 0)
                        Text(pinnedCountText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(text.pageTitle)
                }
            }
            if enabled, AppFeature.windowPinning.isAvailable,
               !permissions.accessibility || !permissions.screenRecording {
                Section(text.permissionRowTitle) {
                    if !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                    if !permissions.screenRecording {
                        PermissionRow(kind: .screenRecording)
                    }
                    Text(text.permissionRowCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: l10n.language) { _, _ in shortcutError = nil }
    }

    private var pinnedCountText: String {
        pinning.pinnedCount == 0
            ? text.pinnedNone
            : String(format: text.pinnedCountFormat, pinning.pinnedCount)
    }

    private var shortcutRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(text.shortcutSection)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: pendingShortcutTakeOver ?? shortcut,
                    isEnabled: enabled,
                    waitingTitle: l10n.s.shortcutPressKeys,
                    notCapturedAction: { shortcutError = l10n.s.shortcutNotCaptured },
                    recordingChanged: { recording in
                        recordingShortcut = recording
                        if recording {
                            shortcutError = nil
                            pendingShortcutTakeOver = nil
                        }
                    },
                    invalidAction: { shortcutError = l10n.s.shortcutInvalid },
                    captureAction: saveShortcut
                )
                .frame(width: 108)
                .disabled(!enabled)
                Button(l10n.s.shortcutReset) {
                    shortcutRaw = GlobalShortcut.windowPinningDefault.storageValue
                    shortcutError = nil
                    pendingShortcutTakeOver = nil
                    SystemShortcutTakeover.setTakeOver(DefaultsKey.windowPinningShortcut, false)
                    WindowPinningService.shared.syncWithPreferences()
                }
                .disabled(!enabled || shortcut == .windowPinningDefault)
            }
            Text(text.shortcutCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let shortcutError {
                Text(shortcutError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if recordingShortcut {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pendingShortcutTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingShortcutTakeOver,
                    onAccept: {
                        shortcutRaw = pendingShortcutTakeOver.storageValue
                        SystemShortcutTakeover.setTakeOver(DefaultsKey.windowPinningShortcut, true)
                        self.pendingShortcutTakeOver = nil
                        WindowPinningService.shared.syncWithPreferences()
                    },
                    onDismiss: {
                        self.pendingShortcutTakeOver = nil
                        shortcutError = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
    }

    private func saveShortcut(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            shortcutError = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            shortcutError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(DefaultsKey.windowPinningShortcut),
            current: GlobalShortcut(storageValue: shortcutRaw)) {
        case .offer:
            pendingShortcutTakeOver = shortcut
            shortcutError = nil
            return
        case .save(let clearTakeOver):
            shortcutRaw = shortcut.storageValue
            shortcutError = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(DefaultsKey.windowPinningShortcut, false) }
        }
        WindowPinningService.shared.syncWithPreferences()
    }
}
