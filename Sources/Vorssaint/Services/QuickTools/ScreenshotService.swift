// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

/// The screenshot tool: freeze-first area, window and full screen capture
/// with an annotation editor, pinned floating captures and direct clipboard
/// or file output. Purely on demand: at rest the only resource is the
/// optional global shortcut registration. Needs Screen Recording, requested
/// contextually on first use.
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var fullScreenShortcutRegistrationFailed = false
    @Published private(set) var lastCaptureShortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 15)
    private let lastCaptureHotkey = QuickToolHotkey(id: 22)
    private let fullScreenHotkey = QuickToolHotkey(id: 23)
    private var session: ScreenshotSelectionController?
    private var preview: ScreenshotQuickPreviewController?
    private var editors: [ScreenshotEditorController] = []
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0
    private var countdownMode: CaptureMode = .standard
    private var directCaptureTask: Task<Void, Never>?
    private var scrollingTask: Task<Void, Never>?
    private var scrollingCaptureID: UUID?

    private enum CaptureMode {
        case standard
        case fullScreen
        case scrolling
    }

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
        fullScreenHotkey.onPress = { [weak self] in self?.captureFullScreen() }
        lastCaptureHotkey.onPress = { [weak self] in self?.openLastCapture() }
    }

    func syncWithPreferences() {
        guard AppFeature.screenshot.isAvailable else {
            shortcutRegistrationFailed = false
            fullScreenShortcutRegistrationFailed = false
            lastCaptureShortcutRegistrationFailed = false
            hotkey.unregister()
            fullScreenHotkey.unregister()
            lastCaptureHotkey.unregister()
            ScreenshotLastCaptureStore.clear()
            teardownSurfaces()
            return
        }
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenshotShortcut,
                                            fallback: .screenshotDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        let fullScreenEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotFullScreenShortcutEnabled)
        let fullScreenShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotFullScreenShortcut,
            fallback: .screenshotFullScreenDefault)
        fullScreenShortcutRegistrationFailed = !fullScreenHotkey.sync(
            enabled: fullScreenEnabled,
            shortcut: fullScreenShortcut)
        let lastCaptureEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        let lastCaptureShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotLastCaptureShortcut,
            fallback: .screenshotLastCaptureDefault)
        lastCaptureShortcutRegistrationFailed = !lastCaptureHotkey.sync(
            enabled: lastCaptureEnabled,
            shortcut: lastCaptureShortcut)
        if !lastCaptureEnabled {
            ScreenshotLastCaptureStore.clear()
        }
    }

    func suspend() {
        hotkey.unregister()
        fullScreenHotkey.unregister()
        lastCaptureHotkey.unregister()
    }

    /// Hub-off means gone: open editors, pins and a selection in progress
    /// all leave the screen.
    private func teardownSurfaces() {
        countdown?.cancel()
        countdown = nil
        directCaptureTask?.cancel()
        directCaptureTask = nil
        scrollingTask?.cancel()
        scrollingTask = nil
        scrollingCaptureID = nil
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
        startCapture(.standard)
    }

    func captureScrolling() {
        startCapture(.scrolling)
    }

    func captureFullScreen() {
        startCapture(.fullScreen)
    }

    private func startCapture(_ mode: CaptureMode) {
        // The same entry point is also the cancel action while a long capture
        // is running. It can never open a second selection or capture task.
        if let scrollingTask {
            scrollingTask.cancel()
            return
        }
        // Another feature may already own the capture surface (copying text
        // off the screen picks an area the same way).
        guard session == nil, directCaptureTask == nil,
              !ScreenshotSelectionController.isSessionOnScreen else { return }
        if countdown != nil {
            countdown?.cancel()
            countdown = nil
            return
        }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        if mode == .scrolling, !Permissions.shared.accessibility {
            Permissions.shared.requestAccessibility()
            return
        }
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.screenshotDelay))
        if delay > 0 {
            countdownMode = mode
            countdownRemaining = delay
            tickCountdown()
        } else {
            beginCapture(mode)
        }
    }

    private func tickCountdown() {
        guard countdownRemaining > 0 else {
            let mode = countdownMode
            countdown = nil
            beginCapture(mode)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown()
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func beginCapture(_ mode: CaptureMode) {
        if mode == .fullScreen {
            beginFullScreenCapture()
        } else {
            beginSelection(mode)
        }
    }

    private func beginSelection(_ mode: CaptureMode) {
        guard session == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        preview?.close()
        preview = nil
        let defaults = UserDefaults.standard
        let controller = ScreenshotSelectionController(
            freeze: defaults.bool(forKey: DefaultsKey.screenshotFreeze),
            includePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer),
            showLastRegion: defaults.bool(forKey: DefaultsKey.screenshotShowLastRegion),
            purpose: mode == .scrolling ? strings.scrollingCaptureTitle : nil,
            mode: mode == .scrolling ? .geometry : .image,
            supportsScrollingCapture: mode == .standard && Permissions.shared.accessibility)
        session = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.session = nil
            switch outcome {
            case .captured(let capture):
                self.route(capture)
            case .region(let region):
                guard mode == .scrolling else { break }
                self.captureScrolling(region)
            case .scrollingRegion(let region):
                self.captureScrolling(region)
            case .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    private func beginFullScreenCapture() {
        guard directCaptureTask == nil, !ScreenshotSelectionController.isSessionOnScreen else {
            return
        }
        preview?.close()
        preview = nil
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main,
              screen.displayID != 0 else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.captureFailed)
            return
        }
        let displayID = screen.displayID
        let scale = screen.backingScaleFactor
        let frame = screen.frame
        let includePointer = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotIncludePointer)
        directCaptureTask = Task { @MainActor [weak self] in
            let image = await ScreenshotCaptureEngine.captureDisplay(
                displayID, includePointer: includePointer)
            guard let self, !Task.isCancelled else { return }
            self.directCaptureTask = nil
            guard let image else {
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
                return
            }
            self.route(ScreenshotSelectionController.Capture(
                image: image,
                scale: scale,
                anchorRect: frame))
        }
    }

    private func captureScrolling(_ region: RecorderSupport.Region) {
        guard scrollingTask == nil else { return }
        guard Permissions.shared.accessibility else {
            Permissions.shared.requestAccessibility()
            return
        }
        QuickToolHUD.show(icon: "rectangle.stack", message: strings.scrollingCaptureProgressHUD)
        let captureID = UUID()
        scrollingCaptureID = captureID
        scrollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ScreenshotScrollingCapture.capture(region: region,
                                                                  includePointer: false)
            guard self.scrollingCaptureID == captureID else { return }
            self.scrollingCaptureID = nil
            self.scrollingTask = nil
            switch result {
            case .success(let capture):
                self.route(capture)
            case .cancelled:
                QuickToolHUD.show(icon: "xmark", message: L10n.shared.s.mediaCancelled)
            case .tooLong:
                QuickToolHUD.show(icon: "rectangle.stack",
                                  message: self.strings.scrollingCaptureTooLongHUD)
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    // MARK: - Routing

    /// Where a direct save landed, and which "%#" number it consumed — so a
    /// later Trash can remove the file and, if applicable, give exactly that
    /// number back.
    private struct SaveOutcome {
        let url: URL
        let consumedNumber: Int?
    }

    /// A finished capture goes to the floating preview, or straight into the
    /// editor when the after-capture action is Edit.
    ///
    /// The clipboard copy happens first and independently, so it also reaches
    /// the captures that open straight in the editor, where no preview button
    /// exists to reach for.
    private func route(_ capture: ScreenshotSelectionController.Capture) {
        preview?.close()
        if UserDefaults.standard.bool(
            forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled) {
            ScreenshotLastCaptureStore.save(capture)
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotCopyToClipboard) {
            autoCopy(capture)
        }
        if ScreenshotDefaultAction.current == .edit {
            openEditor(with: capture)
            return
        }
        var saved: SaveOutcome?
        let controller = ScreenshotQuickPreviewController(
            capture: capture,
            strings: strings,
            action: { [weak self] action in
                guard let self else { return [] }
                switch action {
                case .edit:
                    self.openEditor(with: capture)
                    return [.edit]
                case .copy:
                    return self.copyDirect(capture) ? [.copy] : []
                case .save:
                    guard let outcome = self.saveDirect(capture) else { return [] }
                    saved = outcome
                    return [.save]
                case .saveAndCopy:
                    guard let result = self.saveAndCopyDirect(capture) else { return [] }
                    saved = result.outcome
                    return result.copied ? [.save, .copy] : [.save]
                case .discard:
                    // If this capture was already written to disk — whether
                    // by the default action or a manual Save — Trash should
                    // undo that rather than leave an orphaned file behind.
                    // Into the actual Trash: the person may be discarding a
                    // file the HUD just announced as saved.
                    if let saved {
                        try? FileManager.default.trashItem(at: saved.url,
                                                           resultingItemURL: nil)
                        if let consumed = saved.consumedNumber {
                            Self.rewindNumberSequence(toReuse: consumed)
                        }
                    }
                    return [.discard]
                }
            },
            onClose: { [weak self] in self?.preview = nil })
        preview = controller
        controller.show()
    }

    func openEditor(with capture: ScreenshotSelectionController.Capture) {
        EditorActivationPolicy.retain()
        let editor = ScreenshotEditorController(capture: capture)
        editors.append(editor)
        editor.show()
    }

    private func openLastCapture() {
        guard let capture = ScreenshotLastCaptureStore.load() else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.lastCaptureMissing)
            return
        }
        preview?.close()
        preview = nil
        openEditor(with: capture)
    }

    func editorDidClose(_ editor: ScreenshotEditorController) {
        guard editors.contains(where: { $0 === editor }) else { return }
        editors.removeAll { $0 === editor }
        EditorActivationPolicy.release()
    }

    /// Automatic copy stays quiet on success: the preview or the editor is
    /// already appearing and says the capture happened, so a HUD on top of it
    /// would only repeat that. A failure still beeps, since nothing else
    /// would reveal an empty clipboard before the paste.
    private func autoCopy(_ capture: ScreenshotSelectionController.Capture) {
        if let image = flatten(capture), ScreenshotEditorController.copyImage(image) {
            return
        }
        NSSound.beep()
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

    private func saveDirect(_ capture: ScreenshotSelectionController.Capture) -> SaveOutcome? {
        guard let image = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: image)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            return SaveOutcome(url: url, consumedNumber: consumedNumber)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }
    }

    /// The copy half is reported honestly: when the pasteboard write fails
    /// the HUD keeps the plain saved message, so the caller leaves the Copy
    /// button available instead of claiming work that never happened.
    private func saveAndCopyDirect(_ capture: ScreenshotSelectionController.Capture)
        -> (outcome: SaveOutcome, copied: Bool)? {
        guard let image = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: image)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }

        let copied = ScreenshotEditorController.copyImage(image)
        let format = copied ? strings.savedAndCopiedHUDFormat : strings.savedHUDFormat
        QuickToolHUD.show(icon: "camera.viewfinder",
                          message: String(format: format,
                                          url.deletingLastPathComponent().lastPathComponent))
        return (SaveOutcome(url: url, consumedNumber: consumedNumber), copied)
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
    static func saveDestination(strings: ScreenshotFeatureStrings) -> (url: URL, consumedNumber: Int?) {
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
        var destination = folder
            ?? manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let subfolderPattern = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveSubfolder) ?? ""
        let subfolder = ScreenshotSupport.expandSaveSubfolder(subfolderPattern, date: Date())
        if !subfolder.isEmpty {
            let dated = destination.appendingPathComponent(subfolder, isDirectory: true)
            // Only descend into the dated subfolder if we can actually create
            // it; otherwise fall back to the base folder rather than losing
            // the screenshot.
            if (try? manager.createDirectory(at: dated, withIntermediateDirectories: true)) != nil {
                destination = dated
            }
        }
        let (name, consumedNumber) = Self.fileName(strings: strings)
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
        }
        return (destination.appendingPathComponent(unique), consumedNumber)
    }

    /// The default localized "Screenshot yyyy-MM-dd at HH.mm.ss.png" name
    /// when no pattern is set, otherwise the pattern with date tokens and
    /// an optional "%#" number sequence expanded. Advances and persists the
    /// number sequence when the pattern actually uses it.
    private static func fileName(strings: ScreenshotFeatureStrings) -> (name: String, consumedNumber: Int?) {
        let defaults = UserDefaults.standard
        let pattern = (defaults.string(forKey: DefaultsKey.screenshotFileNamePattern) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return (ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date()), nil)
        }

        if ScreenshotSupport.fileNamePatternUsesNumber(pattern) {
            let number = defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext)
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: number)
            defaults.set(number + 1, forKey: DefaultsKey.screenshotFileNumberNext)
            return (expanded + ".png", number)
        } else {
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: 0)
            return (expanded + ".png", nil)
        }
    }

    /// Gives a consumed "%#" number back after its save failed or was
    /// deleted — but only while nothing else advanced the sequence since,
    /// so a rewind can never undo another capture's number.
    static func rewindNumberSequence(toReuse consumed: Int) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == consumed + 1 else {
            return
        }
        defaults.set(consumed, forKey: DefaultsKey.screenshotFileNumberNext)
    }
}

/// One discardable PNG on disk keeps this shortcut useful across launches
/// without holding a full-resolution screenshot in memory while the app rests.
enum ScreenshotLastCaptureStore {
    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("LatestScreenshot.png")
    }

    static func save(_ capture: ScreenshotSelectionController.Capture) {
        guard let fileURL,
              let data = ScreenshotRenderer.pngData(from: capture.image, scale: capture.scale)
        else {
            clear()
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            clear()
        }
    }

    static func load() -> ScreenshotSelectionController.Capture? {
        guard let fileURL else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let dpi = properties[kCGImagePropertyDPIWidth] as? NSNumber,
              let scale = ScreenshotSupport.captureScale(fromDPI: dpi.doubleValue)
        else { return nil }
        let imageOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else { return nil }
        return ScreenshotSelectionController.Capture(image: image, scale: scale, anchorRect: .zero)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
