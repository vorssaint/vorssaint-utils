// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Shared state for the chooser. Every overlay panel observes the same value,
/// so changing a mode on one display updates the controls on all displays.
final class ScreenCaptureSelectionOptions: ObservableObject {
    let availableTools: [ScreenCaptureTool]
    let recorderAudio = RecorderSelectionAudioOptions()
    @Published private(set) var selectedTool: ScreenCaptureTool
    var onSelectionChange: (() -> Void)?

    init(availableTools: [ScreenCaptureTool], selectedTool: ScreenCaptureTool) {
        precondition(availableTools.contains(selectedTool))
        self.availableTools = availableTools
        self.selectedTool = selectedTool
    }

    func select(_ tool: ScreenCaptureTool) {
        guard availableTools.contains(tool), selectedTool != tool else { return }
        selectedTool = tool
        onSelectionChange?()
    }
}

/// One entry point for screenshot, recording, screen text and color. It owns
/// the only general screen-capture shortcut and one shared selection surface;
/// the established feature services still own what happens after selection.
final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 15)
    private var selection: ScreenshotSelectionController?
    private var options: ScreenCaptureSelectionOptions?
    private var countdown: DispatchWorkItem?
    private var countdownTools: [ScreenCaptureTool]?
    private var countdownRemaining = 0

    var protectedWindowIDs: Set<CGWindowID> {
        selection?.protectedWindowIDs ?? []
    }

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
    }

    func syncWithPreferences() {
        let availableTools = ScreenCaptureTool.available()
        guard !availableTools.isEmpty else {
            shortcutRegistrationFailed = false
            hotkey.unregister()
            cancelSelection()
            return
        }
        if let activeTools = options?.availableTools ?? countdownTools,
           ScreenshotSupport.captureAvailabilityChanged(activeTools: activeTools,
                                                        availableTools: availableTools) {
            cancelSelection()
        }
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenshotShortcut,
                                            fallback: .screenshotDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
        cancelSelection()
    }

    /// Opens the same chooser from every feature surface. A feature-specific
    /// button merely picks the initial mode; the person can switch before
    /// selecting anything.
    func capture(initial preferred: ScreenCaptureTool? = nil) {
        if AppFeature.screenRecorder.isAvailable,
           ScreenRecorderService.shared.stopOrCancelActiveCapture() {
            return
        }
        if countdown != nil {
            cancelSelection()
            return
        }
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }

        let tools = ScreenCaptureTool.available()
        guard !tools.isEmpty else { return }
        let selected = preferred.flatMap { tools.contains($0) ? $0 : nil }
            ?? (tools.contains(.screenshot) ? .screenshot : tools[0])

        guard Permissions.shared.screenRecording else {
            // Color sampling itself needs no capture permission, so its
            // direct action keeps the native path when capture access is off.
            if selected == .color {
                ColorSamplerService.shared.pickNative()
            } else {
                Permissions.shared.requestScreenRecording()
            }
            return
        }
        if selected == .recording,
           !ScreenRecorderService.shared.prepareForSelection() {
            return
        }

        let delay = selected == .screenshot
            ? ScreenshotSupport.sanitizedDelay(
                UserDefaults.standard.integer(forKey: DefaultsKey.screenshotDelay))
            : 0
        guard delay > 0 else {
            beginSelection(tools: tools, selected: selected)
            return
        }
        countdownRemaining = delay
        countdownTools = tools
        tickCountdown(tools: tools, selected: selected)
    }

    private func tickCountdown(tools: [ScreenCaptureTool], selected: ScreenCaptureTool) {
        guard countdownRemaining > 0 else {
            countdown = nil
            countdownTools = nil
            beginSelection(tools: tools, selected: selected)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown(tools: tools, selected: selected)
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func beginSelection(tools: [ScreenCaptureTool], selected: ScreenCaptureTool) {
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        let options = ScreenCaptureSelectionOptions(availableTools: tools,
                                                    selectedTool: selected)
        self.options = options
        startSelection(options: options)
    }

    private func startSelection(options: ScreenCaptureSelectionOptions) {
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen,
              self.options === options else { return }
        let defaults = UserDefaults.standard
        let policy = ScreenshotSupport.unifiedCapturePolicy(
            for: options.selectedTool,
            screenshotFreeze: defaults.bool(forKey: DefaultsKey.screenshotFreeze),
            screenshotIncludePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer),
            screenshotHideVorssaintWindows: defaults.bool(
                forKey: DefaultsKey.screenshotHideVorssaintWindows))
        let controller = ScreenshotSelectionController(
            freeze: policy.freeze,
            includePointer: policy.includePointer,
            showLastRegion: defaults.bool(forKey: DefaultsKey.screenshotShowLastRegion),
            hideVorssaintWindows: policy.hideVorssaintWindows,
            protectedWindowIDs: {
                AppFeature.screenshot.isAvailable
                    ? ScreenshotService.shared.protectedWindowIDsForCapture
                    : []
            },
            purpose: FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle,
            mode: policy.usesGeometry ? .geometry : .image,
            supportsScrollingCapture: options.availableTools.contains(.screenshot),
            screenCaptureOptions: options)
        selection = controller
        controller.begin { [weak self, weak controller, weak options] outcome in
            guard let self, let controller, let options,
                  self.selection === controller else { return }
            self.selection = nil
            self.options = nil
            self.route(outcome, selected: options.selectedTool,
                       recorderAudio: options.recorderAudio)
        }
        options.onSelectionChange = { [weak self, weak controller, weak options] in
            guard let self, let controller, let options else { return }
            self.replaceSelection(controller, options: options)
        }
    }

    private func replaceSelection(_ controller: ScreenshotSelectionController,
                                  options: ScreenCaptureSelectionOptions) {
        guard selection === controller, self.options === options else { return }
        controller.prepareForCapturePolicyChange()
        selection = nil
        controller.cancel()
        DispatchQueue.main.async { [weak self, weak options] in
            guard let self, let options, self.selection == nil,
                  self.options === options,
                  options.selectedTool.feature.isAvailable else { return }
            self.startSelection(options: options)
        }
    }

    private func route(_ outcome: ScreenshotSelectionController.Outcome,
                       selected: ScreenCaptureTool,
                       recorderAudio: RecorderSelectionAudioOptions) {
        guard ScreenshotSupport.captureRouteIsAuthorized(selected: selected) else { return }
        switch outcome {
        case .captured(let capture):
            switch selected {
            case .screenshot:
                ScreenshotService.shared.receiveUnifiedCapture(capture)
            case .text:
                ScreenTextService.shared.receiveUnifiedCapture(capture)
            case .recording, .color:
                showFailure(for: selected)
            }
        case .region(let region):
            guard selected == .recording else {
                showFailure(for: selected)
                return
            }
            ScreenRecorderService.shared.record(region,
                                                audioOptions: recorderAudio)
        case .scrollingRegion(let region):
            guard selected == .screenshot else {
                showFailure(for: selected)
                return
            }
            ScreenshotService.shared.receiveUnifiedScrollingRegion(region)
        case .color(let color):
            guard selected == .color else {
                showFailure(for: selected)
                return
            }
            ColorSamplerService.shared.receiveUnifiedColor(color)
        case .cancelled:
            break
        case .failed:
            showFailure(for: selected)
        }
    }

    private func showFailure(for tool: ScreenCaptureTool) {
        if tool == .recording {
            let strings = FeatureStrings.recorder(L10n.shared.language)
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
        } else {
            let strings = FeatureStrings.screenshot(L10n.shared.language)
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.captureFailed)
        }
    }

    private func cancelSelection() {
        countdown?.cancel()
        countdown = nil
        countdownTools = nil
        countdownRemaining = 0
        selection?.cancel()
        selection = nil
        options = nil
    }
}
