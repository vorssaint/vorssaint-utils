// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct AlwaysOnTopSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AlwaysOnTopService.shared
    @AppStorage(DefaultsKey.alwaysOnTopEnabled) private var enabled = false
    @AppStorage(DefaultsKey.alwaysOnTopShowBorder) private var showBorder = true
    @AppStorage(DefaultsKey.alwaysOnTopBorderColor) private var borderColor = "#00ADEF"
    @AppStorage(DefaultsKey.alwaysOnTopBorderThickness) private var borderThickness = 4.0
    @AppStorage(DefaultsKey.alwaysOnTopPlaySound) private var playSound = true
    @State private var showingAppPicker = false

    private var strings: AlwaysOnTopFeatureStrings {
        FeatureStrings.alwaysOnTop(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(strings.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        AlwaysOnTopService.shared.syncWithPreferences()
                    }
                Text(strings.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(strings.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                ShortcutPreferenceRow(
                    role: .alwaysOnTop,
                    isEnabled: enabled,
                    label: strings.shortcut,
                    onChange: {
                        AlwaysOnTopService.shared.syncWithPreferences()
                    }
                )
                .disabled(!enabled)
            }

            Section {
                Toggle(strings.showBorder, isOn: $showBorder)
                    .disabled(!enabled)
                if showBorder {
                    ColorPicker(strings.borderColor, selection: colorBinding, supportsOpacity: false)
                        .disabled(!enabled)
                    Stepper(value: $borderThickness, in: 1...12, step: 1) {
                        Text("\(strings.borderThickness): \(Int(borderThickness))")
                    }
                    .disabled(!enabled)
                }
            }

            Section {
                Toggle(strings.playSound, isOn: $playSound)
                    .disabled(!enabled)
            }

            Section(strings.excludeTitle) {
                if service.exceptions.isEmpty {
                    Text(strings.excludeEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.exceptions, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            Button {
                                service.removeException(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .disabled(!enabled)
                }

                Button {
                    showingAppPicker = true
                } label: {
                    Label(strings.addApp, systemImage: "plus")
                }
                .disabled(!enabled)

                Text(strings.excludeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !service.pinningAvailable {
                Section {
                    Text(strings.pinningUnavailable)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if enabled, !permissions.accessibility {
                Section(strings.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var colorBinding: Binding<Color> {
        Binding {
            let rgb = MenuBarUsageBarSupport.rgb(for: borderColor, fallback: "#00ADEF")
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { color in
            guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
            borderColor = MenuBarUsageBarSupport.hex(red: Double(converted.redComponent),
                                                     green: Double(converted.greenComponent),
                                                     blue: Double(converted.blueComponent))
        }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.exceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            service.addException(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }
}
