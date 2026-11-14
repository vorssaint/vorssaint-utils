// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FnLockSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var fnLock = FnLockService.shared
    @ObservedObject private var exceptions = MouseAppExceptions.shared
    @AppStorage(DefaultsKey.fnLockEnabled) private var enabled = false

    private var text: FnLockStrings { FeatureStrings.fnLock(l10n.language) }
    private var exceptionText: MouseExceptionStrings { FeatureStrings.mouseExceptions(l10n.language) }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        FnLockService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, fnLock.isRunning, fnLock.engagesFrontmostApp {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if enabled, fnLock.isRunning {
                    Label(text.pausedNote, systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // The list carries its own flip-specific title, unlike the mouse
            // features' shared "apps to leave alone" wording: an entry here is
            // the feature's whole subject, not an exception to it.
            if enabled {
                AppBundleList(
                    title: text.appsTitle,
                    caption: text.appsCaption,
                    addTitle: exceptionText.addButton,
                    removeLabel: exceptionText.removeButton,
                    bundleIDs: exceptions.list(.fnLock),
                    reachesEveryApp: true,
                    acceptsExecutables: true,
                    onAdd: { exceptions.add($0, to: .fnLock) },
                    onRemove: { exceptions.remove($0, from: .fnLock) })
            }

            Section(text.testSection) {
                if fnLock.recentTranslations.isEmpty {
                    Text(text.testEmpty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fnLock.recentTranslations) { record in
                        HStack(spacing: 8) {
                            Image(systemName: record.isKeyDown
                                  ? "arrow.down.circle.fill"
                                  : "arrow.up.circle")
                                .foregroundStyle(record.isKeyDown ? Color.primary : Color.secondary)
                            Text(FnLockSupport.displayName(for: record.source))
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(FnLockSupport.displayName(for: record.target))
                                .fontWeight(.medium)
                            Spacer()
                            Text(record.at, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(text.testClear) {
                        FnLockService.shared.clearTranslationLog()
                    }
                }
            }
            .disabled(!enabled)

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { FnLockService.shared.syncWithPreferences() }
    }
}
