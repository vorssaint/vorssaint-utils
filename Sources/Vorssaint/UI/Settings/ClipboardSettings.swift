// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.pastePlainEnabled) private var pastePlainEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryLimit) private var limit = 50
    @AppStorage(DefaultsKey.clipboardHistorySkipSensitive) private var skipSensitive = true
    @AppStorage(DefaultsKey.clipboardHistoryIncludeImagesFiles) private var includeImagesFiles = true
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showInPanel = true

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    var body: some View {
        Form {
            if AppFeature.clipboardHistory.isAvailable {
                Section {
                    Toggle(text.enable, isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            ClipboardHistoryService.shared.syncWithPreferences()
                        }
                    Text(text.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text.localNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if enabled, history.isRunning {
                        Label(text.active, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Toggle(text.includeImagesFiles, isOn: $includeImagesFiles)
                    Text(text.includeImagesFilesCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(text.skipSensitive, isOn: $skipSensitive)
                    Text(text.skipSensitiveCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(text.limit, selection: $limit) {
                        ForEach(Defaults.allowedClipboardHistoryLimits, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Toggle(text.showInPanel, isOn: $showInPanel)
                }
            }

            if AppFeature.pastePlain.isAvailable {
                Section {
                    Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                        .onChange(of: pastePlainEnabled) { _, _ in
                            PastePlainService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.pastePlainCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShortcutPreferenceRow(role: .pastePlain,
                                          isEnabled: pastePlainEnabled) {
                        PastePlainService.shared.syncWithPreferences()
                    }
                    if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if pastePlainEnabled, !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                } header: {
                    Text(l10n.s.pastePlainName)
                }
            }

            if AppFeature.clipboardHistory.isAvailable {
                clipboardShortcutAndStatsSections
            }
        }
        .formStyle(.grouped)
        .onAppear {
            limit = Defaults.sanitizedClipboardHistoryLimit(limit)
        }
        .onChange(of: limit) { _, value in
            limit = Defaults.sanitizedClipboardHistoryLimit(value)
        }
    }

    @ViewBuilder
    private var clipboardShortcutAndStatsSections: some View {
            Section(text.shortcut) {
                Toggle(text.shortcut, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ClipboardHistoryService.shared.syncHotkey()
                    }
                ShortcutPreferenceRow(role: .clipboard,
                                      isEnabled: enabled && shortcutEnabled,
                                      additionalConflict: WindowLayoutService.shared.shortcutConflictTitle) {
                    ClipboardHistoryService.shared.syncHotkey()
                }
                if enabled, shortcutEnabled, history.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(text.shortcutCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    ClipboardHistoryService.shared.showHistoryWindow()
                } label: {
                    Label(text.shortcut, systemImage: "doc.on.clipboard")
                }
                .disabled(history.entries.isEmpty)
            }

            Section {
                HStack {
                    Text("\(history.pinnedEntries.count)")
                    Text(text.pinned)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(history.recentEntries.count)")
                    Text(text.recent)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(text.clearRecent) {
                        history.clearRecent()
                    }
                    .disabled(history.recentEntries.isEmpty)
                    Button(text.clearAll) {
                        history.clearAll()
                    }
                    .disabled(history.recentEntries.isEmpty)
                }
            }
    }
}
