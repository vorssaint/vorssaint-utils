// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The screenshot tool: freeze-first area, window and full screen capture
/// with an annotation editor, pinned floating captures and direct clipboard
/// or file output. Purely on demand: at rest the only resource is the
/// optional global shortcut registration. Needs Screen Recording, requested
/// contextually on first use.
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 15)
    private var session: ScreenshotSelectionController?
    private var preview: ScreenshotQuickPreviewController?
    private var editors: [ScreenshotEditorController] = []
    /// The menu bar app is normally accessory-only. While an editor exists
    /// it becomes regular so the window is recoverable through Command Tab.
    private var promotedActivationForEditors = false
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
    }

    func syncWithPreferences() {
        guard AppFeature.screenshot.isAvailable else {
            shortcutRegistrationFailed = false
            hotkey.unregister()
            teardownSurfaces()
            return
        }
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenshotShortcut,
                                            fallback: .screenshotDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    /// Hub-off means gone: open editors, pins and a selection in progress
    /// all leave the screen.
    private func teardownSurfaces() {
        countdown?.cancel()
        countdown = nil
        session?.cancel()
        session = nil
        preview?.close()
        preview = nil
        for editor in editors {
            editor.close()
        }
        editors.removeAll()
        ScreenshotPinController.shared.closeAll()
    }

    // MARK: - Entry

    /// Starts a capture; pressing the shortcut again while a countdown runs
    /// cancels it, and a session in progress is left alone.
    func capture() {
        guard session == nil else { return }
        if countdown != nil {
            countdown?.cancel()
            countdown = nil
            return
        }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.screenshotDelay))
        if delay > 0 {
            countdownRemaining = delay
            tickCountdown()
        } else {
            beginSelection()
        }
    }

    private func tickCountdown() {
        guard countdownRemaining > 0 else {
            countdown = nil
            beginSelection()
            return
        }
        QuickToolHUD.show(icon: "timer", message: "\(countdownRemaining)")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown()
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func beginSelection() {
        guard session == nil else { return }
        preview?.close()
        preview = nil
        let defaults = UserDefaults.standard
        let controller = ScreenshotSelectionController(
            freeze: defaults.bool(forKey: DefaultsKey.screenshotFreeze),
            includePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer))
        session = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.session = nil
            switch outcome {
            case .captured(let capture):
                self.route(capture)
            case .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    // MARK: - Routing

    /// A finished capture goes to the floating preview, or straight into the
    /// editor when the direct edit preference is on.
    private func route(_ capture: ScreenshotSelectionController.Capture) {
        preview?.close()
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotOpenEditorDirectly) {
            openEditor(with: capture)
            return
        }
        let controller = ScreenshotQuickPreviewController(
            capture: capture,
            strings: strings,
            action: { [weak self] action in
                guard let self else { return false }
                switch action {
                case .edit:
                    self.openEditor(with: capture)
                    return true
                case .copy:
                    return self.copyDirect(capture)
                case .save:
                    return self.saveDirect(capture)
                case .discard:
                    return true
                }
            },
            onClose: { [weak self] in self?.preview = nil })
        preview = controller
        controller.show()
    }

    func openEditor(with capture: ScreenshotSelectionController.Capture) {
        if editors.isEmpty, NSApp.activationPolicy() != .regular {
            promotedActivationForEditors = NSApp.setActivationPolicy(.regular)
        }
        let editor = ScreenshotEditorController(capture: capture)
        editors.append(editor)
        editor.show()
    }

    func editorDidClose(_ editor: ScreenshotEditorController) {
        editors.removeAll { $0 === editor }
        if editors.isEmpty, promotedActivationForEditors {
            NSApp.setActivationPolicy(.accessory)
            promotedActivationForEditors = false
        }
    }

    @discardableResult
    private func copyDirect(_ capture: ScreenshotSelectionController.Capture) -> Bool {
        guard let image = flatten(capture) else { return false }
        guard ScreenshotEditorController.copyImage(image) else {
            NSSound.beep()
            return false
        }
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        return true
    }

    @discardableResult
    private func saveDirect(_ capture: ScreenshotSelectionController.Capture) -> Bool {
        guard let image = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: image)
        else { return false }
        let url = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    /// Direct outputs go through the same pipeline as the editor so the 1x
    /// downscale preference applies everywhere; no backdrop and no rounding,
    /// a direct capture is the raw pixels.
    private func flatten(_ capture: ScreenshotSelectionController.Capture) -> CGImage? {
        ScreenshotRenderer.renderExport(
            baseImage: capture.image,
            annotations: [],
            pixelated: nil,
            scale: capture.scale,
            annotationShadowsEnabled: false,
            style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
            fill: .none,
            downscaleTo1x: UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale))
    }

    // MARK: - Save location

    /// The configured folder when it still exists, otherwise the Desktop,
    /// with a unique dated file name.
    static func saveDestination(strings: ScreenshotFeatureStrings) -> URL {
        let manager = FileManager.default
        var folder: URL?
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveFolder) ?? ""
        if !stored.isEmpty {
            let expanded = (stored as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folder = URL(fileURLWithPath: expanded)
            }
        }
        let destination = folder
            ?? manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
        }
        return destination.appendingPathComponent(unique)
    }
}
