// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opt-in native interaction fixture: build/metrics-tests --pin-preview.
/// Uses only generated artwork and a disposable drop folder, never user captures.
enum ScreenshotPinPreview {
    @MainActor static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let fixture = Fixture()
        withExtendedLifetime(fixture) { app.run() }
    }

    @MainActor private final class Fixture: NSObject, NSWindowDelegate {
        private let backdrop: NSWindow
        private let pin: ScreenshotPinWindow
        private var timer: Timer?
        private var clicks = 0

        override init() {
            let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
            backdrop = NSWindow(contentRect: CGRect(x: visible.midX - 330, y: visible.midY - 240, width: 660, height: 480),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            let image = NSImage(size: CGSize(width: 640, height: 400))
            image.lockFocus()
            NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.39, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 640, height: 400).fill()
            NSColor.systemTeal.setFill()
            NSRect(x: 32, y: 40, width: 576, height: 10).fill()
            ("PIN REFERENCE" as NSString).draw(at: CGPoint(x: 48, y: 260), withAttributes: [
                .font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.white])
            ("Scroll to zoom · Option-scroll for opacity\nPinch to zoom · Drag the image to move" as NSString)
                .draw(in: CGRect(x: 48, y: 100, width: 550, height: 110), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.white])
            image.unlockFocus()
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                fatalError("Cannot render preview artwork")
            }
            pin = ScreenshotPinWindow(image: cgImage, scale: 2)
            super.init()
            backdrop.title = "Pin Controls Preview"
            backdrop.isReleasedWhenClosed = false
            backdrop.delegate = self
            let content = PreviewDropView(frame: CGRect(x: 0, y: 0, width: 660, height: 480))
            backdrop.contentView = content
            let button = NSButton(title: "Underlying button: 0 clicks", target: self, action: #selector(clicked(_:)))
            button.frame = CGRect(x: 190, y: 222, width: 280, height: 40)
            button.bezelStyle = .rounded
            content.addSubview(button)
            backdrop.makeKeyAndOrderFront(nil)
            pin.showPin()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.pin.updateHover(at: NSEvent.mouseLocation)
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            NSApp.activate(ignoringOtherApps: true)
        }

        @objc private func clicked(_ sender: NSButton) {
            clicks += 1
            sender.title = "Underlying button: \(clicks) clicks"
        }
        func windowWillClose(_ notification: Notification) {
            timer?.invalidate()
            pin.closePin()
            NSApp.terminate(nil)
        }
    }

    private final class PreviewDropView: NSView {
        private let status = NSTextField(labelWithString: "Drop the pin's file handle here")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            status.frame = CGRect(x: 40, y: 35, width: 580, height: 40)
            status.alignment = .center
            addSubview(status)
            registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let receivers = sender.draggingPasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self])
                    as? [NSFilePromiseReceiver], !receivers.isEmpty else { return false }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PinPreview-\(UUID().uuidString)")
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            catch { status.stringValue = "Drop failed: \(error)"; return false }
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { [weak self] url, error in
                    self?.status.stringValue = error.map { "Drop failed: \($0)" } ?? "PNG received: \(url.lastPathComponent)"
                    print("Pin preview file: \(url.path)")
                    fflush(stdout)
                }
            }
            return true
        }
    }
}
