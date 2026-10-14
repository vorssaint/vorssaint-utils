// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct MenuBarHiderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarHiderService.shared

    @AppStorage(DefaultsKey.menuBarHiderEnabled) private var enabled = false
    @AppStorage(DefaultsKey.menuBarHiderAutoCollapse) private var autoCollapse = false
    @AppStorage(DefaultsKey.menuBarHiderAutoCollapseDelay) private var autoCollapseDelay = MenuBarHiderSupport.defaultAutoCollapseDelay
    @AppStorage(DefaultsKey.menuBarHiderExpandOnHover) private var expandOnHover = false
    @AppStorage(DefaultsKey.menuBarHiderScrollToToggle) private var scrollToToggle = true
    @AppStorage(DefaultsKey.menuBarHiderHapticFeedback) private var hapticFeedback = true
    @AppStorage(DefaultsKey.menuBarHiderShortcutEnabled) private var shortcutEnabled = false

    @State private var pageIsVisible = false

    private var text: MenuBarHiderStrings { FeatureStrings.menuBarHider(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(text.pageTitle).font(.title2.bold())
                SettingsCard(title: text.pageTitle) {
                    Toggle(text.enable, isOn: $enabled)
                        .onChange(of: enabled) { _, isNowEnabled in
                            MenuBarHiderService.shared.syncWithPreferences()
                            if isNowEnabled {
                                MenuBarHiderService.shared.beginConfigurationMode()
                            }
                        }
                    Text(text.enableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }
                MenuBarOrganizerEditor()

                SettingsCard(title: text.autoCollapseSection) {
                    Toggle(text.autoCollapseEnable, isOn: $autoCollapse)
                        .onChange(of: autoCollapse) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }

                    if autoCollapse {
                        Picker(text.autoCollapseDelay, selection: $autoCollapseDelay) {
                            ForEach(MenuBarHiderSupport.allowedAutoCollapseDelays, id: \.self) { seconds in
                                Text(String(format: text.secondsFormat, seconds)).tag(seconds)
                            }
                        }
                        .onChange(of: autoCollapseDelay) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }
                    }
                }
                .disabled(!enabled)

                SettingsCard(title: text.interactionSection) {
                    Toggle(text.expandOnHover, isOn: $expandOnHover)
                        .onChange(of: expandOnHover) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }
                    Text(text.expandOnHoverCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(text.scrollToToggle, isOn: $scrollToToggle)
                        .onChange(of: scrollToToggle) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }
                    Text(text.scrollToToggleCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(text.hapticFeedback, isOn: $hapticFeedback)
                        .onChange(of: hapticFeedback) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }
                    Text(text.hapticFeedbackCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enabled)

                SettingsCard(title: text.shortcutSection) {
                    Toggle(text.shortcutToggle, isOn: $shortcutEnabled)
                        .onChange(of: shortcutEnabled) { _, _ in
                            MenuBarHiderService.shared.syncWithPreferences()
                        }

                    ShortcutPreferenceRow(role: .menuBarHider, isEnabled: shortcutEnabled && enabled) {
                        MenuBarHiderService.shared.syncWithPreferences()
                    }
                    if let conflict = service.shortcutConflict {
                        Text(String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s)))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if service.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(!enabled)
                MenuBarOrganizerOptions()
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .onAppear {
            pageIsVisible = true
            if enabled {
                MenuBarHiderService.shared.beginConfigurationMode()
            }
        }
        .onDisappear {
            pageIsVisible = false
            MenuBarHiderService.shared.endConfigurationMode()
        }
        // The retained page does not disappear when Settings closes. Its
        // own window visibility is already tracked centrally by the app.
        .onReceive(SettingsWindowVisibility.shared.$isVisible) { visible in
            guard pageIsVisible else { return }
            if visible && enabled {
                MenuBarHiderService.shared.beginConfigurationMode()
            } else {
                MenuBarHiderService.shared.endConfigurationMode()
            }
        }
    }

}
