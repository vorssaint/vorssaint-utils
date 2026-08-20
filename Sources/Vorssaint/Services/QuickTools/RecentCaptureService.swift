// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Carbon.HIToolbox
import ImageIO
import SwiftUI

struct RecentCaptureEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case screenshot
        case recording
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    let screenshotName: String?
    let recordingPath: String?
    let thumbnailName: String?
    let scale: Double?
    let anchorX: Double?
    let anchorY: Double?
    let anchorWidth: Double?
    let anchorHeight: Double?

    var recordingURL: URL? {
        guard let recordingPath else { return nil }
        return URL(fileURLWithPath: recordingPath)
    }
}

/// A bounded, on-demand list of captures. Screenshots live in this cache so
/// copy-only captures can return after their preview closes. Recordings keep
/// only their file path and a small thumbnail, never a second video copy.
final class RecentCaptureService: ObservableObject {
    static let shared = RecentCaptureService()

    @Published private(set) var entries: [RecentCaptureEntry] = []

    private let manager = FileManager.default
    private let queue = DispatchQueue(label: "com.vorssaint.utils.recent-captures",
                                      qos: .utility)
    private let generationLock = NSLock()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var storedEntries: [RecentCaptureEntry] = []
    private var loaded = false
    private var clearGeneration = 0
    private var panel: NSPanel?
    private var panelKeyMonitor: Any?
    private var panelLocalClickMonitor: Any?
    private var panelGlobalClickMonitor: Any?
    private var panelDeactivateObserver: NSObjectProtocol?

    private init() {
        reload()
    }

    // MARK: - History palette

