// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// App-wide startup and appearance settings.
struct GeneralSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var appearance = AppAppearanceController.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var launchAtLogin = UserDefaults.standard.bool(
        forKey: DefaultsKey.launchAtLoginWanted)
    @State private var loginError: String?
    @State private var loginRefreshID = UUID()
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }
    private var appearanceStrings: AppearanceStrings { FeatureStrings.appearance(l10n.language) }
    private var feedbackStrings: FeedbackStrings { FeatureStrings.feedback(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.s.tabGeneral).font(.title2.bold())
                basicsCard
                appearanceCard
                if AppFeature.keepAwake.isAvailable {
                    shortcutCard
                }
                feedbackCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .onAppear { refreshLaunchAtLogin() }
    }

    private var basicsCard: some View {
        SettingsCard {
            SettingsRow(symbol: "laptopcomputer", title: l10n.s.launchAtLogin,
                        caption: text.launchAtLoginCaption) {
                Toggle(l10n.s.launchAtLogin, isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            SettingsRow(symbol: "globe", title: l10n.s.languageLabel) {
                Picker(l10n.s.languageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: appearanceStrings.label) {
            HStack(spacing: 10) {
                ForEach(AppAppearance.allCases) { option in
                    AppearanceChoice(option: option,
                                     title: option.title(appearanceStrings),
                                     selected: appearance.appearance == option) {
                        appearance.appearance = option
                    }
                }
            }
            Text(text.appearanceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Divider()
                SettingsRow(symbol: "sparkles", title: appearanceStrings.liquidGlass,
                            caption: text.liquidGlassCaption) { EmptyView() }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(text.liquidGlassOtherWindows, isOn: $appearance.liquidGlassEnabled)
                        .accessibilityLabel("\(appearanceStrings.liquidGlass), \(text.liquidGlassOtherWindows)")
                    Toggle(FeatureStrings.notch(l10n.language).title,
                           isOn: $appearance.notchLiquidGlassEnabled)
                        .accessibilityLabel("\(appearanceStrings.liquidGlass), \(FeatureStrings.notch(l10n.language).title)")
                }
                .toggleStyle(TrailingSwitchToggleStyle())
                .padding(.leading, settingsRowTextInset)
            }
#endif
        }
    }

    private var shortcutCard: some View {
        SettingsCard(title: l10n.s.globalHotkeySection) {
            SettingsRow(symbol: "keyboard", title: l10n.s.hotkeyToggle, caption: l10n.s.hotkeyCaption) {
                Toggle(l10n.s.hotkeyToggle, isOn: $hotkeyEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: hotkeyEnabled) { _, enabled in
                        HotkeyManager.shared.setEnabled(enabled)
                    }
            }
            ShortcutPreferenceRow(role: .keepAwake, isEnabled: hotkeyEnabled) {
                HotkeyManager.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if hotkeyEnabled, hotkeys.registrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var feedbackCard: some View {
        SettingsCard {
            SettingsRow(symbol: "bubble.left.and.text.bubble.right", title: feedbackStrings.sectionTitle,
                        caption: feedbackStrings.sectionCaption) {
                Button(feedbackStrings.openButton) {
                    appDelegate()?.openFeedbackWindow()
                }
            }
        }
    }

    private func refreshLaunchAtLogin() {
        let requestID = UUID()
        loginRefreshID = requestID
        DispatchQueue.global(qos: .userInitiated).async {
            let enabled = LaunchAtLogin.isEnabled
            DispatchQueue.main.async {
                guard loginRefreshID == requestID else { return }
                launchAtLogin = enabled
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginRefreshID = UUID()
        launchAtLogin = enabled
        do {
            try LaunchAtLogin.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

}

/// Three little desktops with a window on each: the same picture System
/// Settings uses, so the choice needs no reading.
private struct AppearanceChoice: View {
    let option: AppAppearance
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                thumbnail
                    .frame(height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: selected ? 2 : 1)
                    }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch option {
        case .light:
            DesktopThumbnail(dark: false)
        case .dark:
            DesktopThumbnail(dark: true)
        case .system:
            ZStack {
                DesktopThumbnail(dark: false)
                DesktopThumbnail(dark: true)
                    .mask(DiagonalHalf())
            }
        }
    }
}

/// A desktop gradient with a sidebar window on it, painted in the
/// appearance it stands for; the colors are the subject, so they stay fixed.
private struct DesktopThumbnail: View {
    let dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: dark
                               ? [Color(red: 0.20, green: 0.22, blue: 0.34), Color(red: 0.07, green: 0.07, blue: 0.13)]
                               : [Color(red: 0.80, green: 0.88, blue: 1.00), Color(red: 0.58, green: 0.72, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                    Spacer(minLength: 0)
                }
                .frame(height: 5)
                .padding(.horizontal, 6)
                .frame(height: 12)
                .background(Color(white: dark ? 0.22 : 0.93))
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        bar(width: 18)
                        bar(width: 22)
                        bar(width: 14)
                    }
                    .padding(6)
                    .frame(width: 34, alignment: .topLeading)
                    .background(Color(white: dark ? 0.16 : 0.90))
                    VStack(alignment: .leading, spacing: 5) {
                        bar(width: 46)
                        bar(width: 34)
                        bar(width: 40)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .background(Color(white: dark ? 0.19 : 0.99))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(.top, 12)
            .padding(.leading, 14)
        }
    }

    private func bar(width: CGFloat) -> some View {
        Capsule()
            .fill(Color(white: dark ? 0.40 : 0.76))
            .frame(width: width, height: 3)
    }
}

/// The lower-right half of a rectangle, cut corner to corner.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The idle menu bar glyph, tinted white for dark surfaces.
struct MenuBarGlyph: View {
    var body: some View {
        Group {
            if let image = BlackHoleGlyph.image(active: false) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(.white)
    }
}
