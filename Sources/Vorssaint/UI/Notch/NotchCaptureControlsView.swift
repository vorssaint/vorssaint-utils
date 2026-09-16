// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private enum NotchCaptureControl: Hashable {
    case collapse, close, tool(ScreenCaptureTool), systemAudio, microphone
}

/// The same selection model drives keyboard shortcuts and the screen overlay.
/// Only the controls change their destination; capture remains in its owner.
struct NotchCaptureControlsView: View {
    @ObservedObject var options: ScreenCaptureSelectionOptions
    let service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focusedControl: NotchCaptureControl?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(FeatureStrings.screenshot(l10n.language).screenCaptureTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                NotchIconButton(symbol: "chevron.up", title: FeatureStrings.notch(l10n.language).collapse,
                                action: service.collapseCaptureControls)
                    .focused($focusedControl, equals: .collapse)
                NotchIconButton(symbol: "xmark", title: l10n.s.menuClose, action: service.cancelCaptureControls)
                    .focused($focusedControl, equals: .close)
            }
            HStack(spacing: 6) {
                ForEach(options.showsCaptureMenu ? options.availableTools : [options.selectedTool], id: \.self) { tool in
                    NotchActionTile(symbol: tool.systemImageName,
                                    title: tool.settingsTitle(l10n.s, language: l10n.language),
                                    active: options.selectedTool == tool, stacked: true) { options.select(tool) }
                        .focused($focusedControl, equals: .tool(tool))
                }
            }
            if options.selectedTool.capturesAudio {
                NotchRecordingAudioOptions(options: options.recorderAudio, focusedControl: $focusedControl)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: focusedControl) {
            options.hasFocusedControl = focusedControl != nil
            service.scheduleCaptureControlsCollapse()
        }
        .onDisappear { options.hasFocusedControl = false }
    }
}

private struct NotchRecordingAudioOptions: View {
    @ObservedObject var options: RecorderSelectionAudioOptions
    @ObservedObject private var l10n = L10n.shared
    var focusedControl: FocusState<NotchCaptureControl?>.Binding
    var body: some View {
        HStack {
            Toggle(FeatureStrings.recorder(l10n.language).systemAudioTrackLabel, isOn: $options.systemAudio)
                .focused(focusedControl, equals: .systemAudio)
            Toggle(FeatureStrings.recorder(l10n.language).microphoneTrackLabel, isOn: $options.microphone)
                .focused(focusedControl, equals: .microphone)
        }.toggleStyle(.button).controlSize(.small)
    }
}
