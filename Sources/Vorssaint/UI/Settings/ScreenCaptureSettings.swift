// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// One Settings destination for every tool that starts from the screen. The
/// tools are four modes of one chooser rather than four features, so the page
/// leads with the chooser itself and then gives every installed tool a section
/// of its own, each carrying the shortcut that opens the chooser on that mode.
/// Sections side by side is how the rest of Settings reads, and it lets the
/// section anchors be reached without a switcher having to move first.
struct ScreenCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    private var availableTools: [ScreenCaptureTool] {
        ScreenCaptureTool.available()
    }

    var body: some View {
        Form {
            ForEach(availableTools, id: \.self) { tool in
                settings(for: tool)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func settings(for tool: ScreenCaptureTool) -> some View {
        switch tool {
        case .screenshot: ScreenshotCaptureSettings()
        case .recording: ScreenRecordingCaptureSettings()
        case .text: ScreenTextCaptureSettings()
        case .color: ColorCaptureSettings()
        case .translate: LiveTranslationCaptureSettings()
        }
    }
}

private extension SettingsSectionAnchor {
    var screenCaptureTool: ScreenCaptureTool? {
        switch self {
        case .screenshot: return .screenshot
        case .screenRecorder: return .recording
        case .screenOCR: return .text
        case .colorPicker: return .color
        case .liveTranslation: return .translate
        default: return nil
        }
    }
}

/// The shortcut that opens the chooser straight on one tool, shown inside
/// that tool's own section.
struct ToolShortcutRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ScreenCaptureService.shared
    @AppStorage private var enabled: Bool

    private let tool: ScreenCaptureTool
    private let keys: ScreenCaptureTool.DedicatedShortcut

    init(tool: ScreenCaptureTool) {
        let keys = tool.dedicatedShortcut
        self.tool = tool
        self.keys = keys
        _enabled = AppStorage(wrappedValue: false, keys.enabledKey)
    }

    var body: some View {
        Toggle(keys.role.title(l10n.s), isOn: $enabled)
            .onChange(of: enabled) { _, _ in
                service.syncWithPreferences()
            }
        ShortcutPreferenceRow(role: keys.role, isEnabled: enabled) {
            service.syncWithPreferences()
        }
        if enabled, service.toolShortcutRegistrationFailures.contains(tool) {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

private struct ScreenTextCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.screenOCRDetectQRCodes) private var detectsQRCodes = true

    var body: some View {
        Section {
            Button {
                ScreenTextService.shared.capture()
            } label: {
                Label(l10n.s.ocrName, systemImage: "text.viewfinder")
            }
            Text(l10n.s.ocrCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ToolShortcutRows(tool: .text)
            Toggle(l10n.s.ocrQRToggle, isOn: $detectsQRCodes)
            Text(l10n.s.ocrQRCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !permissions.screenRecording {
                PermissionRow(kind: .screenRecording)
            }
        } header: {
            Text(l10n.s.ocrName)
        }
        .settingsSectionAnchor(.screenOCR)
    }
}

private struct ColorCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.colorPickerFormat) private var format = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var usesBareHex = false

    var body: some View {
        Section {
            Button {
                ColorSamplerService.shared.pick()
            } label: {
                Label(l10n.s.colorPickerPickNow, systemImage: "eyedropper")
            }
            Text(l10n.s.colorPickerCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ToolShortcutRows(tool: .color)
            Picker(l10n.s.colorPickerFormatLabel, selection: $format) {
                ForEach(ColorCopyFormat.allCases) { format in
                    Text(format.label).tag(format.rawValue)
                }
            }
            .pickerStyle(.segmented)
            if format == ColorCopyFormat.hex.rawValue {
                Toggle(l10n.s.colorPickerBareHexToggle, isOn: $usesBareHex)
            }
        } header: {
            Text(l10n.s.colorPickerName)
        }
        .settingsSectionAnchor(.colorPicker)
    }
}

private struct LiveTranslationCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.liveTranslationInterval) private var interval = 0.8
    @AppStorage(DefaultsKey.liveTranslationSourceLanguage) private var sourceLanguage = ""
    @AppStorage(DefaultsKey.liveTranslationTargetLanguage) private var targetLanguage = ""
    @AppStorage(DefaultsKey.liveTranslationMode) private var mode = "inPlace"
    @AppStorage(DefaultsKey.liveTranslationHideOnHover) private var hideOnHover = false
    @AppStorage(DefaultsKey.liveTranslationStrategy) private var strategy = "lowLatency"
    @AppStorage(DefaultsKey.liveTranslationProvider) private var provider = "apple"
    @State private var googleAPIKey = LiveTranslationKeyStore.read() ?? ""
    @FocusState private var googleAPIKeyFieldFocused: Bool
    @State private var apiKeySaveFailed = false
    @AppStorage(DefaultsKey.liveTranslationGoogleCharacterCount) private var googleCharacterCount = 0
    @AppStorage(DefaultsKey.liveTranslationGoogleWordCount) private var googleWordCount = 0
    @AppStorage(DefaultsKey.liveTranslationGoogleUsageCapEnabled) private var usageCapEnabled = false
    @AppStorage(DefaultsKey.liveTranslationGoogleUsageCapCharacters) private var usageCapCharacters = 500_000
    @AppStorage(DefaultsKey.liveTranslationEngine) private var engine = "native"

    private var strings: LiveTranslationFeatureStrings {
        FeatureStrings.liveTranslation(l10n.language)
    }

    private static let usageCapFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1_000
        formatter.maximum = 100_000_000
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    // Broken out of the view body as plain String properties, not inlined
    // into a Text(...) call - a single expression chaining this many `+`
    // operators inside a large SwiftUI body was too much for the type
    // checker to resolve in reasonable time.
    private var usageSummaryText: String {
        strings.usageLabel + ": " + "\(googleCharacterCount) " + strings.usageCharactersUnit
            + " (~" + "\(googleWordCount) " + strings.usageWordsUnit + ")"
    }

    private var usageCostText: String {
        let cost = Double(googleCharacterCount) / 1_000_000 * 20
        return strings.usageCostLabel + ": " + String(format: "$%.2f", cost)
    }

    private var engineStatusText: String {
        strings.engineLabel + ": " + strings.engineCompatibility
    }

    /// Writes the field's current value to the Keychain once, on submit or
    /// when focus leaves the field - not on every keystroke, which would
    /// otherwise hit Keychain I/O for each character typed.
    private func saveGoogleAPIKey() {
        apiKeySaveFailed = !LiveTranslationKeyStore.save(googleAPIKey)
    }

    var body: some View {
        Section {
            Button {
                ScreenCaptureService.shared.capture(initial: .translate)
            } label: {
                Label(strings.translateNowButton, systemImage: ScreenCaptureTool.translate.systemImageName)
            }

            Text(strings.chooserCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            ToolShortcutRows(tool: .translate)

            Picker(strings.liveModeLabel, selection: $mode) {
                Text(strings.liveModeInPlace).tag("inPlace")
                Text(strings.liveModeWindow).tag("window")
            }
            .pickerStyle(.segmented)

            Toggle(strings.hideOnHoverLabel, isOn: $hideOnHover)
            Text(strings.hideOnHoverCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $interval, in: 0.5...3.0, step: 0.1) {
                Text(strings.intervalLabel)
            }
            Text(strings.intervalLabel + ": " + String(format: "%.1fs", interval))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(strings.sourceLanguageLabel, selection: $sourceLanguage) {
                Text(strings.autoDetectOption).tag("")
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            Picker(strings.targetLanguageLabel, selection: $targetLanguage) {
                Text(strings.followAppLanguageOption).tag("")
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }

            if #available(macOS 26.4, *) {
                Picker(strings.translationStrategyLabel, selection: $strategy) {
                    Text(strings.strategyLowLatency).tag("lowLatency")
                    Text(strings.strategyHighFidelity).tag("highFidelity")
                }
                .pickerStyle(.segmented)
                Text(strings.translationStrategyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(strings.providerLabel, selection: $provider) {
                Text(strings.providerApple).tag("apple")
                Text(strings.providerGoogle).tag("google")
            }
            .pickerStyle(.segmented)

            if provider == "apple" {
                Text(strings.appleOnDeviceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(strings.openLanguageSettingsButton, systemImage: "gearshape")
                }
            }

            if provider == "google" {
                SecureField(strings.googleAPIKeyLabel, text: $googleAPIKey)
                    .focused($googleAPIKeyFieldFocused)
                    .onSubmit(saveGoogleAPIKey)
                    .onChange(of: googleAPIKeyFieldFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { saveGoogleAPIKey() }
                    }
                    // The settings pane can close while the field is still
                    // focused, which never fires the focus-lost branch above -
                    // a last-chance save so a key typed just before closing
                    // isn't silently lost.
                    .onDisappear(perform: saveGoogleAPIKey)
                Text(strings.googleAPIKeyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if apiKeySaveFailed {
                    Text(strings.googleAPIKeySaveFailed)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(strings.googlePrivacyNote)
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(usageSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(usageCostText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(strings.usageResetButton) {
                    googleCharacterCount = 0
                    googleWordCount = 0
                }

                Toggle(strings.usageCapToggle, isOn: $usageCapEnabled)
                if usageCapEnabled {
                    HStack {
                        TextField("", value: $usageCapCharacters, formatter: Self.usageCapFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text(strings.usageCharactersUnit)
                    }
                    if googleCharacterCount >= usageCapCharacters {
                        Text(strings.usageCapReachedCaption)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if #available(macOS 26.0, *) {
                Picker(strings.engineLabel, selection: $engine) {
                    Text(strings.engineNative).tag("native")
                    Text(strings.engineCompatibility).tag("compatibility")
                }
                .pickerStyle(.segmented)
                Text(strings.engineCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // No real choice on this OS version - the native engine
                // can't run here regardless of what's stored, so there's
                // nothing to switch, only to report.
                Text(engineStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !permissions.screenRecording {
                PermissionRow(kind: .screenRecording)
            }
        } header: {
            Text(strings.pageTitle)
        }
        .settingsSectionAnchor(.liveTranslation)
    }
}