    func showHistoryWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showHistoryWindow() }
            return
        }
        let anchor = NSApp.keyWindow?.isVisible == true ? NSApp.keyWindow : nil
        let panel = ensurePanel()
        reload()
        position(panel, over: anchor)
        installPanelMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hideHistoryWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.hideHistoryWindow() }
            return
        }
        removePanelMonitors()
        panel?.orderOut(nil)
    }

    private final class KeyableHistoryPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = FeatureStrings.recentCaptures(L10n.shared.language).title
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: RecentCapturesWindowView(
            onClose: { [weak self] in self?.hideHistoryWindow() }))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, over anchor: NSWindow?) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize
            ?? NSSize(width: 468, height: 360)
        let screen = anchor?.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let center = anchor.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? CGPoint(x: screen.midX, y: screen.midY)
        let x = min(max(center.x - size.width / 2, screen.minX + 16),
                    screen.maxX - size.width - 16)
        let y = min(max(center.y - size.height / 2, screen.minY + 16),
                    screen.maxY - size.height - 16)
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size),
                       display: true,
                       animate: false)
    }

    private func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let screen = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        var frame = panel.frame
        frame.origin.y = min(max(frame.maxY - size.height, screen.minY + 16),
                             screen.maxY - size.height - 16)
        frame.origin.x = min(max(frame.origin.x, screen.minX + 16),
                             screen.maxX - size.width - 16)
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    private func installPanelMonitors(for panel: NSPanel) {
        removePanelMonitors()
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak panel] event in
            guard event.window === panel else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self?.hideHistoryWindow()
                return nil
            }
            return event
        }
        panelLocalClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
                if event.window !== panel { self?.hideHistoryWindow() }
                return event
            }
        panelGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hideHistoryWindow()
            }
        panelDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.hideHistoryWindow()
            }
    }

    private func removePanelMonitors() {
        if let panelKeyMonitor { NSEvent.removeMonitor(panelKeyMonitor) }
        if let panelLocalClickMonitor { NSEvent.removeMonitor(panelLocalClickMonitor) }
        if let panelGlobalClickMonitor { NSEvent.removeMonitor(panelGlobalClickMonitor) }
        if let panelDeactivateObserver {
            NotificationCenter.default.removeObserver(panelDeactivateObserver)
        }
        panelKeyMonitor = nil
        panelLocalClickMonitor = nil
        panelGlobalClickMonitor = nil
        panelDeactivateObserver = nil
    }

    private var root: URL? {
        guard let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("RecentCaptures", isDirectory: true)
    }

    private var indexURL: URL? {
        root?.appendingPathComponent("history.json")
    }

    func reload() {
        queue.async { [weak self] in
            guard let self else { return }
            self.loadIfNeeded()
            self.pruneMissingEntries()
            self.persist()
            self.publish()
        }
    }

    func recordScreenshot(_ capture: ScreenshotSelectionController.Capture) {
        let id = UUID()
        let screenshotName = "\(id.uuidString).png"
        let thumbnailName = "\(id.uuidString)-thumbnail.png"
        let entry = RecentCaptureEntry(
            id: id,
            kind: .screenshot,
            createdAt: Date(),
            screenshotName: screenshotName,
            recordingPath: nil,
            thumbnailName: thumbnailName,
            scale: Double(capture.scale),
            anchorX: Double(capture.anchorRect.origin.x),
            anchorY: Double(capture.anchorRect.origin.y),
            anchorWidth: Double(capture.anchorRect.width),
            anchorHeight: Double(capture.anchorRect.height))
        let image = capture.image
        let scale = capture.scale

        queue.async { [weak self] in
            guard let self, let root = self.root else { return }
            self.loadIfNeeded()
            do {
                try self.prepareRoot(root)
                guard let full = ScreenshotRenderer.pngData(from: image, scale: scale),
                      let smallImage = Self.thumbnail(from: image),
                      let small = ScreenshotRenderer.pngData(from: smallImage, scale: 1)
                else { return }
                try self.write(full, to: root.appendingPathComponent(screenshotName))
                do {
                    try self.write(small, to: root.appendingPathComponent(thumbnailName))
                } catch {
                    try? self.manager.removeItem(at: root.appendingPathComponent(screenshotName))
                    try? self.manager.removeItem(at: root.appendingPathComponent(thumbnailName))
                    throw error
                }
                self.prepend(entry)
            } catch {
                return
            }
        }
    }

    func recordRecording(at url: URL) {
        guard Self.isRegularFile(url) else { return }
        let id = UUID()
        let thumbnailName = "\(id.uuidString)-thumbnail.png"
        let createdAt = Date()
        let generation = currentClearGeneration()

        Task { @MainActor [weak self] in
            let thumbnail = await Self.recordingThumbnail(at: url)
            self?.storeRecording(at: url, id: id, createdAt: createdAt,
                                 thumbnailName: thumbnailName, thumbnail: thumbnail,
                                 generation: generation)
        }
    }

    private func storeRecording(at url: URL,
                                id: UUID,
                                createdAt: Date,
                                thumbnailName: String,
                                thumbnail: CGImage?,
                                generation: Int) {
        queue.async { [weak self] in
            guard let self, self.currentClearGeneration() == generation,
                  let root = self.root, Self.isRegularFile(url) else { return }
            self.loadIfNeeded()
            guard (try? self.prepareRoot(root)) != nil else { return }
            var storedThumbnail: String?
            if let thumbnail,
               let data = ScreenshotRenderer.pngData(from: thumbnail, scale: 1),
               (try? self.write(data, to: root.appendingPathComponent(thumbnailName))) != nil {
                storedThumbnail = thumbnailName
            }
            guard self.currentClearGeneration() == generation else {
                if let storedThumbnail {
                    try? self.manager.removeItem(
                        at: root.appendingPathComponent(storedThumbnail))
                }
                return
            }
            let entry = RecentCaptureEntry(
                id: id,
                kind: .recording,
                createdAt: createdAt,
                screenshotName: nil,
                recordingPath: url.standardizedFileURL.path,
                thumbnailName: storedThumbnail,
                scale: nil,
                anchorX: nil,
                anchorY: nil,
                anchorWidth: nil,
                anchorHeight: nil)
            self.prepend(entry)
        }
    }

    func remove(_ entry: RecentCaptureEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.loadIfNeeded()
            guard let stored = self.storedEntries.first(where: { $0.id == entry.id }) else { return }
            self.storedEntries.removeAll { $0.id == entry.id }
            self.removeOwnedFiles(for: stored)
            self.persist()
            self.publish()
        }
    }

    func clear() {
        generationLock.lock()
        clearGeneration &+= 1
        generationLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.loadIfNeeded()
            for entry in self.storedEntries {
                self.removeOwnedFiles(for: entry)
            }
            self.storedEntries.removeAll()
            self.persist()
            self.thumbnailCache.removeAllObjects()
            self.publish()
        }
    }

    func thumbnail(for entry: RecentCaptureEntry) -> NSImage? {
        guard let name = entry.thumbnailName, Self.isSafeName(name), let root else { return nil }
        let key = name as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: root.appendingPathComponent(name)) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func open(_ entry: RecentCaptureEntry) {
        hideHistoryWindow()
        switch entry.kind {
        case .screenshot:
            restoreScreenshot(entry)
        case .recording:
            guard let url = entry.recordingURL, Self.isRegularFile(url) else {
                remove(entry)
                NSSound.beep()
                return
            }
            appDelegate()?.closePopover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func restoreScreenshot(_ entry: RecentCaptureEntry) {
        queue.async { [weak self] in
            guard let self, let capture = self.loadScreenshot(entry) else {
                DispatchQueue.main.async { [weak self] in
                    self?.remove(entry)
                    NSSound.beep()
                }
                return
            }
            DispatchQueue.main.async {
                appDelegate()?.closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    ScreenshotService.shared.restorePreview(capture)
                }
            }
        }
    }

    private func loadScreenshot(_ entry: RecentCaptureEntry)
        -> ScreenshotSelectionController.Capture? {
        guard entry.kind == .screenshot,
              let name = entry.screenshotName,
              Self.isSafeName(name),
              let root,
              let scale = entry.scale,
              scale.isFinite, scale > 0,
              let source = CGImageSourceCreateWithURL(
                root.appendingPathComponent(name) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let anchor = CGRect(
            x: entry.anchorX ?? 0,
            y: entry.anchorY ?? 0,
            width: entry.anchorWidth ?? 0,
            height: entry.anchorHeight ?? 0)
        return ScreenshotSelectionController.Capture(
            image: image, scale: CGFloat(scale), anchorRect: anchor)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let root, (try? prepareRoot(root)) != nil else {
            storedEntries = []
            return
        }
        if let indexURL, Self.isRegularFile(indexURL),
           let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([RecentCaptureEntry].self, from: data) {
            storedEntries = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            storedEntries = []
        }
        removeOrphanedCacheFiles(in: root)
    }

    private func pruneMissingEntries() {
        var kept: [RecentCaptureEntry] = []
        for entry in storedEntries where entryExists(entry) {
            kept.append(entry)
        }
        let keepIDs = cappedIDs(for: kept)
        let removed = storedEntries.filter { !keepIDs.contains($0.id) }
        storedEntries = kept.filter { keepIDs.contains($0.id) }
        for entry in removed {
            removeOwnedFiles(for: entry)
        }
    }

    private func prepend(_ entry: RecentCaptureEntry) {
        if let path = entry.recordingPath,
           let previous = storedEntries.first(where: { $0.recordingPath == path }) {
            storedEntries.removeAll { $0.id == previous.id }
            removeOwnedFiles(for: previous)
        }
        storedEntries.append(entry)
        storedEntries.sort { $0.createdAt > $1.createdAt }
        let keepIDs = cappedIDs(for: storedEntries)
        let removed = storedEntries.filter { !keepIDs.contains($0.id) }
        storedEntries.removeAll { !keepIDs.contains($0.id) }
        for old in removed {
            removeOwnedFiles(for: old)
        }
        persist()
        publish()
    }

    private func entryExists(_ entry: RecentCaptureEntry) -> Bool {
        switch entry.kind {
        case .screenshot:
            guard let name = entry.screenshotName, Self.isSafeName(name), let root else { return false }
            return Self.isRegularFile(root.appendingPathComponent(name))
        case .recording:
            guard let url = entry.recordingURL else { return false }
            return Self.isRegularFile(url)
        }
    }

    private func cappedIDs(for entries: [RecentCaptureEntry]) -> Set<UUID> {
        var screenshotBytes: [UUID: Int64] = [:]
        if let root {
            for entry in entries where entry.kind == .screenshot {
                guard let name = entry.screenshotName, Self.isSafeName(name),
                      let size = try? root.appendingPathComponent(name).resourceValues(
                        forKeys: [.fileSizeKey]).fileSize
                else { continue }
                screenshotBytes[entry.id] = Int64(size)
            }
        }
        return Set(ScreenshotSupport.cappedRecentCaptureIDs(
            entries.map(\.id), screenshotBytes: screenshotBytes))
    }

    private func persist() {
        guard let root, let indexURL else { return }
        do {
            try prepareRoot(root)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try write(encoder.encode(storedEntries), to: indexURL)
        } catch {
            return
        }
    }

    private func publish() {
        let value = storedEntries
        DispatchQueue.main.async { [weak self] in
            self?.entries = value
            DispatchQueue.main.async { [weak self] in self?.refreshPanelLayout() }
        }
    }

    private func prepareRoot(_ root: URL) throws {
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    private func write(_ data: Data, to url: URL) throws {
        if manager.fileExists(atPath: url.path),
           (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func removeOwnedFiles(for entry: RecentCaptureEntry) {
        guard let root else { return }
        if let name = entry.screenshotName,
           name == "\(entry.id.uuidString).png" {
            let file = root.appendingPathComponent(name)
            if Self.isRegularFile(file) { try? manager.removeItem(at: file) }
        }
        if let name = entry.thumbnailName,
           name == "\(entry.id.uuidString)-thumbnail.png" {
            thumbnailCache.removeObject(forKey: name as NSString)
            let file = root.appendingPathComponent(name)
            if Self.isRegularFile(file) { try? manager.removeItem(at: file) }
        }
    }

    private func removeOrphanedCacheFiles(in root: URL) {
        let referenced = Set(storedEntries.flatMap { entry in
            [entry.screenshotName, entry.thumbnailName].compactMap { $0 }
        })
        guard let files = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return }
        for file in files where ScreenshotSupport.isRecentCaptureCacheFileName(
            file.lastPathComponent) && !referenced.contains(file.lastPathComponent) {
            if Self.isRegularFile(file) { try? manager.removeItem(at: file) }
        }
    }

    private func currentClearGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return clearGeneration
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name == URL(fileURLWithPath: name).lastPathComponent
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func thumbnail(from image: CGImage) -> CGImage? {
        let maximum = CGFloat(360)
        let longest = CGFloat(max(image.width, image.height))
        let factor = min(1, maximum / max(1, longest))
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func recordingThumbnail(at url: URL) async -> CGImage? {
        if url.pathExtension.lowercased() == "gif" {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        return try? await generator.image(at: .zero).image
    }
}
