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
    let layout: NotchCaptureControlsLayout
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focusedControl: NotchCaptureControl?

    var body: some View {
        VStack(spacing: 12) {
            header
                .padding(.horizontal, NotchLayout.horizontalInset)
                .frame(height: layout.headerHeight)
            HStack(spacing: 6) {
                ForEach(options.showsCaptureMenu ? options.availableTools : [options.selectedTool], id: \.self) { tool in
                    NotchActionTile(symbol: tool.systemImageName,
                                    title: tool.settingsTitle(l10n.s, language: l10n.language),
                                    active: options.selectedTool == tool) { options.select(tool) }
                        .focused($focusedControl, equals: .tool(tool))
                }
            }
            .padding(.horizontal, 18)
            if options.selectedTool.capturesAudio {
                NotchRecordingAudioOptions(options: options.recorderAudio, focusedControl: $focusedControl)
            }
        }
        .padding(.top, layout.headerTop)
        .foregroundStyle(.white)
        .onChange(of: focusedControl) {
            options.hasFocusedControl = focusedControl != nil
            service.scheduleCaptureControlsCollapse()
        }
        .onDisappear { options.hasFocusedControl = false }
    }

    /// Beside the camera the title and the buttons keep to their own side,
    /// as the open island's header does; otherwise one row holds both.
    @ViewBuilder private var header: some View {
        if layout.cameraGap > 0 {
            HStack(spacing: 0) {
                title
                    .padding(.trailing, NotchCaptureControlsLayout.cameraClearance)
                    .frame(width: layout.sideWidth, alignment: .leading)
                Color.clear.frame(width: layout.cameraGap)
                actions
                    .padding(.leading, NotchCaptureControlsLayout.cameraClearance)
                    .frame(width: layout.sideWidth, alignment: .trailing)
            }
        } else {
            HStack {
                title
                Spacer()
                actions.fixedSize()
            }
        }
    }

    /// The layout measures this title with the same font.
    private var title: some View {
        Text(FeatureStrings.screenshot(l10n.language).screenCaptureTitle)
            .font(Font(NotchCaptureControlsLayout.titleFont as CTFont))
            .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: NotchCaptureControlsLayout.buttonSpacing) {
            if options.offersRepeatLastRegion {
                // A narrow side of the camera keeps only the key.
                ViewThatFits(in: .horizontal) {
                    Label("R", systemImage: "rectangle.dashed")
                        .padding(.horizontal, 8)
                    Text("R").frame(width: 28)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            NotchIconButton(symbol: "chevron.up", title: FeatureStrings.notch(l10n.language).collapse,
                            action: service.collapseCaptureControls)
                .focused($focusedControl, equals: .collapse)
            NotchIconButton(symbol: "xmark", title: l10n.s.menuClose, action: service.cancelCaptureControls)
                .focused($focusedControl, equals: .close)
        }
    }
}

private struct NotchRecordingAudioOptions: View {
    @ObservedObject var options: RecorderSelectionAudioOptions
    @ObservedObject private var l10n = L10n.shared
    var focusedControl: FocusState<NotchCaptureControl?>.Binding
    var body: some View {
        HStack(spacing: 16) {
            Toggle(FeatureStrings.recorder(l10n.language).systemAudioTrackLabel, isOn: $options.systemAudio)
                .focused(focusedControl, equals: .systemAudio)
            Toggle(FeatureStrings.recorder(l10n.language).microphoneTrackLabel, isOn: $options.microphone)
                .focused(focusedControl, equals: .microphone)
        }
        .toggleStyle(.switch)
        .tint(.green)
        .controlSize(.small)
        .fixedSize()
    }
}
