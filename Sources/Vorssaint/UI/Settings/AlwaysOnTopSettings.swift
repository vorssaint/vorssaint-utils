// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Always On Top page: the switch, the pin shortcut, how a pin is
/// revealed and the apps that are never pinned.
struct AlwaysOnTopSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AlwaysOnTopService.shared
    @AppStorage(DefaultsKey.alwaysOnTopEnabled) private var enabled = false
    @AppStorage(DefaultsKey.alwaysOnTopReveal) private var reveal = AlwaysOnTopReveal.click.rawValue
    @AppStorage(DefaultsKey.alwaysOnTopBorder) private var border = AlwaysOnTopBorder.medium.rawValue
    @AppStorage(DefaultsKey.alwaysOnTopBorderColor) private var borderColor = ""

    private var text: AlwaysOnTopStrings { FeatureStrings.alwaysOnTop(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(text.title).font(.title2.bold())
                    Text(text.hubDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                pinCard
                if enabled {
                    SettingsCard {
                        AlwaysOnTopExcludedAppsList()
                    }
                }
                if enabled, !permissions.accessibility {
                    SettingsCard(title: l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
                if enabled, !permissions.screenRecording {
                    SettingsCard {
                        PermissionRow(kind: .screenRecording)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
    }

    private var pinCard: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.alwaysOnTop.symbolName, title: text.enable, caption: text.enableCaption) {
                Toggle(text.enable, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, isOn in
                        service.syncWithPreferences()
                        if isOn { requestMissingPermissions() }
                    }
            }
            if enabled {
                ShortcutPreferenceRow(role: .alwaysOnTop,
                                      isEnabled: enabled,
                                      additionalConflict: {
                                          WindowLayoutService.shared.shortcutConflictTitle($0)
                                      }) {
                    service.syncWithPreferences()
                }
                if service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SettingsChoiceRow(symbol: "cursorarrow.click", title: text.reveal, selection: $reveal) {
                        Text(text.revealClick).tag(AlwaysOnTopReveal.click.rawValue)
                        Text(text.revealHover).tag(AlwaysOnTopReveal.hover.rawValue)
                    }
                    Text(text.revealCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                SettingsChoiceRow(symbol: "square.dashed", title: text.border, selection: $border) {
                    Text(text.borderNone).tag(AlwaysOnTopBorder.none.rawValue)
                    Text(text.borderThin).tag(AlwaysOnTopBorder.thin.rawValue)
                    Text(text.borderMedium).tag(AlwaysOnTopBorder.medium.rawValue)
                    Text(text.borderThick).tag(AlwaysOnTopBorder.thick.rawValue)
                }
                .onChange(of: border) { _, _ in service.syncWithPreferences() }
                if border != AlwaysOnTopBorder.none.rawValue {
                    SettingsRow(symbol: "paintpalette", title: text.borderColor) {
                        HStack(spacing: 8) {
                            if AlwaysOnTopBorder.colorHex(borderColor) != nil {
                                Button(text.borderColorAccent) { borderColor = "" }
                            }
                            ColorPicker(text.borderColor, selection: borderColorBinding, supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                    .onChange(of: borderColor) { _, _ in service.syncWithPreferences() }
                }
                Label(text.indicatorNote, systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shows the accent colour until a colour is picked.
    private var borderColorBinding: Binding<Color> {
        Binding {
            guard let hex = AlwaysOnTopBorder.colorHex(borderColor) else { return Color.accentColor }
            let rgb = MenuBarUsageBarSupport.rgb(for: hex, fallback: hex)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { color in
            guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
            borderColor = MenuBarUsageBarSupport.hex(red: Double(converted.redComponent),
                                                     green: Double(converted.greenComponent),
                                                     blue: Double(converted.blueComponent))
        }
    }

    /// Turning the feature on asks for what pinning needs, through the same
    /// prompts and guide every other feature uses.
    private func requestMissingPermissions() {
        if !permissions.accessibility {
            permissions.requestAccessibility()
        } else if !permissions.screenRecording {
            permissions.requestScreenRecording()
        }
    }
}

struct AlwaysOnTopExcludedAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var excluded = AlwaysOnTopExcludedApps.shared

    private var text: AlwaysOnTopStrings { FeatureStrings.alwaysOnTop(l10n.language) }

    var body: some View {
        AppBundleList(title: text.excludedList,
                      caption: text.excludedCaption,
                      addTitle: text.addApp,
                      removeLabel: text.removeApp,
                      bundleIDs: excluded.apps,
                      reachesEveryApp: true,
                      acceptsExecutables: true,
                      onAdd: {
                          excluded.add($0)
                          AlwaysOnTopService.shared.syncWithPreferences()
                      },
                      onRemove: {
                          excluded.remove($0)
                          AlwaysOnTopService.shared.syncWithPreferences()
                      })
    }
}
