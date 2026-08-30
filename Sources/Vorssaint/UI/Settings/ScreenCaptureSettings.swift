// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One Settings destination for every tool that starts from the screen. The
/// segmented control at the top changes the feature-specific options shown
/// below it, and the top section also carries the selected tool's own
/// shortcut where the old shared shortcut lived.
struct ScreenCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var selectedTool = ScreenCaptureTool.screenshot

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var availableTools: [ScreenCaptureTool] {
        ScreenCaptureTool.available()
    }

    private var currentTool: ScreenCaptureTool {
        availableTools.contains(selectedTool) ? selectedTool : availableTools.first ?? .screenshot
    }

    var body: some View {
        Form {
            if !availableTools.isEmpty {
                Section {
                    if availableTools.count > 1 {
                        Picker(strings.screenCaptureTitle, selection: toolSelection) {
                            ForEach(availableTools, id: \.self) { tool in
                                Label(tool.settingsTitle(l10n.s, language: l10n.language),
                                      systemImage: tool.systemImageName)
                                    .tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.large)
                    }
                    ToolShortcutRows(tool: currentTool, keys: currentTool.dedicatedShortcut)
                        .id(currentTool)
                } header: {
                    Text(strings.screenCaptureTitle)
                }
            }

            selectedSettings
        }
        .formStyle(.grouped)
        .onAppear { reconcileSelection(withDestination: true) }
        .onChange(of: features.revision) { _, _ in
            reconcileSelection(withDestination: false)
        }
        .onChange(of: router.requestID) { _, _ in
            reconcileSelection(withDestination: true)
        }
    }

    private var toolSelection: Binding<ScreenCaptureTool> {
        Binding(get: { currentTool }, set: { selectedTool = $0 })
    }

    @ViewBuilder
    private var selectedSettings: some View {
        if availableTools.isEmpty {
            EmptyView()
        } else {
            switch currentTool {
            case .screenshot:
                ScreenshotCaptureSettings()
            case .recording:
                ScreenRecordingCaptureSettings()
            case .text:
                ScreenTextCaptureSettings()
            case .color:
                ColorCaptureSettings()
            }
        }
    }

    private func reconcileSelection(withDestination: Bool) {
        if withDestination,
           let anchor = router.destination.sectionAnchor,
           let requestedTool = anchor.screenCaptureTool,
           availableTools.contains(requestedTool) {
            selectedTool = requestedTool
            return
        }
        if !availableTools.contains(selectedTool), let first = availableTools.first {
            selectedTool = first
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
        default: return nil
        }
    }
}

/// The shortcut that opens the chooser straight on one tool, shown in the
/// page's top section under the tool's own name while that tool is selected.
private struct ToolShortcutRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ScreenCaptureService.shared
    @AppStorage private var enabled: Bool

    private let tool: ScreenCaptureTool
    private let keys: ScreenCaptureTool.DedicatedShortcut

    init(tool: ScreenCaptureTool, keys: ScreenCaptureTool.DedicatedShortcut) {
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
    @AppStorage(DefaultsKey.screenOCRRemoveLineBreaks) private var removesLineBreaks = false
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
            Toggle(l10n.s.ocrRemoveLineBreaksToggle, isOn: $removesLineBreaks)
            Text(l10n.s.ocrRemoveLineBreaksCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
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
