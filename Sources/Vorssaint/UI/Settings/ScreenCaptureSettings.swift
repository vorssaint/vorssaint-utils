// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
