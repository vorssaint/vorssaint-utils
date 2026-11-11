// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// The screenshot tool: the capture overlay, the instant whole-screen save,
/// and what happens to a finished image (copy, save, print, open in Preview).
/// Nothing is ever uploaded.
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    /// The shortcuts macOS refused, so the settings can say so.
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var fullScreenShortcutRegistrationFailed = false

    // Ids continue past the hand-assigned quick tool range, which ends at 24.
    private let hotkey = QuickToolHotkey(id: 25)
    private let fullScreenHotkey = QuickToolHotkey(id: 26)
    private var overlay: ShotOverlay?
    private var starting = false

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
        fullScreenHotkey.onPress = { [weak self] in self?.saveFullScreen() }
    }

    private var defaults: UserDefaults { .standard }

    /// The overlay, or the area chooser another feature opened, is on screen.
    var isCapturing: Bool { overlay != nil || starting }

    func syncWithPreferences() {
        guard AppFeature.screenshot.isAvailable else {
            suspend()
            return
        }
        let ok = hotkey.sync(enabled: defaults.bool(forKey: DefaultsKey.shotShortcutEnabled),
                             shortcut: GlobalShortcutRole.screenshot.savedShortcut,
                             storageKey: GlobalShortcutRole.screenshot.storageKey)
        let fullOK = fullScreenHotkey.sync(
            enabled: defaults.bool(forKey: DefaultsKey.shotFullScreenShortcutEnabled),
            shortcut: GlobalShortcutRole.screenshotFullScreen.savedShortcut,
            storageKey: GlobalShortcutRole.screenshotFullScreen.storageKey)
        if shortcutRegistrationFailed != !ok { shortcutRegistrationFailed = !ok }
        if fullScreenShortcutRegistrationFailed != !fullOK { fullScreenShortcutRegistrationFailed = !fullOK }
    }

    func suspend() {
        hotkey.unregister()
        fullScreenHotkey.unregister()
        overlay?.close()
        if shortcutRegistrationFailed { shortcutRegistrationFailed = false }
        if fullScreenShortcutRegistrationFailed { fullScreenShortcutRegistrationFailed = false }
    }

    private func hasScreenAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        Permissions.shared.requestScreenRecording()
        return false
    }

    // MARK: Capturing

    /// Freezes the screen and opens the selection overlay.
    func capture() {
        guard AppFeature.screenshot.isAvailable else { return }
        open(mode: .annotate)
    }

    /// Lets another feature choose an area of one display on the frozen
    /// screen. `completion` gets nil when the choice is cancelled.
    func chooseArea(completion: @escaping (ScreenRegionCapture.Region?) -> Void) {
        guard !isCapturing, hasScreenAccess() else { completion(nil); return }
        open(mode: .pick(completion))
    }

    /// Closes the area chooser another feature opened, if it is still up.
    func cancelAreaChoice() {
        if overlay?.isPicking == true { overlay?.close() }
    }

    private func open(mode: ShotOverlay.Mode) {
        guard !isCapturing, hasScreenAccess() else {
            if case .pick(let completion) = mode { completion(nil) }
            return
        }
        starting = true
        let includeCursor: Bool
        if case .annotate = mode { includeCursor = defaults.bool(forKey: DefaultsKey.shotCaptureCursor) }
        else { includeCursor = false }
        Task { @MainActor in
            let frame = await ShotFrame.grab(includeCursor: includeCursor)
            self.starting = false
            guard let frame else {
                QuickToolHUD.show(icon: "camera.viewfinder",
                                  message: FeatureStrings.screenshot(L10n.shared.language).captureFailed)
                if case .pick(let completion) = mode { completion(nil) }
                return
            }
            let overlay = ShotOverlay(service: self, frame: frame, mode: mode)
            overlay.onClose = { [weak overlay] in
                if self.overlay === overlay { self.overlay = nil }
            }
            self.overlay = overlay
            overlay.show()
        }
    }

    /// Saves every display straight to the default folder.
    func saveFullScreen() {
        guard AppFeature.screenshot.isAvailable, !isCapturing, hasScreenAccess() else { return }
        starting = true
        let includeCursor = defaults.bool(forKey: DefaultsKey.shotCaptureCursor)
        Task { @MainActor in
            let frame = await ShotFrame.grab(includeCursor: includeCursor)
            self.starting = false
            let strings = FeatureStrings.screenshot(L10n.shared.language)
            guard let frame,
                  let shot = frame.render(frame.bounds, shapes: [], renderer: ShotRenderer(frame: frame))
            else {
                QuickToolHUD.show(icon: "camera.viewfinder", message: strings.captureFailed)
                return
            }
            let format = ShotFiles.sanitizedFormat(self.defaults.string(forKey: DefaultsKey.shotFormat) ?? "png")
            let url = self.automaticURL(format: format)
            guard self.write(shot.image, scale: shot.scale, to: url, format: format) else {
                QuickToolHUD.show(icon: "exclamationmark.triangle",
                                  message: FeatureStrings.shot(L10n.shared.language).saveFailed)
                return
            }
            AppSoundService.shared.play(.screenshotTaken)
            let copied = self.defaults.bool(forKey: DefaultsKey.shotAutoCopy)
            if copied { self.copy(shot.image, scale: shot.scale, notify: false) }
            self.notifySaved(url, copied: copied)
        }
    }

    // MARK: Files

    /// Where whole-screen saves go, and where the save dialog starts until a
    /// folder is picked there.
    static func defaultFolder(in defaults: UserDefaults = .standard) -> URL {
        let stored = defaults.string(forKey: DefaultsKey.shotFolder) ?? ""
        if !stored.isEmpty {
            return URL(fileURLWithPath: (stored as NSString).expandingTildeInPath, isDirectory: true)
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Screenshots", isDirectory: true)
    }

    private func automaticURL(format: String) -> URL {
        let folder = Self.defaultFolder(in: defaults)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = ShotFiles.fileExtension(format)
        let name = ShotFiles.name(pattern: defaults.string(forKey: DefaultsKey.shotFileNamePattern),
                                  time: Date(), fileExtension: ext) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return folder.appendingPathComponent(name + ext)
    }

    /// The image's bytes in one of the formats the tool saves.
    static func data(_ image: CGImage, scale: CGFloat, format: String, jpegQuality: Int) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        // The point size makes the file carry the display's resolution.
        rep.size = NSSize(width: CGFloat(image.width) / max(1, scale), height: CGFloat(image.height) / max(1, scale))
        switch ShotFiles.sanitizedFormat(format) {
        case "jpg":
            let quality = CGFloat(min(max(jpegQuality, 10), 100)) / 100
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case "bmp":
            return rep.representation(using: .bmp, properties: [:])
        default:
            return rep.representation(using: .png, properties: [:])
        }
    }

    @discardableResult
    func write(_ image: CGImage, scale: CGFloat, to url: URL, format: String) -> Bool {
        guard let data = Self.data(image, scale: scale, format: format,
                                   jpegQuality: defaults.integer(forKey: DefaultsKey.shotJPEGQuality))
        else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: Finished images

    func copy(_ image: CGImage, scale: CGFloat, notify: Bool = true) {
        guard let png = Self.data(image, scale: scale, format: "png", jpegQuality: 100) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if notify {
            AppSoundService.shared.play(.screenshotTaken)
            if defaults.bool(forKey: DefaultsKey.shotNotify) {
                QuickToolHUD.show(icon: "doc.on.doc",
                                  message: FeatureStrings.screenshot(L10n.shared.language).copiedHUD)
            }
        }
    }

    private func notifySaved(_ url: URL, copied: Bool) {
        guard defaults.bool(forKey: DefaultsKey.shotNotify) else { return }
        let strings = FeatureStrings.screenshot(L10n.shared.language)
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        QuickToolHUD.show(icon: "square.and.arrow.down",
                          message: String(format: copied ? strings.savedAndCopiedHUDFormat : strings.savedHUDFormat,
                                          path))
    }

    /// The save dialog. True when the image was saved.
    func saveWithPanel(_ image: CGImage, scale: CGFloat) -> Bool {
        let fileManager = FileManager.default
        let last = defaults.string(forKey: DefaultsKey.shotLastFolder) ?? ""
        var isDirectory: ObjCBool = false
        let folder = !last.isEmpty && fileManager.fileExists(atPath: last, isDirectory: &isDirectory)
            && isDirectory.boolValue
            ? URL(fileURLWithPath: last, isDirectory: true) : Self.defaultFolder(in: defaults)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = ShotFiles.sanitizedFormat(defaults.string(forKey: DefaultsKey.shotFormat) ?? "png")
        let ext = ShotFiles.fileExtension(format)
        let panel = NSSavePanel()
        panel.title = FeatureStrings.shot(L10n.shared.language).saveTitle
        panel.directoryURL = folder
        panel.allowedContentTypes = [.png, .jpeg, .bmp]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = ShotFiles.name(
            pattern: defaults.string(forKey: DefaultsKey.shotFileNamePattern), time: Date(), fileExtension: ext) {
                fileManager.fileExists(atPath: folder.appendingPathComponent($0).path)
            } + ext
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let chosen = ShotFiles.format(fromPath: url.path, fallback: format)
        guard write(image, scale: scale, to: url, format: chosen) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = FeatureStrings.shot(L10n.shared.language).saveFailed
            alert.informativeText = url.path
            alert.runModal()
            return false
        }
        defaults.set(url.deletingLastPathComponent().path, forKey: DefaultsKey.shotLastFolder)
        defaults.set(chosen, forKey: DefaultsKey.shotFormat)
        AppSoundService.shared.play(.screenshotTaken)
        let copied = defaults.bool(forKey: DefaultsKey.shotAutoCopy)
        if copied { copy(image, scale: scale, notify: false) }
        notifySaved(url, copied: copied)
        return true
    }

    /// The print dialog, then the image fitted to the page (never enlarged).
    /// True when printed.
    func print(_ image: CGImage, scale: CGFloat) -> Bool {
        let size = NSSize(width: CGFloat(image.width) / max(1, scale), height: CGFloat(image.height) / max(1, scale))
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleProportionallyDown
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = FeatureStrings.screenshot(L10n.shared.language).pageTitle
        NSApp.activate(ignoringOtherApps: true)
        guard operation.run() else { return false }
        if defaults.bool(forKey: DefaultsKey.shotAutoCopy) { copy(image, scale: scale, notify: false) }
        return true
    }

    /// The image opens in Preview from a temporary file, for anything the
    /// overlay's own tools do not do.
    func openInPreview(_ image: CGImage, scale: CGFloat) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VorssaintScreenshots",
                                                                                   isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dayAgo = Date().addingTimeInterval(-86_400)
        let old = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in old where file.lastPathComponent.hasPrefix("screenshot-") {
            if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, created < dayAgo {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = folder.appendingPathComponent("screenshot-\(formatter.string(from: Date())).png")
        guard write(image, scale: scale, to: url, format: "png") else { return }
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open([url], withApplicationAt: preview,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
