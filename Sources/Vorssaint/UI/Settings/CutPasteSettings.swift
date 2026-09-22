// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct CutPasteSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = FinderCutPaste.shared
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderCutPasteShowHUD) private var showHUD = true
    @AppStorage(DefaultsKey.finderRenameEnabled) private var renameEnabled = false
    @AppStorage(DefaultsKey.finderRenameShortcut) private var renameShortcutRaw =
        GlobalShortcut.finderRenameDefault.storageValue
    @State private var renameError: String?
    @State private var recordingRename = false
    @State private var pendingRenameTakeOver: GlobalShortcut?

    private var renameText: FinderRenameFeatureStrings {
        FeatureStrings.finderRename(l10n.language)
    }

    private var renameShortcut: GlobalShortcut {
        GlobalShortcut(storageValue: renameShortcutRaw) ?? .finderRenameDefault
    }

    private var needsAccessibility: Bool {
        (AppFeature.finderCutPaste.isAvailable && enabled)
            || (AppFeature.finderRename.isAvailable && renameEnabled)
    }

    var body: some View {
        Form {
            if AppFeature.finderCutPaste.isAvailable {
                Section {
                    Toggle(l10n.s.cutPasteEnable, isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            FinderCutPaste.shared.syncWithPreferences()
                        }
                    Text(l10n.s.cutPasteEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if enabled {
                        Toggle(l10n.s.cutPasteShowHUD, isOn: $showHUD)
                            .onChange(of: showHUD) { _, _ in
                                FinderCutPaste.shared.syncWithPreferences()
                            }
                        Text(l10n.s.cutPasteShowHUDCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if enabled, service.isRunning {
                        Label(l10n.s.cutPasteActiveNow, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .settingsSectionAnchor(.finderCutPaste)

                Section(l10n.s.cutPasteHowTitle) {
                    howRow(keys: ["⌘", "X"], text: l10n.s.cutPasteStep1)
                    howRow(keys: ["⌘", "V"], text: l10n.s.cutPasteStep2)
                    Text(l10n.s.cutPasteTextNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if AppFeature.finderRename.isAvailable {
                Section {
                    Toggle(renameText.enableLabel, isOn: $renameEnabled)
                        .onChange(of: renameEnabled) { _, _ in
                            FinderRenameService.shared.syncWithPreferences()
                        }
                    Text(renameText.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(renameText.shortcutLabel)
                        Spacer()
                        ShortcutRecorderButton(
                            shortcut: pendingRenameTakeOver ?? renameShortcut,
                            isEnabled: renameEnabled,
                            waitingTitle: l10n.s.shortcutPressKeys,
                            notCapturedAction: { renameError = l10n.s.shortcutNotCaptured },
                            recordingChanged: { recording in
                                recordingRename = recording
                                if recording {
                                    renameError = nil
                                    pendingRenameTakeOver = nil
                                }
                            },
                            invalidAction: { renameError = l10n.s.shortcutInvalid },
                            captureAction: saveRenameShortcut
                        )
                        .frame(width: 108)
                        .disabled(!renameEnabled)
                        Button(l10n.s.shortcutReset) {
                            renameShortcutRaw = GlobalShortcut.finderRenameDefault.storageValue
                            renameError = nil
                            pendingRenameTakeOver = nil
                            SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, false)
                            FinderRenameService.shared.syncWithPreferences()
                        }
                        .disabled(!renameEnabled || renameShortcut == .finderRenameDefault)
                    }
                    if let renameError {
                        Text(renameError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if recordingRename {
                        Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pendingRenameTakeOver {
                        SystemShortcutTakeOverOffer(
                            shortcut: pendingRenameTakeOver,
                            onAccept: {
                                renameShortcutRaw = pendingRenameTakeOver.storageValue
                                SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, true)
                                self.pendingRenameTakeOver = nil
                                FinderRenameService.shared.syncWithPreferences()
                            },
                            onDismiss: {
                                self.pendingRenameTakeOver = nil
                                renameError = String(format: l10n.s.shortcutConflictFormat, "macOS")
                            }
                        )
                    }
                } header: {
                    Text(renameText.hubTitle)
                }
                .settingsSectionAnchor(.finderRename)
            }

            if needsAccessibility, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                    if AppFeature.finderCutPaste.isAvailable, enabled {
                        Text(l10n.s.cutPasteAutomationNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: l10n.language) { _, _ in renameError = nil }
    }

    private func howRow(keys: [String], text: String) -> some View {
        HStack(spacing: 10) {
            ShortcutCaps(keys: keys)
                .frame(width: 56, alignment: .leading)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveRenameShortcut(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: .finderRename) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut, for: .finderRename),
            takenOver: SystemShortcutTakeover.isTakenOver(DefaultsKey.finderRenameShortcut),
            current: GlobalShortcut(storageValue: renameShortcutRaw)) {
        case .offer:
            pendingRenameTakeOver = shortcut
            renameError = nil
            return
        case .save(let clearTakeOver):
            renameShortcutRaw = shortcut.storageValue
            renameError = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, false) }
        }
        FinderRenameService.shared.syncWithPreferences()
    }
}
