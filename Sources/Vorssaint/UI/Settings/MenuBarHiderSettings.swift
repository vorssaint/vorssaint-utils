// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MenuBarHiderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarHiderService.shared

    @AppStorage(DefaultsKey.menuBarHiderEnabled) private var enabled = true
    @AppStorage(DefaultsKey.menuBarHiderAlwaysHiddenEnabled) private var alwaysHiddenEnabled = false
    @AppStorage(DefaultsKey.menuBarHiderAutoCollapse) private var autoCollapse = false
    @AppStorage(DefaultsKey.menuBarHiderAutoCollapseDelay) private var autoCollapseDelay = MenuBarHiderSupport.defaultAutoCollapseDelay
    @AppStorage(DefaultsKey.menuBarHiderExpandOnHover) private var expandOnHover = false
    @AppStorage(DefaultsKey.menuBarHiderScrollToToggle) private var scrollToToggle = true
    @AppStorage(DefaultsKey.menuBarHiderHapticFeedback) private var hapticFeedback = true
    @AppStorage(DefaultsKey.menuBarHiderIconStyle) private var iconStyleRaw = MenuBarHiderIconStyle.chevron.rawValue
    @AppStorage(DefaultsKey.menuBarHiderShortcutEnabled) private var shortcutEnabled = false

    @State private var didResetPositions = false

    private var text: MenuBarHiderStrings { FeatureStrings.menuBarHider(l10n.language) }

    private var iconStyle: Binding<MenuBarHiderIconStyle> {
        Binding(
            get: { MenuBarHiderIconStyle(rawValue: iconStyleRaw) ?? .chevron },
            set: {
                iconStyleRaw = $0.rawValue
                MenuBarHiderService.shared.syncWithPreferences()
            }
        )
    }

    var body: some View {
        Form {
            Section(text.pageTitle) {
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

                guideDiagram
            }

            Section(text.howToUseTitle) {
                VStack(alignment: .leading, spacing: 8) {
                    guideStep(number: "1", text: text.howToUseStep1)
                    guideStep(number: "2", text: text.howToUseStep2)
                    guideStep(number: "3", text: text.howToUseStep3)
                }
                .padding(.vertical, 4)

                Button(action: triggerResetPositions) {
                    HStack(spacing: 6) {
                        Image(systemName: didResetPositions ? "checkmark.circle.fill" : "arrow.counterclockwise")
                            .foregroundStyle(didResetPositions ? .green : .accentColor)
                        Text(didResetPositions ? text.resetPositionsSuccess : text.resetPositionsButton)
                    }
                }
                .disabled(!enabled)

                Text(text.resetPositionsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(text.iconStyleTitle) {
                Picker(text.iconStyleTitle, selection: iconStyle) {
                    Label(text.styleChevron, systemImage: "chevron.right").tag(MenuBarHiderIconStyle.chevron)
                    Label(text.styleDots, systemImage: "ellipsis.circle").tag(MenuBarHiderIconStyle.dots)
                    Label(text.styleEye, systemImage: "eye").tag(MenuBarHiderIconStyle.eye)
                    Label(text.styleSlash, systemImage: "line.diagonal").tag(MenuBarHiderIconStyle.slash)
                }
                .pickerStyle(.menu)
            }
            .disabled(!enabled)

            Section(text.alwaysHiddenSection) {
                Toggle(text.alwaysHiddenEnable, isOn: $alwaysHiddenEnabled)
                    .onChange(of: alwaysHiddenEnabled) { _, isNowAlwaysHidden in
                        MenuBarHiderService.shared.syncWithPreferences()
                        if isNowAlwaysHidden {
                            MenuBarHiderService.shared.showAll(startTimer: false)
                        }
                    }
                Text(text.alwaysHiddenCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section(text.autoCollapseSection) {
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

            Section(text.interactionSection) {
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

            Section(text.shortcutSection) {
                Toggle(text.shortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        MenuBarHiderService.shared.syncWithPreferences()
                    }

                ShortcutPreferenceRow(role: .menuBarHider, isEnabled: shortcutEnabled && enabled) {
                    MenuBarHiderService.shared.syncWithPreferences()
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .onAppear {
            if enabled {
                MenuBarHiderService.shared.beginConfigurationMode()
            }
        }
        .onDisappear {
            MenuBarHiderService.shared.endConfigurationMode()
        }
    }

    private func triggerResetPositions() {
        MenuBarHiderService.shared.resetSeparatorPositions()
        withAnimation {
            didResetPositions = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                didResetPositions = false
            }
        }
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var guideDiagram: some View {
        HStack(spacing: 8) {
            if alwaysHiddenEnabled {
                diagramBlock(title: "Always Hidden", icon: "lock.slash", color: .purple)
                Text("‖")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            diagramBlock(title: "Hidden Icons", icon: "eye.slash", color: .orange)
            Text("|")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(4)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            diagramBlock(title: "Visible", icon: "eye", color: .green)
        }
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .animation(.easeInOut(duration: 0.2), value: alwaysHiddenEnabled)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func diagramBlock(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .foregroundStyle(color)
    }
}

